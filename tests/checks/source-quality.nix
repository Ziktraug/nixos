{ pkgs }:

let
  repoRoot = ../..;
  # bun-types 1.3.13 references type-only APIs introduced by the Node 26
  # declarations, even though these scripts execute under Bun rather than Node.
  nodeTypesArchive = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@types/node/-/node-26.1.1.tgz";
    hash = "sha512-nxAkRSVkN1Y0JC1W8ky/fTfkGsMmcrRsbx+3XoZE+rMOX71kLYTV7fLXpqud1GpbpP5TuffXFqfX7fH2GgZREw==";
  };
  undiciTypesArchive = pkgs.fetchurl {
    url = "https://registry.npmjs.org/undici-types/-/undici-types-8.3.0.tgz";
    hash = "sha512-j375ScV60dom+YkPFIfTLcOiPxkN/buHz5GobjLhixFuANaNs3C9l4GmrWqejgXWJ7BbJcFYpTEUkS1Ge8bpZQ==";
  };
  bunTypesAliasArchive = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@types/bun/-/bun-1.3.13.tgz";
    hash = "sha512-9fqXWk5YIHGGnUau9TEi+qdlTYDAnOj+xLCmSTwXfAIqXr2x4tytJb43E9uCvt09zJURKXwAtkoH4nLQfzeTXw==";
  };
  bunTypesArchive = pkgs.fetchurl {
    url = "https://registry.npmjs.org/bun-types/-/bun-types-1.3.13.tgz";
    hash = "sha512-QXKeHLlOLqQX9LgYaHJfzdBaV21T63HhFJnvuRCcjZiaUDpbs5ED1MgxbMra71CsryN/1dAoXuJJJwIv/2drVA==";
  };
  opencodePluginVersion = "1.18.18";
  opencodePluginArchive = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@opencode-ai/plugin/-/plugin-${opencodePluginVersion}.tgz";
    hash = "sha512-vqQeqJtn9c+J+tIQDzYk88xip/NVNN1hym1ATmckxo6zINHAoXoul4Sw/jgnvL00rLsfAvhja28qax4h3g/5Jg==";
  };
  opencodeSdkArchive = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@opencode-ai/sdk/-/sdk-${opencodePluginVersion}.tgz";
    hash = "sha512-zJlwXskIR47V1dkPJqeKBgq7nejG1uU8lJaGIGqbX3MWRCT8vKn0fEotbxuPCKnTdmWsDyNGNg9q1qIliDSMDA==";
  };
  zodArchive = pkgs.fetchurl {
    url = "https://registry.npmjs.org/zod/-/zod-4.1.8.tgz";
    hash = "sha512-5R1P+WwQqmmMIEACyzSvo4JXHY5WiAFHRMg+zBZKgKS+Q1viRa0C1hmUKtHltoIFKtIdki3pRxkmpP74jnNYHQ==";
  };
  opencodeTypeModules = pkgs.runCommand "opencode-${opencodePluginVersion}-type-modules" { } ''
    mkdir -p \
      "$out/node_modules/@opencode-ai/plugin" \
      "$out/node_modules/@opencode-ai/sdk" \
      "$out/node_modules/zod"
    ${pkgs.gnutar}/bin/tar -xzf ${opencodePluginArchive} \
      --strip-components=1 -C "$out/node_modules/@opencode-ai/plugin"
    ${pkgs.gnutar}/bin/tar -xzf ${opencodeSdkArchive} \
      --strip-components=1 -C "$out/node_modules/@opencode-ai/sdk"
    ${pkgs.gnutar}/bin/tar -xzf ${zodArchive} \
      --strip-components=1 -C "$out/node_modules/zod"
  '';
  typescriptTypeRoots = pkgs.runCommand "typescript-runtime-types" { } ''
    mkdir -p \
      "$out/node_modules/@types/node" \
      "$out/node_modules/@types/bun" \
      "$out/node_modules/undici-types" \
      "$out/node_modules/bun-types"
    ${pkgs.gnutar}/bin/tar -xzf ${nodeTypesArchive} \
      --strip-components=1 -C "$out/node_modules/@types/node"
    ${pkgs.gnutar}/bin/tar -xzf ${undiciTypesArchive} \
      --strip-components=1 -C "$out/node_modules/undici-types"
    ${pkgs.gnutar}/bin/tar -xzf ${bunTypesAliasArchive} \
      --strip-components=1 -C "$out/node_modules/@types/bun"
    ${pkgs.gnutar}/bin/tar -xzf ${bunTypesArchive} \
      --strip-components=1 -C "$out/node_modules/bun-types"
  '';
  opencodePluginTsconfig = pkgs.writeText "opencode-plugin-tsconfig.json" (
    builtins.toJSON {
      compilerOptions = {
        baseUrl = "${opencodeTypeModules}/node_modules";
        module = "ESNext";
        moduleResolution = "Bundler";
        noEmit = true;
        paths = {
          "@opencode-ai/plugin" = [
            "${opencodeTypeModules}/node_modules/@opencode-ai/plugin/dist/index.d.ts"
          ];
        };
        skipLibCheck = true;
        strict = true;
        target = "ES2022";
        typeRoots = [ "${typescriptTypeRoots}/node_modules/@types" ];
        types = [
          "node"
          "bun"
        ];
      };
      files = [ "${repoRoot}/modules/devtools/ai/opencode/plugins/openrtk.ts" ];
    }
  );
  opencode2 = pkgs.callPackage ../../modules/devtools/ai/opencode/package-v2.nix { };
in
{
  source-quality-shell =
    pkgs.runCommand "source-quality-shell"
      {
        nativeBuildInputs = with pkgs; [
          bash
          findutils
          gnugrep
          jq
          shellcheck
        ];
      }
      ''
        repo=${repoRoot}
        find "$repo" \
          \( -path '*/node_modules' -o -path '*/.cache' \) -prune -o \
          -type f -name '*.sh' -print0 > shell-files
        xargs -0 -r bash -n < shell-files
        while IFS= read -r -d $'\0' file; do
          # This single generated status script belongs to the separate ai-usage project.
          case "$file" in
            */modules/ui/waybar/scripts/ai-usage.sh) continue ;;
          esac
          shellcheck --severity=warning "$file"
        done < shell-files

        skills_hook="$repo/modules/devtools/ai/global-skills/update-flake-pre.sh"
        grep -Eq '^PINNED_REV="[0-9a-f]{40}"$' "$skills_hook"
        grep -Fq 'fetch --depth 1 origin "$PINNED_REV"' "$skills_hook"
        grep -Fq 'checkout --detach "$PINNED_REV"' "$skills_hook"
        if grep -Eq 'origin main|checkout -B main|git clone' "$skills_hook"; then
          echo "Matt Pocock skills hook follows a mutable branch" >&2
          exit 1
        fi

        mcp_nixos_revision=fea707cb1aec3e68baf2a815fa292ab9291451e4
        grep -Fq \
          "github:utensils/mcp-nixos/$mcp_nixos_revision" \
          "$repo/.cursor/mcp.json"
        grep -Fq \
          "github:utensils/mcp-nixos/$mcp_nixos_revision" \
          "$repo/.codex/config.toml"

        jq -e '
          .hooks.PostToolUse[0].hooks[0].command as $command
          | ($command | contains("apply_patch"))
          and ($command | contains("jq -e"))
          and ($command | contains("/.codex/hooks/") | not)
        ' "$repo/.codex/hooks.json" >/dev/null

        touch "$out"
      '';

  source-quality-nix =
    pkgs.runCommand "source-quality-nix"
      {
        nativeBuildInputs = with pkgs; [
          findutils
          nixfmt
        ];
      }
      ''
        repo=${repoRoot}
        find "$repo" \
          \( -path '*/node_modules' -o -path '*/.cache' \) -prune -o \
          -type f -name '*.nix' -print0 > nix-files
        while IFS= read -r -d $'\0' file; do
          # These are literal scaffolding templates whose <placeholder> tokens
          # are intentionally not parseable Nix until instantiated.
          case "$file" in
            */.claude/templates/module-basic.nix|\
            */.claude/templates/module-desktop.nix|\
            */.claude/templates/module-service.nix|\
            */.claude/templates/module-with-dotfiles.nix) continue ;;
          esac
          nixfmt --check "$file"
        done < nix-files
        touch "$out"
      '';

  source-quality-typescript =
    pkgs.runCommand "source-quality-typescript"
      {
        nativeBuildInputs = with pkgs; [
          bun
          findutils
          jq
          typescript
        ];
      }
      ''
        repo=${repoRoot}
        type_roots=${typescriptTypeRoots}/node_modules/@types
        common_flags=(
          --noEmit
          --target ES2022
          --module ESNext
          --moduleResolution Bundler
          --types node
          --typeRoots "$type_roots"
        )

        if ! jq -e '
          [
            ((.agents // {})[] | (.permissions // [])[]),
            (.permissions // [])[]
          ]
          | all(
              .action != "shell"
              or .effect != "allow"
              or (.resource | contains("*") | not)
            )
        ' "$repo/modules/devtools/ai/opencode/v2/opencode.json" >/dev/null; then
          echo "OpenCode2 must not auto-allow wildcard shell commands" >&2
          exit 1
        fi

        for config in \
          "$repo/opencode.json" \
          "$repo/modules/devtools/ai/opencode/opencode.json"; do
          if ! jq -e '
            def bash_rules:
              [
                ((.permission.bash? // {}) | objects | to_entries[]),
                (
                  (.agent // {})[]
                  | (.permission.bash? // {})
                  | objects
                  | to_entries[]
                )
              ];
            bash_rules
            | all(
                .value != "allow"
                or (.key | contains("*") | not)
              )
          ' "$config" >/dev/null; then
            echo "OpenCode must not auto-allow wildcard bash commands: $config" >&2
            exit 1
          fi
        done

        for config in \
          "$repo/opencode.json" \
          "$repo/modules/devtools/ai/opencode/opencode.json"; do
          jq -e '
            .permission.edit == "ask"
            and .permission.read["*"] == "allow"
            and .permission.read[".env"] == "deny"
            and .permission.read[".env.*"] == "deny"
            and .permission.read["**/.env"] == "deny"
            and .permission.read["**/.env.*"] == "deny"
            and .permission.read.secrets == "deny"
            and .permission.read["secrets/**"] == "deny"
            and .permission.read["**/secrets"] == "deny"
            and .permission.read["**/secrets/**"] == "deny"
            and .permission.read.credentials == "deny"
            and .permission.read["credentials/**"] == "deny"
            and .permission.read["**/credentials"] == "deny"
            and .permission.read["**/credentials/**"] == "deny"
            and .permission.read[".git"] == "deny"
            and .permission.read[".git/**"] == "deny"
            and .permission.read["**/.git"] == "deny"
            and .permission.read["**/.git/**"] == "deny"
            and .permission.read.private == "deny"
            and .permission.read["private/**"] == "deny"
            and .permission.read["**/private"] == "deny"
            and .permission.read["**/private/**"] == "deny"
            and .permission.glob == "ask"
            and .permission.grep == "ask"
            and .permission.list == "ask"
          ' "$config" >/dev/null
        done

        find "$repo" \
          \( -path '*/node_modules' -o -path '*/.cache' \) -prune -o \
          -type f -name '*.ts' ! -name '*.d.ts' -print0 | sort -z > typescript-files

        while IFS= read -r -d $'\0' file; do
          relative="''${file#"$repo"/}"
          case "$relative" in
            modules/devtools/ai/agent-memory/scripts/agent-memory.ts)
              tsc "''${common_flags[@]}" --strict --types node,bun "$file"
              ;;
            modules/devtools/tui/update-tui/update-tui.ts)
              tsc "''${common_flags[@]}" --strict "$file"
              ;;
            modules/devtools/tui/codex-monitor/codex-monitor.ts)
              tsc "''${common_flags[@]}" "$file"
              ;;
            modules/devtools/ai/global-skills/recent-work-context/scripts/recent-work-context.ts)
              tsc -p "$repo/modules/devtools/ai/global-skills/tsconfig.json" \
                --typeRoots "$type_roots"
              ;;
            modules/devtools/ai/opencode/plugins/openrtk.ts)
              if [ "${pkgs.opencode.version}" != "${opencodePluginVersion}" ]; then
                echo "OpenCode runtime ${pkgs.opencode.version} and plugin types ${opencodePluginVersion} differ" >&2
                exit 1
              fi
              jq -e --arg version "${opencodePluginVersion}" '
                .packages[""].dependencies["@opencode-ai/plugin"] == $version
                and .packages["node_modules/@opencode-ai/plugin"].version == $version
                and .packages["node_modules/@opencode-ai/sdk"].version == $version
              ' "$repo/.opencode/package-lock.json" >/dev/null
              tsc -p ${opencodePluginTsconfig}
              ;;
            modules/devtools/ai/opencode/v2/plugins/*.ts)
              tsc "''${common_flags[@]}" --strict --types node,bun "$file"
              ;;
            *)
              echo "No TypeScript quality policy for $relative" >&2
              exit 1
              ;;
          esac
        done < typescript-files

        mapfile -d $'\0' -t entrypoints < typescript-files
        bun build "''${entrypoints[@]}" \
          --external @opencode-ai/plugin \
          --target=bun \
          --outdir=typescript-build
        touch "$out"
      '';

  opencode2-preview =
    pkgs.runCommand "opencode2-preview-test"
      {
        nativeBuildInputs = [
          opencode2
          pkgs.coreutils
          pkgs.curl
          pkgs.jq
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$TMPDIR/config"
        export XDG_DATA_HOME="$TMPDIR/data"
        export OPENCODE_DISABLE_AUTOUPDATE=true
        mkdir -p \
          "$HOME" \
          "$XDG_CONFIG_HOME/opencode/v2/plugins" \
          "$XDG_DATA_HOME" \
          "$TMPDIR/project/.claude" \
          "$TMPDIR/project/.opencode"
        cp ${repoRoot}/modules/devtools/ai/opencode/v2/opencode.json \
          "$XDG_CONFIG_HOME/opencode/opencode.json"
        cp ${repoRoot}/modules/devtools/ai/opencode/v2/AGENTS.md \
          "$XDG_CONFIG_HOME/opencode/AGENTS.md"
        cp ${repoRoot}/modules/devtools/ai/opencode/v2/plugins/openrtk.ts \
          "$XDG_CONFIG_HOME/opencode/v2/plugins/openrtk.ts"
        cp ${repoRoot}/modules/devtools/ai/opencode/v2/plugins/secure-agents.ts \
          "$XDG_CONFIG_HOME/opencode/v2/plugins/secure-agents.ts"
        cp ${repoRoot}/opencode.json "$TMPDIR/project/opencode.json"
        cp -R ${repoRoot}/.claude/agents "$TMPDIR/project/.claude/agents"
        cp -R ${repoRoot}/.opencode/agents "$TMPDIR/project/.opencode/agents"

        test "$(opencode2 --version)" = "opencode2 v${opencode2.version}"
        opencode2 acp --help | grep -Fq 'Agent Client Protocol'
        cd "$TMPDIR/project"
        opencode2 serve --hostname 127.0.0.1 --port 0 > server.log 2>&1 &
        server_pid=$!
        trap 'kill "$server_pid" 2>/dev/null || true' EXIT

        server_credential=""
        server_endpoint=""
        for attempt in $(seq 1 200); do
          server_credential="$(sed -n 's/^server password //p' server.log | tail -n 1)"
          server_endpoint="$(sed -n 's/^server listening on //p' server.log | tail -n 1)"
          if [ -n "$server_credential" ] && [ -n "$server_endpoint" ]; then
            break
          fi
          sleep 0.1
        done
        test -n "$server_credential"
        test -n "$server_endpoint"

        for attempt in $(seq 1 200); do
          if curl --fail --silent --show-error \
            --user "opencode:$server_credential" \
            --get \
            --data-urlencode "location[directory]=$TMPDIR/project" \
            "$server_endpoint/api/config" \
            > resolved-config.json; then
            break
          fi
          sleep 0.1
        done
        test -s resolved-config.json

        for attempt in $(seq 1 200); do
          curl --fail --silent --show-error \
            --user "opencode:$server_credential" \
            --get \
            --data-urlencode "location[directory]=$TMPDIR/project" \
            "$server_endpoint/api/agent" \
            | jq '.data' > resolved-agents.json
          if jq -e 'length > 0' resolved-agents.json >/dev/null; then
            break
          fi
          sleep 0.1
        done
        jq -e 'length > 0' resolved-agents.json >/dev/null
        jq -e '
          def effect($action; $resources):
            ([
              .permissions[]
              | select(
                  (.action == "*" or .action == $action)
                  and (.resource as $resource | $resources | index($resource))
                )
            ][-1].effect // "missing");
          . as $agents
          | ([
              "config-validator",
              "dotfiles-expert",
              "hyprland-configurator",
              "memory-distiller",
              "nixos-debugger",
              "nixos-module-architect",
              "service-integrator"
            ] - ($agents | map(.id)) | length) == 0
          and all(
            $agents[];
            effect("shell"; ["*"]) != "allow"
            and effect("shell"; ["*", "git push*"]) == "deny"
            and effect("edit"; ["*"]) != "allow"
            and effect("read"; ["*", ".env"]) == "deny"
            and effect("read"; ["*", "**/.env"]) == "deny"
            and effect("read"; ["*", "**/.env.*"]) == "deny"
            and effect("read"; ["*", "secrets/**"]) == "deny"
            and effect("read"; ["*", "**/secrets/**"]) == "deny"
            and effect("read"; ["*", "credentials/**"]) == "deny"
            and effect("read"; ["*", "**/credentials/**"]) == "deny"
            and effect("read"; ["*", ".git/**"]) == "deny"
            and effect("read"; ["*", "**/.git/**"]) == "deny"
            and effect("read"; ["*", "private", "private/**", "**/private", "**/private/**"]) == "deny"
            and effect("glob"; ["*"]) != "allow"
            and effect("grep"; ["*"]) != "allow"
            and effect("list"; ["*"]) != "allow"
          )
        ' resolved-agents.json >/dev/null
        jq -e '
          any(
            .[];
            .type == "document"
            and .info.default_agent == "lead-codex"
            and (.info.plugins | index("./v2/plugins/openrtk.ts")) != null
            and (.info.plugins | index("./v2/plugins/secure-agents.ts")) != null
          )
        ' resolved-config.json >/dev/null
        touch "$out"
      '';

  source-quality-workflows =
    pkgs.runCommand "source-quality-workflows"
      {
        nativeBuildInputs = with pkgs; [
          actionlint
          yamllint
        ];
      }
      ''
        actionlint ${repoRoot}/.github/workflows/check.yml
        yamllint \
          -d '{extends: default, rules: {line-length: disable, truthy: disable}}' \
          ${repoRoot}/.github/workflows/check.yml
        touch "$out"
      '';

  documentation-contract =
    pkgs.runCommand "documentation-contract" { nativeBuildInputs = [ pkgs.gnugrep ]; }
      ''
        if grep -R -n -E \
          'hosts/nixos|hosts/<hostname>|\./hosts/[^[:space:]]*#|/dev/sdc2' \
          ${repoRoot}/README.md \
          ${repoRoot}/PLAN-CORRECTIFS.md \
          ${repoRoot}/ARCHITECTURE_DOTFILES_PLAN.md \
          ${repoRoot}/docs \
          ${repoRoot}/.claude \
          ${repoRoot}/.cursor \
          ${repoRoot}/.opencode \
          ${repoRoot}/opencode.json \
          ${repoRoot}/modules/devtools/ai/claude-code/settings.json \
          ${repoRoot}/modules/devtools/ai/opencode/opencode.json; then
          echo "Maintained documentation contains an obsolete per-host flake reference or hard-coded repair device" >&2
          exit 1
        fi
        grep -Fq '| `flake.nix` |' ${repoRoot}/.claude/context/project-structure.md
        grep -Fq '`nixosModules.default`' ${repoRoot}/README.md
        grep -Fq '`nixosConfigurations.example`' ${repoRoot}/README.md
        grep -Fq './script/check.sh' ${repoRoot}/README.md
        grep -Fq 'run: ./script/check.sh' ${repoRoot}/.github/workflows/check.yml
        touch "$out"
      '';
}
