#!/bin/sh
# Checks that scripts/release-preflight.sh actually refuses the
# releases it is supposed to refuse.
#
# The superproject has no test runner, so this script is the test:
# it runs a green control and four refusals against the real
# repositories, asserts both the exit code and the message content,
# and prints PASS or FAIL per case. It exits non-zero if any case
# fails.
#
# The green control needs a genuinely publishable tree, so it fails
# honestly while a sibling repository has work in progress. Its
# FAIL output is the pre-flight's own message, which names what is
# in the way.
#
# One case — the mismatched pin — is a real mutation: it detaches
# mboss-web one commit back so the pre-flight compares real SHAs
# from real repositories. A trap puts the submodule back on the ref
# it was on, whether this script finishes, fails, or is interrupted,
# and the last case proves the working tree came back unchanged.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
preflight="$root/scripts/release-preflight.sh"
fixtures="$root/scripts/preflight-fixtures"
web="$root/mboss-web"
e2e="$root/mboss-e2e-tests"

failures=0

# Everything the trap has to put back.
status_before=$(git -C "$root" status --porcelain)
web_ref=$(git -C "$web" symbolic-ref -q --short HEAD ||
  git -C "$web" rev-parse HEAD)
tmp=$(mktemp -d)

restore() {
  git -C "$web" checkout --quiet "$web_ref" 2>/dev/null || true
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

# Runs the pre-flight with a fixture run list; sets rc and out.
run_preflight() {
  out=$(MBOSS_GH_RUNS_JSON="$1" "$preflight" --root "$root" 2>&1) &&
    rc=0 || rc=$?
}

# The fixtures name the commit being released as __E2E_HEAD__ so
# they do not rot every time mboss-e2e-tests moves.
head_sha=$(git -C "$e2e" rev-parse HEAD)
for name in green red none running; do
  sed "s/__E2E_HEAD__/$head_sha/g" "$fixtures/$name.json" \
    >"$tmp/$name.json"
done

printf 'verifying %s\n\n' "$preflight"

# 1. Green control: nothing wrong, so nothing to refuse. Also proves
#    the older run at HEAD is chosen over the newer red run whose
#    SHA belongs to some other branch.
run_preflight "$tmp/green.json"
report "green: a publishable tree with CI green on the e2e HEAD" \
  0 "$rc" "$out" \
  "https://github.com/ashtable/mboss-e2e-tests/actions/runs/2"

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
  run_preflight "$tmp/green.json"
  git -C "$web" checkout --quiet "$web_ref"
  report "mismatched pin: root mboss-web differs from the nested pin" \
    1 "$rc" "$out" "mboss-web" "$web_prev" "$e2e_web"
fi

# 3. Red e2e head: CI ran on exactly this commit and failed.
run_preflight "$tmp/red.json"
report "red e2e head: CI failed on the commit being released" \
  1 "$rc" "$out" "failure" \
  "https://github.com/ashtable/mboss-e2e-tests/actions/runs/3"

# 4. No matching run: CI has never run on this commit.
run_preflight "$tmp/none.json"
report "no matching CI run: nothing covers the e2e HEAD" \
  1 "$rc" "$out" "no CI run covers" "$head_sha"

# 5. Still running: a run in flight has a null conclusion, which is
#    both a release to refuse and the one shape that can silently
#    shift a field out of the parsed run list.
run_preflight "$tmp/running.json"
report "unfinished CI run: the run covering the e2e HEAD is in flight" \
  1 "$rc" "$out" "in_progress" \
  "https://github.com/ashtable/mboss-e2e-tests/actions/runs/5"

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
