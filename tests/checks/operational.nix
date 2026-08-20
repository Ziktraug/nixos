{ pkgs }:

let
  repoRoot = ../..;
in
{
  operational-scripts =
    pkgs.runCommand "operational-script-tests"
      {
        nativeBuildInputs = with pkgs; [
          bash
          bun
          coreutils
          findutils
          git
          gawk
          gnugrep
          gnused
          gnutar
          jq
          rsync
          sqlite
          util-linux
        ];
      }
      ''
        export REPO_ROOT=${repoRoot}
        bash ${../scripts/test-copy-windows-efi.sh}
        bash ${../scripts/test-maintenance.sh}
        bash ${../scripts/test-disk-health-check.sh}
        bash ${../scripts/test-verify-git-ssh.sh}
        bash ${../scripts/test-agent-memory-harvest.sh}
        bash ${../scripts/test-recent-work-context-v2.sh}
        bash ${../scripts/test-check-entrypoint.sh}
        bash ${../scripts/test-public-export.sh}
        touch "$out"
      '';

  update-workflow =
    pkgs.runCommand "update-workflow-tests"
      {
        nativeBuildInputs = with pkgs; [
          bash
          bun
          coreutils
          findutils
          git
          gnugrep
          gnused
          hostname
          jq
        ];
      }
      ''
        export REPO_ROOT=${repoRoot}
        bash ${../scripts/test-update-release-hooks.sh}
        bash ${../scripts/test-update-backend.sh}
        bash ${../scripts/test-update-tui.sh}
        touch "$out"
      '';
}
