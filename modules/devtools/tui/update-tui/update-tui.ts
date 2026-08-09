import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline/promises';

type UpdateSummary = {
  schemaVersion?: number;
  operation?: string;
  status?: string;
  error?: string | null;
  repo?: string;
  host?: string;
  flakePath?: string;
  logFile?: string | null;
  checkStatus?: string;
  dirty?: boolean;
  inputs?: Array<{ name: string; before: string; after: string }>;
  releases?: Array<{ name: string; path: string; before: string; after: string }>;
  gitTargets?: string[];
  releasePolicy?: ReleasePolicy;
};

type ReleasePolicy = 'interactive' | 'accept' | 'keep';

type RebuildSummary = {
  schemaVersion?: number;
  operation?: string;
  status: string;
  exitCode: number;
  recapFile?: string;
  system?: { changed: boolean; before: string | null; after: string | null };
  activation?: {
    policy: 'auto' | 'boot' | 'switch';
    installed: boolean;
    activated: boolean;
    previewSucceeded: boolean;
    risk: 'not-run' | 'low' | 'high' | 'unknown';
    riskItems: string[];
    rebootRequired: boolean;
    installedSystem: string | null;
  };
  packages?: {
    added: number;
    removed: number;
    updated: number;
    addedItems: string[];
    removedItems: string[];
    updatedItems: string[];
  };
  dotfiles?: { changed: number; items: string[] };
};

const repo = process.env.NIXOS_REPO ?? path.join(os.homedir(), 'Projects', 'Github', 'nixos');
const updateScript = path.join(repo, 'script', 'update.sh');
const rebuildScript = path.join(repo, 'script', 'rebuild.sh');
const logsDir = path.join(repo, 'logs');
const stamp = formatTimestamp(new Date());
const logFile = path.join(logsDir, `update-${stamp}.log`);
const summaryFile = path.join(logsDir, `update-${stamp}.json`);
const rebuildSummaryFile = path.join(logsDir, `rebuild-${stamp}.json`);
const useColor = process.stdout.isTTY && !process.env.NO_COLOR;

const color = {
  reset: useColor ? '\u001b[0m' : '',
  bold: useColor ? '\u001b[1m' : '',
  dim: useColor ? '\u001b[2m' : '',
  red: useColor ? '\u001b[31m' : '',
  green: useColor ? '\u001b[32m' : '',
  yellow: useColor ? '\u001b[33m' : '',
  blue: useColor ? '\u001b[34m' : '',
  cyan: useColor ? '\u001b[36m' : '',
};

async function main() {
  if (process.argv.includes('--help') || process.argv.includes('-h')) {
    printHelp();
    return;
  }

  if (process.argv.includes('--raw')) {
    const args = process.argv.slice(2).filter((arg) => arg !== '--raw');
    const result = spawnSync(updateScript, args, { stdio: 'inherit', env: process.env });
    process.exit(result.status ?? 1);
  }

  fs.mkdirSync(logsDir, { recursive: true });

  const requestedPolicy = parseReleasePolicy(process.argv.slice(2));
  const releasePolicy = requestedPolicy ?? (await chooseReleasePolicy());
  if (!releasePolicy) return;

  header('Update');
  line(`${color.dim}Log:${color.reset} ${logFile}`);
  line(`${color.dim}Pinned releases:${color.reset} ${releasePolicy}`);
  line('');

  const updateCode = await runBackendUpdate(releasePolicy);
  const summary = readSummary();

  line('');
  printUpdateSummary(summary, updateCode);

  if (updateCode !== 0 || summary.status !== 'ok') {
    line('');
    warn('Update did not complete cleanly. Raw log kept for inspection.');
    line(`${color.dim}${logFile}${color.reset}`);
    process.exit(updateCode || 1);
  }

  await actionLoop(summary);
}

function printHelp() {
  line('update');
  line('');
  line('Runs NixOS flake update through a compact TUI.');
  line('');
  line('Options:');
  line('  --raw   Run the backend script directly');
  line('  --release-policy <interactive|accept|keep>');
  line('  -h      Show help');
}

function parseReleasePolicy(args: string[]): ReleasePolicy | undefined {
  const equalsOption = args.find((arg) => arg.startsWith('--release-policy='));
  const optionIndex = args.indexOf('--release-policy');
  if (equalsOption === undefined && optionIndex < 0) return undefined;

  const value = equalsOption?.slice('--release-policy='.length) ?? args[optionIndex + 1];
  if (value === undefined) throw new Error('--release-policy requires a value');

  if (value === 'interactive' || value === 'accept' || value === 'keep') return value;
  throw new Error('release policy must be one of: interactive, accept, keep');
}

async function chooseReleasePolicy(): Promise<ReleasePolicy | undefined> {
  const choice = await choose('Pinned releases', ['Update pinned releases', 'Keep pinned releases', 'Exit']);
  if (choice === 'Update pinned releases') return 'accept';
  if (choice === 'Keep pinned releases') return 'keep';
  return undefined;
}

async function runBackendUpdate(releasePolicy: ReleasePolicy): Promise<number> {
  step('Running update backend');

  return new Promise((resolve) => {
    const child = spawn(
      updateScript,
      ['--no-prompts', '--release-policy', releasePolicy, '--log-file', logFile, '--json-summary', summaryFile],
      {
        cwd: repo,
        env: process.env,
        stdio: [releasePolicy === 'interactive' ? 'inherit' : 'ignore', 'pipe', 'pipe'],
      },
    );

    const onData = (chunk: Buffer) => {
      if (releasePolicy === 'interactive') process.stdout.write(chunk);
    };

    child.stdout.on('data', onData);
    child.stderr.on('data', onData);
    child.on('error', () => resolve(127));
    child.on('close', (code) => resolve(code ?? 1));
  });
}

function printUpdateSummary(summary: UpdateSummary, code: number) {
  if (code === 0 && summary.status === 'ok') ok('Update complete');
  else fail(summary.error ?? 'Update failed');

  if (summary.dirty) warn('Repository is dirty. Rebuild may not be reproducible from git alone.');

  const inputs = summary.inputs ?? [];
  const releases = summary.releases ?? [];

  section('Inputs');
  if (inputs.length === 0) {
    line(`  ${color.dim}No flake input changes.${color.reset}`);
  } else {
    for (const input of inputs) {
      line(`  ${color.cyan}${pad(input.name, 18)}${color.reset} ${color.dim}${input.before}${color.reset} -> ${color.green}${input.after}${color.reset}`);
    }
  }

  section('Pinned Releases');
  if (releases.length === 0) {
    line(`  ${color.dim}No pinned release changes.${color.reset}`);
  } else {
    for (const release of releases) {
      line(`  ${color.cyan}${pad(release.name, 18)}${color.reset} ${color.dim}${release.before}${color.reset} -> ${color.green}${release.after}${color.reset}`);
    }
  }

  section('Checks');
  const checkStatus = summary.checkStatus ?? 'unknown';
  if (checkStatus === 'passed') ok('Lightweight flake checks passed');
  else if (checkStatus === 'failed') fail('Lightweight flake checks failed');
  else line(`  ${color.dim}${checkStatus}${color.reset}`);
}

async function actionLoop(summary: UpdateSummary) {
  while (true) {
    line('');
    const options = ['Rebuild now'];
    if ((summary.gitTargets ?? []).length > 0) options.push('Show git add command');
    options.push('Show raw log path', 'Exit');

    const choice = await choose('Next action', options);

    if (choice === 'Rebuild now') {
      line('');
      const result = await runRebuild();
      line('');
      printRebuildResult(result);
      return;
    }

    if (choice === 'Show git add command') {
      line('');
      showGitCommand(summary);
      continue;
    }

    if (choice === 'Show raw log path') {
      line('');
      line(`${color.dim}${logFile}${color.reset}`);
      continue;
    }

    return;
  }
}

async function runRebuild(): Promise<RebuildSummary> {
  step('Running rebuild');
  appendLog('\n========== Rebuild ==========' + '\n');

  return new Promise((resolve) => {
    const child = spawn(
      rebuildScript,
      [
        '--activation-policy',
        'auto',
        '--activation-ui-fd',
        '3',
        '--json-summary',
        rebuildSummaryFile,
      ],
      {
        cwd: repo,
        env: process.env,
        stdio: ['inherit', 'pipe', 'pipe', 'pipe'],
      },
    );

    const onData = (chunk: Buffer) => {
      appendLog(chunk.toString());
      if (chunk.toString().includes('[sudo] password')) process.stderr.write(chunk);
    };

    const onActivationUi = (chunk: Buffer) => {
      appendLog(chunk.toString());
      process.stdout.write(chunk);
    };

    const activationUi = child.stdio[3];
    let activationUiEnded = activationUi === null;
    let childClosed = false;
    let childExitCode = 1;

    const finish = () => {
      if (!activationUiEnded || !childClosed) return;

      const summary = readRebuildSummary();
      if (summary.exitCode !== childExitCode) {
        summary.exitCode = childExitCode;
        summary.status = 'failed';
      }
      resolve(summary);
    };

    child.stdout?.on('data', onData);
    child.stderr?.on('data', onData);
    activationUi?.on('data', onActivationUi);
    activationUi?.on('end', () => {
      activationUiEnded = true;
      finish();
    });
    child.on('error', () => resolve({ status: 'spawn_failed', exitCode: 127 }));
    child.on('close', (code) => {
      childExitCode = code ?? 1;
      childClosed = true;
      finish();
    });
  });
}

function printRebuildResult(result: RebuildSummary) {
  if (result.exitCode === 0 && result.status === 'ok') ok('Generation installed successfully');
  else fail(`Rebuild failed with exit code ${result.exitCode}`);

  section('Rebuild Summary');
  if (result.system?.changed) line(`  Generation ${result.system.before ?? '-'} -> ${result.system.after ?? '-'}`);

  const activation = result.activation;
  if (activation) {
    section('Activation');
    line(`  Risk       ${activation.risk}`);
    if (activation.activated) {
      ok('Generation activated live');
    } else if (activation.rebootRequired) {
      warn('Live activation deferred. Reboot to activate the installed generation.');
    }

    if (activation.riskItems.length > 0) {
      printItems('Sensitive services', activation.riskItems);
    }
  }

  const packages = result.packages;
  if (packages) {
    line(`  Packages   ${packages.added} added   ${packages.removed} removed   ${packages.updated} updated`);
    printItems('Updated packages', packages.updatedItems);
    printItems('Added packages', packages.addedItems);
    printItems('Removed packages', packages.removedItems);
  }

  const dotfiles = result.dotfiles;
  if (dotfiles) {
    line(`  Dotfiles   ${dotfiles.changed} changed`);
    printItems('Dotfile changes', dotfiles.items);
  }

  if (result.recapFile) line(`  Recap      ${result.recapFile}`);

  section('Raw Log');
  line(`  ${logFile}`);
}

function printItems(label: string, items: string[]) {
  if (items.length === 0) return;
  line(`  ${label}`);
  for (const item of items) line(`    - ${item}`);
}

function showGitCommand(summary: UpdateSummary) {
  const targets = summary.gitTargets ?? [];
  if (targets.length === 0) {
    line(`${color.dim}No lock or release metadata changes to stage.${color.reset}`);
    return;
  }

  line('Git staging stays manual. Run this if you want to stage update files:');
  line('');
  line(`  git -C "${repo}" add -- ${targets.map(shellQuote).join(' ')}`);
}

async function choose(label: string, options: string[]): Promise<string> {
  if (commandExists('gum')) {
    const result = spawnSync('gum', ['choose', '--header', label, ...options], {
      encoding: 'utf8',
      stdio: ['inherit', 'pipe', 'inherit'],
    });

    const choice = result.stdout.trim();
    if (choice) return choice;
    return 'Exit';
  }

  line(`${color.bold}${label}${color.reset}`);
  options.forEach((option, index) => line(`  ${index + 1}. ${option}`));

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await rl.question('Select option: ');
  rl.close();

  const index = Number.parseInt(answer, 10) - 1;
  return options[index] ?? 'Exit';
}

function readSummary(): UpdateSummary {
  try {
    const summary = JSON.parse(fs.readFileSync(summaryFile, 'utf8')) as UpdateSummary;
    if (summary.schemaVersion !== 1 || summary.operation !== 'update') {
      return { status: 'invalid_summary', error: 'unsupported update summary contract', logFile };
    }
    return summary;
  } catch {
    return { status: 'missing_summary', error: 'summary file missing', logFile };
  }
}

function readRebuildSummary(): RebuildSummary {
  try {
    const summary = JSON.parse(fs.readFileSync(rebuildSummaryFile, 'utf8')) as RebuildSummary;
    if (summary.schemaVersion !== 1 || summary.operation !== 'rebuild') throw new Error('unsupported contract');
    return summary;
  } catch {
    return { status: 'missing_summary', exitCode: 1 };
  }
}

function appendLog(value: string) {
  fs.appendFileSync(logFile, value);
}

function commandExists(command: string): boolean {
  const result = spawnSync('command', ['-v', command], { shell: true, stdio: 'ignore' });
  return result.status === 0;
}

function formatTimestamp(date: Date): string {
  const pad2 = (value: number) => value.toString().padStart(2, '0');
  return `${date.getFullYear()}${pad2(date.getMonth() + 1)}${pad2(date.getDate())}-${pad2(date.getHours())}${pad2(date.getMinutes())}${pad2(date.getSeconds())}`;
}

function shellQuote(value: string): string {
  if (/^[A-Za-z0-9_./:@%+=,-]+$/.test(value)) return value;
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function pad(value: string, width: number): string {
  return value.length >= width ? value : value.padEnd(width, ' ');
}

function header(value: string) {
  line(`${color.bold}${color.blue}${value}${color.reset}`);
  line(`${color.dim}${'='.repeat(value.length)}${color.reset}`);
}

function section(value: string) {
  line('');
  line(`${color.bold}${value}${color.reset}`);
}

function step(value: string) {
  line(`${color.blue}[..]${color.reset} ${value}`);
}

function ok(value: string) {
  line(`${color.green}[ok]${color.reset} ${value}`);
}

function warn(value: string) {
  line(`${color.yellow}[warn]${color.reset} ${value}`);
}

function fail(value: string) {
  line(`${color.red}[fail]${color.reset} ${value}`);
}

function line(value: string) {
  process.stdout.write(`${process.stdout.isTTY ? '\r' : ''}${value}\n`);
}

main().catch((error) => {
  fail(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
