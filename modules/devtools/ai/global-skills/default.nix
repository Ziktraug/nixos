{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.ai."global-skills";
  globalSkillsUser = config.dotfiles.user;
  userHome = config.users.users.${globalSkillsUser}.home;
  repoPath = config.dotfiles.repoPath;
  mattPocockSkillsDir = "${repoPath}/modules/devtools/ai/global-skills/.cache/matt-pocock-skills/skills";
  recentWorkContextBin = pkgs.writeShellScriptBin "recent-work-context" ''
    exec ${pkgs.bun}/bin/bun "$HOME/.claude/skills/recent-work-context/scripts/recent-work-context.ts" "$@"
  '';
in
{
  options.applications.devtools.ai."global-skills" = {
    enable = mkEnableOption "globally tracked AI skills";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      bun
      recentWorkContextBin
    ];

    dotfiles.modules."global-ai-skills" = {
      enable = true;
      sourceDir = "modules/devtools/ai/global-skills";
      mappings = {
        recent-work-context-skill = {
          source = "recent-work-context/SKILL.md";
          target = "$HOME/.claude/skills/recent-work-context/SKILL.md";
        };
        recent-work-context-agents-skill = {
          source = "recent-work-context/SKILL.md";
          target = "$HOME/.agents/skills/recent-work-context/SKILL.md";
        };
        recent-work-context-script = {
          source = "recent-work-context/scripts/recent-work-context.ts";
          target = "$HOME/.claude/skills/recent-work-context/scripts/recent-work-context.ts";
        };
        recent-work-context-agents-script = {
          source = "recent-work-context/scripts/recent-work-context.ts";
          target = "$HOME/.agents/skills/recent-work-context/scripts/recent-work-context.ts";
        };
        recent-work-context-data-sources = {
          source = "recent-work-context/references/data-sources.md";
          target = "$HOME/.claude/skills/recent-work-context/references/data-sources.md";
        };
        recent-work-context-agents-data-sources = {
          source = "recent-work-context/references/data-sources.md";
          target = "$HOME/.agents/skills/recent-work-context/references/data-sources.md";
        };
        recent-work-context-output-format = {
          source = "recent-work-context/references/output-format.md";
          target = "$HOME/.claude/skills/recent-work-context/references/output-format.md";
        };
        recent-work-context-agents-output-format = {
          source = "recent-work-context/references/output-format.md";
          target = "$HOME/.agents/skills/recent-work-context/references/output-format.md";
        };
        reference-projects-claude-skill = {
          source = "reference-projects/SKILL.md";
          target = "$HOME/.claude/skills/reference-projects/SKILL.md";
        };
        reference-projects-agents-skill = {
          source = "reference-projects/SKILL.md";
          target = "$HOME/.agents/skills/reference-projects/SKILL.md";
        };
        reference-projects-opencode-skill = {
          source = "reference-projects/SKILL.md";
          target = "$HOME/.config/opencode/skills/reference-projects/SKILL.md";
        };
        pr-review-claude-skill = {
          source = "pr-review/SKILL.md";
          target = "$HOME/.claude/skills/pr-review/SKILL.md";
        };
        pr-review-agents-skill = {
          source = "pr-review/SKILL.md";
          target = "$HOME/.agents/skills/pr-review/SKILL.md";
        };
        pr-review-opencode-skill = {
          source = "pr-review/SKILL.md";
          target = "$HOME/.config/opencode/skills/pr-review/SKILL.md";
        };
      };
    };

    systemd.user.services.matt-pocock-skills = {
      description = "Install Matt Pocock skills for the configured user";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        Environment = "HOME=${userHome}";
        ExecStart = pkgs.writeShellScript "setup-matt-pocock-skills" ''
                set -euo pipefail
                echo "Setting up Matt Pocock global AI skills..."

                if [ "$(${pkgs.coreutils}/bin/id -un)" != ${escapeShellArg globalSkillsUser} ]; then
                  echo "Matt Pocock skills must be installed as ${globalSkillsUser}" >&2
                  exit 1
                fi

                user_home="${userHome}"
                skills_source="${mattPocockSkillsDir}"

                if [ ! -d "$skills_source" ]; then
                  echo "Matt Pocock skills source not found at $skills_source; run script/update.sh first" >&2
                  exit 1
                fi

                claude_skills="$user_home/.claude/skills"
                agents_skills="$user_home/.agents/skills"
                opencode_skills="$user_home/.config/opencode/skills"
                cursor_rules="$user_home/.cursor/rules"
                copilot_instructions="$user_home/.github/instructions"

                mkdir -p "$claude_skills" "$agents_skills" "$opencode_skills" "$cursor_rules" "$copilot_instructions"

                rm -f "$cursor_rules"/matt-pocock-*.mdc
                rm -f "$copilot_instructions"/matt-pocock-*.instructions.md

                for skill_dir in "$skills_source"/{engineering,productivity,misc}/*; do
                  [ -d "$skill_dir" ] || continue
                  [ -f "$skill_dir/SKILL.md" ] || continue

                  skill_name="$(basename "$skill_dir")"
                  declared_name="$(${pkgs.gnused}/bin/sed -n 's/^name:[[:space:]]*//p' "$skill_dir/SKILL.md" | ${pkgs.coreutils}/bin/head -n 1)"
                  declared_name="''${declared_name#\"}"
                  declared_name="''${declared_name%\"}"

                  if [ -z "$declared_name" ] || ! ${pkgs.gnugrep}/bin/grep -Eq '^description:[[:space:]]*.+' "$skill_dir/SKILL.md"; then
                    echo "Skipping invalid skill without name/description: $skill_dir" >&2
                    continue
                  fi

                  if [ "$declared_name" != "$skill_name" ]; then
                    echo "Skipping skill with mismatched name: $skill_dir declares $declared_name" >&2
                    continue
                  fi

                  if ! printf '%s\n' "$skill_name" | ${pkgs.gnugrep}/bin/grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
                    echo "Skipping skill with invalid Agent Skills name: $skill_name" >&2
                    continue
                  fi

                  for install_dir in "$claude_skills" "$agents_skills" "$opencode_skills"; do
                    target="$install_dir/$skill_name"
                    if [ -e "$target" ] && [ ! -L "$target" ]; then
                      echo "Skipping existing non-symlink skill target: $target" >&2
                      continue
                    fi

                    ln -sfn "$skill_dir" "$target"
                  done

                  cursor_rule="$cursor_rules/matt-pocock-$skill_name.mdc"
                  copilot_instruction="$copilot_instructions/matt-pocock-$skill_name.instructions.md"

                  cat > "$cursor_rule" <<EOF
          ---
          description: "Matt Pocock skill: $skill_name"
          alwaysApply: false
          ---

          $(cat "$skill_dir/SKILL.md")
          EOF

                  cat > "$copilot_instruction" <<EOF
          ---
          applyTo: "**"
          description: "Matt Pocock skill: $skill_name"
          ---

          $(cat "$skill_dir/SKILL.md")
          EOF
                done

        '';
      };
    };
  };
}
