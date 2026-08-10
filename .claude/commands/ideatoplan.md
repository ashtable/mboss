---
description: Turn an idea or mockup into design docs and a cross-project implementation plan
argument-hint: "[the idea, feature request, or Claude Design file URL]"
allowed-tools: Agent, Read, Write, Edit, Glob, Grep, WebSearch, WebFetch, Bash(mkdir:*), Bash(ls:*)
---

Turn the user's idea or initial mockup into a formal set of design documents and an
implementation plan they can hand to Claude Code.

The user's request: $ARGUMENTS

If the request above is empty, stop and ask what they want designed before doing anything else.

## Code locations

This is the "MBOSS" root-level superproject at `/Users/ash/code/mboss`. Every related Git repo
lives here as a submodule. What belongs where:

- `./` — the root superproject. Holds each repo as a submodule, plus a docker compose file
  tracking the latest commit on the latest version branch of each submodule needed to run the
  cloud stack locally (`mboss-nodejs-api`, `mboss-nodejs-dbos`, `mboss-web`) alongside
  supporting servers (postgres, weaviate, docling).
- `./design-docs/` — transient design documents produced by this command.
- `./mboss-database/` — Prisma migrations and shared data models. Added as a submodule to
  `mboss-nodejs-api` and others as needed.
- `./mboss-nodejs-api/` — Node.js API in TypeScript and Fastify, using the shared data models
  from `./mboss-database/`. The only interface to the mBoss Postgres database.
- `./mboss-nodejs-dbos/` — the DBOS durable-execution workflow service.
- `./mboss-vscode/` — the mBoss VS Code extension, TypeScript and React Flow.
- `./mboss-web/` — the mBoss Next.js UI in TypeScript, using the shared data models from
  `./mboss-database/`.
- `./mboss-zod/` — shared Zod schemas. Added as a submodule to other projects as needed.
- `./prompts/` — ad-hoc prompts the user edits by hand.
- `./scratch/` — where subagents leave notes to pass between steps.

`design-docs/`, `prompts/`, and `scratch/` are gitignored — nothing this command writes there
gets committed.

## Ground rules

- **Create `./design-docs/` and `./scratch/` if they don't exist** before launching any subagent.
- **Clear this command's own scratch files first.** A stale `stepN-*.md` from a previous run is
  indistinguishable from one this run produced, and a subagent that reads one will silently
  design against the wrong system. Before launching any subagent, delete exactly these:

  ```
  rm -f ./scratch/step1-{root,mboss-database,mboss-nodejs-api,mboss-nodejs-dbos,mboss-vscode,mboss-web,mboss-zod}.md \
        ./scratch/step3-request-research.md \
        ./scratch/step5-recommended-revisions.md \
        ./scratch/step6-validity.md \
        ./scratch/step7-necessity.md \
        ./scratch/step8-revisions-to-implement.md
  ```

  **Delete only these paths.** `/plantocode` also writes `stepN-*.md` files into `./scratch/`
  and its names differ from these, so a blanket `rm ./scratch/step*` would destroy its output.
  Leave every other file in `./scratch/` alone.
- **Scratch filenames are the contract between steps.** Every subagent that produces output
  writes to the exact path named below, and every subagent that consumes output reads the exact
  paths named below. Pass these paths explicitly in each subagent prompt — a subagent cannot see
  this file or the other subagents' prompts.
- **Ask before deleting.** `current-design.md` and `design-delta.md` are overwritten by this
  run. If either already exists, ask the user for permission before removing it.
- **Steps are sequential unless stated otherwise.** Where a step launches several subagents at
  once, send them in a single message so they run concurrently.
- **Report faithfully.** If a step produces nothing useful or a subagent fails, say so rather
  than papering over it.

## Review & document the current system

### (Step 1) — Review the current code

Launch seven `sonnet-engineer` subagents **concurrently**, one per directory. Each explores and
summarizes the contents of its directory for a subsequent subagent, writing to its own scratch
file:

| Directory | Writes to |
| --- | --- |
| `./` (root superproject only — not the submodule contents) | `./scratch/step1-root.md` |
| `./mboss-database/` | `./scratch/step1-mboss-database.md` |
| `./mboss-nodejs-api/` | `./scratch/step1-mboss-nodejs-api.md` |
| `./mboss-nodejs-dbos/` | `./scratch/step1-mboss-nodejs-dbos.md` |
| `./mboss-vscode/` | `./scratch/step1-mboss-vscode.md` |
| `./mboss-web/` | `./scratch/step1-mboss-web.md` |
| `./mboss-zod/` | `./scratch/step1-mboss-zod.md` |

Tell each one its summary is input for a later design step, so it should capture architecture,
entry points, key modules, data models, and external dependencies — not a file listing.

**(Step 3) has no dependency on Steps 1 or 2** — launch it in the same message as this batch.

### (Step 2) — Document the current design

Launch a new `sonnet-engineer` subagent to:

- Read all seven `./scratch/step1-*.md` files from (Step 1).
- Document the design of the current system in `./design-docs/current-design.md`.
- Keep it detailed and thorough but concise. Use plenty of mermaid diagrams to convey
  architecture and sequences.

## Design the delta to the current system

### (Step 3) — Review the user's request

Launch a new `sonnet-engineer` subagent to:

- Review the user's request, downloading any Claude Design files the user specified.
- Conduct any web searches necessary to research the request.
- Document its findings for a subsequent subagent in `./scratch/step3-request-research.md`.

### (Step 4) — Design the delta

Launch a new `fable-engineer` subagent to:

- Read `./design-docs/current-design.md` (Step 2) and `./scratch/step3-request-research.md`
  (Step 3).
- Assemble a design for the changes needed to the current system such that it implements the
  user's requested feature(s).
- Document that design in `./design-docs/design-delta.md` for a subsequent subagent.

### (Step 5) — Review the delta

Launch a new `fable-engineer` subagent to:

- Read `./design-docs/current-design.md`, `./scratch/step3-request-research.md`, and
  `./design-docs/design-delta.md`.
- Assemble a list of recommended revisions to `design-delta.md` in
  `./scratch/step5-recommended-revisions.md` for a subsequent subagent. Number each recommended
  revision so later steps can refer to them unambiguously.

### (Steps 6 and 7) — Are the revisions valid? Are they necessary?

These two reviews are independent — launch both `sonnet-engineer` subagents **concurrently** in
a single message. Each reads `./design-docs/current-design.md`,
`./scratch/step3-request-research.md`, `./design-docs/design-delta.md`, and
`./scratch/step5-recommended-revisions.md`, then judges every numbered revision from (Step 5):

- **(Step 6)** — determine which recommended revisions are actually **valid**. Write the verdict
  per revision number, with reasoning, to `./scratch/step6-validity.md`.
- **(Step 7)** — determine which recommended revisions are actually **necessary**. Write the
  verdict per revision number, with reasoning, to `./scratch/step7-necessity.md`.

### (Step 8) — Identify revisions to implement

Launch a new `sonnet-engineer` subagent to:

- Read `./scratch/step6-validity.md` and `./scratch/step7-necessity.md`.
- Determine which recommended revisions from (Step 5) are **both valid and necessary**.
- Write that set — by revision number, with the full text of each — to
  `./scratch/step8-revisions-to-implement.md`. If none qualify, say so explicitly in the file.

Then branch:

- **No revisions qualify** → skip (Step 9) and go straight to (Step 10).
- **Some revisions qualify** → proceed to (Step 9).

### (Step 9) — Implement revisions to the delta

Launch a new `fable-engineer` subagent to:

- Read `./design-docs/design-delta.md` (Step 4) and `./scratch/step8-revisions-to-implement.md`
  (Step 8).
- Edit `./design-docs/design-delta.md` in place to apply those revisions.

## Plan the cross-project implementation

### (Step 10) — Create the implementation plan

Launch a new `fable-engineer` subagent to:

- Read `./design-docs/current-design.md` and `./design-docs/design-delta.md`.
- Design a cross-project implementation plan with an ordered, numbered table of tasks covering
  every impacted Git repo in the root project needed to implement the design in
  `design-delta.md`. Order tasks so cross-repo dependencies come first — a shared schema in
  `mboss-zod` or a migration in `mboss-database` lands before the consumers that need it.
- Document that plan in `./design-docs/plan.md`.

## Report

Tell the user which files were written (`current-design.md`, `design-delta.md`, `plan.md`), give
a short summary of the proposed change, state whether (Step 9) ran and which revisions it
applied, and call out any open questions or assumptions the design rests on.
