#!/bin/sh
# Refuses to release a superproject that nobody could fetch, or
# whose end-to-end evidence came from a different set of commits
# than the one being released.
#
#   scripts/release-preflight.sh [--root <dir>]
#     exit 0  everything is publishable
#     exit 1  first failure, with one message naming the repository
#             and what to do about it
#
# Four checks, in the order a release hits them:
#
#   1. every submodule working tree is clean
#   2. every submodule HEAD exists on its own remote
#   3. every commit mboss-e2e-tests nests matches the commit this
#      superproject is about to record for the same repository
#   4. CI is green on the mboss-e2e-tests commit being released
#
# Checks 3 and 4 are what make the e2e suite mean something. The
# release commands bump the superproject pin only, so a nested pin
# is always a hand edit; when that edit is forgotten, the suite that
# vouched for the release ran against older code. Check 3 catches
# exactly that, and check 4 refuses a release whose evidence never
# actually passed.
#
# The submodules covered by checks 3 and 4 are read out of
# mboss-e2e-tests/.gitmodules rather than listed here, so the gate
# grows on its own as the suite nests more repositories.
#
# Depends on git and gh, and on nothing else.
set -eu

E2E=mboss-e2e-tests

usage() {
  printf 'usage: %s [--root <dir>]\n' "$0" >&2
  exit 2
}

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
while [ $# -gt 0 ]; do
  case $1 in
  --root)
    [ $# -ge 2 ] || usage
    root=$2
    shift 2
    ;;
  -h | --help) usage ;;
  *)
    printf 'unknown argument: %s\n' "$1" >&2
    usage
    ;;
  esac
done

fail() {
  printf 'release pre-flight: %s\n' "$*" >&2
  exit 1
}

# The paths (not the names) recorded in a .gitmodules file, one per
# line. A path is what every git -C invocation below needs.
submodule_paths() {
  git config --file "$1" --get-regexp '^submodule\..*\.path$' |
    cut -d' ' -f2-
}

[ -f "$root/.gitmodules" ] ||
  fail "$root has no .gitmodules — is it the superproject?"

# --- checks 1 and 2: the superproject's own submodules ---

root_paths=$(submodule_paths "$root/.gitmodules")

while IFS= read -r path; do
  [ -n "$path" ] || continue

  [ -e "$root/$path/.git" ] ||
    fail "$path is not checked out. Run:
  git submodule update --init $path"

  if [ -n "$(git -C "$root/$path" status --porcelain)" ]; then
    fail "$path has uncommitted changes:
$(git -C "$root/$path" status --short | sed 's/^/  /')
Releasing the superproject does not commit inside a submodule. Run
that submodule's own /release-<repo> first, or commit there."
  fi

  if [ -z "$(git -C "$root/$path" branch -r --contains HEAD 2>/dev/null)" ]; then
    fail "$path HEAD $(git -C "$root/$path" rev-parse HEAD) is
local-only. Push it before releasing, or the superproject will pin a
commit nobody else can fetch."
  fi
done <<EOF
$root_paths
EOF

# --- check 3: the pins the e2e suite actually tested ---

[ -e "$root/$E2E/.git" ] ||
  fail "$E2E is not checked out, so the release cannot be told which
commits the e2e suite ran against."
[ -f "$root/$E2E/.gitmodules" ] ||
  fail "$E2E has no .gitmodules — it nests no service repositories,
so no release is covered by its suite."

nested_paths=$(submodule_paths "$root/$E2E/.gitmodules")

while IFS= read -r path; do
  [ -n "$path" ] || continue

  [ -e "$root/$path/.git" ] ||
    fail "$E2E nests $path, which the superproject does not have
checked out, so their pins cannot be compared."

  root_sha=$(git -C "$root/$path" rev-parse HEAD)
  e2e_sha=$(git -C "$root/$E2E" rev-parse "HEAD:$path" 2>/dev/null) ||
    e2e_sha=""

  [ -n "$e2e_sha" ] ||
    fail "$E2E/.gitmodules lists $path but its HEAD commit records no
gitlink there. Commit the nested submodule in $E2E."

  if [ "$root_sha" != "$e2e_sha" ]; then
    fail "$path pin mismatch.
  this release pins  $root_sha
  the e2e suite ran  $e2e_sha
The suite that vouches for this release ran against different code.
Check $path out at the released commit inside $E2E, commit the
nested gitlink, push, and let its CI run — no /release-<repo>
command touches a nested pin, so that step is always by hand."
  fi
done <<EOF
$nested_paths
EOF

# --- check 4: CI green on the e2e commit being released ---

e2e_head=$(git -C "$root/$E2E" rev-parse HEAD)

if [ -n "${MBOSS_GH_RUNS_JSON:-}" ]; then
  # The one injection seam, so the refusals below are reachable
  # without a real red build.
  [ -f "$MBOSS_GH_RUNS_JSON" ] ||
    fail "MBOSS_GH_RUNS_JSON=$MBOSS_GH_RUNS_JSON is not a file."
  runs=$(cat "$MBOSS_GH_RUNS_JSON")
  runs_source=$MBOSS_GH_RUNS_JSON
else
  origin=$(git -C "$root/$E2E" config --get remote.origin.url)
  slug=$(printf '%s' "$origin" | sed \
    -e 's#^git@github\.com:##' \
    -e 's#^https://github\.com/##' \
    -e 's#\.git$##')
  runs=$(gh run list --repo "$slug" --workflow CI --limit 20 \
    --json headSha,conclusion,status,url,createdAt) ||
    fail "gh run list failed for $slug. Is gh authenticated?"
  runs_source=$slug
fi

# gh emits a flat array of flat objects, and none of these five
# values can contain a brace or a quote, so splitting on } and
# pulling each key out by name is well defined here. Reading the
# keys by name rather than by position keeps this working whatever
# order gh prints them in.
records=$(printf '%s\n' "$runs" | awk '
  function value(record, key,   pattern, found) {
    pattern = "\"" key "\"[ \t]*:[ \t]*\"[^\"]*\""
    if (!match(record, pattern)) return ""
    found = substr(record, RSTART, RLENGTH)
    sub(/^"[^"]*"[ \t]*:[ \t]*"/, "", found)
    sub(/"$/, "", found)
    return found
  }
  BEGIN { RS = "}"; OFS = "\t" }
  $0 ~ /"headSha"/ {
    print value($0, "createdAt"), value($0, "headSha"),
      value($0, "conclusion"), value($0, "status"), value($0, "url")
  }
' | sort -r)

# createdAt leads each line, so a reverse sort is newest first
# whatever order the run list arrived in.
#
# A run covers this release when its head is an ancestor of the e2e
# HEAD: CI runs on pull requests, so the merge commit itself never
# has a run of its own, but the PR head it merged always does.
match=""
while IFS='	' read -r created sha conclusion status url; do
  [ -n "$sha" ] || continue
  if git -C "$root/$E2E" merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
    match="$conclusion	$status	$url	$sha"
    break
  fi
done <<EOF
$records
EOF

[ -n "$match" ] ||
  fail "no CI run covers $E2E HEAD $e2e_head (searched $runs_source).
Push the branch, open or refresh its PR, and let CI finish before
releasing."

IFS='	' read -r conclusion status url sha <<EOF
$match
EOF

[ "$status" = "completed" ] ||
  fail "the CI run covering $E2E $sha is still '$status':
  $url
Wait for it to finish before releasing."

[ "$conclusion" = "success" ] ||
  fail "CI on $E2E $sha concluded '$conclusion':
  $url
Fix the suite and let it go green before releasing."

printf 'release pre-flight: %s\n' \
  "submodules clean and pushed, nested pins match, $E2E CI green
  $url"
