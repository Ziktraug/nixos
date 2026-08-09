{
  description = "Reusable NixOS modules and an evaluation-only example host";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ocmonitor = {
      url = "github:Shlomob/ocmonitor-share";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      zen-browser,
      claude-code,
      ocmonitor,
      ...
    }:
    let
      system = "x86_64-linux";
      host = "example";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      nixosModules.default = {
        imports = [
          ./modules/unfree-packages.nix
          ./modules/validation.nix
          ./modules/primary-user.nix
          ./modules/dotfiles-manager.nix
          ./modules/applications.nix
        ];
      };

      nixosConfigurations.${host} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit zen-browser claude-code ocmonitor; };
        modules = [
          self.nixosModules.default
          ./hosts/example/configuration.nix
        ];
      };

      checks.${system} = import ./tests/checks.nix {
        inherit
          self
          nixpkgs
          zen-browser
          claude-code
          ocmonitor
          host
          ;
        hostModule = ./hosts/example/configuration.nix;
        lockFile = ./flake.lock;
      };

      packages.${system}.gitleaks = pkgs.gitleaks;
      formatter.${system} = pkgs.nixfmt;
    };
}
