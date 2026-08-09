# Basic Application Module Template
# Replace <app> with application name
# Replace <App description> with description

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.applications.<app>;
in
{
  options.applications.<app> = {
    enable = mkEnableOption "<App description>";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      <app>
    ];
  };
}
