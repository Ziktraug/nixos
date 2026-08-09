{
  self,
  nixpkgs,
  zen-browser,
  claude-code,
  ocmonitor,
  host,
  hostModule,
  lockFile,
}:

let
  pkgs = import nixpkgs { system = "x86_64-linux"; };
in
{
  ${host} = pkgs.runCommand "${host}-eval-check" { } ''
    printf '%s\n' '${
      builtins.unsafeDiscardStringContext
        self.nixosConfigurations.${host}.config.system.build.toplevel.drvPath
    }' > "$out"
  '';
}
// import ./checks/dotfiles.nix {
  inherit pkgs nixpkgs;
}
// import ./checks/operational.nix {
  inherit pkgs;
}
// import ./checks/host-contracts.nix {
  inherit
    self
    nixpkgs
    pkgs
    zen-browser
    claude-code
    ocmonitor
    host
    hostModule
    lockFile
    ;
}
// import ./checks/source-quality.nix {
  inherit pkgs;
}
