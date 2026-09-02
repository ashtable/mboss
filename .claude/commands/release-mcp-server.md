---
description: Release the mboss-mcp-server submodule — merge its version branch into main, cut the next version branch, and bump the superproject pointer
argument-hint: "[next version, e.g. 0.1.0 — defaults to a patch bump]"
allowed-tools: Bash(git:*), Bash(gh:*), Read, Edit
---

Release the `mboss-mcp-server` submodule. Run every git command with `-C mboss-mcp-server`
(or from inside that directory) unless the step says it applies to the superproject.

Requested next version (may be empty): `$1`

## Steps

1. **Resolve the current version branch.**
   Read the checked-out branch: `git -C mboss-mcp-server rev-parse --abbrev-ref HEAD`.
   It must match `mcp-server-vX.Y.Z`. If it does not, find the latest with
   `git -C mboss-mcp-server branch -a --list '*mcp-server-v[0-9]*' --sort=-v:refname | head -1`,
   check it out, and say which branch you picked. If no such branch exists, stop and report.

2. **Commit all changes on that branch.**
   `git -C mboss-mcp-server add -A` then commit. Write a real message summarizing the actual
   diff — do not use a placeholder. If the tree is already clean, skip this step and note it.

3. **Push the branch.** `git -C mboss-mcp-server push -u origin <branch>`

4. **Open the PR.** `gh pr create --repo ashtable/mboss-mcp-server --base main --head <branch>`
   with a title and body describing the work. If a PR for the branch already exists
   (`gh pr view <branch> --repo ashtable/mboss-mcp-server`), reuse it instead of creating a
   duplicate.

5. **Let CI finish, then merge the PR.** Nothing on GitHub makes the merge wait: no
   branch in this project is protected, so `gh pr merge` will happily land a branch whose
   only check has not started. Watch them first —
   `gh pr checks <branch> --repo ashtable/mboss-mcp-server --watch` — and read the conclusion it
   reports. If it reports no checks at all, check that claim rather than assuming it:
   `gh api repos/ashtable/mboss-mcp-server/contents/.github/workflows`. A repository that has a
   workflow and no run has not been asked yet; push again or reopen the PR.
   Then `gh pr merge <branch> --repo ashtable/mboss-mcp-server --merge`.
   If the merge is blocked (checks failing, conflicts, protected branch), stop and report
   the reason — do not force it or switch strategies without asking.

6. **Sync main.** `git -C mboss-mcp-server checkout main && git -C mboss-mcp-server pull --ff-only`

7. **Cut the next branch, and tell the repository its own name.** The new version is `$1`
   if provided, otherwise a patch bump of the branch from step 1 (`mcp-server-v0.0.3` →
   `mcp-server-v0.0.4`). Create it off the freshly merged main:
   `git -C mboss-mcp-server checkout -b mcp-server-v<next>`

   Then write the new branch name into `mboss-mcp-server/.version` and commit it. That
   file is what the server's bundle stamps itself with — a build of this repository as
   somebody else's submodule is detached and has no branch to read, so the name has to
   travel in the checkout. Leaving it behind stamps the next release with the last one's
   version; the repository's own suite fails on it while the branch is checked out, which
   is the safety net rather than the mechanism. Then push:
   `git -C mboss-mcp-server push -u origin mcp-server-v<next>`

8. **Bump the superproject.** In `/Users/ash/code/mboss`:
   - `git config -f .gitmodules submodule.mboss-mcp-server.branch mcp-server-v<next>`
   - `git submodule sync --quiet mboss-mcp-server`
   - `git add .gitmodules mboss-mcp-server`
   - Commit with a message naming the released and new versions.

   Stage only `.gitmodules` and `mboss-mcp-server` — never `-A`, so unrelated superproject
   work stays untouched. Do not push the superproject unless asked.

## Report

Summarize: the released branch, the PR URL and its merge state, the new branch, and the
superproject commit plus the gitlink SHA it now records. Call out anything skipped.
