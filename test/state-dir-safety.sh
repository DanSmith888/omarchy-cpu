#!/usr/bin/env bash
# Proves the runtime state directory cannot be used to write through a symlink.
#
# Everything runs against a throwaway XDG_RUNTIME_DIR, so the live state in
# /run/user/$UID is untouched. Exits non-zero on the first failure.
set -uo pipefail

CTL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/cpuctl"
ID="dansmith888.cpu"
T="$(mktemp -d "${TMPDIR:-/tmp}/cpuctl-safety.XXXXXX")"
trap 'rm -rf "$T"' EXIT
fails=0

check() {  # check <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    printf '  ok    %s\n' "$1"
  else
    printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

echo "1. a normal run creates a private directory"
XDG_RUNTIME_DIR="$T" "$CTL" get >/dev/null 2>&1
check "directory mode is 0700" "700" "$(stat -c '%a' "$T/$ID" 2>/dev/null)"
check "owned by this user"     "$(id -un)" "$(stat -c '%U' "$T/$ID" 2>/dev/null)"

echo "2. a symlink planted at state.json is not written through"
printf 'PRECIOUS' > "$T/victim"
rm -f "$T/$ID/state.json"
ln -s "$T/victim" "$T/$ID/state.json"
XDG_RUNTIME_DIR="$T" "$CTL" get >/dev/null 2>&1
check "victim file untouched" "PRECIOUS" "$(cat "$T/victim")"
check "state.json is a regular file again" "regular file" "$(stat -c '%F' "$T/$ID/state.json" 2>/dev/null)"

echo "3. swapping the whole directory for a symlink is refused"
rm -rf "$T/$ID"
mkdir -p "$T/elsewhere"
ln -s "$T/elsewhere" "$T/$ID"
out="$(XDG_RUNTIME_DIR="$T" "$CTL" get 2>&1)"; rc=$?
check "exits non-zero"                  "nonzero" "$([[ $rc -ne 0 ]] && echo nonzero || echo zero)"
check "refuses to open the directory"   "refused" "$(grep -q 'cannot open' <<<"$out" && echo refused || echo "no: $out")"
check "nothing written into the target" "0"       "$(ls -A "$T/elsewhere" | wc -l)"

echo
if [[ $fails -eq 0 ]]; then
  echo "all checks passed"
else
  echo "$fails check(s) failed"
fi
exit $((fails > 0))
