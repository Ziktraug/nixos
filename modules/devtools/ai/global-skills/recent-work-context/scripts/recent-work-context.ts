#!/usr/bin/env bun

import { Database } from "bun:sqlite";
import { $ } from "bun";
import { existsSync, readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { parseArgs } from "node:util";

type Source = "claude-code" | "opencode";
type SourceFilter = Source | "all";
type Profile = "human" | "agent";
type Lens =
  | "recent"
  | "user"
  | "assistant"
  | "tools"
  | "errors"
  | "files"
  | "plans"
  | "prefs"
  | "decisions";

type Role = "user" | "assistant" | "tool";

interface RepoIdentity {
  root: string;
  name: string;
  branch: string | null;
  remoteUrl: string | null;
}

interface ContextRecord {
  source: Source;
  sessionId: string;
  timestamp: number;
  role: Role;
  kind: string;
  text: string;
  files: string[];
  tool: string | null;
  branch: string | null;
  citation: string;
  repoPath: string | null;
  score: number;
}

interface OutputPayload {
  repo: RepoIdentity;
  profile: Profile;
  query: string | null;
  lens: Lens;
  source: SourceFilter;
  summary: DerivedSummary;
  agentContext: AgentContext;
  counts: {
    total: number;
    matchedTotal: number;
    matchedSessions: number;
    focusedSessions: number;
    bySource: Record<Source, number>;
    sessionsBySource: Record<Source, number>;
  };
  records: ContextRecord[];
}

interface RankedSession {
  source: Source;
  sessionId: string;
  filePath: string;
  timestamp: number;
  branch: string | null;
  repoPath: string | null;
}

interface SessionGroup {
  source: Source;
  sessionId: string;
  branch: string | null;
  latestTimestamp: number;
  files: string[];
  records: ContextRecord[];
}

interface SummaryItem {
  text: string;
  citations: string[];
}

interface SummaryFile {
  path: string;
  mentions: number;
  citations: string[];
}

interface SummaryArea {
  path: string;
  mentions: number;
  citations: string[];
}

interface SummarySession {
  source: Source;
  sessionId: string;
  latestTimestamp: number;
  synopsis: string;
  files: string[];
  citations: string[];
}

interface DerivedSummary {
  overview: string[];
  decisions: SummaryItem[];
  preferences: SummaryItem[];
  relevantFiles: SummaryFile[];
  changedAreas: SummaryArea[];
  failuresAndFixes: SummaryItem[];
  sessions: SummarySession[];
}

interface AgentContext {
  repoRoot: string;
  query: string | null;
  source: SourceFilter;
  lens: Lens;
  overview: string[];
  decisions: string[];
  preferences: string[];
  relevantFiles: string[];
  changedAreas: string[];
  failuresAndFixes: string[];
  sessions: Array<{
    source: Source;
    sessionId: string;
    latestTimestamp: number;
    synopsis: string;
    files: string[];
    citations: string[];
  }>;
  topCitations: string[];
}

type SummaryFormatter = (record: ContextRecord) => string;

const DEFAULT_LIMITS: Record<Profile, number> = {
  human: 20,
  agent: 32,
};
const DEFAULT_PER_SESSION_LIMITS: Record<Profile, number> = {
  human: 4,
  agent: 8,
};
const DEFAULT_SESSION_SCAN_LIMIT = 12;
const DEFAULT_AGENT_RENDERED_GROUPS = 4;
const DEFAULT_AGENT_RENDERED_EXCERPTS = 3;
const DEFAULT_AGENT_SCORE_WINDOW = 20;
const VALID_LENSES: Lens[] = [
  "recent",
  "user",
  "assistant",
  "tools",
  "errors",
  "files",
  "plans",
  "prefs",
  "decisions",
];

const args = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    query: { type: "string", short: "q" },
    lens: { type: "string", short: "l" },
    profile: { type: "string" },
    source: { type: "string" },
    repo: { type: "string", short: "r" },
    since: { type: "string", short: "s" },
    limit: { type: "string", short: "n" },
    "session-limit": { type: "string" },
    "per-session-limit": { type: "string" },
    json: { type: "boolean" },
    help: { type: "boolean", short: "h" },
  },
  allowPositionals: true,
  strict: true,
});

if (args.values.help) {
  printHelp();
  process.exit(0);
}

const lens = parseLens(args.values.lens);
const profile = parseProfile(args.values.profile);
const sourceFilter = parseSourceFilter(args.values.source);
const query = normalizeQuery(args.values.query, args.positionals);
const limit = parseLimit(args.values.limit, profile);
const sinceEpoch = parseSince(args.values.since);
const perSessionLimit = parsePerSessionLimit(args.values["per-session-limit"], profile);

const repo = await resolveRepo(args.values.repo);
const sessionLimit = parseSessionLimit(args.values["session-limit"], limit, query, profile);

const matchedRecords = [
  ...collectClaudeRecords(repo, sessionLimit),
  ...collectOpenCodeRecords(repo, sessionLimit),
]
  .map((record) => ({
    ...record,
    files: unique(
      record.files
        .map((file) => normalizeRepoFile(file, repo))
        .filter((file): file is string => file !== null),
    ),
  }))
  .filter((record) => !isSelfNoise(record, query))
  .filter((record) => (sourceFilter === "all" ? true : record.source === sourceFilter))
  .filter((record) => (sinceEpoch === null ? true : record.timestamp >= sinceEpoch))
  .filter((record) => matchesLens(record, lens))
  .filter((record) => hasQueryMatch(record, query, repo))
  .map((record) => ({ ...record, score: scoreRecord(record, query, lens, repo) }))
  .sort((left, right) => {
    if (right.score !== left.score) {
      return right.score - left.score;
    }

    if (right.timestamp !== left.timestamp) {
      return right.timestamp - left.timestamp;
    }

    return left.citation.localeCompare(right.citation);
  });
const records = selectTopRecords(matchedRecords, limit, perSessionLimit);
const sessionGroups = groupRecordsBySession(matchedRecords);
const summary = deriveSummary(matchedRecords, sessionGroups, repo, query);
const agentContext = deriveAgentContext(summary, records, repo, query, lens, sourceFilter);

const payload: OutputPayload = {
  repo,
  profile,
  query,
  lens,
  source: sourceFilter,
  summary,
  agentContext,
  counts: {
    total: records.length,
    matchedTotal: matchedRecords.length,
    matchedSessions: sessionGroups.length,
    focusedSessions: summary.sessions.length,
    bySource: {
      "claude-code": records.filter((record) => record.source === "claude-code").length,
      opencode: records.filter((record) => record.source === "opencode").length,
    },
    sessionsBySource: {
      "claude-code": new Set(records.filter((record) => record.source === "claude-code").map((record) => record.sessionId)).size,
      opencode: new Set(records.filter((record) => record.source === "opencode").map((record) => record.sessionId)).size,
    },
  },
  records,
};

if (args.values.json) {
  console.log(JSON.stringify(payload, null, 2));
} else {
  console.log(renderHuman(payload, args.values.since ?? null));
}

function printHelp(): void {
  console.log(`Usage: recent-work-context [options] [query]\n\nOptions:\n  --query, -q          Search text to rank excerpts\n  --lens, -l           One of: ${VALID_LENSES.join(", ")}\n  --profile            One of: human, agent\n  --source             One of: all, claude-code, opencode\n  --repo, -r           Override target repo path (defaults to current working directory)\n  --since, -s          Time window like 12h, 7d, or 4w\n  --limit, -n          Number of excerpts to return (defaults: human=${DEFAULT_LIMITS.human}, agent=${DEFAULT_LIMITS.agent})\n  --session-limit      Candidate sessions to scan before ranking\n  --per-session-limit  Max excerpts returned per session (defaults: human=${DEFAULT_PER_SESSION_LIMITS.human}, agent=${DEFAULT_PER_SESSION_LIMITS.agent})\n  --json               Output structured JSON\n  --help, -h           Show this help\n`);
}

function parseLens(value: string | undefined): Lens {
  if (value === undefined) {
    return "recent";
  }

  if (VALID_LENSES.includes(value as Lens)) {
    return value as Lens;
  }

  throw new Error(`Invalid lens '${value}'. Expected one of: ${VALID_LENSES.join(", ")}`);
}

function parseProfile(value: string | undefined): Profile {
  if (value === undefined) {
    return "human";
  }

  if (value === "human" || value === "agent") {
    return value;
  }

  throw new Error(`Invalid --profile '${value}'. Expected one of: human, agent.`);
}

function parseSourceFilter(value: string | undefined): SourceFilter {
  if (value === undefined) {
    return "all";
  }

  if (value === "all" || value === "claude-code" || value === "opencode") {
    return value;
  }

  throw new Error(`Invalid --source '${value}'. Expected one of: all, claude-code, opencode.`);
}

function normalizeQuery(raw: string | undefined, positionals: string[]): string | null {
  const value = raw ?? positionals.join(" ");
  const normalized = collapseWhitespace(value);
  return normalized.length === 0 ? null : normalized;
}

function parseLimit(value: string | undefined, profile: Profile): number {
  if (value === undefined) {
    return DEFAULT_LIMITS[profile];
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`Invalid --limit '${value}'. Expected a positive integer.`);
  }

  return parsed;
}

function parseSessionLimit(value: string | undefined, limit: number, query: string | null, profile: Profile): number {
  if (value === undefined) {
    if (query === null) {
      return profile === "agent"
        ? Math.max(limit * 8, 48)
        : Math.max(limit * 4, DEFAULT_SESSION_SCAN_LIMIT);
    }

    return profile === "agent" ? 1000 : 500;
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`Invalid --session-limit '${value}'. Expected a positive integer.`);
  }

  return parsed;
}

function parsePerSessionLimit(value: string | undefined, profile: Profile): number {
  if (value === undefined) {
    return DEFAULT_PER_SESSION_LIMITS[profile];
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`Invalid --per-session-limit '${value}'. Expected a positive integer.`);
  }

  return parsed;
}

function parseSince(value: string | undefined): number | null {
  if (value === undefined) {
    return null;
  }

  const match = /^(\d+)([smhdw])$/.exec(value.trim());
  if (match === null) {
    throw new Error(`Invalid --since '${value}'. Use values like 12h, 7d, or 4w.`);
  }

  const amountValue = match[1];
  const unit = match[2];
  if (amountValue === undefined || unit === undefined) {
    throw new Error(`Invalid --since '${value}'. Use values like 12h, 7d, or 4w.`);
  }

  const amount = Number.parseInt(amountValue, 10);
  const unitMs: Record<string, number> = {
    s: 1000,
    m: 60 * 1000,
    h: 60 * 60 * 1000,
    d: 24 * 60 * 60 * 1000,
    w: 7 * 24 * 60 * 60 * 1000,
  };
  const unitDuration = unitMs[unit];
  if (unitDuration === undefined) {
    throw new Error(`Invalid --since '${value}'. Use values like 12h, 7d, or 4w.`);
  }

  return Date.now() - amount * unitDuration;
}

async function resolveRepo(requestedRepo: string | undefined): Promise<RepoIdentity> {
  const inputPath = path.resolve(requestedRepo ?? process.cwd());
  const repoRootResult = await $`git -C ${inputPath} rev-parse --show-toplevel`.nothrow().quiet();
  const repoRoot = repoRootResult.exitCode === 0 ? repoRootResult.stdout.toString("utf8").trim() : inputPath;
  const branchResult = await $`git -C ${repoRoot} branch --show-current`.nothrow().quiet();
  const remoteResult = await $`git -C ${repoRoot} config --get remote.origin.url`.nothrow().quiet();

  return {
    root: normalizePath(repoRoot),
    name: path.basename(repoRoot),
    branch: branchResult.exitCode === 0 ? collapseWhitespace(branchResult.stdout.toString("utf8")) || null : null,
    remoteUrl: remoteResult.exitCode === 0 ? normalizeRemote(remoteResult.stdout.toString("utf8")) : null,
  };
}

function collectClaudeRecords(repo: RepoIdentity, sessionLimit: number): ContextRecord[] {
  const claudeProjectsDir = path.join(homedir(), ".claude", "projects");
  if (!existsSync(claudeProjectsDir)) {
    return [];
  }

  const indexes = findFilesByName(claudeProjectsDir, "sessions-index.json");
  const projectDirs = new Set<string>();
  const sessionMeta = new Map<
    string,
    {
      timestamp: number;
      branch: string | null;
      repoPath: string | null;
    }
  >();
  const rankedSessions: RankedSession[] = [];

  for (const indexPath of indexes) {
    const raw = safeReadText(indexPath);
    if (raw === null) {
      continue;
    }

    const parsed = safeJsonParse<{ entries?: Array<Record<string, unknown>> }>(raw);
    if (parsed === null || !Array.isArray(parsed.entries)) {
      continue;
    }

    for (const entry of parsed.entries) {
      const projectPath = asString(entry.projectPath);
      if (!repoMatches(projectPath, repo)) {
        continue;
      }

      projectDirs.add(path.dirname(indexPath));

      const sessionId = asString(entry.sessionId);
      const fullPath = asString(entry.fullPath);
      if (sessionId === null || fullPath === null) {
        continue;
      }

      sessionMeta.set(sessionId, {
        timestamp: dateStringToEpoch(asString(entry.modified)) ?? Number(asNumber(entry.fileMtime) ?? 0),
        branch: asString(entry.gitBranch),
        repoPath: projectPath,
      });
    }
  }

  for (const projectDir of projectDirs) {
    for (const filePath of findFilesBySuffix(projectDir, ".jsonl")) {
      if (filePath.includes(`${path.sep}subagents${path.sep}`)) {
        continue;
      }

      const sessionId = path.basename(filePath, ".jsonl");
      const meta = sessionMeta.get(sessionId);
      rankedSessions.push({
        source: "claude-code",
        sessionId,
        filePath,
        timestamp: meta?.timestamp ?? safeMtimeMs(filePath),
        branch: meta?.branch ?? null,
        repoPath: meta?.repoPath ?? null,
      });
    }
  }

  const dedupedSessions = uniqueBy(
    rankedSessions,
    (session) => `${session.sessionId}:${session.filePath}`,
  ).sort((left, right) => right.timestamp - left.timestamp);

  return dedupedSessions.slice(0, sessionLimit).flatMap((session) => parseClaudeSession(session));
}

function parseClaudeSession(session: RankedSession): ContextRecord[] {
  const raw = safeReadText(session.filePath);
  if (raw === null) {
    return [];
  }

  const records: ContextRecord[] = [];
  const lines = raw.split(/\r?\n/);

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (line === undefined || line.trim().length === 0) {
      continue;
    }

    const entry = safeJsonParse<Record<string, unknown>>(line);
    if (entry === null) {
      continue;
    }

    const type = asString(entry.type);
    const timestamp = dateStringToEpoch(asString(entry.timestamp)) ?? session.timestamp;

    if (type === "user") {
      const message = asRecord(entry.message);
      const content = message?.content;

      if (typeof content === "string") {
        const text = collapseWhitespace(content);
        if (text.length > 0 && !Boolean(entry.isMeta) && !text.includes("<local-command-caveat>")) {
          records.push(createRecord({
            source: "claude-code",
            session,
            timestamp,
            role: "user",
            kind: "message",
            text,
            files: extractFilesFromUnknown(content),
            tool: null,
            citation: `${session.sessionId}#L${index + 1}`,
          }));
        }

        continue;
      }

      if (Array.isArray(content)) {
        for (const part of content) {
          const partRecord = asRecord(part);
          if (partRecord?.type !== "tool_result") {
            continue;
          }

          const text = collapseWhitespace(typeof partRecord.content === "string" ? partRecord.content : JSON.stringify(partRecord.content));
          if (text.length === 0) {
            continue;
          }

          records.push(createRecord({
            source: "claude-code",
            session,
            timestamp,
            role: "tool",
            kind: partRecord.is_error === true ? "tool-error" : "tool-result",
            text,
            files: extractFilesFromUnknown((asRecord(entry.toolUseResult)?.filenames ?? partRecord.content) as unknown),
            tool: null,
            citation: `${session.sessionId}#L${index + 1}`,
          }));
        }
      }

      continue;
    }

    if (type !== "assistant") {
      continue;
    }

    const message = asRecord(entry.message);
    const content = message?.content;
    if (!Array.isArray(content)) {
      continue;
    }

    for (const part of content) {
      const partRecord = asRecord(part);
      const partType = asString(partRecord?.type);

      if (partType === "text") {
        const text = collapseWhitespace(asString(partRecord?.text) ?? "");
        if (text.length === 0) {
          continue;
        }

        records.push(createRecord({
          source: "claude-code",
          session,
          timestamp,
          role: "assistant",
          kind: "message",
          text,
          files: extractFilesFromUnknown(text),
          tool: null,
          citation: `${session.sessionId}#L${index + 1}`,
        }));
        continue;
      }

      if (partType === "tool_use") {
        const toolName = asString(partRecord?.name);
        const input = partRecord?.input;
        const text = collapseWhitespace(`${toolName ?? "tool"}: ${safeStringify(input)}`);
        records.push(createRecord({
          source: "claude-code",
          session,
          timestamp,
          role: "tool",
          kind: "tool-use",
          text,
          files: extractFilesFromUnknown(input),
          tool: toolName,
          citation: `${session.sessionId}#L${index + 1}`,
        }));
      }
    }
  }

  return records;
}

function collectOpenCodeRecords(repo: RepoIdentity, sessionLimit: number): ContextRecord[] {
  const databasePath = path.join(homedir(), ".local", "share", "opencode", "opencode-stable.db");
  if (!existsSync(databasePath)) {
    return [];
  }

  using db = new Database(databasePath, { readonly: true, strict: true });
  const sessionRows = db
    .query<{
      id: string;
      directory: string;
      time_updated: number;
    }, []>("select id, directory, time_updated from session order by time_updated desc")
    .all();

  const matchingSessions = sessionRows
    .filter((row) => repoMatches(row.directory, repo))
    .slice(0, sessionLimit)
    .map((row) => ({
      source: "opencode" as const,
      sessionId: row.id,
      filePath: databasePath,
      timestamp: row.time_updated,
      branch: repo.branch,
      repoPath: row.directory,
    }));

  const records: ContextRecord[] = [];

  const partQuery = db.query<
    {
      part_id: string;
      time_created: number;
      part_data: string;
      message_data: string;
    },
    [string]
  >(
    `select
      p.id as part_id,
      p.time_created as time_created,
      p.data as part_data,
      m.data as message_data
    from part p
    join message m on m.id = p.message_id
    where p.session_id = ?1
    order by p.time_created asc`
  );

  for (const session of matchingSessions) {
    const rows = partQuery.all(session.sessionId);
    for (const row of rows) {
      const partData = safeJsonParse<Record<string, unknown>>(row.part_data);
      const messageData = safeJsonParse<Record<string, unknown>>(row.message_data);
      if (partData === null || messageData === null) {
        continue;
      }

      const partType = asString(partData.type);
      const role = asString(messageData.role);
      const timestamp = row.time_created;
      const citation = `${session.sessionId}/${row.part_id}`;

      if (partType === "text" && (role === "user" || role === "assistant")) {
        const text = collapseWhitespace(asString(partData.text) ?? "");
        if (text.length === 0) {
          continue;
        }

        records.push(createRecord({
          source: "opencode",
          session,
          timestamp,
          role,
          kind: "message",
          text,
          files: extractFilesFromUnknown(text),
          tool: null,
          citation,
        }));
        continue;
      }

      if (partType === "tool") {
        const tool = asString(partData.tool);
        const state = asRecord(partData.state);
        const input = state?.input;
        const output = state?.output;
        const status = asString(state?.status) ?? "unknown";
        const text = collapseWhitespace(
          `${tool ?? "tool"} (${status}) input=${safeStringify(input)} output=${truncate(collapseWhitespace(stringifyUnknown(output)), 240)}`
        );

        records.push(createRecord({
          source: "opencode",
          session,
          timestamp,
          role: "tool",
          kind: status === "error" ? "tool-error" : "tool-result",
          text,
          files: extractFilesFromUnknown([input, output]),
          tool,
          citation,
        }));
      }
    }
  }

  return records;
}

function createRecord(input: {
  source: Source;
  session: RankedSession;
  timestamp: number;
  role: Role;
  kind: string;
  text: string;
  files: string[];
  tool: string | null;
  citation: string;
}): ContextRecord {
  return {
    source: input.source,
    sessionId: input.session.sessionId,
    timestamp: input.timestamp,
    role: input.role,
    kind: input.kind,
    text: truncate(input.text, 800),
    files: unique(input.files),
    tool: input.tool,
    branch: input.session.branch,
    citation: input.citation,
    repoPath: input.session.repoPath,
    score: 0,
  };
}

function matchesLens(record: ContextRecord, lens: Lens): boolean {
  switch (lens) {
    case "recent":
      return true;
    case "user":
      return record.role === "user";
    case "assistant":
      return record.role === "assistant";
    case "tools":
      return record.kind.startsWith("tool") || record.role === "tool";
    case "errors":
      return /\berror\b|\bfailed\b|\bexception\b|\bdenied\b|not found/i.test(record.text);
    case "files":
      return record.files.length > 0;
    case "plans":
      return /\bplan\b|\bsteps\b|\btodo\b|\bworkflow\b|\bapproach\b/i.test(record.text);
    case "prefs":
      return record.role === "user" && /\bprefer\b|\bi want\b|\bi'd like\b|\bgo with\b|\bskip\b|\bonly\b/i.test(record.text);
    case "decisions":
      return /\brecommend\b|\bgo with\b|\bdecided\b|\bsettled\b|\bbest\b|\bshould use\b/i.test(record.text);
  }
}

function isSelfNoise(record: ContextRecord, query: string | null): boolean {
  const normalizedText = record.text.toLowerCase();
  const normalizedQuery = query?.toLowerCase() ?? null;
  const isToolingQuery =
    normalizedQuery !== null &&
    ["recent-work-context", "recent work context", "opencode", "claude-code", "claude code", "skill"].some((term) =>
      normalizedQuery.includes(term),
    );

  if (!isToolingQuery) {
    const recentWorkContextMentions = [
      "recent-work-context",
      ".claude/skills/recent-work-context",
      "modules/devtools/ai/global-skills/recent-work-context",
      "--session-limit",
      "source=all",
      "source=claude-code",
      "source=opencode",
    ];

    if (recentWorkContextMentions.some((term) => normalizedText.includes(term))) {
      return true;
    }

    if (
      record.files.some(
        (file) => file.includes("recent-work-context") || file.includes("modules/devtools/ai/global-skills/recent-work-context"),
      )
    ) {
      return true;
    }
  }

  return (
    normalizedText.includes("recent work context for") ||
    normalizedText.includes("bun ~/.claude/skills/recent-work-context") ||
    normalizedText.includes("recent-work-context.ts") ||
    (record.role === "tool" &&
      (normalizedText.includes("recent-work-context.ts") ||
      normalizedText.includes("bun run typecheck") ||
      normalizedText.includes("tsc -p tsconfig.json") ||
      normalizedText.includes("description\":\"typechecks") ||
      normalizedText.includes("description\":\"tests") ||
      normalizedText.includes("description\":\"re-tests") ||
      normalizedText.includes("recent-work-context --profile") ||
      normalizedText.includes("sessions-index.json") ||
      normalizedText.includes(".claude/projects/") ||
      normalizedText.includes("readfilesync(") ||
      normalizedText.includes("node - <<'node'") ||
      record.files.some((file) => file.includes("recent-work-context.ts"))))
  );
}

function hasQueryMatch(record: ContextRecord, query: string | null, repo: RepoIdentity): boolean {
  if (query === null) {
    return true;
  }

  const normalizedQuery = query.toLowerCase();
  const tokens = tokenizeQuery(normalizedQuery);
  const repoFiles = record.files
    .map((file) => normalizeRepoFile(file, repo))
    .filter((file): file is string => file !== null)
    .map((file) => file.toLowerCase());
  const haystacks = [record.text.toLowerCase(), ...repoFiles];

  if (haystacks.some((haystack) => haystack.includes(normalizedQuery))) {
    return true;
  }

  const matchedTokens = tokens.filter((token) => haystacks.some((haystack) => haystack.includes(token)));
  const requiredMatches = tokens.length <= 1 ? 1 : Math.min(2, tokens.length);

  return unique(matchedTokens).length >= requiredMatches;
}

function scoreRecord(record: ContextRecord, query: string | null, lens: Lens, repo: RepoIdentity): number {
  let score = 0;

  if (query !== null) {
    const normalizedQuery = query.toLowerCase();
    const normalizedText = record.text.toLowerCase();
    const tokens = tokenizeQuery(normalizedQuery);
    const repoFiles = record.files
      .map((file) => normalizeRepoFile(file, repo))
      .filter((file): file is string => file !== null)
      .map((file) => file.toLowerCase());

    if (normalizedText.includes(normalizedQuery)) {
      score += 24;
    }

    for (const token of tokens) {
      if (normalizedText.includes(token)) {
        score += 6;
      }

      if (repoFiles.some((file) => file.includes(token))) {
        score += 8;
      }
    }
  }

  if (lens === "files" && record.files.length > 0) {
    score += 10;
  }

  if (lens === "tools" && record.role === "tool") {
    score += 10;
  }

  if (lens === "errors" && /\berror\b|\bfailed\b|\bexception\b/i.test(record.text)) {
    score += 12;
  }

  if (record.repoPath !== null && normalizePath(record.repoPath) === repo.root) {
    score += 15;
  }

  if (record.role === "user") {
    score += 5;
  } else if (record.role === "assistant") {
    score += 3;
  } else if (lens !== "tools") {
    score -= 10;
  }

  if (lens === "recent" && record.role === "tool") {
    score -= 12;
  }

  if (record.role === "tool" && ["Read", "Grep", "Glob", "Edit", "Write", "read", "grep", "glob", "edit", "write"].includes(record.tool ?? "")) {
    score -= 8;
  }

  const ageDays = Math.max(0, (Date.now() - record.timestamp) / (24 * 60 * 60 * 1000));
  score += Math.max(0, 12 - ageDays / 14);

  return score;
}

function renderHuman(payload: OutputPayload, since: string | null): string {
  if (payload.profile === "agent") {
    return renderAgent(payload, since);
  }

  const lines = [
    `Recent work context for ${payload.repo.root}`,
    `profile=${payload.profile} lens=${payload.lens} source=${payload.source}${payload.query === null ? "" : ` query=${JSON.stringify(payload.query)}`}${since === null ? "" : ` since=${since}`}`,
    `results=${payload.counts.total} excerpts claude-code=${payload.counts.bySource["claude-code"]}/${payload.counts.sessionsBySource["claude-code"]}sessions opencode=${payload.counts.bySource.opencode}/${payload.counts.sessionsBySource.opencode}sessions`,
  ];

  if (payload.records.length === 0) {
    lines.push("No matching excerpts found.");
    return lines.join("\n");
  }

  lines.push("");

  for (const record of payload.records) {
    lines.push(`- [${formatTimestamp(record.timestamp)}] ${record.source} ${record.role} ${record.citation}`);
    lines.push(`  ${record.text}`);
    if (record.files.length > 0) {
      lines.push(`  files: ${record.files.slice(0, 5).join(", ")}`);
    }
  }

  return lines.join("\n");
}

function renderAgent(payload: OutputPayload, since: string | null): string {
  const groups = selectFocusedGroups(
    groupRecordsBySession(payload.records),
    DEFAULT_AGENT_RENDERED_GROUPS,
    DEFAULT_AGENT_SCORE_WINDOW,
  );
  const lines = [
    `Recent work context for ${payload.repo.root}`,
    `profile=${payload.profile} lens=${payload.lens} source=${payload.source}${payload.query === null ? "" : ` query=${JSON.stringify(payload.query)}`}${since === null ? "" : ` since=${since}`}`,
    `results=${payload.counts.total} excerpts sessions=${groups.length} claude-code=${payload.counts.bySource["claude-code"]}/${payload.counts.sessionsBySource["claude-code"]}sessions opencode=${payload.counts.bySource.opencode}/${payload.counts.sessionsBySource.opencode}sessions`,
  ];

  if (groups.length === 0) {
    lines.push("No matching excerpts found.");
    return lines.join("\n");
  }

  lines.push("");
  lines.push("Derived summary:");

  renderSummarySection(lines, "Overview", payload.summary.overview);
  renderSummaryItems(lines, "Decisions", payload.summary.decisions);
  renderSummaryItems(lines, "Preferences", payload.summary.preferences);
  renderSummaryFiles(lines, "Relevant Files", payload.summary.relevantFiles);
  renderSummaryAreas(lines, "Changed Areas", payload.summary.changedAreas);
  renderSummaryItems(lines, "Failures / Fixes", payload.summary.failuresAndFixes);
  renderSummarySessions(lines, "Session Summaries", payload.summary.sessions);

  lines.push("");
  lines.push("Evidence groups:");

  for (const group of groups) {
    lines.push(`- ${group.source} ${group.sessionId} latest=${formatTimestamp(group.latestTimestamp)} excerpts=${group.records.length}${group.branch === null ? "" : ` branch=${group.branch}`}`);

    const synopsis = selectSynopsisRecord(group.records, payload.query);
    if (synopsis !== undefined) {
      lines.push(`  synopsis: ${previewText(synopsis.text, 240)}`);
    }

    const visibleFiles = unique(
      group.files
        .map((file) => normalizeRepoFile(file, payload.repo))
        .filter((file): file is string => file !== null)
    ).slice(0, 6);

    if (visibleFiles.length > 0) {
      lines.push(`  files: ${visibleFiles.join(", ")}`);
    }

    const evidenceRecords = selectEvidenceRecords(group.records, payload.lens, payload.query);

    for (const record of evidenceRecords) {
      lines.push(`  - [${record.role}] ${record.citation}`);
      lines.push(`    ${previewText(record.text, 320)}`);
    }

    if (group.records.length > evidenceRecords.length) {
      lines.push(`  - ... ${group.records.length - evidenceRecords.length} more excerpts omitted`);
    }
  }

  return lines.join("\n");
}

function selectTopRecords(records: ContextRecord[], limit: number, perSessionLimit: number): ContextRecord[] {
  const selected: ContextRecord[] = [];
  const perSessionCounts = new Map<string, number>();

  for (const record of records) {
    const currentCount = perSessionCounts.get(record.sessionId) ?? 0;
    if (currentCount >= perSessionLimit) {
      continue;
    }

    selected.push(record);
    perSessionCounts.set(record.sessionId, currentCount + 1);

    if (selected.length >= limit) {
      break;
    }
  }

  return selected;
}

function groupRecordsBySession(records: ContextRecord[]): SessionGroup[] {
  const groups = new Map<string, SessionGroup>();
  const orderedGroups: SessionGroup[] = [];

  for (const record of records) {
    const existing = groups.get(record.sessionId);
    if (existing !== undefined) {
      existing.records.push(record);
      existing.latestTimestamp = Math.max(existing.latestTimestamp, record.timestamp);
      existing.files = unique([...existing.files, ...record.files]).slice(0, 10);
      continue;
    }

    const group: SessionGroup = {
      source: record.source,
      sessionId: record.sessionId,
      branch: record.branch,
      latestTimestamp: record.timestamp,
      files: unique(record.files).slice(0, 10),
      records: [record],
    };

    groups.set(record.sessionId, group);
    orderedGroups.push(group);
  }

  return orderedGroups;
}

function selectFocusedGroups(groups: SessionGroup[], maxGroups: number, scoreWindow: number): SessionGroup[] {
  const topGroup = groups[0];
  if (topGroup === undefined) {
    return [];
  }

  const topScore = maxGroupScore(topGroup);
  return groups
    .filter((group) => maxGroupScore(group) >= topScore - scoreWindow)
    .slice(0, maxGroups);
}

function maxGroupScore(group: SessionGroup): number {
  return Math.max(...group.records.map((record) => record.score));
}

function selectEvidenceRecords(records: ContextRecord[], lens: Lens, query: string | null): ContextRecord[] {
  if (lens === "tools") {
    return records.slice(0, DEFAULT_AGENT_RENDERED_EXCERPTS);
  }

  const nonToolRecords = records
    .filter((record) => record.role !== "tool")
    .slice()
    .sort((left, right) => synopsisScore(right, query) - synopsisScore(left, query));

  if (nonToolRecords.length > 0) {
    return nonToolRecords.slice(0, DEFAULT_AGENT_RENDERED_EXCERPTS);
  }

  return records.slice(0, DEFAULT_AGENT_RENDERED_EXCERPTS);
}

function previewText(value: string, maxLength: number): string {
  const compact = collapseWhitespace(value);
  return truncate(compact, maxLength);
}

function deriveSummary(
  records: ContextRecord[],
  groups: SessionGroup[],
  repo: RepoIdentity,
  query: string | null,
): DerivedSummary {
  const focusedGroups = selectFocusedGroups(groups, 6, DEFAULT_AGENT_SCORE_WINDOW);
  const focusedRecords = focusedGroups.flatMap((group) => group.records);
  const summaryRecords = focusedRecords.some((record) => record.role !== "tool")
    ? focusedRecords.filter((record) => record.role !== "tool")
    : focusedRecords;
  const relevantFiles = summarizeFiles(summaryRecords, repo, 8);
  const changedAreas = summarizeAreas(relevantFiles, 8);
  const overview = [
    `Matched ${records.length} ranked excerpts across ${groups.length} sessions${query === null ? "" : ` for ${JSON.stringify(query)}`}.`,
  ];

  if (focusedGroups.length < groups.length) {
    overview.push(`Focused summary covers the top ${focusedGroups.length} sessions by relevance.`);
  }

  if (relevantFiles.length > 0) {
    overview.push(`Most mentioned repo files: ${relevantFiles.slice(0, 4).map((file) => file.path).join(", ")}.`);
  }

  if (changedAreas.length > 0) {
    overview.push(`Most active areas: ${changedAreas.slice(0, 3).map((area) => area.path).join(", ")}.`);
  }

  const topGroup = focusedGroups[0] ?? groups[0];
  if (topGroup !== undefined) {
    overview.push(`Most recent strong match: ${topGroup.source} ${topGroup.sessionId} at ${formatTimestamp(topGroup.latestTimestamp)}.`);
  }

  const decisions = summarizeRecords(
    summaryRecords.filter((record) => isDecisionRecord(record)),
    6,
    undefined,
    formatDecisionSummary,
  );
  const preferences = summarizeRecords(
    summaryRecords.filter((record) => isPreferenceRecord(record)),
    6,
    undefined,
    formatPreferenceSummary,
  );
  const failures = summarizeRecords(
    summaryRecords.filter((record) => /\berror\b|\bfailed\b|\bexception\b|\bdenied\b|not found|warning: download buffer is full/i.test(record.text)),
    3,
    "Failure",
  );
  const fixes = summarizeRecords(
    summaryRecords.filter((record) => record.role !== "user" && /\bupdated\b|\bchanged\b|\bfixed\b|\bnow writes\b|\bredirect\b|\bcreated\b|\brecap written\b/i.test(record.text)),
    3,
    "Fix",
  );

  return {
    overview,
    decisions,
    preferences,
    relevantFiles,
    changedAreas,
    failuresAndFixes: [...failures, ...fixes].slice(0, 6),
    sessions: focusedGroups.map((group) => {
      const synopsisRecord = selectSynopsisRecord(group.records, query);

      return {
        source: group.source,
        sessionId: group.sessionId,
        latestTimestamp: group.latestTimestamp,
        synopsis: synopsisRecord === undefined ? "" : previewText(synopsisRecord.text, 220),
        files: unique(group.files.map((file) => normalizeRepoFile(file, repo)).filter((file): file is string => file !== null)).slice(0, 4),
        citations: unique(group.records.map((record) => record.citation)).slice(0, 4),
      };
    }),
  };
}

function summarizeRecords(records: ContextRecord[], maxItems: number, prefix?: string, formatter?: SummaryFormatter): SummaryItem[] {
  const items = new Map<string, SummaryItem>();

  for (const record of records) {
    const body = formatter === undefined ? previewText(record.text, 220) : formatter(record);
    const text = `${prefix === undefined ? "" : `${prefix}: `}${body}`;
    const key = normalizeSummaryKey(text);
    const existing = items.get(key);

    if (existing !== undefined) {
      existing.citations = unique([...existing.citations, record.citation]).slice(0, 4);
      continue;
    }

    items.set(key, {
      text,
      citations: [record.citation],
    });

    if (items.size >= maxItems) {
      break;
    }
  }

  return [...items.values()];
}

function summarizeFiles(records: ContextRecord[], repo: RepoIdentity, maxItems: number): SummaryFile[] {
  const files = new Map<string, { mentions: number; citations: string[] }>();

  for (const record of records) {
    for (const file of record.files) {
      const normalized = normalizeRepoFile(file, repo);
      if (normalized === null) {
        continue;
      }

      const existing = files.get(normalized);
      if (existing !== undefined) {
        existing.mentions += 1;
        existing.citations = unique([...existing.citations, record.citation]).slice(0, 4);
        continue;
      }

      files.set(normalized, {
        mentions: 1,
        citations: [record.citation],
      });
    }
  }

  return [...files.entries()]
    .sort((left, right) => {
      if (right[1].mentions !== left[1].mentions) {
        return right[1].mentions - left[1].mentions;
      }

      return left[0].localeCompare(right[0]);
    })
    .slice(0, maxItems)
    .map(([filePath, data]) => ({
      path: filePath,
      mentions: data.mentions,
      citations: data.citations,
    }));
}

function summarizeAreas(files: SummaryFile[], maxItems: number): SummaryArea[] {
  const areas = new Map<string, { mentions: number; citations: string[] }>();

  for (const file of files) {
    const areaPath = toAreaPath(file.path);
    const existing = areas.get(areaPath);
    if (existing !== undefined) {
      existing.mentions += file.mentions;
      existing.citations = unique([...existing.citations, ...file.citations]).slice(0, 4);
      continue;
    }

    areas.set(areaPath, {
      mentions: file.mentions,
      citations: file.citations,
    });
  }

  return [...areas.entries()]
    .sort((left, right) => {
      if (right[1].mentions !== left[1].mentions) {
        return right[1].mentions - left[1].mentions;
      }

      return left[0].localeCompare(right[0]);
    })
    .slice(0, maxItems)
    .map(([areaPath, data]) => ({
      path: areaPath,
      mentions: data.mentions,
      citations: data.citations,
    }));
}

function toAreaPath(filePath: string): string {
  const parts = filePath.split("/").filter(Boolean);
  if (parts.length <= 1) {
    return filePath;
  }

  const head = parts[0];
  if (head === undefined) {
    return filePath;
  }

  if (head === "modules") {
    return parts.slice(0, Math.min(3, parts.length)).join("/");
  }

  if (head === "hosts") {
    return parts.slice(0, Math.min(2, parts.length)).join("/");
  }

  if (head.startsWith(".")) {
    return head;
  }

  return head;
}

function normalizeRepoFile(file: string, repo: RepoIdentity): string | null {
  const clean = file
    .trim()
    .replace(/[),.;:]+$/g, "")
    .replace(/#L\d+(?:C\d+)?$/i, "")
    .replace(/:\d+(?::\d+)?$/i, "");

  if (
    clean.length === 0 ||
    clean.includes("$") ||
    clean.startsWith("//") ||
    clean.startsWith("/nix/store/") ||
    clean.startsWith("/etc/") ||
    clean.startsWith("/usr/") ||
    clean.startsWith("/dev/") ||
    clean.startsWith("HOME/")
  ) {
    return null;
  }

  const candidate = path.isAbsolute(clean)
    ? path.resolve(clean)
    : path.resolve(repo.root, clean);
  if (!pathIsInside(repo.root, candidate) || !existsSync(candidate)) {
    return null;
  }

  let canonicalCandidate: string;
  try {
    canonicalCandidate = normalizePath(realpathSync(candidate));
  } catch {
    return null;
  }

  if (!pathIsInside(repo.root, canonicalCandidate)) {
    return null;
  }

  return path.relative(repo.root, canonicalCandidate).split(path.sep).join("/");
}

function renderSummarySection(lines: string[], title: string, values: string[]): void {
  if (values.length === 0) {
    return;
  }

  lines.push(`${title}:`);
  for (const value of values) {
    lines.push(`- ${value}`);
  }
}

function renderSummaryItems(lines: string[], title: string, items: SummaryItem[]): void {
  if (items.length === 0) {
    return;
  }

  lines.push(`${title}:`);
  for (const item of items) {
    lines.push(`- ${item.text} [${item.citations.join(", ")}]`);
  }
}

function renderSummaryFiles(lines: string[], title: string, files: SummaryFile[]): void {
  if (files.length === 0) {
    return;
  }

  lines.push(`${title}:`);
  for (const file of files) {
    lines.push(`- ${file.path} (${file.mentions} mentions; ${file.citations.join(", ")})`);
  }
}

function renderSummaryAreas(lines: string[], title: string, areas: SummaryArea[]): void {
  if (areas.length === 0) {
    return;
  }

  lines.push(`${title}:`);
  for (const area of areas) {
    lines.push(`- ${area.path} (${area.mentions} mentions; ${area.citations.join(", ")})`);
  }
}

function renderSummarySessions(lines: string[], title: string, sessions: SummarySession[]): void {
  if (sessions.length === 0) {
    return;
  }

  lines.push(`${title}:`);
  for (const session of sessions) {
    const suffix = session.files.length === 0 ? "" : ` files=${session.files.join(", ")}`;
    lines.push(`- ${session.source} ${session.sessionId} latest=${formatTimestamp(session.latestTimestamp)}${suffix}`);
    lines.push(`  ${session.synopsis}`);
    lines.push(`  citations: ${session.citations.join(", ")}`);
  }
}

function normalizeSummaryKey(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function formatDecisionSummary(record: ContextRecord): string {
  const text = stripSummaryMarkup(record.text);
  return previewText(extractSummaryCandidate(text, "decision"), 180);
}

function formatPreferenceSummary(record: ContextRecord): string {
  const text = stripSummaryMarkup(record.text);
  return previewText(extractSummaryCandidate(text, "preference"), 180);
}

function stripSummaryMarkup(value: string): string {
  return collapseWhitespace(
    value
      .replace(/```[\s\S]*?```/g, " ")
      .replace(/`([^`]+)`/g, "$1")
      .replace(/\*\*([^*]+)\*\*/g, "$1")
      .replace(/\[(.*?)\]\((.*?)\)/g, "$1")
  );
}

function extractSummaryCandidate(value: string, mode: "decision" | "preference"): string {
  const normalized = collapseWhitespace(
    value
      .replace(/^#+\s*/gm, "")
      .replace(/^[-*]\s+/gm, "")
      .replace(/\b(current state|fit check|summary|read-only findings|overview):\s*/gi, "")
  );

  const sentences = normalized
    .split(/(?<=[.!?])\s+/)
    .map((sentence) => sentence.trim())
    .filter(Boolean);

  const ranked = sentences
    .map((sentence) => ({ sentence, score: summarySentenceScore(sentence, mode) }))
    .sort((left, right) => right.score - left.score);

  const best = ranked[0]?.sentence;
  if (best !== undefined && ranked[0]?.score !== undefined && ranked[0].score > 0) {
    return best;
  }

  return normalized;
}

function summarySentenceScore(sentence: string, mode: "decision" | "preference"): number {
  const text = sentence.toLowerCase();
  let score = 0;

  if (mode === "decision") {
    if (/\brecommend\b|\bgo with\b|\bdecided\b|\bsettled\b|\bbest\b|\bshould use\b|\bgood choice\b/.test(text)) {
      score += 10;
    }
    if (/\boptional\b|\bnot required\b|\bskip\b/.test(text)) {
      score += 4;
    }
  } else {
    if (/\bpref(?:er|err|fer)\b|\bi want\b|\bi'd like\b|\bgo with\b|\bskip\b|\bonly\b|\bshould be\b/.test(text)) {
      score += 10;
    }
    if (/\bglobal\b|\brepo\b|\bshared cli\b|\bbun\b/.test(text)) {
      score += 3;
    }
  }

  if (/^\*+/.test(sentence) || text.startsWith("web search results") || text.startsWith("found ")) {
    score -= 8;
  }

  if (sentence.length > 240) {
    score -= 2;
  }

  return score;
}

function deriveAgentContext(
  summary: DerivedSummary,
  records: ContextRecord[],
  repo: RepoIdentity,
  query: string | null,
  lens: Lens,
  source: SourceFilter,
): AgentContext {
  return {
    repoRoot: repo.root,
    query,
    source,
    lens,
    overview: summary.overview,
    decisions: summary.decisions.map((item) => item.text),
    preferences: summary.preferences.map((item) => item.text),
    relevantFiles: summary.relevantFiles.map((item) => item.path),
    changedAreas: summary.changedAreas.map((item) => item.path),
    failuresAndFixes: summary.failuresAndFixes.map((item) => item.text),
    sessions: summary.sessions.map((session) => ({
      source: session.source,
      sessionId: session.sessionId,
      latestTimestamp: session.latestTimestamp,
      synopsis: session.synopsis,
      files: session.files,
      citations: session.citations,
    })),
    topCitations: unique(records.slice(0, 8).map((record) => record.citation)),
  };
}

function selectSynopsisRecord(records: ContextRecord[], query: string | null): ContextRecord | undefined {
  const candidates = records
    .filter((record) => record.role !== "tool")
    .slice()
    .sort((left, right) => synopsisScore(right, query) - synopsisScore(left, query));

  return candidates[0] ?? records[0];
}

function synopsisScore(record: ContextRecord, query: string | null): number {
  let score = record.score;
  const text = record.text.toLowerCase();

  if (record.role === "assistant") {
    score += 4;
  }

  if (record.role === "user") {
    score += 2;
  }

  if (text.startsWith("explore this repository") || text.startsWith("report how ")) {
    score -= 16;
  }

  if (/\bdone\b|\bimplemented\b|\bupdated\b|\bfixed\b|\bcurrent state\b|\bsummary\b/i.test(record.text)) {
    score += 5;
  }

  if (query !== null && text.includes(query.toLowerCase())) {
    score += 3;
  }

  return score;
}

function tokenizeQuery(query: string): string[] {
  return unique(
    query
      .split(/\s+/)
      .map((token) => token.trim())
      .filter((token) => token.length >= 2)
  );
}

function isDecisionRecord(record: ContextRecord): boolean {
  if (record.kind !== "message" || record.role === "tool") {
    return false;
  }

  const text = record.text.toLowerCase();
  if (text.includes("web search results for query") || text.startsWith("found ")) {
    return false;
  }

  return /\brecommend\b|\bgo with\b|\bdecided\b|\bsettled\b|\bbest\b|\bshould use\b|\bgood choice\b|\bbest shape\b/.test(text);
}

function isPreferenceRecord(record: ContextRecord): boolean {
  if (record.kind !== "message" || record.role !== "user") {
    return false;
  }

  const text = record.text.toLowerCase();
  if (text.startsWith("explore this repository") || text.startsWith("report how ")) {
    return false;
  }

  return /\bpref(?:er|err|fer)\b|\bi want\b|\bi'd like\b|\bgo with\b|\bskip\b|\bonly\b|\bshould be\b|\bmy [a-z0-9- ]+ should\b/.test(text);
}

function repoMatches(candidate: string | null, repo: RepoIdentity): boolean {
  if (candidate === null) {
    return false;
  }

  return normalizePath(candidate) === repo.root;
}

function pathIsInside(root: string, candidate: string): boolean {
  const relative = path.relative(root, candidate);
  return relative === "" || (
    relative !== ".." &&
    !relative.startsWith(`..${path.sep}`) &&
    !path.isAbsolute(relative)
  );
}

function findFilesByName(root: string, targetName: string): string[] {
  const matches: string[] = [];
  const stack = [root];

  while (stack.length > 0) {
    const current = stack.pop();
    if (current === undefined) {
      continue;
    }

    let entries: string[];
    try {
      entries = readdirSync(current);
    } catch {
      continue;
    }

    for (const entry of entries) {
      const fullPath = path.join(current, entry);
      let stats;
      try {
        stats = statSync(fullPath);
      } catch {
        continue;
      }

      if (stats.isDirectory()) {
        stack.push(fullPath);
        continue;
      }

      if (stats.isFile() && entry === targetName) {
        matches.push(fullPath);
      }
    }
  }

  return matches;
}

function findFilesBySuffix(root: string, suffix: string): string[] {
  const matches: string[] = [];
  const stack = [root];

  while (stack.length > 0) {
    const current = stack.pop();
    if (current === undefined) {
      continue;
    }

    let entries: string[];
    try {
      entries = readdirSync(current);
    } catch {
      continue;
    }

    for (const entry of entries) {
      const fullPath = path.join(current, entry);
      let stats;
      try {
        stats = statSync(fullPath);
      } catch {
        continue;
      }

      if (stats.isDirectory()) {
        stack.push(fullPath);
        continue;
      }

      if (stats.isFile() && entry.endsWith(suffix)) {
        matches.push(fullPath);
      }
    }
  }

  return matches;
}

function safeMtimeMs(filePath: string): number {
  try {
    return statSync(filePath).mtimeMs;
  } catch {
    return 0;
  }
}

function extractFilesFromUnknown(value: unknown): string[] {
  const text = stringifyUnknown(value);
  const matches = text.match(/(?:\/[^\s"'`<>]+(?:\.[A-Za-z0-9_-]+)?)|(?:[A-Za-z0-9._-]+\/[A-Za-z0-9._\/-]*\.[A-Za-z0-9_-]+)/g) ?? [];
  return unique(
    matches
      .map((match) => match.replace(/[),.;:]+$/g, ""))
      .filter((match) => !match.includes("://"))
      .filter((match) => match.includes("/") || match.startsWith("."))
  );
}

function safeReadText(filePath: string): string | null {
  try {
    return readFileSync(filePath, "utf8");
  } catch {
    return null;
  }
}

function safeJsonParse<T>(value: string): T | null {
  try {
    return JSON.parse(value) as T;
  } catch {
    return null;
  }
}

function stringifyUnknown(value: unknown): string {
  if (typeof value === "string") {
    return value;
  }

  if (value === null || value === undefined) {
    return "";
  }

  return safeStringify(value);
}

function safeStringify(value: unknown): string {
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function asString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function asNumber(value: unknown): number | null {
  return typeof value === "number" ? value : null;
}

function normalizePath(value: string): string {
  const resolved = path.resolve(value);
  try {
    return realpathSync(resolved).replace(/\/+$/, "");
  } catch {
    return resolved.replace(/\/+$/, "");
  }
}

function normalizeRemote(value: string): string {
  return collapseWhitespace(value)
    .replace(/^[^@\s]+@([^:]+):/, "$1/")
    .replace(/^[a-z][a-z0-9+.-]*:\/\//i, "")
    .replace(/^[^/@\s]+@/, "")
    .replace(/\.git$/, "")
    .replace(/\/+$/, "")
    .toLowerCase();
}

function collapseWhitespace(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

function truncate(value: string, length: number): string {
  return value.length <= length ? value : `${value.slice(0, length - 1)}...`;
}

function unique(values: string[]): string[] {
  return [...new Set(values)];
}

function uniqueBy<T>(values: T[], keyFn: (value: T) => string): T[] {
  const seen = new Set<string>();
  const uniqueValues: T[] = [];

  for (const value of values) {
    const key = keyFn(value);
    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    uniqueValues.push(value);
  }

  return uniqueValues;
}

function dateStringToEpoch(value: string | null): number | null {
  if (value === null) {
    return null;
  }

  const epoch = Date.parse(value);
  return Number.isNaN(epoch) ? null : epoch;
}

function formatTimestamp(value: number): string {
  return new Date(value).toISOString().replace("T", " ").replace(".000Z", "Z");
}
