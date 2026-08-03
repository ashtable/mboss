---
description: Release the mboss-zod submodule — merge its version branch into main, cut the next version branch, and bump the superproject pointer
argument-hint: "[next version, e.g. 0.1.0 — defaults to a patch bump]"
allowed-tools: Bash(git:*), Bash(gh:*), Read, Edit
---

Release the `mboss-zod` submodule. Run every git command with `-C mboss-zod`
(or from inside that directory) unless the step says it applies to the superproject.

Requested next version (may be empty): `$1`

## Steps

1. **Resolve the current version branch.**
   Read the checked-out branch: `git -C mboss-zod rev-parse --abbrev-ref HEAD`.
   It must match `zod-vX.Y.Z`. If it does not, find the latest with
   `git -C mboss-zod branch -a --list '*zod-v[0-9]*' --sort=-v:refname | head -1`,
   check it out, and say which branch you picked. If no such branch exists, stop and report.

2. **Commit all changes on that branch.**
   `git -C mboss-zod add -A` then commit. Write a real message summarizing the actual
   diff — do not use a placeholder. If the tree is already clean, skip this step and note it.

3. **Push the branch.** `git -C mboss-zod push -u origin <branch>`

4. **Open the PR.** `gh pr create --repo ashtable/mboss-zod --base main --head <branch>`
   with a title and body describing the work. If a PR for the branch already exists
   (`gh pr view <branch> --repo ashtable/mboss-zod`), reuse it instead of creating a
   duplicate.

5. **Merge the PR.** `gh pr merge <branch> --repo ashtable/mboss-zod --merge`.
   If the merge is blocked (checks failing, conflicts, protected branch), stop and report
   the reason — do not force it or switch strategies without asking.

6. **Sync main.** `git -C mboss-zod checkout main && git -C mboss-zod pull --ff-only`

7. **Cut the next branch.** The new version is `$1` if provided, otherwise a patch bump of
   the branch from step 1 (`zod-v0.0.3` → `zod-v0.0.4`). Create it off the freshly
   merged main and push:
   `git -C mboss-zod checkout -b zod-v<next>` then
   `git -C mboss-zod push -u origin zod-v<next>`

8. **Bump the superproject.** In `/Users/ash/code/mboss`:
   - `git config -f .gitmodules submodule.mboss-zod.branch zod-v<next>`
   - `git submodule sync --quiet mboss-zod`
   - `git add .gitmodules mboss-zod`
   - Commit with a message naming the released and new versions.

   Stage only `.gitmodules` and `mboss-zod` — never `-A`, so unrelated superproject
   work stays untouched. Do not push the superproject unless asked.

## Report

Summarize: the released branch, the PR URL and its merge state, the new branch, and the
superproject commit plus the gitlink SHA it now records. Call out anything skipped.
