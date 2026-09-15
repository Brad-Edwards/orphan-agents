#!/usr/bin/env bash
# Behavioural tests for orphan-agent-check.
#
# Each case builds a real process in the state the detector claims to recognise,
# so a rule that stopped working would fail here. `setsid --fork` is required:
# plain `setsid` does not fork when it is already a process-group leader, and
# the child then keeps its parent instead of being reparented to init.
set -uo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/orphan-agent-check"
export XDG_STATE_HOME; XDG_STATE_HOME="$(mktemp -d)"
export ORPHAN_QUIET=1
STATE="$XDG_STATE_HOME/orphan-agents"
SEEN="$STATE/reported"
REPORT="$STATE/latest.txt"
pass=0; fail=0
probes=()

cleanup() { for p in "${probes[@]:-}"; do kill "$p" 2>/dev/null || true; done; rm -f "$SEEN" "$REPORT"; }
trap cleanup EXIT

spawn() { # name [cwd]
  local name="$1" dir="${2:-$PWD}" p
  setsid --fork bash -c "cd '$dir' && exec -a '$name' sleep 60" >/dev/null 2>&1
  sleep 0.3
  p=$(pgrep -f -- "$name" | head -1)
  probes+=("$p"); echo "$p"
}
reset() { : > "$SEEN"; rm -f "$REPORT"; }
run()   { ORPHAN_MIN_AGE_SECONDS="${1:-1}" bash "$CHECK"; }
check() { # description expected(yes|no) pattern
  local got
  if grep -q -- "$3" "$REPORT" 2>/dev/null; then got=yes; else got=no; fi
  if [ "$got" = "$2" ]; then echo "  pass  $1"; pass=$((pass+1)); else echo "  FAIL  $1 (expected $2, got $got)"; fail=$((fail+1)); fi
}

mkdir -p "$STATE"

stranded_dir=$(mktemp -d)
stranded_pid=$(spawn 'claude --t-stranded' "$stranded_dir")
rmdir "$stranded_dir"
workload_pid=$(spawn 'pytest --t-workload')
spawn 'claude --t-healthy' >/dev/null
sleep 2

reset; run 1
check "stranded: orphan with deleted cwd is reported" yes 't-stranded'
check "workload: orphaned test process is reported"   yes 't-workload'
check "healthy: detached agent with live cwd ignored" no  't-healthy'

rm -f "$REPORT"; run 1
check "dedup: an already-reported process is not repeated" no 't-stranded'

reset; run 999999
check "threshold: a young orphan is below the age floor" no 't-stranded'

# Scoped to the PIDs this test owns: unrelated matching processes on the host
# may legitimately hold entries of their own.
reset; run 1 >/dev/null
# Only these two are meant to be detected; the healthy probe never enters state.
mine=("$stranded_pid" "$workload_pid")
recorded=0
for p in "${mine[@]}"; do grep -q "^$p:" "$SEEN" && recorded=$((recorded+1)); done
for p in "${mine[@]}"; do kill "$p" 2>/dev/null; done
probes=(); sleep 1
run 1 >/dev/null
left=0
for p in "${mine[@]}"; do grep -q "^$p:" "$SEEN" && left=$((left+1)); done
if [ "$recorded" -eq "${#mine[@]}" ] && [ "$left" -eq 0 ]; then
  echo "  pass  state: entries pruned once processes exit"; pass=$((pass+1))
else
  echo "  FAIL  state: pruning (recorded $recorded/${#mine[@]}, still present $left)"; fail=$((fail+1))
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
