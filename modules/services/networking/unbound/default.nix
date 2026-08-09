{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.services.networking.unbound;
  dns = config.applications.services.networking.localDns;
in
{
  options.applications.services.networking.unbound = {
    enable = mkEnableOption "Unbound DNS resolver";
  };

  config = mkIf cfg.enable {
    # Ensure Unbound waits for network to be online before starting
    # This prevents DNSSEC trust anchor priming failures at boot
    systemd.services.unbound = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    services.unbound = {
      enable = true;
      settings = {
        server = {
          # When only using Unbound as DNS, make sure to replace 127.0.0.1 with your ip address
          # When using Unbound in combination with pi-hole or Adguard, leave 127.0.0.1, and point Adguard to 127.0.0.1:PORT
          interface = [
            "127.0.0.1"
            "::1"
          ];
          port = dns.unboundPort;
          access-control = [
            "127.0.0.1 allow"
            "::1 allow"
          ];
          # Based on recommended settings in https://docs.pi-hole.net/guides/dns/unbound/#configure-unbound
          harden-glue = true;
          harden-dnssec-stripped = true;
          use-caps-for-id = false;
          prefetch = true;
          prefetch-key = true;
          serve-expired = true;
          serve-expired-ttl = 86400;
          serve-expired-client-timeout = 1800;
          serve-expired-reply-ttl = 30;
          cache-min-ttl = 60;
          cache-max-ttl = 86400;
          msg-cache-size = "64m";
          rrset-cache-size = "128m";
          edns-buffer-size = 1232;
          qname-minimisation = true;
          aggressive-nsec = true;

          # Custom settings
          hide-identity = true;
          hide-version = true;
        };
      };
    };
  };
}
