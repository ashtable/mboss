# Pre-flight fixtures

Each file is a recorded `gh run list --json
headSha,conclusion,status,url,createdAt` response, fed to
`scripts/release-preflight.sh` through `MBOSS_GH_RUNS_DIR` by
`scripts/verify-release-preflight.sh`. That environment variable is
the pre-flight's only injection seam: it names a directory holding
one `<submodule path>.json` per repository being released, and it
exists so the red-CI and no-run refusals are reachable without
waiting for a real build to break.

`__HEAD__` and `__REPO__` are placeholders. The verify script
rewrites them to that submodule's `rev-parse HEAD` and its path
before each run, so the fixtures keep describing the commits
actually being released instead of rotting into stale SHAs — and so
one file can stand for whichever repository a case is about.

A repository with no `.github/workflows/ci.yml` is given no file at
all. The pre-flight must not demand evidence a repository cannot
produce, and the green case is where that is proved: an unwanted
question shows up as a refusal naming the missing run list.

| File | What it stands for |
| --- | --- |
| `green.json` | CI passed on the commit being released. The newer run is for a SHA this clone has never fetched, so a pre-flight that matched it anyway — or aborted the whole search on it — would fail this case; `unknown.json` below pins the refusal that same shape produces when it is the *only* run. |
| `red.json` | CI failed on the commit being released. The older, green run at the same SHA is there so picking any matching run rather than the newest one fails this case. |
| `none.json` | No runs at all — the honest state before a repository's CI has ever run against this branch. |
| `running.json` | CI is still in flight on the commit being released. Its `"conclusion": null` is also the one field shape that can silently shift a column out of the parsed run list, so this case pins the parsing as much as the refusal. |
| `unknown.json` | The only run names a commit this clone has never fetched — distinct from `none.json`'s "no runs exist at all": the fix here is `git fetch`, not push-and-wait, and the pre-flight's message needs to say so rather than reusing the no-run refusal. |
