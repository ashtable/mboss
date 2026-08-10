---
description: Turn design docs and the implementation plan into tested, working code across the mBoss submodules
argument-hint: "[the plan task(s) to implement, plus any Claude Design file URLs]"
allowed-tools: Agent, Read, Write, Edit, Glob, Grep, WebSearch, WebFetch, Bash, Skill
---

Turn the design documents in `./design-docs/`, the implementation plan in
`./design-docs/plan.md`, and optionally an initial mockup into a working, tested implementation
across the mBoss submodules, using test-driven development.

The user's request: $ARGUMENTS

If the request above is empty, stop and ask which plan task(s) they want implemented before
doing anything else.

## Code locations

This is the "MBOSS" root-level superproject at `/Users/ash/code/mboss`. Every related Git repo
lives here as a submodule. What belongs where:

- `./` — the root superproject. Holds each repo as a submodule, plus a Dockerfile and docker
  compose file tracking the latest commit on the latest version branch of each submodule needed
  to run the cloud stack locally (`mboss-nodejs-api`, `mboss-nodejs-dbos`, `mboss-web`)
  alongside supporting servers (postgres, weaviate, docling).
- `./design-docs/` — the transient design documents this command consumes:
  `current-design.md`, `design-delta.md`, `plan.md`, and `mboss-vision-brief.md`.
- `./mboss-database/` — Prisma migrations and shared data models. Added as a submodule to
  `mboss-nodejs-api` and others as needed.
- `./mboss-nodejs-api/` — Node.js API in TypeScript and Fastify, using the shared data models
  from `./mboss-database/`. The only interface to the mBoss Postgres database. Must expose
  endpoint(s) that accept a flag engaging DBOS's idempotency superpower, where workflow state
  and application data share the same Postgres database.
- `./mboss-nodejs-dbos/` — the DBOS durable-execution worker in TypeScript, using the shared
  Zod models from `./mboss-zod/` and the data models from `./mboss-database/`. Passes the
  transaction flag to the API for idempotent operations that need workflow and application
  data co-located.
- `./mboss-vscode/` — the mBoss VS Code extension, TypeScript and React Flow.
- `./mboss-web/` — the mBoss Next.js UI in TypeScript, using the shared data models from
  `./mboss-database/`.
- `./mboss-zod/` — shared Zod schemas. Added as a submodule to other projects as needed.
- `./prompts/` — ad-hoc prompts the user edits by hand.
- `./scratch/` — where subagents leave notes to pass between steps.

`design-docs/`, `prompts/`, and `scratch/` are gitignored — nothing this command writes there
gets committed.

## Relevant skills

Subagents cannot see this file — when a step's work touches one of these areas, name the skill
in that subagent's prompt:

- `dbos-typescript` — any work involving DBOS workflows or the DBOSClient SDK.
- `frontend-design` — the Next.js UI in `mboss-web`, or Next.js UIs generated/scaffolded by the
  VS Code extension.
- `webapp-testing`, plus the Playwright plugin and MCP server — designing, writing, and running
  tests, and verifying functionality.
- The chrome-devtools MCP server and its skills — browser debugging and verification.
- `react-flow` — the React Flow UI inside the VS Code extension.
- `vscode-ext-commands` and `vscode-ext-localization` — VS Code extension functionality.
- `zod` — Zod schemas.
- `prisma-cli`, `prisma-client-api`, `prisma-database-setup`, `prisma-postgres` — anything
  Prisma.
- `nodejs-backend-patterns` — the Fastify API.
- `improve-codebase-architecture` — wherever appropriate.

## Ground rules

- **Create `./scratch/` if it doesn't exist** before launching any subagent. The design docs
  are inputs, not outputs — if `current-design.md`, `design-delta.md`, or `plan.md` is missing,
  stop and ask the user to run `/ideatoplan` first.
- **Clear this command's own scratch files first.** A stale `stepN-*.md` from a previous run is
  indistinguishable from one this run produced, and a subagent that reads one will silently
  implement against the wrong state of the code. Before launching any subagent, delete exactly
  these:

  ```
  rm -f ./scratch/step1-request-research.md \
        ./scratch/step2-design-review.md \
        ./scratch/step3-{root,mboss-database,mboss-nodejs-api,mboss-nodejs-dbos,mboss-vscode,mboss-web,mboss-zod}.md \
        ./scratch/step4-tdd-plan.md \
        ./scratch/step5-implementation-notes.md \
        ./scratch/step6-commits.md \
        ./scratch/step7-recommended-revisions.md \
        ./scratch/step8-validity.md \
        ./scratch/step9-necessity.md \
        ./scratch/step10-revisions-to-implement.md \
        ./scratch/step11-revision-notes.md \
        ./scratch/step12-commits.md
  ```

  **Delete only these paths.** `/ideatoplan` also writes `stepN-*.md` files into `./scratch/`
  and its names differ from these, so a blanket `rm ./scratch/step*` would destroy the design
  research this command depends on. Leave every other file in `./scratch/` alone.

  One consequence worth knowing: `step6-commits.md` and `step12-commits.md` drive (Step 13)'s
  release. Clearing them at the start means a re-run that stops before (Step 6) has no record of
  the earlier run's commits — so if you re-run after committing but before releasing, release
  from `git log` rather than trusting an empty commits file.
- **Scratch filenames are the contract between steps.** Every subagent that produces output
  writes to the exact path named below, and every subagent that consumes output reads the exact
  paths named below. Pass these paths explicitly in each subagent prompt — a subagent cannot
  see this file or the other subagents' prompts.
- **Confirm before releasing; version branches only.** Steps 5, 6, 11, and 12 commit and push,
  and (Step 13) releases to GitHub — outward-facing and hard to reverse. Every commit and push
  goes to the repo's current `*-vX.Y.Z` version branch, never directly to `main`; the
  `/release-*` commands are the only path to `main`. Stop and get the user's explicit
  go-ahead before starting (Step 13).
- **Steps are sequential unless stated otherwise.** Where a step launches several subagents at
  once, send them in a single message so they run concurrently.
- **Report faithfully.** If tests fail, show the failure. If a subagent fails or leaves work
  unfinished, say so rather than papering over it.

## Review the request, the design docs, and the code

Steps 1, 2, and 3 are mutually independent — launch all nine subagents (one for Step 1, one
for Step 2, seven for Step 3) in a single message so they run concurrently.

### (Step 1) — Review the user's request and any mockups

Launch a new `sonnet-engineer` subagent to:

- Download any Claude Design files the user specified and identify the aspects relevant to the
  user's request.
- Conduct any web searches necessary to research the request.
- Document its findings for subsequent subagents in `./scratch/step1-request-research.md`.

### (Step 2) — Review the design docs

Launch a new `sonnet-engineer` subagent (give it the user's request verbatim) to summarize each
of the following, specifically from the perspective of implementing the user's requested
task(s), in `./scratch/step2-design-review.md`:

- `./design-docs/current-design.md` — the current system's most recent design.
- `./design-docs/design-delta.md` — the overall design changes to implement, possibly
  partially done.
- `./design-docs/plan.md` — the overall implementation plan, possibly partially done.
- `./design-docs/mboss-vision-brief.md` — the vision brief.

### (Step 3) — Review the current state of the codebase

Launch seven `sonnet-engineer` subagents **concurrently**, one per directory. Each reviews its
directory from two perspectives — how the code differs from `current-design.md`,
`design-delta.md`, and `plan.md`, and what the user's requested task(s) need from this repo —
and writes notes for subsequent subagents to its own scratch file:

| Directory | Writes to |
| --- | --- |
| `./` (root superproject only — not the submodule contents) | `./scratch/step3-root.md` |
| `./mboss-database/` | `./scratch/step3-mboss-database.md` |
| `./mboss-nodejs-api/` | `./scratch/step3-mboss-nodejs-api.md` |
| `./mboss-nodejs-dbos/` | `./scratch/step3-mboss-nodejs-dbos.md` |
| `./mboss-vscode/` | `./scratch/step3-mboss-vscode.md` |
| `./mboss-web/` | `./scratch/step3-mboss-web.md` |
| `./mboss-zod/` | `./scratch/step3-mboss-zod.md` |

## Cross-project TDD implementation

### (Step 4) — Design the TDD plan

Launch a new `opus-engineer` subagent to:

- Read `./scratch/step1-request-research.md`, `./scratch/step2-design-review.md`, and all seven
  `./scratch/step3-*.md` files.
- Assemble an overall test-driven development plan using Playwright and unit tests as
  appropriate for the user's requested task(s). (The Playwright plugin and MCP server are
  available.)
- Note every cross-repo dependency across the Git submodules: the `/release-*` commands run
  only at the very end, so mid-run the plan must sometimes commit code to one repo and update
  submodule pointers to it before the next piece of code can be written or a test can pass.
- Document the plan in `./scratch/step4-tdd-plan.md`.

### (Step 5) — Implement the TDD plan

Launch a new `opus-engineer` subagent to:

- Read `./scratch/step1-request-research.md`, `./scratch/step2-design-review.md`, the
  `./scratch/step3-*.md` files, and `./scratch/step4-tdd-plan.md`.
- Implement the TDD plan using test-driven development — unit tests and Playwright end-to-end
  tests as appropriate. Write the failing test first, then make it pass.
- The Dockerfile in the root repo and its docker compose point at the nested submodules, which
  always carry the latest dev code — sometimes containers must be brought down and back up to
  pick up new code.
- Commit code and update submodule pointers only as needed to get tests to pass, always on
  each repo's current `*-vX.Y.Z` version branch.
- Record what was implemented, test results, commits made, deviations from the plan, and
  anything unfinished in `./scratch/step5-implementation-notes.md`.

### (Step 6) — Commit the implementation

Launch a new `sonnet-engineer` subagent to:

- Review, commit, and push any outstanding code changes from (Step 5) that are still
  uncommitted, on each repo's current `*-vX.Y.Z` version branch.
- Record which repos changed and what was committed and pushed, per repo, in
  `./scratch/step6-commits.md` — (Step 13) reads this to know what to release.

## Review and revise the implementation

### (Step 7) — Review the implementation

Launch a new `opus-engineer` subagent to:

- Read `./scratch/step1-request-research.md`, `./scratch/step2-design-review.md`, the
  `./scratch/step3-*.md` files, `./scratch/step4-tdd-plan.md`, and
  `./scratch/step5-implementation-notes.md`, then review the implementation itself.
- Assemble a list of recommended revisions to the (Step 5) implementation in
  `./scratch/step7-recommended-revisions.md`. Number each recommended revision so later steps
  can refer to them unambiguously.

### (Steps 8 and 9) — Are the revisions valid? Are they necessary?

These two reviews are independent — launch both `sonnet-engineer` subagents **concurrently**
in a single message. Each reads the same inputs as (Step 7) plus
`./scratch/step7-recommended-revisions.md`, then judges every numbered revision:

- **(Step 8)** — determine which recommended revisions are actually **valid**. Write the
  verdict per revision number, with reasoning, to `./scratch/step8-validity.md`.
- **(Step 9)** — determine which recommended revisions are actually **necessary**. Write the
  verdict per revision number, with reasoning, to `./scratch/step9-necessity.md`.

### (Step 10) — Identify revisions to implement

Launch a new `sonnet-engineer` subagent to:

- Read `./scratch/step8-validity.md` and `./scratch/step9-necessity.md`.
- Determine which recommended revisions from (Step 7) are **both valid and necessary**.
- Write that set — by revision number, with the full text of each — to
  `./scratch/step10-revisions-to-implement.md`. If none qualify, say so explicitly in the file.

Then branch:

- **No revisions qualify** → skip (Step 11); run (Step 12) anyway to confirm nothing is left
  uncommitted.
- **Some revisions qualify** → proceed to (Step 11).

### (Step 11) — Implement revisions to tests and code

Launch a new `opus-engineer` subagent to:

- Read `./scratch/step4-tdd-plan.md`, `./scratch/step5-implementation-notes.md`, and
  `./scratch/step10-revisions-to-implement.md` (with `./scratch/step1-request-research.md`,
  `./scratch/step2-design-review.md`, and the `./scratch/step3-*.md` files as context).
- Implement the qualifying revisions using test-driven development — unit tests and Playwright
  end-to-end tests as appropriate.
- Same rules as (Step 5): docker compose points at the nested submodules (bounce containers to
  pick up new code); commit and update submodule pointers only as needed to get tests to pass,
  always on version branches.
- Record what changed, test results, and commits made in `./scratch/step11-revision-notes.md`.

### (Step 12) — Commit the revisions

Launch a new `sonnet-engineer` subagent to:

- Review, commit, and push any outstanding code changes from (Step 11) that are still
  uncommitted, on each repo's current `*-vX.Y.Z` version branch.
- Record which repos changed and what was committed and pushed in
  `./scratch/step12-commits.md`. If nothing was outstanding, say so in the file.

## Release

### (Step 13) — Release all changes in GitHub

**Stop and confirm with the user before this step** (see ground rules). Once confirmed, launch
a new `sonnet-engineer` subagent to:

- Read `./scratch/step6-commits.md` and `./scratch/step12-commits.md` to determine which
  submodules changed.
- Release each updated submodule via its `/release-*` command (`/release-database`,
  `/release-zod`, `/release-api`, `/release-dbos`, `/release-vscode`, `/release-web`).
- Finally, release the root project with `/release-root`.

## Update the implementation plan

### (Step 14) — Mark completed plan tasks

No subagent — do this inline. Edit `./design-docs/plan.md` and mark each task completed during
this run as Done with a green checkmark emoji (✅) next to its number in the table. Mark only
tasks that were actually implemented and verified — not tasks skipped or left partially done.

## Report

Tell the user which plan tasks were implemented and checked off, summarize the code and tests
written per submodule, and state test results honestly — including any failures, with output.
State whether (Step 11) ran and which revisions it applied. List which submodules were released
and confirm `/release-root` ran (or that the user declined the release). Call out anything
unfinished, skipped, or unverified.
