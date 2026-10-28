#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Builds the examples and test runners (Linux, FPC only).
#    build.sh [linux32|linux64]        (default: linux64)
#  FPC    : needs fpc on PATH (3.2.2+)
#  Output : build/fpc-<platform>/bin
#  Built  : tests/Test*.pas, schema/tests/Test*.pas, cts/tests/Test*.pas,
#            examples/Sample*.dpr, schema/samples/Sample*.pas
#  Compiler logs: build/<tag>/logs/<program>.log
#  Exit code: 0 = everything built, 1 = failure.
# ---------------------------------------------------------------------------
set -euo pipefail

PLATFORM="${1:-linux64}"

case "$PLATFORM" in
  linux32) FPC_TARGET="-Pi386 -Tlinux" ;;
  linux64) FPC_TARGET="-Px86_64 -Tlinux" ;;
  *)
    echo "Usage: build.sh [linux32|linux64]     (default: linux64)"
    exit 2
    ;;
esac

ROOT="$(cd "$(dirname "$0")" && pwd)"
TAG="fpc-${PLATFORM}"
OUT="${ROOT}/build/${TAG}"
FAILED=0
BUILT=0

# ---------------------------------------------------------------------------
check_fpc() {
  if ! command -v fpc &>/dev/null; then
    echo "ERROR: fpc was not found on PATH."
    exit 1
  fi
}

# ---------------------------------------------------------------------------
prepare() {
  for d in bin obj dcu logs; do
    mkdir -p "${OUT}/${d}"
  done
}

# ---------------------------------------------------------------------------
fpc_one() {
  local SRC="$1"
  local NAME
  NAME="$(basename "${SRC%.*}")"

  # Skip TestSupport (not a standalone program)
  if [[ "${NAME}" == "TestSupport" ]]; then
    return
  fi

  fpc -Mdelphi -Sh -O1 ${FPC_TARGET} \
      -Fusrc -Fuschema -Fucts -Futests -Fuschema/tests \
      -FU"${OUT}/obj" \
      -FE"${OUT}/bin" \
      -o"${OUT}/bin/${NAME}" \
      "${SRC}" \
      >"${OUT}/logs/${NAME}.log" 2>&1

  if [[ $? -ne 0 ]]; then
    echo "  FAILED  ${NAME}  (see build/${TAG}/logs/${NAME}.log)"
    (( FAILED++ )) || true
  else
    echo "  ok      ${NAME}"
    (( BUILT++ )) || true
  fi
}

# ---------------------------------------------------------------------------
each_source() {
  shopt -s nullglob
  for F in \
      tests/Test*.pas \
      schema/tests/Test*.pas \
      cts/tests/Test*.pas \
      examples/Sample*.dpr \
      schema/samples/Sample*.pas
  do
    fpc_one "$F"
  done
  shopt -u nullglob
}

# ---------------------------------------------------------------------------
cd "${ROOT}"

check_fpc

echo
echo "=== Free Pascal, ${PLATFORM} => build/${TAG}/bin ==="

prepare
each_source

echo
echo "Built ${BUILT} program(s), ${FAILED} failed."

if [[ ${FAILED} -gt 0 ]]; then
  exit 1
fi
if [[ ${BUILT} -eq 0 ]]; then
  echo "ERROR: no sources were found - nothing was built."
  exit 1
fi
exit 0
