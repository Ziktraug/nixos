{
  config,
  lib,
  options,
  pkgs,
  ...
}:

let
  cfg = config.applications.browsers.firefox;
  hasPhoenixOption = lib.hasAttrByPath [ "programs" "firefox" "phoenix" "enable" ] options;
in
{
  options.applications.browsers.firefox = {
    enable = lib.mkEnableOption "Firefox browser";
  };

  config = lib.mkIf cfg.enable {
    # Install Firefox
    environment.systemPackages = with pkgs; [
      firefox
    ];

    # Enable Firefox program for additional configuration options
    programs.firefox = {
      enable = true;
    }
    // lib.optionalAttrs hasPhoenixOption {
      phoenix.enable = true;
    };
  };
}
