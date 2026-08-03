---
description: Release the mboss superproject — merge its version branch into main and cut the next version branch
argument-hint: "[next version, e.g. 0.1.0 — defaults to a patch bump]"
allowed-tools: Bash(git:*), Bash(gh:*), Read, Edit
---

Release the `mboss` superproject itself. All commands run in `/Users/ash/code/mboss`.

Requested next version (may be empty): `$1`

## Pre-flight — submodule pointers must be publishable

The superproject records a gitlink per submodule. Before committing, verify each recorded
commit is reachable on its own remote, or the release will point at commits nobody else
can fetch. For every submodule in `.gitmodules`:

- **Uncommitted changes?** `git -C <path> status --porcelain` must be empty. If not, stop
  and report which submodules are dirty — releasing the root does not commit inside them,
  and their release command (`/release-database`, `/release-web`, `/release-api`,
  `/release-dbos`, `/release-zod`) should run first.
- **Unpushed commits?** The HEAD recorded for each submodule must exist on its remote:
  `git -C <path> branch -r --contains HEAD` must be non-empty. If a submodule's HEAD is
  local-only, stop and report it.

Stop on any failure and list what needs to happen first. Do not proceed with a partial
release.

## Steps

1. **Resolve the current version branch.**
   Read the checked-out branch: `git rev-parse --abbrev-ref HEAD`.
   It must match `vX.Y.Z` (no prefix — the root branches are plain versions). If it does
   not, find the latest with `git branch -a --list '*v[0-9]*' --sort=-v:refname | head -1`,
   check it out, and say which branch you picked. If no such branch exists, stop and report.

2. **Commit all changes on that branch.**
   `git add -A` then commit. This stages any submodule gitlink advances along with the
   superproject's own files (compose, e2e tests, prompts, docs). Write a real message
   summarizing the actual diff — name which submodule pointers moved and to what. If the
   tree is already clean, skip this step and note it.

3. **Push the branch.** `git push -u origin <branch>`

4. **Open the PR.** `gh pr create --repo ashtable/mboss --base main --head <branch>` with a
   title and body describing the work, including the submodule versions this release pins.
   If a PR for the branch already exists (`gh pr view <branch> --repo ashtable/mboss`),
   reuse it instead of creating a duplicate.

5. **Merge the PR.** `gh pr merge <branch> --repo ashtable/mboss --merge`.
   If the merge is blocked (checks failing, conflicts, protected branch), stop and report
   the reason — do not force it or switch strategies without asking.

6. **Sync main.** `git checkout main && git pull --ff-only`

7. **Cut the next branch.** The new version is `$1` if provided, otherwise a patch bump of
   the branch from step 1 (`v0.0.3` → `v0.0.4`). Create it off the freshly merged main and
   push: `git checkout -b v<next>` then `git push -u origin v<next>`

8. **No pointer bump.** Nothing tracks the superproject, so the release ends here. Leave the
   submodules on their own version branches — do not run `git submodule update`, which would
   detach them from the branches they are checked out on.

## Report

Summarize: the released branch, the PR URL and its merge state, the new branch, and the
submodule versions and SHAs this release pinned. Call out anything skipped.
