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
  opencodePluginVersion = "1.18.13";
  opencodePluginArchive = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@opencode-ai/plugin/-/plugin-${opencodePluginVersion}.tgz";
    hash = "sha512-2H9YT80M1PYElpG+lmd/9kGqsNouiJIBCUhLblmgFwoSrB4wyahgkCS6NcFQR/AYXNH4I1Yd3lmQcVaEPu1qNg==";
  };
  opencodeSdkArchive = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@opencode-ai/sdk/-/sdk-${opencodePluginVersion}.tgz";
    hash = "sha512-JY9etiVcu1G/pZjaH2vjK/b8z54ujxaWCD1GziO4ADUhRM6m6zm2332bPGcxEfA6TwweiJfNlK6wVZQ0f/X4KQ==";
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
in
{
  source-quality-shell =
    pkgs.runCommand "source-quality-shell"
      {
        nativeBuildInputs = with pkgs; [
          bash
          findutils
          gnugrep
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
