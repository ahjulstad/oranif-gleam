#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXAMPLE_DIR="${ROOT_DIR}/examples/proxy_wrapper_smoke"
ORANIF_FORK_DIR="${ORANIF_FORK_DIR:-/workspaces/20260805 gleam/oranif_demo/oranif_fork}"
ERL_BIN="${ERL_BIN:-$(command -v erl)}"

if [[ ! -d "${ORANIF_FORK_DIR}" ]]; then
  echo "oranif fork directory not found: ${ORANIF_FORK_DIR}" >&2
  exit 1
fi

cd "${ROOT_DIR}"
echo "[1/3] Building wrapper library"
gleam build

cd "${EXAMPLE_DIR}"
echo "[2/3] Building example"
gleam build

echo "[3/3] Running example"
LD_LIBRARY_PATH="${ORANIF_FORK_DIR}/c_src/odpi/lib:/opt/instantclient_21_20:/usr/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}" \
"${ERL_BIN}" \
  -pa "${ORANIF_FORK_DIR}/_build/default/lib/oranif/ebin" \
  -pa "${ROOT_DIR}/build/dev/erlang/oranif_gleam/ebin" \
  -pa "${ROOT_DIR}/build/dev/erlang/gleam_stdlib/ebin" \
  -pa "${EXAMPLE_DIR}/build/dev/erlang/proxy_wrapper_smoke/ebin" \
  -pa "${EXAMPLE_DIR}/build/dev/erlang/gleam_stdlib/ebin" \
  -noshell \
  -eval 'main:main(), halt().'
