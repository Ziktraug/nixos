{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.media.guitar;
in
{
  options.applications.media.guitar = {
    enable = mkEnableOption "Electric guitar effects environment";

    sampleRate = mkOption {
      type = types.int;
      default = 48000;
      description = "Preferred sample rate for the audio graph.";
    };

    quantum = {
      min = mkOption {
        type = types.int;
        default = 32;
        description = "Minimum JACK quantum (buffer size) in frames.";
      };

      max = mkOption {
        type = types.int;
        default = 128;
        description = "Maximum JACK quantum (buffer size) in frames.";
      };

      default = mkOption {
        type = types.int;
        default = 64;
        description = "Default JACK quantum (buffer size) in frames.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.quantum.min <= cfg.quantum.default && cfg.quantum.default <= cfg.quantum.max;
        message = "PipeWire JACK quantum must satisfy min <= default <= max";
      }
    ];

    services.pipewire = {
      jack.enable = true;
      extraConfig.pipewire."context.properties" = {
        "default.clock.rate" = cfg.sampleRate;
        "default.clock.allowed-rates" = [
          cfg.sampleRate
          44100
        ];
        "default.clock.quantum" = cfg.quantum.default;
        "default.clock.min-quantum" = cfg.quantum.min;
        "default.clock.max-quantum" = cfg.quantum.max;
      };
    };

    environment.systemPackages = with pkgs; [
      guitarix
      calf
      helvum
      qpwgraph

      # LSP plugins without desktop launchers (they're plugins, not apps)
      (lsp-plugins.overrideAttrs (oldAttrs: {
        postInstall = (oldAttrs.postInstall or "") + ''
          rm -rf $out/share/applications
        '';
      }))

      # Carla - keep only main launcher, remove variants
      (carla.overrideAttrs (oldAttrs: {
        postInstall = (oldAttrs.postInstall or "") + ''
          cd $out/share/applications
          # Keep only the main carla.desktop, remove all variants
          find . -name "carla-*.desktop" -delete
        '';
      }))
    ];
  };
}
