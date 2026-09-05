#!/bin/sh
# Checks that scripts/release-preflight.sh actually refuses the
# releases it is supposed to refuse.
#
# The superproject has no test runner, so this script is the test:
# it runs two controls the pre-flight must accept and seven
# refusals against the real repositories, asserts both the exit
# code and the message content, and prints PASS or FAIL per case.
# It exits non-zero if any case fails.
#
# Every case needs a genuinely publishable tree, so every case
# fails honestly while a sibling repository has work in progress:
# the pre-flight stops at its first refusal, which is then the
# message a case set up elsewhere gets judged against. That FAIL
# output is the pre-flight's own message, and it names what is in
# the way.
#
# Two cases — the mismatched pins — are real mutations: they detach
# a submodule one commit back so the pre-flight compares real SHAs
# from real repositories. A trap puts each submodule back on the
# ref it was on, whether this script finishes, fails, or is
# interrupted, and the last case proves the working tree came back
# unchanged.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
preflight="$root/scripts/release-preflight.sh"
fixtures="$root/scripts/preflight-fixtures"
web="$root/mboss-web"
core="$root/mboss-core"
e2e="$root/mboss-e2e-tests"

failures=0

# Everything the trap has to put back.
status_before=$(git -C "$root" status --porcelain)
web_ref=$(git -C "$web" symbolic-ref -q --short HEAD ||
  git -C "$web" rev-parse HEAD)
core_ref=$(git -C "$core" symbolic-ref -q --short HEAD ||
  git -C "$core" rev-parse HEAD)
tmp=$(mktemp -d)

restore() {
  git -C "$web" checkout --quiet "$web_ref" 2>/dev/null || true
  git -C "$core" checkout --quiet "$core_ref" 2>/dev/null || true
  rm -rf "$tmp"
}

trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# report <case> <want-exit> <got-exit> <message> [substring...]
report() {
  case_name=$1
  want_exit=$2
  got_exit=$3
  message=$4
  shift 4

  why=""
  if [ "$got_exit" != "$want_exit" ]; then
    why="expected exit $want_exit, got $got_exit"
  fi
  for needle in "$@"; do
    case $message in
    *"$needle"*) ;;
    *) why="${why:+$why; }message is missing '$needle'" ;;
    esac
  done

  if [ -n "$why" ]; then
    failures=$((failures + 1))
    printf 'FAIL  %s\n        %s\n' "$case_name" "$why"
    printf '%s\n' "$message" | sed 's/^/        | /'
  else
    printf 'PASS  %s\n' "$case_name"
  fi
}

# Runs the pre-flight with a directory of fixture run lists; sets
# rc and out.
run_preflight() {
  out=$(MBOSS_GH_RUNS_DIR="$1" "$preflight" --root "$root" 2>&1) &&
    rc=0 || rc=$?
}

# The pre-flight reads a run list per submodule, so each case is a
# directory rather than a file: every repository that contributes a
# CI workflow gets one, named after its path.
#
# The fixtures name the commit being released as __HEAD__ and the
# repository as __REPO__, so they do not rot every time a submodule
# moves. __ANCESTOR__ and __MERGE_PARENT__ name the two commits
# that are not the release but sit next to it: one the pre-flight
# must refuse and one it must accept. Repositories with no workflow
# are deliberately given no file at all — the pre-flight must not
# ask about them, and the green case is where that is proved.
covered_paths=$(git config --file "$root/.gitmodules" \
  --get-regexp '^submodule\..*\.path$' | cut -d' ' -f2- |
  while IFS= read -r path; do
    if git -C "$root/$path" cat-file -e HEAD:.github/workflows/ci.yml \
      2>/dev/null; then
      printf '%s\n' "$path"
    fi
  done)

# case_dir <case> [<path>=<case> ...] — a directory holding the
# named case for every covered submodule, with the overrides
# applied to the paths that name them.
case_dir() {
  base=$1
  shift
  dir="$tmp/$base$(printf '%s' "$*" | tr -c 'A-Za-z0-9._-' '_')"
  mkdir -p "$dir"

  for path in $covered_paths; do
    name=$base
    for override in "$@"; do
      case $override in
      "$path="*) name=${override#*=} ;;
      esac
    done

    # Each placeholder is resolved only where a fixture asks for
    # it: HEAD^2 exists in a merge commit alone, and asking for it
    # everywhere would abort the run instead of writing the case.
    body=$(cat "$fixtures/$name.json")
    case $body in
    *__HEAD__*)
      sha=$(git -C "$root/$path" rev-parse HEAD)
      body=$(printf '%s\n' "$body" | sed "s/__HEAD__/$sha/g")
      ;;
    esac
    case $body in
    *__ANCESTOR__*)
      sha=$(git -C "$root/$path" rev-parse HEAD~2)
      body=$(printf '%s\n' "$body" | sed "s/__ANCESTOR__/$sha/g")
      ;;
    esac
    case $body in
    *__MERGE_PARENT__*)
      sha=$(git -C "$root/$path" rev-parse HEAD^2)
      body=$(printf '%s\n' "$body" | sed "s/__MERGE_PARENT__/$sha/g")
      ;;
    esac

    printf '%s\n' "$body" | sed "s/__REPO__/$path/g" \
      >"$dir/$path.json"
  done

  printf '%s' "$dir"
}

printf 'verifying %s\n\n' "$preflight"

green=$(case_dir green)

# 1. Green control: nothing wrong, so nothing to refuse. Also proves
#    a run whose SHA this clone has never fetched (the newer, red
#    one) is skipped rather than either matching it by mistake or
#    aborting the whole search — and that a submodule contributing
#    no CI workflow is not asked for evidence it cannot have, since
#    no fixture was written for one.
run_preflight "$green"
report "green: a publishable tree with CI green on every pin" \
  0 "$rc" "$out" \
  "https://github.com/ashtable/mboss-e2e-tests/actions/runs/2" \
  "https://github.com/ashtable/mboss-vscode/actions/runs/2"

# 2. Mismatched pin: the root is about to release an mboss-web
#    commit that mboss-e2e-tests never tested. Real detach, real
#    comparison, restored immediately.
web_prev=$(git -C "$web" rev-parse HEAD~1)
e2e_web=$(git -C "$e2e" rev-parse HEAD:mboss-web)
if [ "$web_prev" = "$e2e_web" ]; then
  failures=$((failures + 1))
  printf 'FAIL  %s\n        %s\n' \
    "mismatched pin: root mboss-web differs from the nested pin" \
    "mboss-web HEAD~1 already equals the nested pin, so detaching
        it would not mismatch anything"
else
  git -C "$web" checkout --quiet --detach "$web_prev"
  run_preflight "$green"
  git -C "$web" checkout --quiet "$web_ref"
  report "mismatched pin: root mboss-web differs from the nested pin" \
    1 "$rc" "$out" "mboss-web" "$web_prev" "$e2e_web"
fi

# 3. A pin the suite cannot vouch for: mboss-core is nested by the
#    extension and by the server, never by the suite, so only a
#    walk that goes past mboss-e2e-tests compares it at all.
core_prev=$(git -C "$core" rev-parse HEAD~1)
git -C "$core" checkout --quiet --detach "$core_prev"
run_preflight "$green"
git -C "$core" checkout --quiet "$core_ref"
report "unsuited pin: root mboss-core differs from what nests it" \
  1 "$rc" "$out" "mboss-core" "$core_prev"

# 4. Red e2e head: CI ran on exactly this commit and failed.
run_preflight "$(case_dir green mboss-e2e-tests=red)"
report "red e2e head: CI failed on the commit being released" \
  1 "$rc" "$out" "mboss-e2e-tests" "failure" \
  "https://github.com/ashtable/mboss-e2e-tests/actions/runs/3"

# 5. Red anywhere else: the hole this gate was widened to close. The
#    e2e suite going green says nothing about whether the extension
#    it drives ever built — and a /release-<repo> command can merge
#    a branch before its own CI has started, because no branch here
#    is protected.
run_preflight "$(case_dir green mboss-vscode=red)"
report "red submodule: CI failed on a pin that is not the suite's" \
  1 "$rc" "$out" "mboss-vscode" "failure" \
  "https://github.com/ashtable/mboss-vscode/actions/runs/3"

# 6. No matching run: CI has never run on this commit.
run_preflight "$(case_dir green mboss-e2e-tests=none)"
report "no matching CI run: nothing covers the e2e HEAD" \
  1 "$rc" "$out" "no CI run covers" "$(git -C "$e2e" rev-parse HEAD)"

# 7. Still running: a run in flight has a null conclusion, which is
#    both a release to refuse and the one shape that can silently
#    shift a field out of the parsed run list.
run_preflight "$(case_dir green mboss-e2e-tests=running)"
report "unfinished CI run: the run covering the e2e HEAD is in flight" \
  1 "$rc" "$out" "in_progress" \
  "https://github.com/ashtable/mboss-e2e-tests/actions/runs/5"

# 8. Unknown commit: the only run names a SHA this clone has never
#    fetched, which is a different refusal from "no runs at all" —
#    the fix is to fetch, not to push and wait.
run_preflight "$(case_dir green mboss-e2e-tests=unknown)"
report "unknown commit: the only run names a SHA this clone lacks" \
  1 "$rc" "$out" "never fetched" "fetch --all"

# 9. A run behind the release: the only success ran two commits
#    back. An ancestor is not evidence for what came after it — a
#    run that covers a whole branch's worth of later commits covers
#    none of them.
run_preflight "$(case_dir green mboss-e2e-tests=stale)"
report "stale run: the only success is behind the commit released" \
  1 "$rc" "$out" "no CI run covers" "$(git -C "$e2e" rev-parse HEAD)"

# 10. The one commit an earlier run does cover, and the reason the
#     refusal above cannot simply demand equality: CI runs on pull
#     requests, so a merge commit's evidence is the run on the head
#     it merged.
merged_repo=""
for path in $covered_paths; do
  case $(git -C "$root/$path" rev-list --parents -n1 HEAD) in
  *' '*' '*)
    merged_repo=$path
    break
    ;;
  esac
done

merged_case="merge parent: the run on the head a merge commit merged"
if [ -z "$merged_repo" ]; then
  failures=$((failures + 1))
  printf 'FAIL  %s\n        %s\n' "$merged_case" \
    "no submodule is checked out at a merge commit, so the case
        cannot be built"
else
  run_preflight "$(case_dir green "$merged_repo=merged")"
  report "$merged_case" 0 "$rc" "$out" \
    "https://github.com/ashtable/$merged_repo/actions/runs/8"
fi

# The mutation above is only safe if it is provably undone.
status_after=$(git -C "$root" status --porcelain)
if [ "$status_before" = "$status_after" ]; then
  printf 'PASS  working tree unchanged by this script\n'
else
  failures=$((failures + 1))
  printf 'FAIL  working tree unchanged by this script\n'
  printf '        before:\n%s\n' "$status_before" | sed 's/^/        | /'
  printf '        after:\n%s\n' "$status_after" | sed 's/^/        | /'
fi

printf '\n'
if [ "$failures" -eq 0 ]; then
  printf 'all cases passed\n'
  exit 0
fi
printf '%s case(s) failed\n' "$failures"
exit 1
