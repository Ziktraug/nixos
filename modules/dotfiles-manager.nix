{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.dotfiles;
  customTypes = import ./lib/types.nix { inherit lib config; };
  repoRoot = ../.;
  userHelper = ./dotfiles-manager/user-activation.sh;
  systemCopyHelper = ./dotfiles-manager/system-copy.sh;

  userHome = config.users.users.${cfg.user}.home;
  hasPathTraversal = path: elem ".." (splitString "/" path);
  resolveHome = path: builtins.replaceStrings [ "$HOME" ] [ userHome ] path;
  isUnderHome = path: hasPrefix "${userHome}/" (resolveHome path);
  isInHome = path: resolveHome path == userHome || isUnderHome path;

  validateSource =
    source:
    assert !hasPathTraversal source || throw "Dotfiles source '${source}' contains path traversal (..)";
    assert !hasPrefix "/" source || throw "Dotfiles source '${source}' must be relative";
    source;

  validateTarget =
    target:
    let
      resolved = resolveHome target;
    in
    assert
      !hasPathTraversal resolved || throw "Dotfiles target '${target}' contains path traversal (..)";
    assert
      isUnderHome target
      || throw "Dotfiles target '${target}' must be below the configured home (${userHome})";
    resolved;

  enabledMappings = flatten (
    map (
      moduleName:
      let
        moduleConfig = cfg.modules.${moduleName};
      in
      optionals moduleConfig.enable (
        map (mappingName: {
          inherit moduleName mappingName;
          sourceDir = moduleConfig.sourceDir;
          mapping = moduleConfig.mappings.${mappingName};
        }) (attrNames moduleConfig.mappings)
      )
    ) (attrNames cfg.modules)
  );

  sourceInCheckout =
    entry: "${cfg.repoPath}/${entry.sourceDir}/${validateSource entry.mapping.source}";
  sourceInRepository = entry: repoRoot + "/${entry.sourceDir}/${validateSource entry.mapping.source}";
  sourceInStore =
    entry:
    builtins.path {
      path = sourceInRepository entry;
      name = lib.strings.sanitizeDerivationName "dotfile-${entry.moduleName}-${entry.mappingName}";
    };
  formatMapping = entry: "${entry.moduleName}.${entry.mappingName}";
  mappingTargets = map (entry: validateTarget entry.mapping.target) enabledMappings;
  duplicateTargets = filter (target: count (candidate: candidate == target) mappingTargets > 1) (
    unique mappingTargets
  );
  missingSources = filter (entry: !(builtins.pathExists (sourceInRepository entry))) enabledMappings;
  systemCopyMappings = filter (entry: entry.mapping.copyTo != null) enabledMappings;
  invalidSystemCopies = filter (entry: isInHome entry.mapping.copyTo) systemCopyMappings;

  userSetupScript = pkgs.writeShellScript "setup-dotfiles-for-${cfg.user}" ''
    set -euo pipefail
    export HOME=${escapeShellArg userHome}
    echo "Applying dotfiles as ${cfg.user}..."
    ${concatMapStringsSep "\n" (entry: ''
      ${pkgs.bash}/bin/bash ${userHelper} \
        ${escapeShellArg cfg.user} \
        ${escapeShellArg userHome} \
        ${escapeShellArg entry.moduleName} \
        ${escapeShellArg entry.mappingName} \
        ${escapeShellArg (sourceInCheckout entry)} \
        ${escapeShellArg (validateTarget entry.mapping.target)} \
        ${if entry.mapping.executable then "1" else "0"}
    '') enabledMappings}
    echo "Dotfiles applied for ${cfg.user}."
  '';

  systemCopyScript = pkgs.writeShellScript "copy-system-dotfiles" ''
    set -euo pipefail
    ${concatMapStringsSep "\n" (entry: ''
      ${pkgs.bash}/bin/bash ${systemCopyHelper} \
        ${escapeShellArg entry.moduleName} \
        ${escapeShellArg entry.mappingName} \
        ${escapeShellArg (sourceInStore entry)} \
        ${escapeShellArg (resolveHome entry.mapping.copyTo)}
    '') systemCopyMappings}
  '';
in
{
  options.dotfiles = {
    enable = mkEnableOption "custom dotfiles management";

    user = mkOption {
      type = customTypes.existingUser;
      description = "User who owns and applies managed dotfiles";
      example = "alice";
    };

    repoPath = mkOption {
      type = customTypes.absolutePath;
      description = "Editable repository checkout used as the user dotfile source";
      example = "/srv/alice/nixos";
    };

    modules = mkOption {
      type = types.attrsOf customTypes.dotfilesModuleSubmodule;
      default = { };
      description = "Dotfile module mappings";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != "" && config.users.users ? ${cfg.user};
        message = "Dotfiles user '${cfg.user}' must exist in users.users";
      }
      {
        assertion = cfg.repoPath != "";
        message = "Dotfiles repoPath must be specified";
      }
      {
        assertion = duplicateTargets == [ ];
        message = "Dotfiles mappings contain duplicate targets: ${concatStringsSep ", " duplicateTargets}";
      }
      {
        assertion = missingSources == [ ];
        message = "Dotfiles mappings reference missing sources: ${concatStringsSep ", " (map formatMapping missingSources)}";
      }
      {
        assertion = invalidSystemCopies == [ ];
        message = "copyTo is privileged and must be outside the user home: ${concatStringsSep ", " (map formatMapping invalidSystemCopies)}";
      }
    ];

    environment.sessionVariables = {
      NIXOS_REPO = cfg.repoPath;
      NIXOS_FLAKE_PATH = cfg.repoPath;
      NIXOS_HOST_KEY = config.networking.hostName;
    };

    systemd.user.services.dotfiles-manager = {
      description = "Apply repository-managed dotfiles";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = userSetupScript;
        Environment = "HOME=${userHome}";
      };
    };

    system.activationScripts.dotfiles-system-copy = optionalString (systemCopyMappings != [ ]) ''
      echo "Applying privileged dotfile copies from immutable Nix store sources..."
      ${systemCopyScript}
    '';

    system.build.dotfilesUserScript = userSetupScript;
    system.build.dotfilesSystemScript = systemCopyScript;
  };
}
