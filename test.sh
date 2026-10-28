#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Builds, then runs the unit tests and the examples as a smoke test (the
#  JSONPath compliance test suite runner is exercised on a bundled suite, on
#  a failing suite and on a missing file).
#    test.sh [linux32|linux64]        (default: linux64)
#  Only fpc is supported on Linux. No external tools are needed.
#  Program output is kept in build/<tag>/bin/*.out
#  Exit code: 0 = everything passed, 1 = a build, test or example failed.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"

PLATFORM="${1:-linux64}"

case "$PLATFORM" in
  linux32|linux64) ;;
  *)
    echo "Usage: test.sh [linux32|linux64]    (default: linux64)"
    exit 2
    ;;
esac

BIN="$ROOT/build/fpc-$PLATFORM/bin"
TESTS=0
TFAIL=0
SMOKE=0
SFAIL=0
SEQ=0

pushd "$BIN" > /dev/null

echo
echo "### Unit tests"
for T in Test*; do
  [[ -x "$T" ]] || continue
  TESTS=$((TESTS + 1))
  "./$T"
  RC=$?
  if [[ $RC -ne 0 ]]; then
    TFAIL=$((TFAIL + 1))
    echo "  >>> ${T} FAILED"
  fi
done

echo
echo "### Examples (smoke tests)"
#  smoke <program> "<arguments>" "<text that must appear in output>" [expected exit code]
smoke() {
  local PROG="$1"
  local ARGS="${2:-}"
  local WANT_TEXT="$3"
  local WANT_RC="${4:-0}"

  SEQ=$((SEQ + 1))
  SMOKE=$((SMOKE + 1))
  local OUTF="$BIN/${PROG}.${SEQ}.out"

  if [[ -n "$ARGS" ]]; then
    "$BIN/$PROG" $ARGS > "$OUTF" 2>&1
  else
    "$BIN/$PROG" > "$OUTF" 2>&1
  fi
  local RC=$?

  if [[ "$RC" != "$WANT_RC" ]]; then
    echo "  FAILED  $PROG $ARGS  (exit code $RC, expected $WANT_RC)"
    cat "$OUTF"
    SFAIL=$((SFAIL + 1))
    return 0
  fi

  if ! grep -qF "$WANT_TEXT" "$OUTF"; then
    echo "  FAILED  $PROG $ARGS  (the output does not contain \"$WANT_TEXT\")"
    cat "$OUTF"
    SFAIL=$((SFAIL + 1))
    return 0
  fi

  echo "  ok      $PROG $ARGS"
}

smoke SampleStore "" "Sayings of the Century"

popd > /dev/null

echo
echo "============================================================"
echo "Unit tests : $TESTS program(s), $TFAIL failed"
echo "Examples   : $SMOKE run, $SFAIL failed"
echo "============================================================"

if [[ $TFAIL -gt 0 ]]; then exit 1; fi
if [[ $SFAIL -gt 0 ]]; then exit 1; fi
if [[ $TESTS -eq 0 ]]; then
  echo "ERROR: no test programs were found in $BIN"
  exit 1
fi
echo "All tests passed."
exit 0