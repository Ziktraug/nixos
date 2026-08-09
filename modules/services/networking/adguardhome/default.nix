{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.services.networking.adguardhome;
  dns = config.applications.services.networking.localDns;
in
{
  options.applications.services.networking.adguardhome = {
    enable = mkEnableOption "AdGuard Home DNS server";
  };

  config = mkIf cfg.enable {
    # CRITICAL: Ensure AdGuardHome waits for Unbound (its upstream DNS)
    # Without this, AdGuardHome starts before Unbound is ready, causing
    # "connection refused" errors and DNS failures at boot.
    systemd.services.adguardhome = {
      after = [ "unbound.service" ];
      requires = [ "unbound.service" ];
    };

    services.adguardhome = {
      enable = true;
      host = "127.0.0.1";
      port = dns.adguardWebPort;
      settings = {
        http = {
          address = "127.0.0.1:${toString dns.adguardWebPort}";
        };
        dns = {
          bind_hosts = [
            "127.0.0.1"
            "::1"
          ];
          port = dns.adguardDnsPort;
          upstream_dns = [
            "127.0.0.1:${toString dns.unboundPort}"
          ];
          # This instance only listens locally. Browser, Steam, Proton, and
          # tooling traffic all collapse to localhost, so the default per-client
          # rate limit creates false pressure under normal desktop load.
          ratelimit = 0;
          cache_optimistic = true;
          cache_ttl_min = 60;
          cache_ttl_max = 86400;
        };
        filtering = {
          protection_enabled = true;
          filtering_enabled = true;
          parental_enabled = false;
          safe_search = {
            enabled = false;
          };
        };
        filters =
          map
            (url: {
              enabled = true;
              url = url;
            })
            [
              "https://adguardteam.github.io/HostlistsRegistry/assets/filter_9.txt"
              "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt"
              "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"
            ];
      };
    };
  };
}
