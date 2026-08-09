---
name: pr-review
description: Review a Git branch against the repository default branch and produce concise, prioritized PR feedback focused on correctness, security, TypeScript quality, performance, and test coverage.
disable-model-invocation: true
---

# PR Review

## Purpose

Review the current branch against the repository default branch and produce concise, actionable PR feedback.

This skill is generic and should work across repositories, with a strong bias toward TypeScript / JavaScript projects. Focus on real risks introduced by the diff, not broad architectural commentary.

Do not produce a verbose file-by-file review. Group findings by severity and topic.

## Review Principles

- Review the diff, not the entire repository.
- Prioritize correctness, regressions, security, data boundaries, API/schema compatibility, and test gaps.
- Prefer a few high-signal findings over exhaustive low-value commentary.
- Do not nitpick style unless it impacts maintainability, consistency, safety, or readability.
- Do not suggest large rewrites unless the current change introduces real risk.
- Distinguish confirmed issues from speculative risks.
- Do not modify files unless explicitly asked.
- Do not commit, push, rebase, install dependencies, or run destructive commands.

## Inputs

Detect from the user message when available:

- Review ref: branch/ref to review. Default: `HEAD`.
- Base ref: branch/ref to compare against. Default: repository default branch.
- Ticket or issue context: optional. Treat as context only.
- Focus paths or focus areas: optional. Prioritize those areas but still scan the whole diff.

## Base Branch Detection

Determine the base branch in this order:

1. Provided base ref, if any.
2. `origin/HEAD`.
3. `origin/main`.
4. `origin/master`.
5. If none are available, use the best local merge-base and clearly state the fallback.

Prefer read-only Git commands.

Useful commands:

    git status --short
    git branch --show-current
    git symbolic-ref --quiet --short refs/remotes/origin/HEAD
    git show-ref --verify --quiet refs/remotes/origin/main
    git show-ref --verify --quiet refs/remotes/origin/master
    git diff --name-status --find-renames <base-ref>...<review-ref>
    git diff --stat <base-ref>...<review-ref>
    git diff <base-ref>...<review-ref>

Avoid `git fetch --all` by default. If refs are stale, fetch only the needed remote/base ref.

## Required Review Process

### 1. Establish Scope

Inspect:

- Changed files
- Diff stats
- Renames/deletes
- Generated files
- Config/package changes
- Test changes
- API/schema/type changes
- Server/client boundary changes

Group changes mentally by domain:

- API/server/backend
- UI/frontend
- shared types/libs
- tests
- config/build/tooling
- database/schema/migrations
- infra/deployment

### 2. Identify High-Risk Areas First

Prioritize deep review of changes touching:

- auth/authz/session logic
- permissions and tenant/customer boundaries
- payments, pricing, checkout, orders
- API contracts, schemas, generated clients
- validation and parsing
- cache invalidation and stale data
- server/client boundaries
- secrets, logs, telemetry
- database writes/migrations
- concurrency, async flows, retries
- error handling
- shared utilities used widely
- public exports
- dependency/version changes

### 3. Read Relevant Context

For changed symbols, inspect enough surrounding context to understand behavior:

- direct callers/callees
- exported API usage
- similar existing patterns
- project conventions
- nearby tests
- type definitions
- validation schemas
- server/client entry points

Do not read unrelated files just to be exhaustive.

### 4. Run Checks When Reasonable

Detect package manager and scripts from project files.

Prefer targeted checks:

- typecheck
- lint
- unit tests related to changed files
- existing test command for affected package/workspace

Report commands run and results.

If checks cannot be run because dependencies are missing, scripts are absent, or the repo is not set up, state that clearly and continue with static review.

Do not run expensive full test suites unless it is clearly the project's normal workflow or necessary to validate the change.

## TypeScript Review Rules

Apply these rules to TypeScript and JavaScript projects.

### Dangerous Type Assertions

Flag these unless strongly justified and locally safe:

- `as any`
- `as unknown as Something`
- `value as SomeType` on untrusted data
- non-null assertions `!` on values that can plausibly be absent
- type assertions used to silence real incompatibilities
- assertions around API responses, CMS data, localStorage, URL params, env vars, or external input

Prefer:

- `unknown` plus explicit narrowing
- schema validation at boundaries
- `satisfies` for object conformance
- precise helper types
- discriminated unions
- typed adapters/mappers between external and internal shapes

Examples of safer alternatives:

    const config = {
      mode: "strict",
      retries: 3,
    } satisfies AppConfig

    const parsed = Schema.safeParse(input)
    if (!parsed.success) {
      throw new Error("Invalid input")
    }

### Boundary Validation

Require validation or narrowing for:

- API responses
- request bodies
- query params
- route params
- form data
- environment variables
- localStorage/sessionStorage
- postMessage payloads
- CMS data
- feature flag payloads
- webhook payloads
- third-party SDK data

Do not trust external data because it has a TypeScript type.

### Exported APIs

For exported functions, components, hooks, and utilities:

- ensure types are explicit enough for consumers
- avoid leaking implementation-specific types
- avoid overly broad generics
- avoid weak parameter types like `object`, `Function`, `{}`, `Record<string, any>`
- ensure return types do not accidentally widen important literals
- check backward compatibility when public/shared exports change

### Nullability

Check for unsafe assumptions around:

- optional fields
- nullable API data
- empty arrays
- missing map entries
- failed lookups
- absent route params
- undefined async results
- partial configuration

Prefer explicit handling over assertion.

### Discriminated Unions

Prefer discriminated unions over:

- boolean flag combinations
- stringly-typed state without narrowing
- optional-field-based state machines
- enums used only as string constants

Prefer `as const` objects or string literal unions over TypeScript enums unless the project already consistently uses enums.

### Error Handling

Flag:

- swallowed errors
- `catch {}` without rationale
- `catch (e) { console.log(e) }` without propagation or recovery
- loss of error cause
- throwing raw strings
- returning ambiguous `null` / `undefined` for error cases
- converting typed errors into generic errors too early

Prefer preserving error context and using project-standard error types.

### Async and Concurrency

Check for:

- missing `await`
- unhandled promises
- race conditions
- stale closures
- duplicated requests
- missing abort/timeout for long-running work
- unsafe parallel writes
- order-dependent async logic
- retries without backoff or idempotency

### Object and Data Transformations

Check for:

- accidental mutation of inputs
- shallow copy bugs
- dropped fields during mapping
- incorrect default values
- spreading untrusted objects into trusted structures
- serialization issues with `Date`, `Map`, `Set`, class instances, functions, BigInt

### Dependency and Package Changes

For package changes, check:

- new transitive risk
- client bundle impact
- SSR compatibility
- ESM/CJS compatibility
- Node/browser compatibility
- duplicate libraries
- abandoned or unnecessary dependencies
- lockfile consistency

## React / Frontend Review Rules

Apply when relevant.

Check:

- unnecessary `"use client"` boundaries
- server components passing non-serializable props to client components
- secrets or server-only data reaching client code
- unstable dependencies in `useEffect`, `useMemo`, `useCallback`
- missing cleanup in effects
- derived state that can go stale
- rendering heavy computations without memoization
- hydration mismatch risks
- incorrect keys in lists
- uncontrolled/controlled input mismatches
- missing loading, empty, and error states
- accessibility regressions for interactive UI

Do not recommend memoization everywhere. Only suggest it for measured or plausible hot paths, unstable props, expensive calculations, or avoidable rerenders.

## Server / API Review Rules

Apply when relevant.

Check:

- authentication and authorization
- tenant/customer/resource ownership checks
- input validation
- output data minimization
- safe error responses
- rate limiting or abuse considerations for public endpoints
- idempotency for mutations
- transaction boundaries
- pagination for large result sets
- N+1 queries
- cache invalidation
- logging of sensitive data
- SSR/CSR data leakage

## Security and Privacy Rules

Flag confirmed or plausible issues involving:

- missing auth/authz
- trusting client-provided IDs or roles
- insecure direct object references
- secrets in code, logs, client bundles, config, or errors
- PII in logs or analytics
- unsafe redirects
- injection risks
- unsafe HTML rendering
- weak validation at trust boundaries
- dependency risks
- overly broad permissions
- accidental exposure through serialized props or API responses

For each security finding, include the concrete attack/failure scenario.

## Performance Rules

Look for:

- repeated expensive computations
- duplicated network calls
- inefficient loops over large collections
- N+1 database/API calls
- large client bundle additions
- unnecessary client-side rendering
- expensive work during render
- missing pagination/streaming for large data
- unstable cache keys
- missing request deduplication
- memory leaks from effects/subscriptions/timers
- large synchronous work on hot paths

Do not over-optimize low-traffic or non-hot code without evidence.

## Cache Review Rules

Only include cache analysis when the diff touches:

- data fetching
- API calls
- database queries
- expensive computation
- rendering boundaries
- cache configuration
- invalidation logic
- revalidation/TTL/staleTime settings

Check:

- cache key correctness
- user/tenant/session scoping
- invalidation after writes
- stale data risks
- request deduplication
- TTL consistency with project patterns
- caching of errors or unauthorized responses
- accidental sharing of private data across users

If cache is irrelevant, write only:

    No relevant cache changes detected.

## Test Review Rules

Focus on missing tests for behavior introduced or changed by the diff.

Check for coverage of:

- happy path
- edge cases
- validation failures
- authorization failures
- empty/null inputs
- error branches
- async race/retry behavior
- cache invalidation
- schema/contract changes
- backward compatibility
- regression cases linked to the ticket

Prefer concrete test suggestions over generic "add tests".

## Ticket Alignment

If ticket context is provided:

- infer the intended behavior
- compare implementation to acceptance criteria
- identify missing scope
- identify out-of-scope changes
- identify behavior that may satisfy code but not product intent

If ticket context is too thin, state that alignment could only be partially checked.

## Large Diff Strategy

If the diff is large:

1. Review diff stats and changed file list first.
2. Deep-review high-risk files.
3. Sample repetitive or mechanical changes.
4. Group repeated findings into one item.
5. Clearly state review coverage and any areas not deeply inspected.

Do not produce a long file-by-file section.

## Output Format

Start with a concise summary.

Then use this exact structure:

## Summary

- Scope:
- Main risk areas:
- Checks run:
- Overall confidence:

## Action Items by Severity

### Critical

Use only for issues that are very likely to cause security incidents, data loss, broken production behavior, or severe regressions.

Each item must include:

- Files:
- Issue:
- Why it matters:
- Suggested fix:
- Evidence:
- Confidence:

### High

Use for likely bugs, unsafe data handling, broken edge cases, significant security risks, or missing validation.

Same item format.

### Medium

Use for maintainability, moderate correctness risks, missing tests around changed behavior, or performance risks.

Same item format.

### Low

Use for small cleanup, naming, consistency, minor test improvements, or non-blocking suggestions.

Same item format.

If a severity has no findings, write:

    No findings.

## Diff Summary

Briefly summarize:

- changed domains
- notable files
- config/dependency/schema changes
- deleted/renamed files
- tests added/changed

Do not list every file unless the diff is small.

## Key Review Notes

Group notes by topic, not by file.

Suggested topics when relevant:

- Correctness
- TypeScript / type safety
- API / schema compatibility
- React / rendering
- Server / data boundaries
- Security / privacy
- Performance
- Cache behavior
- Tests

Keep this section concise. Do not repeat action items unless additional context is useful.

## Tests and Verification Plan

Include:

- commands run and results
- commands that should be run
- targeted tests to add
- manual acceptance checks
- rollback or monitoring notes if relevant

## Ticket Alignment

Only include this section when ticket context is provided.

Include:

- aligned behavior
- gaps
- out-of-scope changes
- unclear requirements

## Code References

When referencing existing code, use path and line numbers when available:

    src/example.ts:12-20

Do not paste large code blocks from existing files.

For proposed code, include short snippets only when they make the fix clearer.

## Finding Quality Bar

Before reporting a finding, verify:

- Is this introduced or affected by the diff?
- Is it actionable?
- Is the severity appropriate?
- Is there enough evidence?
- Could this be a false positive?
- Is the suggested fix concrete?

Avoid vague findings like:

- "Consider improving error handling"
- "Maybe add tests"
- "This could be cleaner"
- "Potential performance issue"

Prefer precise findings like:

- "`parseUserInput` asserts API data with `as unknown as User`, so malformed payloads can reach checkout without validation. Validate with the existing schema before mapping."
- "The mutation updates the order but does not invalidate the cached order query, so users may see stale status after payment."
- "The new client component receives `session` including server-only fields. Pass a minimized DTO instead."