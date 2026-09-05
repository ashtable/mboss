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
- **Nested pin parity?** For every submodule nested inside a submodule, the commit the
  parent records must equal the commit this release is about to pin. A repository is
  built and tested from what it nests: the e2e suite runs the commits inside it, and the
  packaged extension inlines the library and the skill inside it. No `/release-<repo>`
  command touches a nested pin, so that edit is always by hand and is the step that gets
  forgotten.
- **CI green on every pin?** For each submodule this release records, the newest CI run
  that ran on that submodule's HEAD must have concluded `success`. A merge commit is
  covered by a run on one of its parents instead, because CI runs on pull requests and a
  merge commit has no run of its own — but nothing further back counts, or one green run
  would vouch for every commit pushed after it. A run still in flight is refused too — an
  unfinished suite is not evidence. A submodule whose released commit contributes no
  `.github/workflows/ci.yml` is skipped, because there is no evidence to demand.

  Every submodule and not only the suite, because the suite going green says nothing
  about whether a repository it does not exercise ever built — and no branch here is
  protected, so a `/release-<repo>` command can merge a version branch before its own CI
  has even started.

Both checks read the repositories they cover out of the relevant `.gitmodules` rather
than a list, so they grow on their own as any repository nests more. Until a repository's CI has run at least once, the honest
outcome is "no CI run covers HEAD", which is a refusal, not a bug.

The gate itself is checked by `./scripts/verify-release-preflight.sh`, which exercises a
green control, a genuinely mismatched pin, a red e2e head, a red pin that is not the
suite's, a missing CI run, an unfinished one, a run that is behind the commit being
released, and the merge parent that is the one earlier run a release may lean on. Run it
after changing either script.

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

5. **Let CI finish, then merge the PR.** Nothing on GitHub makes the merge wait: no
   branch in this project is protected, so `gh pr merge` will happily land a branch whose
   only check has not started. Watch them first —
   `gh pr checks <branch> --repo ashtable/mboss --watch` — and read the conclusion it
   reports. If it reports no checks at all, check that claim rather than assuming it:
   `gh api repos/ashtable/mboss/contents/.github/workflows`. A repository that has a
   workflow and no run has not been asked yet; push again or reopen the PR.
   Then `gh pr merge <branch> --repo ashtable/mboss --merge`.
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
