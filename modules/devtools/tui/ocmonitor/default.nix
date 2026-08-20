{
  config,
  pkgs,
  lib,
  ocmonitor,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.tui.ocmonitor;
  dotfilesUser = config.dotfiles.user;
  userHome = config.users.users.${dotfilesUser}.home;

  ocmonitorPkg = pkgs.python3Packages.buildPythonApplication rec {
    pname = "ocmonitor";
    version = "unstable-${builtins.substring 0 10 ocmonitor.lastModifiedDate or "19700101"}";

    src = ocmonitor;

    patches = [ ./opencode-v2.patch ];

    pyproject = true;

    build-system = with pkgs.python3Packages; [
      setuptools
      wheel
    ];

    propagatedBuildInputs = with pkgs.python3Packages; [
      click
      rich
      pydantic
      prometheus-client
      pyyaml
      toml
      pandas
      matplotlib
    ];

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck

      python - <<'PY'
      import json
      import sqlite3
      import tempfile
      from pathlib import Path

      from ocmonitor.utils.sqlite_utils import SQLiteProcessor

      database = Path(tempfile.mkdtemp()) / "opencode-next.db"
      setup = sqlite3.connect(database)
      setup.executescript(
          """
          CREATE TABLE project (id TEXT PRIMARY KEY, worktree TEXT, name TEXT);
          CREATE TABLE session_v2 (
              id TEXT PRIMARY KEY,
              project_id TEXT,
              parent_id TEXT,
              directory TEXT,
              title TEXT,
              time_created INTEGER,
              time_updated INTEGER
          );
          CREATE TABLE session_message (
              id TEXT PRIMARY KEY,
              session_id TEXT,
              type TEXT,
              time_created INTEGER,
              time_updated INTEGER,
              data TEXT
          );
          INSERT INTO project VALUES ('project', '/tmp/project', 'project');
          INSERT INTO session_v2 VALUES (
              'session', 'project', NULL, '/tmp/project', 'V2 session', 1000, 2000
          );
          """
      )
      message = {
          "agent": "lead-codex",
          "model": {"id": "gpt-5.6-sol", "providerID": "openai"},
          "tokens": {"input": 12, "output": 4, "cache": {"read": 2, "write": 1}},
          "time": {"created": 1000, "completed": 2000},
          "content": [
              {
                  "type": "tool",
                  "name": "shell",
                  "state": {"status": "completed", "input": {}, "content": "ok"},
              }
          ],
      }
      setup.execute(
          "INSERT INTO session_message VALUES (?, ?, ?, ?, ?, ?)",
          ("message", "session", "assistant", 1000, 2000, json.dumps(message)),
      )
      setup.commit()
      setup.close()

      connection = SQLiteProcessor._get_connection(database)
      assert connection.execute("SELECT count(*) FROM session").fetchone()[0] == 1
      assert connection.execute("SELECT count(*) FROM message").fetchone()[0] == 1
      assert connection.execute("SELECT count(*) FROM part").fetchone()[0] == 1
      interaction = SQLiteProcessor.load_session_messages(connection, "session")[0]
      assert interaction.model_id == "gpt-5.6-sol"
      assert interaction.provider_id == "openai"
      assert interaction.project_path == "/tmp/project"
      sessions = SQLiteProcessor.load_all_sessions(database)
      assert len(sessions) == 1
      assert sessions[0].session_title == "V2 session"
      PY

      runHook postInstallCheck
    '';

    meta = with lib; {
      description = "CLI tool for monitoring and analyzing OpenCode AI coding usage";
      homepage = "https://github.com/Shlomob/ocmonitor-share";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "ocmonitor";
    };
  };
  ocmonitorV2 = pkgs.writeShellScriptBin "ocmonitor" ''
    export OCMONITOR_DATABASE_FILE=${lib.escapeShellArg "${userHome}/.local/share/opencode/opencode-next.db"}
    exec ${ocmonitorPkg}/bin/ocmonitor "$@"
  '';
  ocmonitorV1 = pkgs.writeShellScriptBin "ocmonitor-v1" ''
    export OCMONITOR_DATABASE_FILE=${lib.escapeShellArg "${userHome}/.local/share/opencode/opencode-stable.db"}
    exec ${ocmonitorPkg}/bin/ocmonitor "$@"
  '';
in
{
  options.applications.devtools.tui.ocmonitor = {
    enable = mkEnableOption "OpenCode Monitor - CLI tool for monitoring OpenCode AI usage";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      ocmonitorV2
      ocmonitorV1
    ];

    # Create ocmonitor config directory
    dotfiles.modules.ocmonitor = {
      enable = true;
      sourceDir = "modules/devtools/tui/ocmonitor";
      mappings = {
        config = {
          source = "config.toml";
          target = "$HOME/.config/ocmonitor/config.toml";
        };
      };
    };

    systemd.user.services.ocmonitor-directories = {
      description = "Create ocmonitor user directories";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "create-ocmonitor-directories" ''
          set -euo pipefail
          test "$(${pkgs.coreutils}/bin/id -un)" = ${lib.escapeShellArg dotfilesUser}
          ${pkgs.coreutils}/bin/mkdir -p \
            ${lib.escapeShellArg "${userHome}/.config/ocmonitor"} \
            ${lib.escapeShellArg "${userHome}/.local/share/ocmonitor/exports"}
        '';
        Environment = "HOME=${userHome}";
      };
    };
  };
}
