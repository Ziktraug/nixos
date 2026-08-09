#!/usr/bin/env bun

import {
  accessSync,
  appendFileSync,
  chmodSync,
  constants as fsConstants,
  existsSync,
  linkSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import type { Stats } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";

const VERSION = "0.1.0";
const MANAGED_START = "<!-- agent-memory:start -->";
const MANAGED_END = "<!-- agent-memory:end -->";
const DISTILLED_INDEX_START = "<!-- agent-memory:distilled-index:start -->";
const DISTILLED_INDEX_END = "<!-- agent-memory:distilled-index:end -->";
const PRIVATE_DIRECTORY_MODE = 0o700;
const PRIVATE_FILE_MODE = 0o600;
const DEFAULT_RETENTION_DAYS = 30;
const DEFAULT_MAX_HARVEST_EVENTS = 128;
const DAY_MS = 24 * 60 * 60 * 1000;
const HARVEST_STATE_VERSION = 1;

type AdapterName = "claude" | "copilot" | "opencode" | "cursor" | "generic";

type MemoryScope = "repo" | "global" | "session";
type DurableEntryType = "decision" | "pattern" | "pitfall" | "command" | "constraint" | "handoff" | "lesson" | "preference";

type MemoryConfig = {
  globalRepoPath: string;
  managedRepos: string[];
  autoCapture?: {
    enable?: boolean;
    since?: string;
    onCalendar?: string;
    retentionDays?: number;
    maxEvents?: number;
  };
  adapters?: Partial<Record<AdapterName, boolean>>;
};

type CommandResult = {
  ok: boolean;
  status: number;
  stdout: string;
  stderr: string;
};

type Change = {
  path: string;
  action: "ok" | "create" | "update" | "missing" | "error";
  message: string;
};

type MemoryEvent = {
  version: string;
  timestamp: string;
  scope: MemoryScope;
  type: string;
  title: string;
  body: string;
  repo: string | null;
  source: string;
  sensitivity: "public" | "private" | "sensitive" | "secret-redacted";
  payload?: unknown;
};

type DistilledEntry = {
  type: DurableEntryType;
  scope: Exclude<MemoryScope, "session">;
  title: string;
  summary: string;
  guidance: string[];
  evidence: string[];
  source: string;
  tags: string[];
  created: string;
  trust: "explicit" | "harvest-accepted";
  hash: string;
};

type HarvestObservation = {
  fingerprint: string;
  timestamp: number | null;
};

type HarvestState = {
  version: number;
  watermark: number | null;
  seen: Record<string, string>;
};

type InboxLockInspection = {
  alive: boolean | null;
  content: string;
  device: number;
  inode: number;
};

const DURABLE_ENTRY_TYPES: DurableEntryType[] = [
  "decision",
  "pattern",
  "pitfall",
  "command",
  "constraint",
  "handoff",
  "lesson",
  "preference",
];

const args = Bun.argv.slice(2);
const command = args[0] ?? "help";
const rest = args.slice(1);

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});

async function main(): Promise<void> {
  switch (command) {
    case "help":
    case "--help":
    case "-h":
      printHelp();
      return;
    case "version":
    case "--version":
      console.log(VERSION);
      return;
    case "doctor":
      runDoctor(loadConfig());
      return;
    case "init-global":
      initGlobal(loadConfig(), hasFlag(rest, "check"));
      return;
    case "sync-adapters":
      syncAdapters(loadConfig(), rest);
      return;
    case "append":
      await appendEvent(loadConfig(), rest);
      return;
    case "harvest":
      await harvest(loadConfig(), rest);
      return;
    case "distill":
      distill(loadConfig(), rest);
      return;
    case "recall":
      recall(rest);
      return;
    case "lint":
      lint(loadConfig(), rest);
      return;
    default:
      console.error(`Unknown command '${command}'.`);
      printHelp();
      process.exit(2);
  }
}

function printHelp(): void {
  console.log(`agent-memory ${VERSION}

Usage:
  agent-memory doctor
  agent-memory init-global [--check]
  agent-memory sync-adapters [--check] [--repo /path]
  agent-memory recall [recent-work-context options]
  agent-memory harvest [--repo /path] [--since 24h] [--query text] [--lens recent]
                       [--retention-days 30] [--max-events 128] [--dry-run]
  agent-memory distill [--scope repo|global] [--repo /path] [--dry-run] [--limit N]
                       [--accept-session-harvest]
  agent-memory append --scope repo|global|session --type TYPE --title TITLE [--body TEXT] [--repo /path]
  agent-memory lint [--global] [--repos]

Environment:
  AGENT_MEMORY_CONFIG  Path to declarative JSON config. Defaults to ~/.config/agent-memory/config.json.

Rules:
  - Durable memory is operational guidance, not a source of truth.
  - Writes are append-only by default.
  - Secrets are redacted before writing events.
`);
}

function loadConfig(): MemoryConfig {
  const configuredPath = process.env.AGENT_MEMORY_CONFIG ?? path.join(homedir(), ".config", "agent-memory", "config.json");
  const envGlobalRepo = process.env.AGENT_MEMORY_GLOBAL_REPO;
  if (existsSync(configuredPath)) {
    const parsed = JSON.parse(readFileSync(configuredPath, "utf8")) as Partial<MemoryConfig>;
    return normalizeConfig({
      ...parsed,
      globalRepoPath: parsed.globalRepoPath ?? envGlobalRepo,
    });
  }

  return normalizeConfig({
    globalRepoPath: envGlobalRepo ?? defaultGlobalRepoPath(),
    managedRepos: [],
    adapters: {
      claude: true,
      copilot: true,
      opencode: true,
      cursor: true,
      generic: true,
    },
  });
}

function normalizeConfig(config: Partial<MemoryConfig>): MemoryConfig {
  const fallbackGlobalRepo = process.env.AGENT_MEMORY_GLOBAL_REPO ?? defaultGlobalRepoPath();

  return {
    globalRepoPath: normalizePath(expandHome(config.globalRepoPath ?? fallbackGlobalRepo)),
    managedRepos: unique((config.managedRepos ?? []).map((repo) => normalizePath(expandHome(repo)))),
    autoCapture: {
      enable: config.autoCapture?.enable ?? false,
      since: config.autoCapture?.since ?? "24h",
      onCalendar: config.autoCapture?.onCalendar ?? "hourly",
      retentionDays: positiveIntegerOrDefault(config.autoCapture?.retentionDays, DEFAULT_RETENTION_DAYS),
      maxEvents: positiveIntegerOrDefault(config.autoCapture?.maxEvents, DEFAULT_MAX_HARVEST_EVENTS),
    },
    adapters: {
      claude: config.adapters?.claude ?? true,
      copilot: config.adapters?.copilot ?? true,
      opencode: config.adapters?.opencode ?? true,
      cursor: config.adapters?.cursor ?? true,
      generic: config.adapters?.generic ?? true,
    },
  };
}

function defaultGlobalRepoPath(): string {
  const candidates = [
    path.join(homedir(), "Projects", "Github", "second-brain"),
    path.join(homedir(), "second-brain"),
  ];

  for (const candidate of candidates) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  return candidates[0] ?? path.join(homedir(), "second-brain");
}

function runDoctor(config: MemoryConfig): void {
  const checks: Change[] = [];
  checks.push(checkDirectory(config.globalRepoPath, "global memory repo"));
  checks.push(checkGitRepo(config.globalRepoPath));

  for (const repo of config.managedRepos) {
    checks.push(checkDirectory(repo, "managed repo"));
    checks.push(checkGitRepo(repo));
  }

  const recentWorkContext = findRecentWorkContextCommand();
  checks.push({
    path: recentWorkContext ?? "recent-work-context",
    action: recentWorkContext === null ? "missing" : "ok",
    message: recentWorkContext === null ? "recent-work-context command/script not found" : "recent-work-context available",
  });

  console.log(`agent-memory ${VERSION}`);
  console.log(`config: ${process.env.AGENT_MEMORY_CONFIG ?? "~/.config/agent-memory/config.json (fallback if missing)"}`);
  console.log(`globalRepoPath: ${config.globalRepoPath}`);
  console.log(`managedRepos: ${config.managedRepos.length}`);
  console.log(`autoCapture: ${config.autoCapture?.enable === true ? "enabled" : "disabled"}`);
  console.log(`adapters: ${enabledAdapters(config).join(", ")}`);
  console.log("");

  for (const check of checks) {
    console.log(`${statusIcon(check.action)} ${check.message}: ${check.path}`);
  }

  if (checks.some((check) => check.action === "missing" || check.action === "error")) {
    process.exit(1);
  }
}

function initGlobal(config: MemoryConfig, checkOnly: boolean): void {
  const changes: Change[] = [];
  const root = config.globalRepoPath;
  const directories = [
    root,
    path.join(root, "global"),
    path.join(root, "global", "decisions"),
    path.join(root, "global", "lessons"),
    path.join(root, "global", "patterns"),
    path.join(root, "global", "pitfalls"),
    path.join(root, "global", "commands"),
    path.join(root, "global", "constraints"),
    path.join(root, "global", "handoffs"),
    path.join(root, "global", "preferences"),
    path.join(root, "repos"),
    path.join(root, "inbox"),
    path.join(root, "templates"),
  ];

  if (!preflightPrivateDirectories(directories, changes)) {
    printChanges(changes);
    process.exit(1);
  }

  for (const directory of directories) {
    ensureDirectory(directory, checkOnly, changes);
  }

  ensureFile(path.join(root, "SCHEMA.md"), globalSchemaTemplate(), checkOnly, changes);
  ensureFile(path.join(root, "index.md"), globalIndexTemplate(), checkOnly, changes);
  ensureFile(path.join(root, "log.md"), globalLogTemplate(), checkOnly, changes);
  ensureFile(path.join(root, "inbox", "events.jsonl"), "", checkOnly, changes);
  ensureFile(path.join(root, "repos", "registry.md"), repoRegistryTemplate(config), checkOnly, changes);
  ensureFile(path.join(root, "templates", "memory-entry.md"), memoryEntryTemplate(), checkOnly, changes);

  printChanges(changes);
  exitIfCheckFailed(changes, checkOnly);
}

function syncAdapters(config: MemoryConfig, commandArgs: string[]): void {
  const checkOnly = hasFlag(commandArgs, "check");
  const repos = getAllOptions(commandArgs, "repo").map((repo) => normalizePath(expandHome(repo)));
  const targets = repos.length > 0 ? repos : config.managedRepos;
  const changes: Change[] = [];

  if (targets.length === 0) {
    console.error("No managed repos configured. Use --repo /path or set managedRepos in Nix config.");
    process.exit(2);
  }

  for (const repo of targets) {
    syncRepo(repo, config, checkOnly, changes);
  }

  printChanges(changes);
  exitIfCheckFailed(changes, checkOnly);
}

async function appendEvent(config: MemoryConfig, commandArgs: string[]): Promise<void> {
  const scope = parseScope(getOption(commandArgs, "scope") ?? "repo");
  const type = getOption(commandArgs, "type") ?? "note";
  const title = getOption(commandArgs, "title") ?? type;
  const source = getOption(commandArgs, "source") ?? "agent-memory append";
  const repo = normalizePath(expandHome(getOption(commandArgs, "repo") ?? process.cwd()));
  const repoRoot = scope === "global" ? null : resolveGitRoot(repo);
  const root = repoRoot === null ? config.globalRepoPath : path.join(repoRoot, ".agent-memory");
  const sensitivity = parseSensitivity(getOption(commandArgs, "sensitivity") ?? "private");
  const body = hasFlag(commandArgs, "stdin") ? await Bun.stdin.text() : (getOption(commandArgs, "body") ?? "");
  const redactedBody = redactSecrets(body);
  const event: MemoryEvent = {
    version: VERSION,
    timestamp: new Date().toISOString(),
    scope,
    type,
    title: redactSecrets(title),
    body: redactedBody,
    repo: repoRoot,
    source: redactSecrets(source),
    sensitivity: redactedBody === body ? sensitivity : "secret-redacted",
  };

  const target = path.join(root, "inbox", "events.jsonl");
  ensurePrivateMemoryStorage(root);
  const releaseLock = await acquireInboxLock(root);
  try {
    hardenPrivateMemoryTree(root);
    appendJsonl(target, event);
  } finally {
    releaseLock();
  }
  console.log(`appended ${scope}/${type}: ${target}`);
}

async function harvest(config: MemoryConfig, commandArgs: string[]): Promise<void> {
  const repos = getAllOptions(commandArgs, "repo").map((repo) => normalizePath(expandHome(repo)));
  const targets = repos.length > 0 ? repos : config.managedRepos;
  const since = getOption(commandArgs, "since") ?? config.autoCapture?.since ?? "24h";
  const query = getOption(commandArgs, "query");
  const lens = getOption(commandArgs, "lens") ?? "recent";
  const dryRun = hasFlag(commandArgs, "dry-run");
  const retentionDays = parseOptionalPositiveInt(getOption(commandArgs, "retention-days"))
    ?? positiveIntegerOrDefault(config.autoCapture?.retentionDays, DEFAULT_RETENTION_DAYS);
  const maxEvents = parseOptionalPositiveInt(getOption(commandArgs, "max-events"))
    ?? positiveIntegerOrDefault(config.autoCapture?.maxEvents, DEFAULT_MAX_HARVEST_EVENTS);

  if (targets.length === 0) {
    console.error("No managed repos configured. Use --repo /path or set managedRepos in Nix config.");
    process.exit(2);
  }

  for (const repo of targets) {
    const repoRoot = resolveGitRoot(repo);
    const result = runRecentWorkContext(repoRoot, [
      "--profile", "agent",
      "--json",
      "--repo", repoRoot,
      "--since", since,
      "--lens", lens,
      ...(query === null ? [] : ["--query", query]),
    ]);

    if (!result.ok) {
      console.error(`harvest failed for ${repoRoot}: ${redactSecrets(result.stderr || result.stdout)}`);
      continue;
    }

    const now = new Date();
    const target = path.join(repoRoot, ".agent-memory", "inbox", "events.jsonl");
    const statePath = path.join(repoRoot, ".agent-memory", "inbox", "harvest-state.json");
    const payloadRedaction = redactSensitiveValue(safeJsonParse(result.stdout) ?? { raw: result.stdout });
    const payload = payloadRedaction.value;
    const observations = harvestObservations(payload);
    if (!dryRun) {
      ensurePrivateMemoryStorage(path.join(repoRoot, ".agent-memory"));
    }
    const releaseLock = dryRun ? null : await acquireInboxLock(path.join(repoRoot, ".agent-memory"));
    try {
      if (!dryRun) {
        hardenPrivateMemoryTree(path.join(repoRoot, ".agent-memory"));
      }
      const state = loadHarvestState(statePath, target);
      // The watermark is diagnostic only: unseen fingerprints stay eligible even when their source timestamp is older.
      const newFingerprints = new Set(
        observations
          .filter((observation) => state.seen[observation.fingerprint] === undefined)
          .map((observation) => observation.fingerprint),
      );
      const incrementalPayload = incrementalHarvestPayload(payload, newFingerprints, observations.length);
      const currentWatermark = observations.reduce<number | null>((watermark, observation) => {
        if (observation.timestamp === null) {
          return watermark;
        }

        return watermark === null ? observation.timestamp : Math.max(watermark, observation.timestamp);
      }, null);
      const nextState = updateHarvestState(
        state,
        observations,
        now,
        Math.max(retentionDays * DAY_MS, parseSinceDuration(since) * 2, 7 * DAY_MS),
        currentWatermark,
      );
      const event: MemoryEvent = {
        version: VERSION,
        timestamp: now.toISOString(),
        scope: "repo",
        type: "session-harvest",
        title: `Recent work harvest (${since})`,
        body: `Automated harvest from recent-work-context for ${repoRoot}. Distill durable lessons before promoting to decisions/patterns/pitfalls.`,
        repo: repoRoot,
        source: "recent-work-context",
        sensitivity: payloadRedaction.redacted ? "secret-redacted" : "private",
        payload: incrementalPayload,
      };

      if (dryRun) {
        if (newFingerprints.size === 0) {
          console.log(`no new observations for ${repoRoot}`);
        } else {
          console.log(JSON.stringify(event, null, 2));
        }
      } else {
        if (newFingerprints.size === 0) {
          console.log(`no new observations for ${repoRoot}`);
        } else {
          appendJsonl(target, event);
          console.log(`harvested ${newFingerprints.size} new observation(s) from ${repoRoot} -> ${target}`);
        }
        compactHarvestInbox(target, retentionDays, maxEvents, now);
        writePrivateFile(statePath, `${JSON.stringify(nextState, null, 2)}\n`);
      }
    } finally {
      releaseLock?.();
    }
  }
}

function distill(config: MemoryConfig, commandArgs: string[]): void {
  const scope = parseDistillScope(getOption(commandArgs, "scope") ?? "repo");
  const dryRun = hasFlag(commandArgs, "dry-run");
  const acceptSessionHarvest = hasFlag(commandArgs, "accept-session-harvest");
  const limit = parseOptionalPositiveInt(getOption(commandArgs, "limit"));
  const repo = normalizePath(expandHome(getOption(commandArgs, "repo") ?? process.cwd()));
  const memoryRoot = scope === "global" ? config.globalRepoPath : path.join(resolveGitRoot(repo), ".agent-memory");
  const eventsPath = getOption(commandArgs, "events") ?? path.join(memoryRoot, "inbox", "events.jsonl");
  const changes: Change[] = [];

  if (!existsSync(eventsPath)) {
    console.error(`Inbox not found: ${eventsPath}`);
    process.exit(1);
  }
  assertDirectory(memoryRoot);
  assertRegularFile(eventsPath);
  if (!dryRun) {
    ensurePrivateMemoryStorage(memoryRoot);
    hardenPrivateMemoryTree(memoryRoot);
  }

  const events = readMemoryEvents(eventsPath);
  const skippedSessionHarvests = acceptSessionHarvest
    ? 0
    : events.filter((event) => event.type === "session-harvest" && event.sensitivity !== "secret-redacted").length;
  const entries = events.flatMap((event) => distillEvent(event, scope, acceptSessionHarvest));
  const selectedEntries = limit === null ? entries : entries.slice(0, limit);

  if (skippedSessionHarvests > 0) {
    console.log(`Skipped ${skippedSessionHarvests} session-harvest event(s); review their provenance and pass --accept-session-harvest to promote them.`);
  }

  if (selectedEntries.length === 0) {
    console.log(`No distillable entries found in ${eventsPath}`);
    return;
  }

  for (const entry of selectedEntries) {
    const target = durableEntryPath(memoryRoot, entry);
    const markdown = renderDurableEntry(entry, target.relativePath);

    if (existsSync(target.absolutePath)) {
      changes.push({ path: target.absolutePath, action: "ok", message: "durable entry already exists" });
      continue;
    }

    if (dryRun) {
      changes.push({ path: target.absolutePath, action: "create", message: "would create durable entry" });
      continue;
    }

    writePrivateFile(target.absolutePath, markdown);
    changes.push({ path: target.absolutePath, action: "create", message: "durable entry created" });
  }

  if (!dryRun) {
    updateDistilledIndex(memoryRoot, scope, changes);
  }

  printChanges(changes);
}

function recall(commandArgs: string[]): void {
  const result = runRecentWorkContext(process.cwd(), ["--profile", "agent", ...commandArgs]);
  process.stdout.write(result.stdout);
  process.stderr.write(result.stderr);
  process.exit(result.status);
}

function lint(config: MemoryConfig, commandArgs: string[]): void {
  const includeGlobal = hasFlag(commandArgs, "global") || !hasFlag(commandArgs, "repos");
  const includeRepos = hasFlag(commandArgs, "repos") || !hasFlag(commandArgs, "global");
  const requestedRepos = getAllOptions(commandArgs, "repo").map((repo) => normalizePath(expandHome(repo)));
  const targetRepos = requestedRepos.length > 0 ? requestedRepos : config.managedRepos;
  const changes: Change[] = [];

  if (includeGlobal) {
    lintRoot(config.globalRepoPath, false, changes);
  }

  if (includeRepos) {
    for (const repo of targetRepos) {
      lintRoot(path.join(repo, ".agent-memory"), true, changes);
    }
  }

  printChanges(changes);

  if (changes.some((change) => change.action === "missing" || change.action === "error")) {
    process.exit(1);
  }
}

function syncRepo(repoInput: string, config: MemoryConfig, checkOnly: boolean, changes: Change[]): void {
  const repo = resolveGitRoot(repoInput);
  const memoryRoot = path.join(repo, ".agent-memory");
  const directories = [
    memoryRoot,
    path.join(memoryRoot, "inbox"),
    path.join(memoryRoot, "decisions"),
    path.join(memoryRoot, "patterns"),
    path.join(memoryRoot, "pitfalls"),
    path.join(memoryRoot, "handoffs"),
    path.join(memoryRoot, "commands"),
    path.join(memoryRoot, "constraints"),
    path.join(memoryRoot, "lessons"),
    path.join(memoryRoot, "preferences"),
  ];
  if (!preflightPrivateDirectories(directories, changes)) {
    return;
  }
  for (const directory of directories) {
    ensureDirectory(directory, checkOnly, changes);
  }
  ensureFile(path.join(memoryRoot, "SCHEMA.md"), repoSchemaTemplate(config), checkOnly, changes);
  ensureFile(path.join(memoryRoot, "index.md"), repoIndexTemplate(repo, config), checkOnly, changes);
  ensureFile(path.join(memoryRoot, "inbox", "events.jsonl"), "", checkOnly, changes);

  if (config.adapters?.generic !== false) {
    upsertBlock(path.join(repo, "AGENTS.md"), "# Agent Instructions\n", genericAdapterBlock(config), checkOnly, changes);
  }

  if (config.adapters?.copilot !== false) {
    upsertBlock(path.join(repo, ".github", "copilot-instructions.md"), "# Copilot Instructions\n", copilotAdapterBlock(config), checkOnly, changes);
  }

  if (config.adapters?.cursor !== false) {
    upsertCursorRule(path.join(repo, ".cursor", "rules", "agent-memory.mdc"), cursorRuleTemplate(config), checkOnly, changes);
  }

  if (config.adapters?.claude !== false) {
    upsertBlock(path.join(repo, ".claude", "CLAUDE.md"), "# Claude Project Instructions\n", claudeAdapterBlock(config), checkOnly, changes);
    upsertTextFile(
      path.join(repo, ".claude", "agents", "memory-distiller.md"),
      claudeMemoryDistillerAgentTemplate(),
      checkOnly,
      changes,
      "Claude memory distiller up to date",
      "Claude memory distiller missing",
      "Claude memory distiller created",
      "Claude memory distiller updated",
    );
    upsertClaudeAgentRegistry(path.join(repo, ".claude", "agent-registry.json"), checkOnly, changes);
  }

  if (config.adapters?.opencode !== false) {
    upsertTextFile(
      path.join(repo, ".opencode", "agents", "memory-distiller.md"),
      opencodeMemoryDistillerAgentTemplate(),
      checkOnly,
      changes,
      "OpenCode memory distiller up to date",
      "OpenCode memory distiller missing",
      "OpenCode memory distiller created",
      "OpenCode memory distiller updated",
    );
  }
}

function lintRoot(root: string, isRepoMemoryRoot: boolean, changes: Change[]): void {
  if (!existsSync(root)) {
    changes.push({ path: root, action: "missing", message: "memory root missing" });
    return;
  }

  const schemaPath = path.join(root, "SCHEMA.md");
  const indexPath = path.join(root, "index.md");
  const eventsPath = path.join(root, "inbox", "events.jsonl");
  changes.push(checkFile(schemaPath, "schema"));
  changes.push(checkFile(indexPath, "index"));
  changes.push(checkFile(eventsPath, "event inbox"));

  if (existsSync(eventsPath)) {
    const lines = readFileSync(eventsPath, "utf8").split(/\r?\n/).filter((line) => line.trim().length > 0);
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      if (line === undefined || safeJsonParse(line) === null) {
        changes.push({ path: `${eventsPath}:${index + 1}`, action: "error", message: "invalid JSONL event" });
      }
    }
  }

  if (isRepoMemoryRoot) {
    for (const dir of ["decisions", "patterns", "pitfalls", "handoffs", "commands", "constraints", "lessons", "preferences"]) {
      const dirPath = path.join(root, dir);
      if (!existsSync(dirPath)) {
        changes.push({ path: dirPath, action: "missing", message: `repo memory directory missing: ${dir}` });
      }
    }
  }
}

function loadHarvestState(statePath: string, eventsPath: string): HarvestState {
  assertRegularFileOrMissing(statePath);
  assertRegularFileOrMissing(eventsPath);
  if (existsSync(statePath)) {
    const parsed = safeJsonParse(readFileSync(statePath, "utf8"));
    if (isRecord(parsed) && parsed.version === HARVEST_STATE_VERSION && isRecord(parsed.seen)) {
      const seen = Object.fromEntries(
        Object.entries(parsed.seen)
          .filter((entry): entry is [string, string] => typeof entry[1] === "string"),
      );
      const watermark = typeof parsed.watermark === "number" && Number.isFinite(parsed.watermark)
        ? parsed.watermark
        : null;
      return {
        version: HARVEST_STATE_VERSION,
        watermark,
        seen,
      };
    }

    console.error(`warning: invalid harvest state; rebuilding from ${eventsPath}`);
  }

  const state: HarvestState = {
    version: HARVEST_STATE_VERSION,
    watermark: null,
    seen: {},
  };
  if (!existsSync(eventsPath)) {
    return state;
  }

  for (const line of readFileSync(eventsPath, "utf8").split(/\r?\n/)) {
    const event = safeJsonParse(line);
    if (!isRecord(event) || event.type !== "session-harvest") {
      continue;
    }

    const observedAt = validIsoTimestamp(event.timestamp) ?? new Date(0).toISOString();
    const payload = redactSensitiveValue(event.payload).value;
    for (const observation of harvestObservations(payload)) {
      state.seen[observation.fingerprint] = observedAt;
      if (observation.timestamp !== null) {
        state.watermark = state.watermark === null
          ? observation.timestamp
          : Math.max(state.watermark, observation.timestamp);
      }
    }
  }

  return state;
}

function updateHarvestState(
  state: HarvestState,
  observations: HarvestObservation[],
  now: Date,
  retentionMs: number,
  currentWatermark: number | null,
): HarvestState {
  const nowIso = now.toISOString();
  const cutoff = now.getTime() - retentionMs;
  const seen = { ...state.seen };

  for (const observation of observations) {
    seen[observation.fingerprint] = nowIso;
  }

  // Keep the exact cache for at least twice the sliding source window. A count cap could evict an
  // old fingerprint and make it indistinguishable from a genuinely late observation.
  const retained = Object.entries(seen)
    .filter(([, observedAt]) => {
      const observedAtMs = Date.parse(observedAt);
      return Number.isFinite(observedAtMs) && observedAtMs >= cutoff;
    })
    .sort((left, right) => Date.parse(right[1]) - Date.parse(left[1]));

  return {
    version: HARVEST_STATE_VERSION,
    watermark: currentWatermark === null
      ? state.watermark
      : state.watermark === null
        ? currentWatermark
        : Math.max(state.watermark, currentWatermark),
    seen: Object.fromEntries(retained),
  };
}

function harvestObservations(payload: unknown): HarvestObservation[] {
  if (!isRecord(payload)) {
    return [{
      fingerprint: `payload:${fullHash(stableSerialize(payload))}`,
      timestamp: null,
    }];
  }

  const observations: HarvestObservation[] = [];
  if (Array.isArray(payload.records)) {
    observations.push(...payload.records.map((record) => ({
      fingerprint: harvestRecordFingerprint(record),
      timestamp: isRecord(record) && typeof record.timestamp === "number" && Number.isFinite(record.timestamp)
        ? record.timestamp
        : null,
    })));
  }

  const summary = isRecord(payload.summary) ? payload.summary : null;
  if (summary !== null) {
    for (const field of harvestSummaryFields()) {
      if (!Array.isArray(summary[field])) {
        continue;
      }

      observations.push(...summary[field].map((item) => ({
        fingerprint: harvestSummaryFingerprint(field, item),
        timestamp: field === "sessions" && isRecord(item) && typeof item.latestTimestamp === "number" && Number.isFinite(item.latestTimestamp)
          ? item.latestTimestamp
          : null,
      })));
    }
  }

  return observations.length > 0 ? observations : [{
    fingerprint: `payload:${fullHash(stableSerialize(payload))}`,
    timestamp: null,
  }];
}

function harvestRecordFingerprint(record: unknown): string {
  if (!isRecord(record)) {
    return `record:${fullHash(stableSerialize(record))}`;
  }

  const identity = {
    source: record.source,
    sessionId: record.sessionId,
    timestamp: record.timestamp,
    role: record.role,
    kind: record.kind,
    text: record.text,
    files: record.files,
    tool: record.tool,
    branch: record.branch,
    citation: record.citation,
    repoPath: record.repoPath,
  };
  return `record:${fullHash(stableSerialize(identity))}`;
}

function harvestSummaryFields(): string[] {
  return ["decisions", "preferences", "relevantFiles", "changedAreas", "failuresAndFixes", "sessions"];
}

function harvestSummaryFingerprint(field: string, item: unknown): string {
  return `summary:${field}:${fullHash(stableSerialize(item))}`;
}

function incrementalHarvestPayload(payload: unknown, newFingerprints: Set<string>, windowObservations: number): unknown {
  if (!isRecord(payload) || !Array.isArray(payload.records)) {
    return payload;
  }

  const sourceSummary = isRecord(payload.summary) ? payload.summary : null;
  const hasSummaryObservations = sourceSummary !== null && harvestSummaryFields().some(
    (field) => Array.isArray(sourceSummary[field]) && sourceSummary[field].length > 0,
  );
  if (payload.records.length === 0 && !hasSummaryObservations) {
    return payload;
  }

  const records = payload.records.filter((record) => newFingerprints.has(harvestRecordFingerprint(record)));
  const citations = new Set(
    records
      .map((record) => isRecord(record) ? asString(record.citation) : null)
      .filter((citation): citation is string => citation !== null),
  );
  const summary = filterHarvestSummary(payload.summary, newFingerprints, citations);

  return {
    ...payload,
    records,
    summary,
    agentContext: filterHarvestAgentContext(payload.agentContext, summary, citations),
    counts: incrementalHarvestCounts(payload.counts, records),
    harvest: {
      incremental: true,
      newObservations: newFingerprints.size,
      windowObservations,
    },
  };
}

function filterHarvestSummary(
  summaryValue: unknown,
  newFingerprints: Set<string>,
  recordCitations: Set<string>,
): Record<string, unknown> {
  const summary = isRecord(summaryValue) ? summaryValue : {};
  return {
    ...summary,
    overview: [],
    decisions: filterHarvestSummaryItems("decisions", summary.decisions, newFingerprints, recordCitations),
    preferences: filterHarvestSummaryItems("preferences", summary.preferences, newFingerprints, recordCitations),
    relevantFiles: filterHarvestSummaryItems("relevantFiles", summary.relevantFiles, newFingerprints, recordCitations),
    changedAreas: filterHarvestSummaryItems("changedAreas", summary.changedAreas, newFingerprints, recordCitations),
    failuresAndFixes: filterHarvestSummaryItems("failuresAndFixes", summary.failuresAndFixes, newFingerprints, recordCitations),
    sessions: filterHarvestSummaryItems("sessions", summary.sessions, newFingerprints, recordCitations),
  };
}

function filterHarvestSummaryItems(
  field: string,
  value: unknown,
  newFingerprints: Set<string>,
  recordCitations: Set<string>,
): unknown[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((item) => {
    if (newFingerprints.has(harvestSummaryFingerprint(field, item))) {
      return true;
    }

    return isRecord(item)
      && Array.isArray(item.citations)
      && item.citations.some((citation) => typeof citation === "string" && recordCitations.has(citation));
  });
}

function filterHarvestAgentContext(
  agentContextValue: unknown,
  summary: Record<string, unknown>,
  citations: Set<string>,
): Record<string, unknown> {
  const agentContext = isRecord(agentContextValue) ? agentContextValue : {};
  const textValues = (value: unknown): string[] => Array.isArray(value)
    ? value.flatMap((item) => isRecord(item) && typeof item.text === "string" ? [item.text] : [])
    : [];
  const pathValues = (value: unknown): string[] => Array.isArray(value)
    ? value.flatMap((item) => isRecord(item) && typeof item.path === "string" ? [item.path] : [])
    : [];

  return {
    ...agentContext,
    overview: [],
    decisions: textValues(summary.decisions),
    preferences: textValues(summary.preferences),
    relevantFiles: pathValues(summary.relevantFiles),
    changedAreas: pathValues(summary.changedAreas),
    failuresAndFixes: textValues(summary.failuresAndFixes),
    sessions: Array.isArray(summary.sessions) ? summary.sessions : [],
    topCitations: collectSummaryCitations(summary, citations),
  };
}

function collectSummaryCitations(summary: Record<string, unknown>, recordCitations: Set<string>): string[] {
  const citations = new Set(recordCitations);
  for (const field of harvestSummaryFields()) {
    const items = summary[field];
    if (!Array.isArray(items)) {
      continue;
    }

    for (const item of items) {
      if (!isRecord(item) || !Array.isArray(item.citations)) {
        continue;
      }
      for (const citation of item.citations) {
        if (typeof citation === "string") {
          citations.add(citation);
        }
      }
    }
  }

  return Array.from(citations).slice(0, 16);
}

function incrementalHarvestCounts(countsValue: unknown, records: unknown[]): Record<string, unknown> {
  const counts = isRecord(countsValue) ? countsValue : {};
  const sourceCount = (source: string): number => records.filter(
    (record) => isRecord(record) && record.source === source,
  ).length;
  const sourceSessions = (source: string): number => new Set(
    records.flatMap((record) => isRecord(record) && record.source === source && typeof record.sessionId === "string"
      ? [record.sessionId]
      : []),
  ).size;

  return {
    ...counts,
    total: records.length,
    matchedTotal: records.length,
    matchedSessions: new Set(records.flatMap((record) => isRecord(record) && typeof record.sessionId === "string" ? [record.sessionId] : [])).size,
    focusedSessions: new Set(records.flatMap((record) => isRecord(record) && typeof record.sessionId === "string" ? [record.sessionId] : [])).size,
    bySource: {
      "claude-code": sourceCount("claude-code"),
      opencode: sourceCount("opencode"),
    },
    sessionsBySource: {
      "claude-code": sourceSessions("claude-code"),
      opencode: sourceSessions("opencode"),
    },
  };
}

function compactHarvestInbox(target: string, retentionDays: number, maxEvents: number, now: Date): void {
  assertRegularFileOrMissing(target);
  if (!existsSync(target)) {
    writePrivateFile(target, "");
    return;
  }

  const cutoff = now.getTime() - retentionDays * DAY_MS;
  const current = readFileSync(target, "utf8");
  const lines = current
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0)
    .map((line, index) => {
      const parsed = safeJsonParse(line);
      if (!isRecord(parsed)) {
        return {
          index,
          serialized: redactSecrets(line),
          isHarvest: false,
          retainedByAge: true,
        };
      }

      const redaction = redactSensitiveValue(parsed);
      const event = isRecord(redaction.value) ? { ...redaction.value } : parsed;
      if (redaction.redacted) {
        event.sensitivity = "secret-redacted";
      }
      const timestamp = typeof event.timestamp === "string" ? Date.parse(event.timestamp) : Number.NaN;
      return {
        index,
        serialized: JSON.stringify(event),
        isHarvest: event.type === "session-harvest",
        retainedByAge: !Number.isFinite(timestamp) || timestamp >= cutoff,
      };
    });

  const retainedHarvestIndexes = new Set(
    lines
      .filter((line) => line.isHarvest && line.retainedByAge)
      .slice(-maxEvents)
      .map((line) => line.index),
  );
  // Manual append events are durable candidates; retention applies only to replaceable automatic harvests.
  const compacted = lines
    .filter((line) => !line.isHarvest || retainedHarvestIndexes.has(line.index))
    .map((line) => line.serialized)
    .join("\n");
  const next = compacted.length > 0 ? `${compacted}\n` : "";
  if (next === current) {
    chmodSync(target, PRIVATE_FILE_MODE);
  } else {
    writePrivateFile(target, next);
  }
}

function readMemoryEvents(eventsPath: string): MemoryEvent[] {
  return readFileSync(eventsPath, "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line, index) => {
      const parsed = safeJsonParse(line);
      if (!isRecord(parsed)) {
        throw new Error(`Invalid event at ${eventsPath}:${index + 1}`);
      }

      return normalizeMemoryEvent(parsed, eventsPath, index + 1);
    });
}

function normalizeMemoryEvent(raw: Record<string, unknown>, eventsPath: string, line: number): MemoryEvent {
  const timestamp = asString(raw.timestamp) ?? new Date(0).toISOString();
  const scope = raw.scope === "global" || raw.scope === "repo" || raw.scope === "session" ? raw.scope : "repo";
  const type = asString(raw.type) ?? "note";
  const title = asString(raw.title) ?? type;
  const body = asString(raw.body) ?? "";
  const source = asString(raw.source) ?? `${eventsPath}:${line}`;
  const repo = asString(raw.repo);
  const sensitivity = raw.sensitivity === "public" || raw.sensitivity === "private" || raw.sensitivity === "sensitive" || raw.sensitivity === "secret-redacted"
    ? raw.sensitivity
    : "private";

  return {
    version: asString(raw.version) ?? VERSION,
    timestamp,
    scope,
    type,
    title,
    body,
    repo,
    source,
    sensitivity,
    payload: raw.payload,
  };
}

function distillEvent(
  event: MemoryEvent,
  requestedScope: Exclude<MemoryScope, "session">,
  acceptSessionHarvest: boolean,
): DistilledEntry[] {
  if (event.sensitivity === "secret-redacted") {
    return [createDistilledEntry({
      type: "pitfall",
      scope: requestedScope,
      title: `Secret-like content redacted from ${event.type}`,
      summary: "An inbox event contained credential-like content and was redacted before durable promotion.",
      guidance: [
        "Do not promote raw credential-like content into durable memory.",
        "Review the source event manually if more context is needed.",
      ],
      evidence: [event.source, event.timestamp],
      source: event.source,
      tags: ["security", "redaction"],
      created: dateFromTimestamp(event.timestamp),
    })];
  }

  if (event.type === "session-harvest" && !acceptSessionHarvest) {
    return [];
  }

  const durableType = parseDurableType(event.type);
  if (durableType !== null && event.body.trim().length > 0) {
    return [createDistilledEntry({
      type: durableType,
      scope: requestedScope,
      title: event.title,
      summary: truncate(redactSecrets(event.body), 700),
      guidance: splitGuidance(event.body),
      evidence: compactStrings([event.source, event.repo, event.timestamp]),
      source: event.source,
      tags: [durableType, "append"],
      created: dateFromTimestamp(event.timestamp),
    })];
  }

  if (event.type === "session-harvest") {
    return distillSessionHarvest(event, requestedScope);
  }

  if (event.body.trim().length > 0) {
    return [createDistilledEntry({
      type: "handoff",
      scope: requestedScope,
      title: event.title,
      summary: truncate(redactSecrets(event.body), 700),
      guidance: splitGuidance(event.body),
      evidence: compactStrings([event.source, event.repo, event.timestamp]),
      source: event.source,
      tags: ["inbox", event.type],
      created: dateFromTimestamp(event.timestamp),
    })];
  }

  return [];
}

function distillSessionHarvest(event: MemoryEvent, requestedScope: Exclude<MemoryScope, "session">): DistilledEntry[] {
  const payload = isRecord(event.payload) ? event.payload : null;
  const agentContext = isRecord(payload?.agentContext) ? payload.agentContext : null;
  if (agentContext === null) {
    return [];
  }

  const topCitations = asStringArray(agentContext.topCitations).slice(0, 8);
  const overview = asStringArray(agentContext.overview).slice(0, 8).filter((line) => !isLowSignalHarvestOverview(line));
  const sessionSynopses = extractSessionSynopses(agentContext.sessions).slice(0, 8);
  const entries: DistilledEntry[] = [];
  const created = dateFromTimestamp(event.timestamp);
  const evidence = compactStrings([event.source, event.repo, event.timestamp, ...topCitations]);

  const decisions = asStringArray(agentContext.decisions).slice(0, 12);
  if (decisions.length > 0) {
    entries.push(createDistilledEntry({
      type: "decision",
      scope: requestedScope,
      title: `Distilled decisions from recent session context`,
      summary: firstSentence(decisions[0] ?? "Prior sessions contain decision-like context."),
      guidance: decisions,
      evidence,
      source: event.source,
      tags: ["session-harvest", "decisions"],
      created,
    }));
  }

  const preferences = asStringArray(agentContext.preferences).slice(0, 12);
  if (preferences.length > 0) {
    entries.push(createDistilledEntry({
      type: "preference",
      scope: requestedScope,
      title: `Distilled preferences from recent session context`,
      summary: firstSentence(preferences[0] ?? "Prior sessions contain preference-like context."),
      guidance: preferences,
      evidence,
      source: event.source,
      tags: ["session-harvest", "preferences"],
      created,
    }));
  }

  const failuresAndFixes = asStringArray(agentContext.failuresAndFixes).slice(0, 12);
  if (failuresAndFixes.length > 0) {
    entries.push(createDistilledEntry({
      type: "pitfall",
      scope: requestedScope,
      title: `Distilled failures and fixes from recent session context`,
      summary: firstSentence(failuresAndFixes[0] ?? "Prior sessions contain failure/fix context."),
      guidance: failuresAndFixes,
      evidence,
      source: event.source,
      tags: ["session-harvest", "failures", "fixes"],
      created,
    }));
  }

  const relevantFiles = asStringArray(agentContext.relevantFiles).slice(0, 12);
  const changedAreas = asStringArray(agentContext.changedAreas).slice(0, 12);
  const handoffGuidance = compactStrings([
    ...overview,
    ...sessionSynopses,
    ...changedAreas.map((area) => `Changed area: ${area}`),
    ...relevantFiles.map((file) => `Relevant file: ${file}`),
  ]).slice(0, 24);
  if (handoffGuidance.length > 0) {
    entries.push(createDistilledEntry({
      type: "handoff",
      scope: requestedScope,
      title: `Distilled handoff from recent session context`,
      summary: firstSentence(handoffGuidance[0] ?? "Recent session context is available for future work."),
      guidance: handoffGuidance,
      evidence,
      source: event.source,
      tags: ["session-harvest", "handoff"],
      created,
    }));
  }

  return entries;
}

function createDistilledEntry(
  input: Omit<DistilledEntry, "hash" | "trust"> & { trust?: DistilledEntry["trust"] },
): DistilledEntry {
  const fromAcceptedHarvest = input.tags.includes("session-harvest");
  const normalized = {
    type: input.type,
    scope: input.scope,
    title: redactSecrets(input.title),
    summary: redactSecrets(input.summary),
    guidance: input.guidance.map(redactSecrets).filter((item) => item.trim().length > 0),
    evidence: input.evidence.map(redactSecrets).filter((item) => item.trim().length > 0),
    source: redactSecrets(input.source),
    tags: unique([...input.tags, ...(fromAcceptedHarvest ? ["harvest-accepted"] : [])].map((tag) => slugify(tag)).filter((tag) => tag.length > 0)),
    created: input.created,
    trust: input.trust ?? (fromAcceptedHarvest ? "harvest-accepted" : "explicit"),
  };

  return {
    ...normalized,
    hash: shortHash(JSON.stringify(normalized)),
  };
}

function durableEntryPath(memoryRoot: string, entry: DistilledEntry): { absolutePath: string; relativePath: string } {
  const directory = durableDirectory(entry.scope, entry.type);
  const filename = `${entry.created}-${slugify(entry.title)}-${entry.hash}.md`;
  const relativePath = path.join(directory, filename);
  return {
    absolutePath: path.join(memoryRoot, relativePath),
    relativePath,
  };
}

function durableDirectory(scope: Exclude<MemoryScope, "session">, type: DurableEntryType): string {
  const directoryByType: Record<DurableEntryType, string> = {
    decision: "decisions",
    pattern: "patterns",
    pitfall: "pitfalls",
    command: "commands",
    constraint: "constraints",
    handoff: "handoffs",
    lesson: "lessons",
    preference: "preferences",
  };
  const directory = directoryByType[type];
  return scope === "global" ? path.join("global", directory) : directory;
}

function renderDurableEntry(entry: DistilledEntry, relativePath: string): string {
  return `---
title: "${escapeYamlString(entry.title)}"
type: ${entry.type}
scope: ${entry.scope}
status: active
created: ${entry.created}
updated: ${entry.created}
trust: ${entry.trust}
source: "${escapeYamlString(entry.source)}"
provenance:
${entry.evidence.length > 0 ? entry.evidence.map((item) => `  - "${escapeYamlString(item)}"`).join("\n") : "  []"}
tags: [${entry.tags.join(", ")}]
distillation_hash: ${entry.hash}
---

# ${entry.title}

## Summary

${entry.summary}

## Guidance for future agents

${renderBullets(entry.guidance)}

## Evidence / provenance

${renderBullets(entry.evidence)}

## File

${relativePath}

## Supersedes

None.

## Superseded by

None.
`;
}

function updateDistilledIndex(memoryRoot: string, scope: Exclude<MemoryScope, "session">, changes: Change[]): void {
  const indexPath = path.join(memoryRoot, "index.md");
  if (!existsSync(indexPath)) {
    return;
  }

  const entries = listDurableEntries(memoryRoot, scope);
  const block = `${DISTILLED_INDEX_START}\n## Distilled Memory\n\n${entries.length > 0 ? entries.map((entry) => `- [${entry.title}](${entry.relativePath}) — ${entry.type}`).join("\n") : "No distilled entries yet."}\n${DISTILLED_INDEX_END}\n`;
  const current = readFileSync(indexPath, "utf8");
  const next = replaceOrAppendBlock(current, DISTILLED_INDEX_START, DISTILLED_INDEX_END, block);
  if (next !== current) {
    writePrivateFile(indexPath, next);
    changes.push({ path: indexPath, action: "update", message: "distilled index updated" });
  }
}

function listDurableEntries(memoryRoot: string, scope: Exclude<MemoryScope, "session">): Array<{ relativePath: string; title: string; type: DurableEntryType }> {
  const entries: Array<{ relativePath: string; title: string; type: DurableEntryType }> = [];
  for (const type of DURABLE_ENTRY_TYPES) {
    const directory = path.join(memoryRoot, durableDirectory(scope, type));
    if (!existsSync(directory)) {
      continue;
    }

    for (const file of readdirSync(directory)) {
      if (!file.endsWith(".md")) {
        continue;
      }

      const absolutePath = path.join(directory, file);
      if (!statSync(absolutePath).isFile()) {
        continue;
      }

      const relativePath = path.relative(memoryRoot, absolutePath);
      entries.push({
        relativePath,
        title: extractMarkdownTitle(absolutePath) ?? file.replace(/\.md$/, ""),
        type,
      });
    }
  }

  return entries.sort((left, right) => left.relativePath.localeCompare(right.relativePath));
}

function extractMarkdownTitle(filePath: string): string | null {
  const raw = readFileSync(filePath, "utf8");
  const frontmatterTitle = /^title:\s*["']?([^"'\n]+)["']?$/m.exec(raw)?.[1];
  if (frontmatterTitle !== undefined) {
    return frontmatterTitle.trim();
  }

  const heading = /^#\s+(.+)$/m.exec(raw)?.[1];
  return heading?.trim() ?? null;
}

function parseDistillScope(value: string): Exclude<MemoryScope, "session"> {
  if (value === "repo" || value === "global") {
    return value;
  }

  throw new Error(`Invalid --scope '${value}'. Expected repo or global.`);
}

function parseDurableType(value: string): DurableEntryType | null {
  return DURABLE_ENTRY_TYPES.includes(value as DurableEntryType) ? value as DurableEntryType : null;
}

function parseOptionalPositiveInt(value: string | null): number | null {
  if (value === null) {
    return null;
  }

  if (!/^[1-9][0-9]*$/.test(value)) {
    throw new Error(`Invalid positive integer: ${value}`);
  }

  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) {
    throw new Error(`Invalid positive integer: ${value}`);
  }

  return parsed;
}

function positiveIntegerOrDefault(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isInteger(value) && value > 0 ? value : fallback;
}

function parseSinceDuration(value: string): number {
  const match = /^(\d+)([smhdw])$/.exec(value.trim());
  if (match === null) {
    return DAY_MS;
  }

  const amount = Number.parseInt(match[1] ?? "1", 10);
  const unit = match[2] ?? "d";
  const unitMs: Record<string, number> = {
    s: 1000,
    m: 60 * 1000,
    h: 60 * 60 * 1000,
    d: DAY_MS,
    w: 7 * DAY_MS,
  };
  return amount * (unitMs[unit] ?? DAY_MS);
}

function validIsoTimestamp(value: unknown): string | null {
  if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) {
    return null;
  }

  return new Date(value).toISOString();
}

function splitGuidance(body: string): string[] {
  const lines = body
    .split(/\r?\n/)
    .map((line) => line.replace(/^\s*[-*]\s+/, "").trim())
    .filter((line) => line.length > 0);

  if (lines.length > 0) {
    return lines.slice(0, 12);
  }

  return [truncate(body.trim(), 500)].filter((line) => line.length > 0);
}

function asString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function asStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string").map((item) => item.trim()).filter((item) => item.length > 0)
    : [];
}

function extractSessionSynopses(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((item) => {
    if (!isRecord(item)) {
      return [];
    }

    const synopsis = asString(item.synopsis)?.trim();
    if (synopsis === undefined || synopsis.length === 0) {
      return [];
    }

    const prefix = compactStrings([asString(item.source), asString(item.sessionId)]).join(" ");
    return [prefix.length > 0 ? `${prefix}: ${synopsis}` : synopsis];
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function compactStrings(values: Array<string | null | undefined>): string[] {
  return values.map((value) => value?.trim() ?? "").filter((value) => value.length > 0);
}

function firstSentence(value: string): string {
  const normalized = value.trim();
  const sentence = normalized.match(/^(.{1,220}?[.!?])\s/)?.[1];
  return truncate(sentence ?? normalized, 260);
}

function isLowSignalHarvestOverview(value: string): boolean {
  const normalized = value.trim().toLowerCase();
  return /^matched \d+ ranked excerpts across \d+ sessions?\.?$/.test(normalized)
    || /^focused summary covers the top \d+ sessions? by relevance\.?$/.test(normalized)
    || /^most recent strong match: /.test(normalized);
}

function renderBullets(items: string[]): string {
  return items.length > 0 ? items.map((item) => `- ${item}`).join("\n") : "None.";
}

function escapeYamlString(value: string): string {
  return value.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
}

function slugify(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 72) || "entry";
}

function shortHash(value: string): string {
  return createHash("sha256").update(value).digest("hex").slice(0, 10);
}

function fullHash(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function stableSerialize(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(stableSerialize).join(",")}]`;
  }

  if (isRecord(value)) {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableSerialize(value[key])}`)
      .join(",")}}`;
  }

  return JSON.stringify(value) ?? "null";
}

function dateFromTimestamp(timestamp: string): string {
  const parsed = new Date(timestamp);
  if (Number.isNaN(parsed.getTime())) {
    return today();
  }

  return parsed.toISOString().slice(0, 10);
}

function replaceOrAppendBlock(current: string, startMarker: string, endMarker: string, block: string): string {
  const start = current.indexOf(startMarker);
  const end = current.indexOf(endMarker);
  if (start >= 0 && end > start) {
    const before = current.slice(0, start);
    const after = current.slice(end + endMarker.length).replace(/^\n+/, "");
    return `${before}${block}${after}`.replace(/\n{3,}/g, "\n\n");
  }

  return `${current.replace(/\s+$/, "")}\n\n${block}`;
}

function truncate(value: string, maxLength: number): string {
  return value.length <= maxLength ? value : `${value.slice(0, maxLength - 1)}…`;
}

function runRecentWorkContext(repo: string, commandArgs: string[]): CommandResult {
  const commandPath = findRecentWorkContextCommand();
  if (commandPath === null) {
    return {
      ok: false,
      status: 127,
      stdout: "",
      stderr: "recent-work-context command/script not found",
    };
  }

  if (commandPath.endsWith(".ts")) {
    const result = spawnSync(process.execPath || "bun", [commandPath, ...commandArgs], { cwd: repo, encoding: "utf8" });
    return commandResult(result.status ?? 1, result.stdout, result.stderr, result.error);
  }

  const result = spawnSync(commandPath, commandArgs, { cwd: repo, encoding: "utf8" });
  return commandResult(result.status ?? 1, result.stdout, result.stderr, result.error);
}

function findRecentWorkContextCommand(): string | null {
  const bundledScript = path.join(homedir(), ".claude", "skills", "recent-work-context", "scripts", "recent-work-context.ts");
  if (existsSync(bundledScript)) {
    return bundledScript;
  }

  for (const directory of (process.env.PATH ?? "").split(path.delimiter)) {
    if (directory.length === 0) {
      continue;
    }
    const candidate = path.join(directory, "recent-work-context");
    try {
      accessSync(candidate, fsConstants.X_OK);
      return candidate;
    } catch {
      // Continue through PATH just like execvp; missing and non-executable candidates are ignored.
    }
  }

  return null;
}

function commandResult(status: number, stdout: string | Buffer | null, stderr: string | Buffer | null, error?: Error): CommandResult {
  return {
    ok: status === 0,
    status,
    stdout: stdout?.toString() ?? "",
    stderr: stderr?.toString() || error?.message || "",
  };
}

function checkDirectory(target: string, label: string): Change {
  if (!existsSync(target)) {
    return { path: target, action: "missing", message: `${label} missing` };
  }

  if (!statSync(target).isDirectory()) {
    return { path: target, action: "error", message: `${label} is not a directory` };
  }

  return { path: target, action: "ok", message: `${label} exists` };
}

function checkFile(target: string, label: string): Change {
  if (!existsSync(target)) {
    return { path: target, action: "missing", message: `${label} missing` };
  }

  if (!statSync(target).isFile()) {
    return { path: target, action: "error", message: `${label} is not a file` };
  }

  return { path: target, action: "ok", message: `${label} exists` };
}

function checkGitRepo(target: string): Change {
  const result = spawnSync("git", ["-C", target, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
  if (result.status !== 0) {
    return { path: target, action: "missing", message: "git repo missing or inaccessible" };
  }

  return { path: result.stdout.trim(), action: "ok", message: "git repo available" };
}

function preflightPrivateDirectories(targets: string[], changes: Change[]): boolean {
  for (const target of targets) {
    const stats = lstatIfExists(target);
    if (stats === null) {
      continue;
    }
    if (stats.isSymbolicLink()) {
      changes.push({
        path: target,
        action: "error",
        message: "expected private directory is a symbolic link",
      });
      return false;
    }
    if (!stats.isDirectory()) {
      changes.push({
        path: target,
        action: "error",
        message: "expected private directory is not a directory",
      });
      return false;
    }
  }

  return true;
}

function ensureDirectory(target: string, checkOnly: boolean, changes: Change[]): void {
  const stats = lstatIfExists(target);
  if (stats !== null) {
    if (stats.isSymbolicLink() || !stats.isDirectory()) {
      changes.push({ path: target, action: "error", message: "path exists but is not a regular directory" });
      return;
    }

    if (fileMode(target) !== PRIVATE_DIRECTORY_MODE) {
      if (checkOnly) {
        changes.push({ path: target, action: "update", message: "directory permissions would become 0700" });
      } else {
        chmodSync(target, PRIVATE_DIRECTORY_MODE);
        changes.push({ path: target, action: "update", message: "directory permissions set to 0700" });
      }
      return;
    }

    changes.push({ path: target, action: "ok", message: "private directory exists" });
    return;
  }

  if (checkOnly) {
    changes.push({ path: target, action: "missing", message: "directory missing" });
    return;
  }

  mkdirSync(target, { recursive: true, mode: PRIVATE_DIRECTORY_MODE });
  chmodSync(target, PRIVATE_DIRECTORY_MODE);
  changes.push({ path: target, action: "create", message: "private directory created" });
}

function ensureFile(target: string, content: string, checkOnly: boolean, changes: Change[]): void {
  const stats = lstatIfExists(target);
  if (stats !== null) {
    if (stats.isSymbolicLink() || !stats.isFile()) {
      changes.push({ path: target, action: "error", message: "path exists but is not a regular file" });
      return;
    }

    if (fileMode(target) !== PRIVATE_FILE_MODE) {
      if (checkOnly) {
        changes.push({ path: target, action: "update", message: "file permissions would become 0600" });
      } else {
        chmodSync(target, PRIVATE_FILE_MODE);
        changes.push({ path: target, action: "update", message: "file permissions set to 0600" });
      }
      return;
    }

    changes.push({ path: target, action: "ok", message: "private file exists" });
    return;
  }

  if (checkOnly) {
    changes.push({ path: target, action: "missing", message: "file missing" });
    return;
  }

  writePrivateFile(target, content);
  changes.push({ path: target, action: "create", message: "private file created" });
}

function upsertBlock(target: string, header: string, blockBody: string, checkOnly: boolean, changes: Change[]): void {
  const managedBlock = `${MANAGED_START}\n${blockBody.trim()}\n${MANAGED_END}\n`;
  const current = existsSync(target) ? readFileSync(target, "utf8") : null;
  const next = current === null
    ? `${header.trim()}\n\n${managedBlock}`
    : replaceOrAppendManagedBlock(current, managedBlock);

  if (current === next) {
    changes.push({ path: target, action: "ok", message: "managed block up to date" });
    return;
  }

  if (checkOnly) {
    changes.push({ path: target, action: current === null ? "missing" : "update", message: current === null ? "adapter missing" : "managed block would update" });
    return;
  }

  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, next, "utf8");
  changes.push({ path: target, action: current === null ? "create" : "update", message: current === null ? "adapter created" : "managed block updated" });
}

function upsertCursorRule(target: string, content: string, checkOnly: boolean, changes: Change[]): void {
  const current = existsSync(target) ? readFileSync(target, "utf8") : null;
  if (current === content) {
    changes.push({ path: target, action: "ok", message: "Cursor memory rule up to date" });
    return;
  }

  if (checkOnly) {
    changes.push({ path: target, action: current === null ? "missing" : "update", message: current === null ? "Cursor memory rule missing" : "Cursor memory rule would update" });
    return;
  }

  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, content, "utf8");
  changes.push({ path: target, action: current === null ? "create" : "update", message: current === null ? "Cursor memory rule created" : "Cursor memory rule updated" });
}

function upsertTextFile(
  target: string,
  content: string,
  checkOnly: boolean,
  changes: Change[],
  okMessage: string,
  missingMessage: string,
  createMessage: string,
  updateMessage: string,
): void {
  const current = existsSync(target) ? readFileSync(target, "utf8") : null;
  if (current === content) {
    changes.push({ path: target, action: "ok", message: okMessage });
    return;
  }

  if (checkOnly) {
    changes.push({ path: target, action: current === null ? "missing" : "update", message: current === null ? missingMessage : updateMessage.replace(" updated", " would update") });
    return;
  }

  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, content, "utf8");
  changes.push({ path: target, action: current === null ? "create" : "update", message: current === null ? createMessage : updateMessage });
}

function upsertClaudeAgentRegistry(target: string, checkOnly: boolean, changes: Change[]): void {
  const current = existsSync(target) ? readFileSync(target, "utf8") : null;
  const parsedCurrent = current === null ? null : safeJsonParse(current);

  if (current !== null && !isRecord(parsedCurrent)) {
    changes.push({ path: target, action: "error", message: "Claude agent registry is not valid JSON" });
    return;
  }

  const currentObject = isRecord(parsedCurrent) ? parsedCurrent : {};
  const currentAgents = isRecord(currentObject.agents) ? currentObject.agents : {};
  const nextObject = {
    ...currentObject,
    version: asString(currentObject.version) ?? "1.0.0",
    agents: {
      ...currentAgents,
      "memory-distiller": {
        file: "agents/memory-distiller.md",
        description: "Compress checkpoint context into proposal-only memory candidates",
        model: "haiku",
      },
    },
  };
  const next = `${JSON.stringify(nextObject, null, 2)}\n`;

  if (current === next) {
    changes.push({ path: target, action: "ok", message: "Claude agent registry up to date" });
    return;
  }

  if (checkOnly) {
    changes.push({ path: target, action: current === null ? "missing" : "update", message: current === null ? "Claude agent registry missing" : "Claude agent registry would update" });
    return;
  }

  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, next, "utf8");
  changes.push({ path: target, action: current === null ? "create" : "update", message: current === null ? "Claude agent registry created" : "Claude agent registry updated" });
}

function replaceOrAppendManagedBlock(current: string, managedBlock: string): string {
  const start = current.indexOf(MANAGED_START);
  const end = current.indexOf(MANAGED_END);
  if (start >= 0 && end > start) {
    const before = current.slice(0, start);
    const after = current.slice(end + MANAGED_END.length).replace(/^\n+/, "");
    return `${before}${managedBlock}${after}`.replace(/\n{3,}/g, "\n\n");
  }

  return `${current.replace(/\s+$/, "")}\n\n${managedBlock}`;
}

function ensurePrivateMemoryStorage(root: string): void {
  ensurePrivateDirectory(root);
  ensurePrivateDirectory(path.join(root, "inbox"));
  assertRegularFileOrMissing(path.join(root, "inbox", "events.jsonl"));
  assertRegularFileOrMissing(path.join(root, "inbox", "harvest-state.json"));
}

function hardenPrivateMemoryTree(root: string): void {
  const privateDirectories = [
    "inbox",
    "decisions",
    "patterns",
    "pitfalls",
    "handoffs",
    "commands",
    "constraints",
    "lessons",
    "preferences",
    "global",
    "repos",
    "templates",
  ];
  const privateFiles = ["SCHEMA.md", "index.md", "log.md"];

  assertDirectory(root);
  chmodSync(root, PRIVATE_DIRECTORY_MODE);
  for (const name of privateDirectories) {
    const target = path.join(root, name);
    if (lstatIfExists(target) !== null) {
      hardenOwnedMemoryPath(target);
    }
  }
  for (const name of privateFiles) {
    const target = path.join(root, name);
    if (lstatIfExists(target) !== null) {
      assertRegularFile(target);
      chmodSync(target, PRIVATE_FILE_MODE);
    }
  }
}

function hardenOwnedMemoryPath(target: string): void {
  const stats = lstatIfExists(target);
  if (stats === null) {
    return;
  }
  if (stats.isSymbolicLink()) {
    throw new Error(`refusing symbolic link in private memory storage: ${target}`);
  }
  if (stats.isFile()) {
    chmodSync(target, PRIVATE_FILE_MODE);
    return;
  }
  if (!stats.isDirectory()) {
    throw new Error(`unsupported path in private memory storage: ${target}`);
  }

  chmodSync(target, PRIVATE_DIRECTORY_MODE);
  for (const entry of readdirSync(target, { withFileTypes: true })) {
    hardenOwnedMemoryPath(path.join(target, entry.name));
  }
}

async function acquireInboxLock(root: string): Promise<() => void> {
  const lockPath = path.join(root, "inbox", ".write-lock");
  const startTime = processStartTime(process.pid);
  if (startTime === null) {
    throw new Error("cannot establish a fenced inbox lock without the current process start time");
  }
  const owner = JSON.stringify({
    pid: process.pid,
    startTime,
    token: randomUUID(),
  });
  const releaseGate = await acquireInboxLockGate(root);
  try {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const candidatePath = `${lockPath}.candidate-${randomUUID()}`;
      try {
        writePrivateFile(candidatePath, `${owner}\n`);
        linkSync(candidatePath, lockPath);
        rmSync(candidatePath, { force: true });
        return () => {
          const ownerStats = lstatIfExists(lockPath);
          if (ownerStats?.isFile() && readFileSync(lockPath, "utf8").trim() === owner) {
            const releasePath = `${lockPath}.release-${randomUUID()}`;
            try {
              renameSync(lockPath, releasePath);
              rmSync(releasePath, { recursive: true, force: true });
            } catch (error) {
              const code = isRecord(error) && typeof error.code === "string" ? error.code : null;
              if (code !== "ENOENT") {
                throw error;
              }
            }
          }
        };
      } catch (error) {
        rmSync(candidatePath, { recursive: true, force: true });
        const code = isRecord(error) && typeof error.code === "string" ? error.code : null;
        if (code !== "EEXIST" && code !== "ENOTEMPTY") {
          throw error;
        }

        const inspection = inspectInboxLock(lockPath);
        if (inspection?.alive === false) {
          await pauseAfterDeadLockCheckForTest();
          const current = inspectInboxLock(lockPath);
          if (current === null || !sameInboxLock(inspection, current)) {
            continue;
          }

          const stalePath = `${lockPath}.stale-${randomUUID()}`;
          try {
            renameSync(lockPath, stalePath);
            const displaced = inspectInboxLock(stalePath);
            if (displaced === null || !sameInboxLock(inspection, displaced)) {
              restoreDisplacedInboxLock(stalePath, lockPath);
              throw new Error(`agent-memory inbox lock changed during fenced takeover: ${lockPath}`);
            }
            rmSync(stalePath, { recursive: true, force: true });
            continue;
          } catch (renameError) {
            const renameCode = isRecord(renameError) && typeof renameError.code === "string" ? renameError.code : null;
            if (renameCode === "ENOENT") {
              continue;
            }
            throw renameError;
          }
        }

        const reason = inspection?.alive === true ? "owned by a live process" : "has no verifiable owner";
        throw new Error(`agent-memory inbox is busy (${reason}): ${lockPath}`);
      }
    }

    throw new Error(`unable to lock agent-memory inbox: ${lockPath}`);
  } finally {
    await releaseGate();
  }
}

async function acquireInboxLockGate(root: string): Promise<() => Promise<void>> {
  const inbox = path.join(root, "inbox");
  const gatePath = path.join(inbox, ".write-lock-gate");
  const readyPath = path.join(inbox, `.write-lock-gate-ready-${process.pid}-${randomUUID()}`);
  createStablePrivateFile(gatePath);
  createTestSignal("AGENT_MEMORY_TEST_LOCK_GATE_ATTEMPT_SIGNAL");

  const flock = process.env.AGENT_MEMORY_FLOCK_BIN ?? "flock";
  const subprocess = Bun.spawn({
    cmd: [
      flock,
      "--exclusive",
      gatePath,
      "sh",
      "-c",
      'umask 077; : > "$1"; IFS= read -r _',
      "agent-memory-lock-gate",
      readyPath,
    ],
    stdin: "pipe",
    stdout: "ignore",
    stderr: "pipe",
  });

  const deadline = Date.now() + 30_000;
  while (lstatIfExists(readyPath) === null) {
    if (subprocess.exitCode !== null) {
      const stderr = await new Response(subprocess.stderr).text();
      throw new Error(`unable to acquire agent-memory inbox gate: ${stderr.trim() || `flock exited ${subprocess.exitCode}`}`);
    }
    if (Date.now() >= deadline) {
      subprocess.kill();
      await subprocess.exited;
      throw new Error(`timed out acquiring agent-memory inbox gate: ${gatePath}`);
    }
    await Bun.sleep(10);
  }

  assertRegularFile(readyPath);
  return async () => {
    try {
      subprocess.stdin.write("release\n");
      subprocess.stdin.end();
      const status = await subprocess.exited;
      if (status !== 0) {
        throw new Error(`agent-memory inbox gate exited with status ${status}: ${gatePath}`);
      }
    } finally {
      rmSync(readyPath, { force: true });
    }
  };
}

function inspectInboxLock(lockPath: string): InboxLockInspection | null {
  let ownerStats: ReturnType<typeof lstatSync> | null = null;
  let content: string | null = null;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const beforeRead = lstatIfExists(lockPath);
    if (beforeRead === null || !beforeRead.isFile()) {
      return null;
    }
    try {
      content = readFileSync(lockPath, "utf8").trim();
    } catch (error) {
      const code = isRecord(error) && typeof error.code === "string" ? error.code : null;
      if (code === "ENOENT") {
        continue;
      }
      throw error;
    }
    const afterRead = lstatIfExists(lockPath);
    if (
      afterRead !== null
      && afterRead.isFile()
      && beforeRead.dev === afterRead.dev
      && beforeRead.ino === afterRead.ino
    ) {
      ownerStats = afterRead;
      break;
    }
  }
  if (ownerStats === null || content === null) {
    return null;
  }
  const owner = safeJsonParse(content);
  if (
    !isRecord(owner)
    || typeof owner.pid !== "number"
    || !Number.isInteger(owner.pid)
    || owner.pid <= 0
    || typeof owner.startTime !== "string"
    || typeof owner.token !== "string"
    || owner.token.length === 0
  ) {
    return {
      alive: null,
      content,
      device: ownerStats.dev,
      inode: ownerStats.ino,
    };
  }

  const currentStartTime = processStartTime(owner.pid);
  if (currentStartTime !== null) {
    return {
      alive: currentStartTime === owner.startTime,
      content,
      device: ownerStats.dev,
      inode: ownerStats.ino,
    };
  }

  try {
    process.kill(owner.pid, 0);
    return {
      alive: true,
      content,
      device: ownerStats.dev,
      inode: ownerStats.ino,
    };
  } catch (error) {
    const code = isRecord(error) && typeof error.code === "string" ? error.code : null;
    return {
      alive: code === "ESRCH" ? false : true,
      content,
      device: ownerStats.dev,
      inode: ownerStats.ino,
    };
  }
}

function sameInboxLock(left: InboxLockInspection, right: InboxLockInspection): boolean {
  return left.device === right.device
    && left.inode === right.inode
    && left.content === right.content;
}

function restoreDisplacedInboxLock(stalePath: string, lockPath: string): void {
  try {
    linkSync(stalePath, lockPath);
    rmSync(stalePath, { force: true });
  } catch (error) {
    const code = isRecord(error) && typeof error.code === "string" ? error.code : null;
    if (code === "EEXIST") {
      throw new Error(`cannot safely restore displaced agent-memory inbox lock: ${lockPath}`);
    }
    throw error;
  }
}

function createStablePrivateFile(target: string): void {
  try {
    writeFileSync(target, "", {
      encoding: "utf8",
      flag: "ax",
      mode: PRIVATE_FILE_MODE,
    });
  } catch (error) {
    const code = isRecord(error) && typeof error.code === "string" ? error.code : null;
    if (code !== "EEXIST") {
      throw error;
    }
  }
  assertRegularFile(target);
  chmodSync(target, PRIVATE_FILE_MODE);
}

function createTestSignal(environmentName: string): void {
  const target = process.env[environmentName];
  if (target === undefined || target === "") {
    return;
  }
  writeFileSync(target, "", { encoding: "utf8", flag: "wx", mode: PRIVATE_FILE_MODE });
}

async function pauseAfterDeadLockCheckForTest(): Promise<void> {
  const signal = process.env.AGENT_MEMORY_TEST_DEAD_LOCK_CHECK_SIGNAL;
  const continuePath = process.env.AGENT_MEMORY_TEST_DEAD_LOCK_CHECK_CONTINUE;
  if (signal === undefined || signal === "" || continuePath === undefined || continuePath === "") {
    return;
  }

  createTestSignal("AGENT_MEMORY_TEST_DEAD_LOCK_CHECK_SIGNAL");
  const deadline = Date.now() + 30_000;
  while (lstatIfExists(continuePath) === null) {
    if (Date.now() >= deadline) {
      throw new Error(`timed out waiting for lock-takeover test continuation: ${continuePath}`);
    }
    await Bun.sleep(10);
  }
}

function processStartTime(pid: number): string | null {
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
    const fieldsAfterCommand = stat.slice(stat.lastIndexOf(")") + 1).trim().split(/\s+/);
    return fieldsAfterCommand[19] ?? null;
  } catch {
    return null;
  }
}

function ensurePrivateDirectory(target: string): void {
  const stats = lstatIfExists(target);
  if (stats?.isSymbolicLink()) {
    throw new Error(`refusing symbolic-link directory for private memory: ${target}`);
  }
  if (stats !== null && !stats.isDirectory()) {
    throw new Error(`private memory path is not a directory: ${target}`);
  }
  if (stats === null) {
    mkdirSync(target, { recursive: true, mode: PRIVATE_DIRECTORY_MODE });
  }
  chmodSync(target, PRIVATE_DIRECTORY_MODE);
}

function writePrivateFile(target: string, content: string): void {
  ensurePrivateDirectory(path.dirname(target));
  assertRegularFileOrMissing(target);
  const temporary = path.join(
    path.dirname(target),
    `.${path.basename(target)}.${process.pid}.${Date.now()}.tmp`,
  );

  try {
    writeFileSync(temporary, content, {
      encoding: "utf8",
      flag: "wx",
      mode: PRIVATE_FILE_MODE,
    });
    renameSync(temporary, target);
    chmodSync(target, PRIVATE_FILE_MODE);
  } finally {
    rmSync(temporary, { force: true });
  }
}

function fileMode(target: string): number {
  return statSync(target).mode & 0o777;
}

function lstatIfExists(target: string): Stats | null {
  try {
    return lstatSync(target) ?? null;
  } catch (error) {
    const code = isRecord(error) && typeof error.code === "string" ? error.code : null;
    if (code === "ENOENT") {
      return null;
    }
    throw error;
  }
}

function assertDirectory(target: string): void {
  const stats = lstatIfExists(target);
  if (stats?.isSymbolicLink()) {
    throw new Error(`refusing symbolic-link memory root: ${target}`);
  }
  if (stats === null || !stats.isDirectory()) {
    throw new Error(`memory root is not a directory: ${target}`);
  }
}

function assertRegularFile(target: string): void {
  const stats = lstatIfExists(target);
  if (stats?.isSymbolicLink()) {
    throw new Error(`refusing symbolic-link memory file: ${target}`);
  }
  if (stats === null || !stats.isFile()) {
    throw new Error(`memory path is not a regular file: ${target}`);
  }
}

function assertRegularFileOrMissing(target: string): void {
  const stats = lstatIfExists(target);
  if (stats === null) {
    return;
  }
  assertRegularFile(target);
}

function appendJsonl(target: string, event: unknown): void {
  ensurePrivateDirectory(path.dirname(target));
  assertRegularFileOrMissing(target);
  if (existsSync(target)) {
    chmodSync(target, PRIVATE_FILE_MODE);
  }
  appendFileSync(target, `${JSON.stringify(event)}\n`, {
    encoding: "utf8",
    mode: PRIVATE_FILE_MODE,
  });
  chmodSync(target, PRIVATE_FILE_MODE);
}

function printChanges(changes: Change[]): void {
  for (const change of changes) {
    console.log(`${statusIcon(change.action)} ${change.message}: ${change.path}`);
  }
}

function exitIfCheckFailed(changes: Change[], checkOnly: boolean): void {
  const hasError = changes.some((change) => change.action === "error");
  const checkWouldChange = checkOnly && changes.some((change) => change.action !== "ok");
  if (hasError || checkWouldChange) {
    process.exit(1);
  }
}

function statusIcon(action: Change["action"]): string {
  switch (action) {
    case "ok":
      return "ok";
    case "create":
      return "create";
    case "update":
      return "update";
    case "missing":
      return "missing";
    case "error":
      return "error";
  }
}

function enabledAdapters(config: MemoryConfig): AdapterName[] {
  return (Object.keys(config.adapters ?? {}) as AdapterName[]).filter((name) => config.adapters?.[name] !== false);
}

function parseScope(value: string): MemoryScope {
  if (value === "repo" || value === "global" || value === "session") {
    return value;
  }

  throw new Error(`Invalid --scope '${value}'. Expected repo, global, or session.`);
}

function parseSensitivity(value: string): MemoryEvent["sensitivity"] {
  if (value === "public" || value === "private" || value === "sensitive" || value === "secret-redacted") {
    return value;
  }

  throw new Error(`Invalid --sensitivity '${value}'.`);
}

function hasFlag(commandArgs: string[], name: string): boolean {
  return commandArgs.includes(`--${name}`);
}

function getOption(commandArgs: string[], name: string): string | null {
  for (let index = 0; index < commandArgs.length; index += 1) {
    const arg = commandArgs[index];
    if (arg === `--${name}`) {
      return requiredFollowingOptionValue(commandArgs, index, name);
    }

    if (arg?.startsWith(`--${name}=`)) {
      return arg.slice(name.length + 3);
    }
  }

  return null;
}

function getAllOptions(commandArgs: string[], name: string): string[] {
  const values: string[] = [];
  for (let index = 0; index < commandArgs.length; index += 1) {
    const arg = commandArgs[index];
    if (arg === `--${name}`) {
      values.push(requiredFollowingOptionValue(commandArgs, index, name));
      index += 1;
      continue;
    }

    if (arg?.startsWith(`--${name}=`)) {
      values.push(arg.slice(name.length + 3));
    }
  }

  return values;
}

function requiredFollowingOptionValue(commandArgs: string[], optionIndex: number, name: string): string {
  const value = commandArgs[optionIndex + 1];
  if (value === undefined || value.startsWith("--")) {
    throw new Error(`--${name} requires a value`);
  }
  return value;
}

function resolveGitRoot(input: string): string {
  const normalized = normalizePath(expandHome(input));
  const result = spawnSync("git", ["-C", normalized, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
  if (result.status === 0) {
    return normalizePath(result.stdout.trim());
  }

  return normalized;
}

function normalizePath(input: string): string {
  return path.resolve(expandHome(input));
}

function expandHome(input: string): string {
  if (input === "~") {
    return homedir();
  }

  if (input.startsWith("~/")) {
    return path.join(homedir(), input.slice(2));
  }

  return input;
}

function unique<T>(items: T[]): T[] {
  return Array.from(new Set(items));
}

function safeJsonParse(input: string): unknown | null {
  try {
    return JSON.parse(input);
  } catch {
    return null;
  }
}

function redactSecrets(input: string): string {
  return input
    .replace(/-----BEGIN [^-\r\n]*PRIVATE KEY-----[\s\S]*?-----END [^-\r\n]*PRIVATE KEY-----/gi, "[REDACTED PRIVATE KEY]")
    .replace(/-----BEGIN [^-\r\n]*PRIVATE KEY-----[\s\S]*$/gi, "[REDACTED PRIVATE KEY]")
    .replace(/\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}\b/g, "$1_[REDACTED]")
    .replace(/\bsk-[A-Za-z0-9_-]{16,}\b/g, "sk-[REDACTED]")
    .replace(/\bAKIA[A-Z0-9]{16}\b/g, "AKIA[REDACTED]")
    .replace(/\bxox[baprs]-[A-Za-z0-9-]{10,}\b/g, "xox-[REDACTED]")
    .replace(/\bBearer\s+[A-Za-z0-9._~+\/-]{8,}/gi, "Bearer [REDACTED]")
    .replace(/\bBasic\s+[A-Za-z0-9+/=]{8,}/gi, "Basic [REDACTED]")
    .replace(/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g, "[REDACTED JWT]")
    .replace(/\b([a-z][a-z0-9+.-]*:\/\/)([^\s/:@]+):([^\s/@]+)@/gi, "$1[REDACTED]@")
    .replace(
      /\b((?:[a-z0-9]+[_-])*(?:api[_-]?key|access[_-]?token|refresh[_-]?token|auth[_-]?token|client[_-]?secret|secret|token|password|passwd|pwd|private[_-]?key|credentials?|key)\s*[:=]\s*)(?:"[^"]*"|'[^']*'|`[^`]*`|[^\s,;]+)/gi,
      "$1[REDACTED]",
    );
}

function redactSensitiveValue(value: unknown, key: string | null = null): { value: unknown; redacted: boolean } {
  if (key !== null && isSensitiveKey(key)) {
    return {
      value: "[REDACTED]",
      redacted: value !== "[REDACTED]",
    };
  }

  if (typeof value === "string") {
    const redactedValue = redactSecrets(value);
    return {
      value: redactedValue,
      redacted: redactedValue !== value,
    };
  }

  if (Array.isArray(value)) {
    let redacted = false;
    const items = value.map((item) => {
      const itemResult = redactSensitiveValue(item);
      redacted ||= itemResult.redacted;
      return itemResult.value;
    });
    return { value: items, redacted };
  }

  if (isRecord(value)) {
    let redacted = false;
    const entries = Object.entries(value).map(([entryKey, entryValue]) => {
      const entryResult = redactSensitiveValue(entryValue, entryKey);
      redacted ||= entryResult.redacted;
      return [entryKey, entryResult.value] as const;
    });
    return {
      value: Object.fromEntries(entries),
      redacted,
    };
  }

  return { value, redacted: false };
}

function isSensitiveKey(key: string): boolean {
  const normalized = key.replace(/[^a-z0-9]/gi, "").toLowerCase();
  const exactKeys = [
    "authorization",
    "proxyauthorization",
    "cookie",
    "setcookie",
    "apikey",
    "accesstoken",
    "refreshtoken",
    "authtoken",
    "clientsecret",
    "secret",
    "token",
    "password",
    "passwd",
    "pwd",
    "privatekey",
    "credential",
    "credentials",
    "key",
  ];
  const sensitiveSuffixes = [
    "apikey",
    "accesstoken",
    "refreshtoken",
    "authtoken",
    "clientsecret",
    "privatekey",
    "password",
    "passwd",
    "credential",
    "credentials",
    "secret",
    "token",
  ];
  return exactKeys.includes(normalized) || sensitiveSuffixes.some((suffix) => normalized.endsWith(suffix));
}

function globalSchemaTemplate(): string {
  return `# Agent Memory Schema

## Purpose

Global operational memory for agentic coding work across repositories.

This repository stores durable knowledge that should change future agent behavior.
It is not a source of truth for project code, docs, secrets, or external facts.

## Scopes

- global: cross-repo preferences, workflows, lessons, tool pitfalls.
- repo: project-specific constraints, decisions, commands, known issues.
- session: temporary observations waiting for distillation.

## Entry Types

- decision: accepted technical or workflow choice.
- pattern: repeatable approach that worked.
- pitfall: error mode and how to avoid it.
- command: validated command with cwd and safety notes.
- constraint: durable rule or boundary.
- handoff: current state for continuation.
- lesson: transferable learning.
- preference: user preference that should guide behavior.

## Required Fields

Every durable entry should include:

- title
- type
- scope
- status: active | superseded | rejected
- created
- updated
- source
- provenance
- tags
- summary
- guidance

## Rules

- Store only actionable knowledge.
- Keep global entries short and behavioral.
- Keep raw global session captures in inbox/events.jsonl until distilled.
- Never store secrets; redact suspicious tokens.
- Do not delete durable entries; mark superseded.
- Prefer citations to session IDs, commits, files, or commands when available.
`;
}

function repoSchemaTemplate(config: MemoryConfig): string {
  return `# Repo Agent Memory Schema

This directory stores project-specific operational memory for future agents.

Global memory repo: $AGENT_MEMORY_GLOBAL_REPO

## Directories

- .agent-memory/inbox/events.jsonl: append-only repo-local raw captures and harvests.
- decisions/: durable project decisions.
- patterns/: repo-specific patterns that worked.
- pitfalls/: known failure modes and fixes.
- handoffs/: continuation notes.
- commands/: validated repo commands.
- constraints/: durable project boundaries.
- lessons/: transferable repo learnings.
- preferences/: repo-specific user preferences.

## Rules

- Do not store secrets.
- Do not treat memory as source of truth; verify against files.
- Evaluate durable memory at meaningful checkpoints, not on a timer.
- Prefer append for one clear insight and distill only when multiple raw signals need compression.
- Promote only actionable knowledge from inbox to durable markdown.
- Mark outdated entries as superseded instead of deleting.
- Keep entries concise enough for agents to read at task start.
`;
}

function globalIndexTemplate(): string {
  return `# Second Brain Index

Operational memory for agentic coding sessions.

## Global Memory

- [Preferences](global/preferences.md)
- [Workflows](global/workflows.md)
- [Patterns](global/patterns.md)
- [Pitfalls](global/pitfalls.md)
- [Tools](global/tools.md)

## Repositories

See [repo registry](repos/registry.md).

## Inbox

Global raw captures live in inbox/events.jsonl until distilled.
`;
}

function globalLogTemplate(): string {
  return `# Agent Memory Log

> Append-only human-readable maintenance log.

## [${today()}] create | Global second brain initialized

- Created global operational memory structure.
`;
}

function repoRegistryTemplate(config: MemoryConfig): string {
  const repos = config.managedRepos.map((repo) => `- ${repo}`).join("\n");
  return `# Managed Repositories

${repos.length > 0 ? repos : "No managed repositories declared yet."}
`;
}

function repoIndexTemplate(repo: string, config: MemoryConfig): string {
  return `# Agent Memory Index

Repo: current repository
Global memory repo: $AGENT_MEMORY_GLOBAL_REPO

## Durable Memory

- decisions/
- patterns/
- pitfalls/
- handoffs/
- commands/
- constraints/
- lessons/
- preferences/

## Inbox

- .agent-memory/inbox/events.jsonl
`;
}

function memoryEntryTemplate(): string {
  return `---
title: ""
type: decision | pattern | pitfall | command | constraint | handoff | lesson | preference
scope: global | repo | session
status: active
created: ${today()}
updated: ${today()}
source: ""
provenance: []
tags: []
---

# Title

## Summary

## Guidance for future agents

## Evidence / provenance

## Supersedes

## Superseded by
`;
}

function genericAdapterBlock(config: MemoryConfig): string {
  return `## Agent Memory Protocol

Global memory repo: $AGENT_MEMORY_GLOBAL_REPO
Local repo memory: .agent-memory/

Before non-trivial work:
- Consult local memory in .agent-memory/index.md and recent handoffs.
- Recall prior sessions with: agent-memory recall --repo "$PWD" --query "<task>"

During work:
- Capture durable discoveries with: agent-memory append --scope repo --type pattern|pitfall|decision --title "..." --body "..."
- At meaningful checkpoints, evaluate whether durable memory is worth the current cost budget.
- Skip trivial edits and duplicate insights.
- Prefer append for one clear reusable insight.
- If multiple raw events or a rich session harvest need compression, use a bounded memory-distiller subagent when available; otherwise distill inline after review.
- Do not store secrets or raw credentials.

After meaningful work:
- Run: agent-memory harvest --repo "$PWD" --since 24h
- Distill only actionable knowledge, and avoid running distill more than once per task unless direction changed or new validated lessons appeared.

Memory is guidance, not source of truth. Verify against repository files.`;
}

function copilotAdapterBlock(config: MemoryConfig): string {
  return `## Agent Memory

Use the local memory directory .agent-memory/ and the global memory repo declared in $AGENT_MEMORY_GLOBAL_REPO for durable operational context.

When starting multi-step work, inspect .agent-memory/index.md and search prior context with agent-memory recall when terminal access is available.
When discovering reusable decisions, patterns, pitfalls, or commands, append a concise event with agent-memory append.
At meaningful checkpoints, skip trivial edits, prefer append for one clear insight, and only distill when multiple pending signals justify consolidation.
When the current tool supports repo-local subagents, use a bounded memory-distiller in proposal-only mode for dense checkpoint compression before writing durable memory.
Never store secrets. Treat memory as guidance only; verify against source files.`;
}

function claudeAdapterBlock(config: MemoryConfig): string {
  return `## Agent Memory Protocol

Global memory repo: $AGENT_MEMORY_GLOBAL_REPO
Repo memory: .agent-memory/

At task start, use recent-work-context or agent-memory recall when prior session context may matter.
For multi-step work, append durable decisions, patterns, pitfalls, and handoffs with agent-memory append.
At meaningful checkpoints, skip trivial edits, prefer append for one clear reusable insight, and use the memory-distiller subagent in proposal-only mode when recent harvest output or multiple inbox signals need compression.
At the end of meaningful sessions, run agent-memory harvest --repo "$PWD" --since 24h when allowed.
Do not run distill on a timer; run it when checkpoint value justifies the cost.
Do not store secrets. Verify memory against files before acting.`;
}

function cursorRuleTemplate(config: MemoryConfig): string {
  return `---
description: Agent Memory protocol for durable cross-session coding context
globs: ["**/*"]
alwaysApply: true
---

# Agent Memory

Global memory repo: $AGENT_MEMORY_GLOBAL_REPO
Local repo memory: .agent-memory/

Before multi-step work:
- Read .agent-memory/index.md if present.
- Use agent-memory recall --repo "$PWD" --query "<task>" when terminal access is available.

During and after work:
- Capture durable decisions, patterns, pitfalls, commands, constraints, and handoffs.
- Prefer agent-memory append for raw capture.
- At meaningful checkpoints, skip trivial edits and prefer append for a single clear insight.
- Use distill only when multiple pending signals justify consolidation.
- If repo-local subagents are available, use memory-distiller in proposal-only mode for dense checkpoint compression.
- Promote only actionable knowledge.
- Never store secrets.
- Treat memory as guidance, not source of truth.
`;
}

function claudeMemoryDistillerAgentTemplate(): string {
  return `---
name: memory-distiller
description: Compress checkpoint context into proposal-only durable memory candidates
tools: Read, Grep, Glob, Bash
model: haiku
---

# Memory Distiller

You are a bounded read-only subagent for checkpoint-driven memory distillation.

## Purpose

Compress raw checkpoint context into a small set of durable memory candidates without writing files.

## Inputs

- .agent-memory/inbox/events.jsonl
- .agent-memory/index.md
- recent handoffs, decisions, patterns, pitfalls, commands, constraints, lessons, preferences
- recent-work-context or session-harvest output when provided
- a small set of repository files only when needed to validate evidence

## Rules

- Proposal-only: never edit or write memory files.
- Skip trivial edits, duplicates, and temporary observations.
- Prefer "append" when there is one clear reusable insight.
- Recommend "distill" only when multiple raw signals or a rich session-harvest justify compression.
- Never include secrets or credential-like material.
- Return structured summaries, not raw logs.

## Output Format

Return exactly these sections:

Checkpoint Verdict
- recommended_action: skip | append | distill
- reason: <one concise sentence>

Candidates
1. type: decision | pattern | pitfall | command | constraint | handoff | lesson | preference
   scope: repo | global
   title: <short title>
   summary: <1-2 sentences>
   guidance:
   - <actionable guidance>
   evidence:
   - <file, command, session citation, or timestamp>
   confidence: low | medium | high
   should_write: yes | no
   reason: <why this candidate is or is not worth writing>

If nothing durable is justified, return "No durable candidates." in the Candidates section.
`;
}

function opencodeMemoryDistillerAgentTemplate(): string {
  return `---
description: Compress checkpoint context into proposal-only durable memory candidates
mode: subagent
tools:
  read: true
  bash: true
  grep: true
  glob: true
  edit: false
  write: false
---

# Memory Distiller

You are a bounded read-only subagent for checkpoint-driven memory distillation.

## Purpose

Compress raw checkpoint context into a small set of durable memory candidates without writing files.

## Inputs

- .agent-memory/inbox/events.jsonl
- .agent-memory/index.md
- recent handoffs, decisions, patterns, pitfalls, commands, constraints, lessons, preferences
- recent-work-context or session-harvest output when provided
- a small set of repository files only when needed to validate evidence

## Rules

- Proposal-only: never edit or write memory files.
- Skip trivial edits, duplicates, and temporary observations.
- Prefer "append" when there is one clear reusable insight.
- Recommend "distill" only when multiple raw signals or a rich session-harvest justify compression.
- Never include secrets or credential-like material.
- Return structured summaries, not raw logs.

## Output Format

Return exactly these sections:

Checkpoint Verdict
- recommended_action: skip | append | distill
- reason: <one concise sentence>

Candidates
1. type: decision | pattern | pitfall | command | constraint | handoff | lesson | preference
   scope: repo | global
   title: <short title>
   summary: <1-2 sentences>
   guidance:
   - <actionable guidance>
   evidence:
   - <file, command, session citation, or timestamp>
   confidence: low | medium | high
   should_write: yes | no
   reason: <why this candidate is or is not worth writing>

If nothing durable is justified, return "No durable candidates." in the Candidates section.
`;
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}
