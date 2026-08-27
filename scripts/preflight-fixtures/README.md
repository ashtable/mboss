# Pre-flight fixtures

Each file is a recorded `gh run list --json
headSha,conclusion,status,url,createdAt` response, fed to
`scripts/release-preflight.sh` through `MBOSS_GH_RUNS_JSON` by
`scripts/verify-release-preflight.sh`. That environment variable is
the pre-flight's only injection seam: it exists so the red-CI and
no-run refusals are reachable without waiting for a real build to
break.

`__E2E_HEAD__` is a placeholder. The verify script rewrites it to
`git -C mboss-e2e-tests rev-parse HEAD` before each run, so the
fixtures keep describing the commit actually being released instead
of rotting into a stale SHA.

| File | What it stands for |
| --- | --- |
| `green.json` | CI passed on the commit being released. The newer, red run is for a SHA that is not an ancestor of that commit — a run from some other branch — so a pre-flight that ignored the ancestor test would fail this case. |
| `red.json` | CI failed on the commit being released. The older, green run at the same SHA is there so picking any matching run rather than the newest one fails this case. |
| `none.json` | No runs at all — the honest state before the e2e suite's CI has ever run against this branch. |
