import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const DEFAULT_SESSIONS_DIR = path.join(os.homedir(), '.codex', 'sessions');
const DEFAULT_SESSION_INDEX = path.join(os.homedir(), '.codex', 'session_index.jsonl');

const HELP = `codex-monitor

Usage:
  codex-monitor sessions [options]

Options:
  --path <path>       Codex sessions directory (default: ~/.codex/sessions)
  --index <path>      Codex session index file (default: ~/.codex/session_index.jsonl)
  --limit <number>    Limit rendered workflows (default: all)
  --since <duration>  Include sessions active since duration, e.g. 24h, 7d, 2w
  --project <name>    Filter by project directory basename
  --json              Print parsed workflow data as JSON
  --no-expand         Do not expand sub-agent workflow rows
  -h, --help          Show help
`;

const parseArgs = (argv) => {
  const args = {
    command: 'sessions',
    sessionsDir: DEFAULT_SESSIONS_DIR,
    indexPath: DEFAULT_SESSION_INDEX,
    limit: null,
    since: null,
    project: null,
    json: false,
    expand: true,
    help: false,
  };

  const rest = [...argv];
  if (rest[0] && !rest[0].startsWith('-')) {
    args.command = rest.shift();
  }

  while (rest.length > 0) {
    const arg = rest.shift();
    if (arg === '--path') args.sessionsDir = expandHome(requireValue(arg, rest.shift()));
    else if (arg === '--index') args.indexPath = expandHome(requireValue(arg, rest.shift()));
    else if (arg === '--limit') args.limit = Number.parseInt(requireValue(arg, rest.shift()), 10);
    else if (arg === '--since') args.since = parseDuration(requireValue(arg, rest.shift()));
    else if (arg === '--project') args.project = requireValue(arg, rest.shift()).toLowerCase();
    else if (arg === '--json') args.json = true;
    else if (arg === '--no-expand') args.expand = false;
    else if (arg === '-h' || arg === '--help') args.help = true;
    else throw new Error(`Unknown option: ${arg}`);
  }

  if (args.limit !== null && (!Number.isInteger(args.limit) || args.limit < 1)) {
    throw new Error('--limit must be a positive integer');
  }

  return args;
};

const requireValue = (name, value) => {
  if (!value) throw new Error(`${name} requires a value`);
  return value;
};

const expandHome = (value) => {
  if (value === '~') return os.homedir();
  if (value.startsWith('~/')) return path.join(os.homedir(), value.slice(2));
  return value;
};

const parseDuration = (value) => {
  const match = /^(\d+)([hdw])$/.exec(value);
  if (!match) throw new Error('--since expects a duration like 24h, 7d, or 2w');
  const amount = Number.parseInt(match[1], 10);
  const multipliers = { h: 60 * 60 * 1000, d: 24 * 60 * 60 * 1000, w: 7 * 24 * 60 * 60 * 1000 };
  return new Date(Date.now() - amount * multipliers[match[2]]);
};

const listJsonlFiles = (dir) => {
  if (!fs.existsSync(dir)) return [];
  const files = [];
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) visit(fullPath);
      else if (entry.isFile() && entry.name.endsWith('.jsonl')) files.push(fullPath);
    }
  };
  visit(dir);
  return files.sort();
};

const loadSessionNames = (indexPath) => {
  const names = new Map();
  if (!fs.existsSync(indexPath)) return names;

  for (const line of fs.readFileSync(indexPath, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    try {
      const item = JSON.parse(line);
      if (item.id && item.thread_name) names.set(item.id, item.thread_name);
    } catch {
      continue;
    }
  }

  return names;
};

const parseSessionFile = (filePath, sessionNames) => {
  const session = {
    filePath,
    id: null,
    name: null,
    startedAt: null,
    lastEventAt: null,
    cwd: null,
    project: null,
    sourceKind: 'unknown',
    originator: null,
    model: null,
    parentThreadId: null,
    agentRole: null,
    agentNickname: null,
    taskCount: 0,
    tokenEventCount: 0,
    maxTotalTokens: null,
    maxFreshTokens: null,
    latestRateLimits: null,
    latestUsage: null,
  };

  const lines = fs.readFileSync(filePath, 'utf8').split('\n');
  for (const line of lines) {
    if (!line.trim()) continue;

    let event;
    try {
      event = JSON.parse(line);
    } catch {
      continue;
    }

    if (event.timestamp) {
      const eventDate = new Date(event.timestamp);
      if (Number.isFinite(eventDate.getTime())) {
        session.startedAt = earliestDate(session.startedAt, eventDate);
        session.lastEventAt = latestDate(session.lastEventAt, eventDate);
      }
    }

    const payload = event.payload ?? {};
    if (event.type === 'session_meta') {
      session.id = payload.id ?? session.id;
      session.name = sessionNames.get(session.id) ?? session.name;
      session.startedAt = parseMaybeDate(payload.timestamp) ?? session.startedAt;
      session.cwd = payload.cwd ?? session.cwd;
      session.project = projectName(payload.cwd) ?? session.project;
      session.originator = payload.originator ?? session.originator;
      applySource(session, payload.source);
    }

    if (event.type === 'turn_context') {
      session.model = payload.model ?? payload.collaboration_mode?.settings?.model ?? session.model;
      session.cwd = payload.cwd ?? session.cwd;
      session.project = projectName(payload.cwd) ?? session.project;
    }

    if (payload.type === 'task_started') {
      session.taskCount += 1;
    }

    if (payload.type === 'token_count') {
      session.tokenEventCount += 1;
      session.latestRateLimits = payload.rate_limits ?? session.latestRateLimits;
      session.latestUsage = payload.info ?? session.latestUsage;

      const totalUsage = payload.info?.total_token_usage;
      const totalTokens = totalUsage?.total_tokens;
      if (Number.isInteger(totalTokens)) {
        session.maxTotalTokens = Math.max(session.maxTotalTokens ?? 0, totalTokens);
      }

      const freshTokens = freshTokenCount(totalUsage);
      if (freshTokens !== null) {
        session.maxFreshTokens = Math.max(session.maxFreshTokens ?? 0, freshTokens);
      }
    }
  }

  session.project ??= projectName(session.cwd) ?? 'unknown';
  session.model ??= inferModel(session);
  session.name ??= sessionName(session);
  return session.id || session.startedAt ? session : null;
};

const parseMaybeDate = (value) => {
  if (!value) return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
};

const earliestDate = (current, next) => (current && current < next ? current : next);
const latestDate = (current, next) => (current && current > next ? current : next);

const projectName = (cwd) => {
  if (!cwd) return null;
  return path.basename(cwd) || cwd;
};

const sessionName = (session) => {
  if (session.agentNickname) return session.agentNickname;
  if (session.id) return session.id.slice(0, 8);
  return path.basename(session.filePath, '.jsonl').replace(/^rollout-/, '');
};

const applySource = (session, source) => {
  if (typeof source === 'string') {
    session.sourceKind = source;
    return;
  }

  const threadSpawn = source?.subagent?.thread_spawn;
  if (threadSpawn) {
    session.sourceKind = 'subagent';
    session.parentThreadId = threadSpawn.parent_thread_id ?? null;
    session.agentRole = threadSpawn.agent_role ?? null;
    session.agentNickname = threadSpawn.agent_nickname ?? null;
    return;
  }

  if (source?.subagent) {
    session.sourceKind = 'subagent';
  }
};

const freshTokenCount = (totalUsage) => {
  const inputTokens = totalUsage?.input_tokens;
  const cachedInputTokens = totalUsage?.cached_input_tokens ?? 0;
  const outputTokens = totalUsage?.output_tokens;
  if (!Number.isInteger(inputTokens) || !Number.isInteger(cachedInputTokens) || !Number.isInteger(outputTokens)) return null;
  return Math.max(0, inputTokens - cachedInputTokens) + outputTokens;
};

const inferModel = (session) => {
  if (session.originator === 'codex_vscode' || session.sourceKind === 'vscode') return 'codex';
  if (session.originator === 'codex-tui' || session.sourceKind === 'cli') return 'codex';
  return 'unknown';
};

const buildWorkflows = (sessions) => {
  const byId = new Map(sessions.filter((session) => session.id).map((session) => [session.id, session]));
  const childrenByParent = new Map();
  const childIds = new Set();

  for (const session of sessions) {
    if (!session.parentThreadId) continue;
    childIds.add(session.id);
    const children = childrenByParent.get(session.parentThreadId) ?? [];
    children.push(session);
    childrenByParent.set(session.parentThreadId, children);
  }

  const workflows = [];
  for (const session of sessions) {
    if (childIds.has(session.id) && byId.has(session.parentThreadId)) continue;
    const children = childrenByParent.get(session.id) ?? [];
    workflows.push({ parent: session, children: sortSessions(children) });
  }

  return workflows.sort((a, b) => compareDates(a.parent.startedAt, b.parent.startedAt));
};

const sortSessions = (sessions) => [...sessions].sort((a, b) => compareDates(a.startedAt, b.startedAt));
const compareDates = (a, b) => (a?.getTime() ?? 0) - (b?.getTime() ?? 0);

const filterSessions = (sessions, args) => {
  return sessions.filter((session) => {
    if (args.since && (!session.lastEventAt || session.lastEventAt < args.since)) return false;
    if (args.project && session.project.toLowerCase() !== args.project) return false;
    return true;
  });
};

const summarize = (sessions, workflows) => {
  const latestTokenSession = sessions
    .filter((session) => session.latestRateLimits)
    .sort((a, b) => compareDates(b.lastEventAt, a.lastEventAt))[0];

  return {
    sessions: sessions.length,
    interactions: sessions.reduce((sum, session) => sum + session.taskCount, 0),
    tokenEvents: sessions.reduce((sum, session) => sum + session.tokenEventCount, 0),
    observedTokens: sessions.reduce((sum, session) => sum + (session.maxTotalTokens ?? 0), 0),
    observedFreshTokens: sessions.reduce((sum, session) => sum + (session.maxFreshTokens ?? 0), 0),
    modelsUsed: new Set(sessions.map((session) => session.model).filter(Boolean)).size,
    workflows: workflows.length,
    workflowsWithSubagents: workflows.filter((workflow) => workflow.children.length > 0).length,
    latestRateLimits: latestTokenSession?.latestRateLimits ?? null,
    latestUsage: latestTokenSession?.latestUsage ?? null,
  };
};

const formatDate = (date) => {
  if (!date) return '';
  const pad = (value) => String(value).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

const formatNumber = (value) => new Intl.NumberFormat('en-US').format(value);

const formatCompactNumber = (value) => {
  if (!Number.isFinite(value) || value === null) return '';
  if (value >= 1_000_000_000) return `${trimDecimal(value / 1_000_000_000)}B`;
  if (value >= 1_000_000) return `${trimDecimal(value / 1_000_000)}M`;
  if (value >= 1_000) return `${trimDecimal(value / 1_000)}K`;
  return String(value);
};

const trimDecimal = (value) => value.toFixed(value >= 10 ? 1 : 2).replace(/\.0+$/, '').replace(/(\.\d)0$/, '$1');

const agentLabel = (session) => {
  if (session.sourceKind === 'subagent') {
    const role = session.agentRole ?? 'subagent';
    return session.agentNickname ? `${role}: ${session.agentNickname}` : role;
  }
  if (session.originator === 'codex-tui') return 'cli';
  return session.sourceKind;
};

const tableRows = (workflows, expand) => {
  const rows = [];
  for (const workflow of workflows) {
    const parent = workflow.parent;
    rows.push([
      formatDate(parent.startedAt),
      parent.project,
      parent.name,
      parent.model,
      workflow.children.length > 0 ? `+${workflow.children.length}` : agentLabel(parent),
      formatCompactNumber(parent.maxTotalTokens),
      formatCompactNumber(parent.maxFreshTokens),
    ]);

    if (expand && workflow.children.length > 0) {
      rows.push([
        '',
        '',
        parent.name,
        parent.model,
        agentLabel(parent),
        formatCompactNumber(parent.maxTotalTokens),
        formatCompactNumber(parent.maxFreshTokens),
      ]);
      for (const child of workflow.children) {
        rows.push([
          '',
          '',
          child.name,
          child.model,
          agentLabel(child),
          formatCompactNumber(child.maxTotalTokens),
          formatCompactNumber(child.maxFreshTokens),
        ]);
      }
    }
  }
  return rows;
};

const renderSessions = (sessionsDir, sessionCount, workflows, summary, expand) => {
  console.log(`Using data source: ${sessionsDir}`);
  console.log(`Analyzing ${sessionCount} sessions...`);
  console.log(
    renderTable('Codex Session Workflows', ['Started', 'Project', 'Session', 'Model', 'Agent', 'Tokens', 'Fresh'], tableRows(workflows, expand)),
  );
  console.log(renderBox('Summary', summaryLines(summary)));
  console.log(renderBox('Workflow Summary', [`${summary.workflows} workflows (${summary.workflowsWithSubagents} with sub-agents)`]));
};

const summaryLines = (summary) => {
  const quota = summary.latestRateLimits;
  const lines = [
    `Sessions: ${formatNumber(summary.sessions)}`,
    `Interactions: ${formatNumber(summary.interactions)}`,
    `Token Events: ${formatNumber(summary.tokenEvents)}`,
    `Observed Tokens: ${formatNumber(summary.observedTokens)}`,
    `Observed Fresh Tokens: ${formatNumber(summary.observedFreshTokens)}`,
    `Models Used: ${formatNumber(summary.modelsUsed)}`,
  ];

  if (quota) {
    lines.push(`Latest Quota: 5h ${quota.primary?.used_percent ?? '?'}%, 7d ${quota.secondary?.used_percent ?? '?'}%`);
    lines.push(`Plan: ${quota.plan_type ?? 'unknown'}`);
  }

  return lines;
};

const renderTable = (title, headers, rows) => {
  const terminalWidth = process.stdout.columns || 120;
  const maxTableWidth = Math.max(80, Math.min(terminalWidth, 120));
  const widths = computeWidths(headers, rows, maxTableWidth);
  const tableWidth = widths.reduce((sum, width) => sum + width, 0) + widths.length * 3 + 1;
  const centeredTitle = center(title, tableWidth);

  return [
    centeredTitle,
    `┏${widths.map((width) => '━'.repeat(width + 2)).join('┳')}┓`,
    `┃${headers.map((header, index) => ` ${padCell(header, widths[index])} `).join('┃')}┃`,
    `┡${widths.map((width) => '━'.repeat(width + 2)).join('╇')}┩`,
    ...rows.map((row) => `│${row.map((cell, index) => ` ${padCell(truncate(String(cell ?? ''), widths[index]), widths[index])} `).join('│')}│`),
    `└${widths.map((width) => '─'.repeat(width + 2)).join('┴')}┘`,
  ].join('\n');
};

const computeWidths = (headers, rows, maxTableWidth) => {
  const preferred = headers.map((header, index) => {
    const maxCell = Math.max(String(header).length, ...rows.map((row) => String(row[index] ?? '').length));
    return Math.min(Math.max(maxCell, String(header).length), [16, 16, 24, 19, 22, 10, 10][index]);
  });

  const availableContentWidth = maxTableWidth - (headers.length * 3 + 1);
  while (preferred.reduce((sum, width) => sum + width, 0) > availableContentWidth) {
    const largestIndex = preferred.indexOf(Math.max(...preferred));
    if (preferred[largestIndex] <= headers[largestIndex].length) break;
    preferred[largestIndex] -= 1;
  }

  return preferred;
};

const renderBox = (title, lines) => {
  const width = Math.max(78, ...lines.map((line) => line.length + 4), title.length + 6);
  const titleSegment = ` ${title} `;
  return [
    `╭─${titleSegment}${'─'.repeat(width - titleSegment.length - 3)}╮`,
    ...lines.map((line) => `│ ${line}${' '.repeat(width - line.length - 3)}│`),
    `╰${'─'.repeat(width - 2)}╯`,
  ].join('\n');
};

const padCell = (value, width) => `${value}${' '.repeat(Math.max(0, width - value.length))}`;
const center = (value, width) => `${' '.repeat(Math.max(0, Math.floor((width - value.length) / 2)))}${value}`;

const truncate = (value, width) => {
  if (value.length <= width) return value;
  if (width <= 1) return '…';
  return `${value.slice(0, width - 1)}…`;
};

const toJson = (workflows, summary) => ({
  summary,
  workflows: workflows.map((workflow) => ({
    parent: serializeSession(workflow.parent),
    children: workflow.children.map(serializeSession),
  })),
});

const serializeSession = (session) => ({
  id: session.id,
  name: session.name,
  startedAt: session.startedAt?.toISOString() ?? null,
  lastEventAt: session.lastEventAt?.toISOString() ?? null,
  cwd: session.cwd,
  project: session.project,
  sourceKind: session.sourceKind,
  originator: session.originator,
  model: session.model,
  parentThreadId: session.parentThreadId,
  agentRole: session.agentRole,
  agentNickname: session.agentNickname,
  taskCount: session.taskCount,
  tokenEventCount: session.tokenEventCount,
  maxTotalTokens: session.maxTotalTokens,
  maxFreshTokens: session.maxFreshTokens,
});

const main = () => {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(HELP);
    return;
  }

  if (args.command !== 'sessions') {
    throw new Error(`Unknown command: ${args.command}`);
  }

  const sessionNames = loadSessionNames(args.indexPath);
  const sessions = filterSessions(
    listJsonlFiles(args.sessionsDir)
      .map((filePath) => parseSessionFile(filePath, sessionNames))
      .filter(Boolean),
    args,
  );
  let workflows = buildWorkflows(sortSessions(sessions));
  if (args.limit !== null) workflows = workflows.slice(-args.limit);
  const workflowSessionIds = new Set(workflows.flatMap((workflow) => [workflow.parent.id, ...workflow.children.map((child) => child.id)]));
  const renderedSessions = sessions.filter((session) => workflowSessionIds.has(session.id));
  const summary = summarize(renderedSessions, workflows);

  if (args.json) {
    console.log(JSON.stringify(toJson(workflows, summary), null, 2));
    return;
  }

  renderSessions(args.sessionsDir, renderedSessions.length, workflows, summary, args.expand);
};

try {
  main();
} catch (error) {
  console.error(`codex-monitor: ${error.message}`);
  process.exit(1);
}
