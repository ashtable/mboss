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
#   4. CI is green on every commit this release records
#
# Checks 3 and 4 are what make the evidence mean something. The
# release commands bump the superproject pin only, so a nested pin
# is always a hand edit; when that edit is forgotten, the suite that
# vouched for the release ran against older code. Check 3 catches
# exactly that.
#
# Check 4 asks every submodule, not only the suite. A
# /release-<repo> command merges a version branch into main, no
# branch here is protected, and nothing makes that merge wait for
# the branch's own CI — so a repository can reach a release having
# never gone green. One did, and this superproject pinned it.
#
# The submodules covered by check 3 are read out of
# mboss-e2e-tests/.gitmodules and those covered by check 4 out of
# this superproject's own, rather than listed here, so the gate
# grows on its own as either nests more repositories.
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

  remotes=$(git -C "$root/$path" branch -r --contains HEAD 2>/dev/null)
  if [ -z "$remotes" ]; then
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
[ -n "$nested_paths" ] ||
  fail "$E2E/.gitmodules records no submodules, so this release is
covered by nothing. Nest the service repositories it tests."

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

# --- check 4: CI green on every commit being released ---
#
# A run covers a commit when it ran on that commit. CI runs on pull
# requests, so a merge commit never has a run of its own; what
# covers it is the run on the head it merged, which is one of its
# parents. Nothing further back counts: a commit pushed after the
# last run was built by nothing, and accepting any ancestor would
# let that run vouch for every commit pushed since.

CI_WORKFLOW=.github/workflows/ci.yml

# What GitHub calls the repository a submodule was cloned from.
slug_of() {
  git -C "$root/$1" config --get remote.origin.url |
    sed -e 's#^git@github\.com:##' \
      -e 's#^https://github\.com/##' \
      -e 's#\.git$##'
}

# Refuses unless a finished, successful CI run covers $1's HEAD.
# Appends one line to $covered saying which run, or why none was
# asked for.
check_ci() {
  repo=$1
  head=$(git -C "$root/$repo" rev-parse HEAD)

  # A commit that contributes no workflow has no CI evidence to
  # demand. Read out of the commit being released rather than off
  # the working tree, because what is being pinned is the question.
  if ! git -C "$root/$repo" cat-file -e "HEAD:$CI_WORKFLOW" \
    2>/dev/null; then
    covered="$covered
  $repo $head — no $CI_WORKFLOW, so no CI to wait for"

    return 0
  fi

  if [ -n "${MBOSS_GH_RUNS_DIR:-}" ]; then
    # The one injection seam, so the refusals below are reachable
    # without a real red build.
    runs_source=$MBOSS_GH_RUNS_DIR/$repo.json
    [ -f "$runs_source" ] ||
      fail "MBOSS_GH_RUNS_DIR holds no run list for $repo:
  $runs_source"
    runs=$(cat "$runs_source")
  else
    runs_source=$(slug_of "$repo")
    runs=$(gh run list --repo "$runs_source" --workflow CI --limit 20 \
      --json headSha,conclusion,status,url,createdAt </dev/null) ||
      fail "gh run list failed for $runs_source. Is gh authenticated?"
  fi

  # gh emits a flat array of flat objects, and none of these five
  # values can contain a brace, a quote or a pipe, so splitting on }
  # and pulling each key out by name is well defined here. Reading
  # the keys by name rather than by position keeps this working
  # whatever order gh prints them in.
  #
  # The fields are pipe-separated rather than tab-separated because
  # a run still in flight has "conclusion": null, and read collapses
  # a run of IFS whitespace into one delimiter — a tab would shift
  # every later field one to the left exactly when the conclusion is
  # missing.
  records=$(printf '%s\n' "$runs" | awk '
    function value(record, key,   pattern, found) {
      pattern = "\"" key "\"[ \t]*:[ \t]*\"[^\"]*\""
      if (!match(record, pattern)) return ""
      found = substr(record, RSTART, RLENGTH)
      sub(/^"[^"]*"[ \t]*:[ \t]*"/, "", found)
      sub(/"$/, "", found)
      return found
    }
    BEGIN { RS = "}"; OFS = "|" }
    $0 ~ /"headSha"/ {
      print value($0, "createdAt"), value($0, "headSha"),
        value($0, "conclusion"), value($0, "status"), value($0, "url")
    }
  ' | sort -r)

  # The commits a run may name and still cover this release: the
  # commit itself, and the heads it merged when it is a merge.
  # rev-list prints the commit and then its parents, so two spaces
  # is what a merge looks like.
  parents=$(git -C "$root/$repo" rev-list --parents -n1 HEAD)
  covering=$head
  case $parents in
  *' '*' '*) covering=$parents ;;
  esac

  # createdAt leads each line, so a reverse sort is newest first
  # whatever order the run list arrived in.
  #
  # A run naming a commit this clone has never fetched is a
  # different problem from no run at all — the fix is to fetch, not
  # to push and wait — so cat-file separates the two rather than
  # letting an unfetched SHA read as "nothing covers this".
  match=""
  unknown=""
  while IFS='|' read -r created sha conclusion status url; do
    [ -n "$sha" ] || continue
    if ! git -C "$root/$repo" cat-file -e "$sha^{commit}" \
      2>/dev/null; then
      unknown="$unknown $sha"
      continue
    fi
    case " $covering " in
    *" $sha "*)
      match="$conclusion|$status|$url|$sha"
      break
      ;;
    esac
  done <<INNER
$records
INNER

  if [ -z "$match" ] && [ -n "$unknown" ]; then
    fail "no CI run covers $repo HEAD $head (searched $runs_source).
$(printf '%s\n' "$unknown" | tr ' ' '\n' | sed '/^$/d;s/^/  /') named a
commit this clone has never fetched. Run \`git -C $repo fetch --all\`
and try again."
  fi

  [ -n "$match" ] ||
    fail "no CI run covers $repo HEAD $head (searched $runs_source).
Push the branch, open or refresh its PR, and let CI finish before
releasing."

  IFS='|' read -r conclusion status url sha <<INNER
$match
INNER

  [ "$status" = "completed" ] ||
    fail "the CI run covering $repo $sha is still '$status':
  $url
Wait for it to finish before releasing."

  [ "$conclusion" = "success" ] ||
    fail "CI on $repo $sha concluded '${conclusion:-none}':
  $url
Fix it and let it go green before releasing."

  covered="$covered
  $repo $sha
    $url"
}

covered=""

while IFS= read -r path; do
  [ -n "$path" ] || continue

  check_ci "$path"
done <<EOF
$root_paths
EOF

printf 'release pre-flight: %s\n' \
  "submodules clean and pushed, nested pins match, CI green$covered"
