---
description: Release the mboss superproject — merge its version branch into main and cut the next version branch
argument-hint: "[next version, e.g. 0.1.0 — defaults to a patch bump]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(./scripts/release-preflight.sh:*), Read, Edit
---

Release the `mboss` superproject itself. All commands run in `/Users/ash/code/mboss`.

Requested next version (may be empty): `$1`

## Pre-flight — the release must be fetchable and evidenced

Run `./scripts/release-preflight.sh`. If it exits non-zero, stop, report its message
verbatim, and do not proceed with a partial release. Do not work around it by hand.

Four checks, and why each one exists:

- **Uncommitted changes?** `git -C <path> status --porcelain` must be empty for every
  submodule in `.gitmodules`. Releasing the root does not commit inside a submodule, so
  the work would simply be left behind; that submodule's own release command
  (`/release-web`, `/release-api`, `/release-dbos`, …) should run first.
- **Unpushed commits?** `git -C <path> branch -r --contains HEAD` must be non-empty.
  The superproject records a gitlink per submodule, and a local-only HEAD is a commit
  nobody else can fetch.
- **Nested pin parity?** For every submodule `mboss-e2e-tests` nests, the commit it
  records must equal the commit this release is about to pin. The e2e suite is the
  evidence for the release, so it has to have run against the code being released — and
  no `/release-<repo>` command touches a nested pin, so that edit is always by hand and
  is the step that gets forgotten.
- **e2e CI green?** The newest CI run whose head commit is an ancestor of the
  `mboss-e2e-tests` HEAD must have concluded `success`. Ancestry rather than equality,
  because CI runs on pull requests: a merge commit has no run of its own, but the PR head
  it merged always does. A run still in flight is refused too — an unfinished suite is
  not evidence.

The pin-parity check covers whatever `mboss-e2e-tests/.gitmodules` lists, so it grows on
its own as the suite nests more repositories. Until that suite's CI has run at least
once, the honest outcome is "no CI run covers HEAD", which is a refusal, not a bug.

The gate itself is checked by `./scripts/verify-release-preflight.sh`, which exercises a
green control, a genuinely mismatched pin, a red e2e head, a missing CI run and an
unfinished one. Run it after changing either script.

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
