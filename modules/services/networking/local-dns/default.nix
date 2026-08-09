{ config, lib, ... }:

with lib;

let
  cfg = config.applications.services.networking;
in
{
  options.applications.services.networking.localDns = {
    enable = mkEnableOption "the local AdGuard Home and Unbound DNS stack";

    adguardDnsPort = mkOption {
      type = types.port;
      default = 53;
      readOnly = true;
      description = "Local DNS port exposed by AdGuard Home; fixed at 53 because resolv.conf cannot encode a custom port";
    };

    adguardWebPort = mkOption {
      type = types.port;
      default = 3010;
      description = "Loopback web interface port exposed by AdGuard Home";
    };

    unboundPort = mkOption {
      type = types.port;
      default = 5335;
      description = "Loopback resolver port used by Unbound and AdGuard Home";
    };
  };

  config = mkMerge [
    (mkIf cfg.localDns.enable {
      applications.services.networking = {
        adguardhome.enable = mkDefault true;
        unbound.enable = mkDefault true;
      };

      networking.networkmanager.dns = mkDefault "none";
      networking.nameservers = mkDefault [
        "127.0.0.1"
        "::1"
      ];
      services.resolved.enable = mkDefault false;
    })

    {
      assertions = [
        {
          assertion = !cfg.localDns.enable || (cfg.adguardhome.enable && cfg.unbound.enable);
          message = "The local DNS stack requires both AdGuard Home and Unbound";
        }
        {
          assertion = !cfg.localDns.enable || cfg.localDns.adguardDnsPort == 53;
          message = "The local DNS stack must expose AdGuard Home on port 53";
        }
        {
          assertion = !cfg.localDns.enable || config.networking.networkmanager.dns == "none";
          message = "The local DNS stack requires NetworkManager DNS management to be disabled";
        }
        {
          assertion = !cfg.localDns.enable || !config.services.resolved.enable;
          message = "The local DNS stack conflicts with systemd-resolved";
        }
        {
          assertion =
            !cfg.localDns.enable
            || allUnique [
              cfg.localDns.adguardDnsPort
              cfg.localDns.adguardWebPort
              cfg.localDns.unboundPort
            ];
          message = "AdGuard DNS, AdGuard web, and Unbound must use distinct ports";
        }
        {
          assertion = !cfg.adguardhome.enable || cfg.unbound.enable;
          message = "AdGuard Home requires Unbound as upstream resolver";
        }
        {
          assertion =
            !cfg.adguardhome.enable
            ||
              config.networking.nameservers == [
                "127.0.0.1"
                "::1"
              ];
          message = "When AdGuard Home is enabled, networking.nameservers must use the local DNS stack";
        }
      ];
    }
  ];
}
