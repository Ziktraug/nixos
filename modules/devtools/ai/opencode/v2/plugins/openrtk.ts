type ShellCreateBefore = {
  command: string;
};

type OpenCode2PluginContext = {
  shell: {
    hook: (
      name: "create.before",
      callback: (event: ShellCreateBefore) => void | Promise<void>,
    ) => Promise<void>;
  };
};

type OpenCode2Plugin = {
  id: string;
  setup: (context: OpenCode2PluginContext) => void | Promise<void>;
};

const ENV_PREFIX_RE = /^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)+/;

const RULES: ReadonlyArray<readonly [RegExp, string]> = [
  [/^git status(?=\s|$)/, "rtk git status"],
  [/^git diff(?=\s|$)/, "rtk git diff"],
  [/^git log(?=\s|$)/, "rtk git log"],
  [/^git add(?=\s|$)/, "rtk git add"],
  [/^git commit(?=\s|$)/, "rtk git commit"],
  [/^git push(?=\s|$)/, "rtk git push"],
  [/^git pull(?=\s|$)/, "rtk git pull"],
  [/^git branch(?=\s|$)/, "rtk git branch"],
  [/^git fetch(?=\s|$)/, "rtk git fetch"],
  [/^git stash(?=\s|$)/, "rtk git stash"],
  [/^git show(?=\s|$)/, "rtk git show"],
  [/^gh (?=(pr|issue|run|api|release)(\s|$))/, "rtk gh "],
  [/^cargo test(?=\s|$)/, "rtk cargo test"],
  [/^cargo build(?=\s|$)/, "rtk cargo build"],
  [/^cargo clippy(?=\s|$)/, "rtk cargo clippy"],
  [/^cargo check(?=\s|$)/, "rtk cargo check"],
  [/^cargo install(?=\s|$)/, "rtk cargo install"],
  [/^cargo fmt(?=\s|$)/, "rtk cargo fmt"],
  [/^cat /, "rtk read "],
  [/^(rg|grep) /, "rtk grep "],
  [/^ls(?=\s|$)/, "rtk ls"],
  [/^tree(?=\s|$)/, "rtk tree"],
  [/^find /, "rtk find "],
  [/^diff /, "rtk diff "],
  [/^(pnpm )?(npx )?vitest( run)?(?=\s|$)/, "rtk vitest run"],
  [/^pnpm test(?=\s|$)/, "rtk vitest run"],
  [/^npm test(?=\s|$)/, "rtk npm test"],
  [/^npm run /, "rtk npm "],
  [/^(npx )?vue-tsc(?=\s|$)/, "rtk tsc"],
  [/^pnpm tsc(?=\s|$)/, "rtk tsc"],
  [/^(npx )?tsc(?=\s|$)/, "rtk tsc"],
  [/^pnpm lint(?=\s|$)/, "rtk lint"],
  [/^(npx )?eslint(?=\s|$)/, "rtk lint"],
  [/^(npx )?prettier(?=\s|$)/, "rtk prettier"],
  [/^(npx )?playwright(?=\s|$)/, "rtk playwright"],
  [/^pnpm playwright(?=\s|$)/, "rtk playwright"],
  [/^(npx )?prisma(?=\s|$)/, "rtk prisma"],
  [/^docker (?=compose(\s|$)|(ps|images|logs|run|build|exec)(\s|$))/, "rtk docker "],
  [/^kubectl (?=(get|logs|describe|apply)(\s|$))/, "rtk kubectl "],
  [/^curl /, "rtk curl "],
  [/^wget /, "rtk wget "],
  [/^pnpm (?=(list|ls|outdated)(\s|$))/, "rtk pnpm "],
  [/^pytest(?=\s|$)/, "rtk pytest"],
  [/^python -m pytest(?=\s|$)/, "rtk pytest"],
  [/^ruff (?=(check|format)(\s|$))/, "rtk ruff "],
  [/^pip (?=(list|outdated|install|show)(\s|$))/, "rtk pip "],
  [/^uv pip (?=(list|outdated|install|show)(\s|$))/, "rtk pip "],
  [/^go test(?=\s|$)/, "rtk go test"],
  [/^go build(?=\s|$)/, "rtk go build"],
  [/^go vet(?=\s|$)/, "rtk go vet"],
  [/^golangci-lint(?=\s|$)/, "rtk golangci-lint"],
  [/^mix phx\.routes(?=\s|$)/, "rtk --cache mix phx.routes"],
  [/^mix ash\.info(?=\s|$)/, "rtk --cache mix ash.info"],
  [/^mix test(?=\s|$)/, "rtk test mix test"],
  [/^mix credo(?=\s|$)/, "rtk lint mix credo"],
  [/^mix format(?=\s|$)/, "rtk format mix format"],
  [/^mix dialyzer(?=\s|$)/, "rtk err mix dialyzer"],
  [/^mix compile(?=\s|$)/, "rtk mix compile"],
  [/^mix ecto\.(migrate|migrations)(?=\s|$)/, "rtk mix ecto.$1"],
  [/^mix help(?=\s|$)/, "rtk --cache mix help"],
  [/^mix /, "rtk mix "],
  [/^iex /, "rtk iex "],
];

function rewrite(command: string): string | null {
  if (/^(.*\/)?rtk\s/.test(command) || command.includes("<<")) return null;

  const envMatch = command.match(ENV_PREFIX_RE);
  const envPrefix = envMatch?.[0] ?? "";
  const body = envPrefix ? command.slice(envPrefix.length) : command;

  for (const [pattern, replacement] of RULES) {
    if (pattern.test(body)) return envPrefix + body.replace(pattern, replacement);
  }

  return null;
}

const openrtk: OpenCode2Plugin = {
  id: "local.openrtk",
  setup: async (context) => {
    if (!Bun.which("rtk")) {
      console.warn("[openrtk] rtk binary not found in PATH - plugin disabled");
      return;
    }

    await context.shell.hook("create.before", (event) => {
      const rewritten = rewrite(event.command);
      if (rewritten) event.command = rewritten;
    });
  },
};

export default openrtk;
