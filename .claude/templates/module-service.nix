# System Service Module Template
# Replace <service> with service name
# Replace <Service description> with description

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.<service>;
in
{
  options.services.<service> = {
    enable = mkEnableOption "<Service description>";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for <service> to listen on";
    };

    settings = mkOption {
      type = types.attrs;
      default = {};
      description = "Additional <service> settings";
    };
  };

  config = mkIf cfg.enable {
    services.<service> = {
      enable = true;
      port = cfg.port;
      settings = cfg.settings;
    };

    # Firewall (if service needs external access)
    # networking.firewall.allowedTCPPorts = [ cfg.port ];

    # Service dependencies
    systemd.services.<service> = {
      after = [ "network.target" ];
      wants = [ "network.target" ];
    };
  };
}
