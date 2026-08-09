{ ... }:

{
  imports = [ ./modules.nix ];

  # This host exists only for evaluation and deliberately has no disk layout.
  boot.isContainer = true;

  networking = {
    hostName = "example";
    networkmanager.enable = true;
  };

  users.users.alice = {
    isNormalUser = true;
    description = "Example User";
    home = "/srv/alice";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  primaryUser.name = "alice";

  dotfiles = {
    enable = true;
    repoPath = "/srv/alice/nixos";
  };

  time.timeZone = "Etc/UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  services.xserver.xkb.layout = "us";
  console.keyMap = "us";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "25.05";
}
