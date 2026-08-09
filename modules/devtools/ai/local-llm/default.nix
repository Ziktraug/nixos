{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.ai."local-llm";
  ollamaPackage = pkgs.callPackage ./ollama-prebuilt.nix { };
  ollamaBaseUrl = "http://${cfg.ollama.host}:${toString cfg.ollama.port}";
in
{
  options.applications.devtools.ai."local-llm" = {
    enable = mkEnableOption "local LLM stack powered by Ollama and Open WebUI";

    defaultModel = mkOption {
      type = types.str;
      default = "qwen3:8b";
      description = "Default model exposed in Open WebUI.";
    };

    models = mkOption {
      type = types.listOf types.str;
      default = [
        "qwen3:8b"
        "deepseek-r1:8b"
      ];
      description = "Models to pull automatically once the Ollama service starts.";
    };

    modelsDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/var/lib/ollama/models";
      description = "Optional absolute path where Ollama stores downloaded models.";
    };

    ollama = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Host address for the Ollama HTTP API.";
      };

      port = mkOption {
        type = types.port;
        default = 11434;
        description = "Port for the Ollama HTTP API.";
      };
    };

    webui = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Expose Open WebUI on top of the local Ollama service.";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Host address for Open WebUI.";
      };

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Port for Open WebUI.";
      };
    };
  };

  config = mkIf cfg.enable {
    unfreePackages = [ "open-webui" ];

    assertions = [
      {
        assertion = cfg.models == [ ] || builtins.elem cfg.defaultModel cfg.models;
        message = "applications.devtools.ai.\"local-llm\".defaultModel must be included in models when models are preloaded.";
      }
      {
        assertion = cfg.modelsDir == null || hasPrefix "/" cfg.modelsDir;
        message = "applications.devtools.ai.\"local-llm\".modelsDir must be an absolute path.";
      }
    ];

    services.ollama = {
      enable = true;
      package = ollamaPackage;
      host = cfg.ollama.host;
      port = cfg.ollama.port;
      loadModels = cfg.models;
      syncModels = false;
    }
    // optionalAttrs (cfg.modelsDir != null) {
      models = cfg.modelsDir;
    };

    services."open-webui" = mkIf cfg.webui.enable {
      enable = true;
      host = cfg.webui.host;
      port = cfg.webui.port;
      environment = {
        OLLAMA_BASE_URL = ollamaBaseUrl;
        OLLAMA_API_BASE_URL = "${ollamaBaseUrl}/api";
        DEFAULT_MODELS = cfg.defaultModel;
      };
    };

    environment.systemPackages = [ config.services.ollama.package ];
  };
}
