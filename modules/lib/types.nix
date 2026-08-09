# Custom type definitions for NixOS configuration
#
# Usage in modules:
#   let
#     customTypes = import ../lib/types.nix { inherit lib config; };
#   in {
#     options.myOption = mkOption {
#       type = customTypes.relativePath;
#     };
#   }
#
{ lib, config }:

let
  inherit (lib) types mkOption;

  isRelativePath =
    x:
    types.str.check x
    && x != ""
    && builtins.substring 0 1 x != "/"
    && !(builtins.elem ".." (lib.splitString "/" x));

in
rec {
  # Path that must be relative (no leading / or .. segments)
  # Use for: dotfiles source paths, relative file references
  relativePath = types.strMatching "[^/].*" // {
    description = "relative path (no leading / or .. segments)";
    descriptionClass = "noun";
    check = isRelativePath;
  };

  # Path under $HOME (can use $HOME variable or absolute path)
  # Use for: dotfiles target paths, user config locations
  homePath = types.strMatching "(\\$HOME|/home/).*" // {
    description = "path under user home directory";
    descriptionClass = "noun";
  };

  # Absolute filesystem path
  # Use for: repoPath
  absolutePath = types.strMatching "/.*" // {
    description = "absolute filesystem path";
    descriptionClass = "noun";
  };

  # User that must exist in config.users.users
  # Note: This creates a deferred check - validation happens at eval time
  # Use for: dotfiles.user, module user options
  existingUser = types.str // {
    description = "existing system user";
    descriptionClass = "noun";
    check = x: types.str.check x && x != "";
  };

  # Helper to create user validation assertion
  # Use in module config: assertions = [ (customTypes.assertUserExists cfg.user) ];
  assertUserExists = userName: {
    assertion = config.users.users ? ${userName};
    message = "User '${userName}' must exist in users.users";
  };

  # Network port (convenience alias with description)
  port = types.port;

  # Non-empty string
  nonEmptyStr = types.strMatching ".+" // {
    description = "non-empty string";
    descriptionClass = "noun";
  };

  # Complete mapping submodule with validated types
  mappingSubmodule = types.submodule {
    options = {
      source = mkOption {
        type = relativePath;
        description = "Source file name in module directory (relative path, no ..)";
        example = "config.toml";
      };
      copyTo = mkOption {
        type = types.nullOr absolutePath;
        default = null;
        description = ''
          Optional privileged destination outside the configured user home.
          The file is copied from the immutable Nix store during system activation.
        '';
        example = "/etc/xdg/monitors.xml";
      };
      executable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether the source file is expected to be executable.
          The dotfiles manager validates this but never changes permissions in the repo checkout.
        '';
      };
      target = mkOption {
        type = homePath;
        description = "Target path (must start with $HOME or /home/)";
        example = "$HOME/.config/app/config.toml";
      };
    };
  };

  # Full dotfiles module submodule with all validated types
  dotfilesModuleSubmodule = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable this dotfiles module";
      };

      sourceDir = mkOption {
        type = relativePath;
        description = ''
          Repository-relative path to the directory containing this module's configuration files.
          The dotfiles manager links targets directly to files under dotfiles.repoPath.
        '';
        example = "modules/devtools/ide/zed";
      };

      mappings = mkOption {
        type = types.attrsOf mappingSubmodule;
        default = { };
        description = "File mappings for this module";
        example = {
          config = {
            source = "settings.json";
            target = "$HOME/.config/app/settings.json";
          };
        };
      };
    };
  };
}
