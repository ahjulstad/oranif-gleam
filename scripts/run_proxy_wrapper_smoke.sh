#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXAMPLE_DIR="${ROOT_DIR}/examples/proxy_wrapper_smoke"
ORANIF_FORK_DIR="${ORANIF_FORK_DIR:-/workspaces/20260805 gleam/demos/oranif_demo/oranif_fork}"
ORANIF_REPO_URL="${ORANIF_REPO_URL:-https://github.com/ahjulstad/oranif.git}"
ORANIF_REPO_REF="${ORANIF_REPO_REF:-master}"
ORANIF_ODPI_TAG="${ORANIF_ODPI_TAG:-v5.6.4}"
ORANIF_LINK_ODPI="${ORANIF_LINK_ODPI:-true}"
ERL_BIN="${ERL_BIN:-$(command -v erl)}"
ORANIF_ODPI_LIB_DIR=""

ensure_oranif_fork() {
  if [[ -d "${ORANIF_FORK_DIR}/.git" ]]; then
    return 0
  fi

  echo "[setup] cloning oranif fork from ${ORANIF_REPO_URL} (${ORANIF_REPO_REF})"
  rm -rf "${ORANIF_FORK_DIR}"
  mkdir -p "$(dirname "${ORANIF_FORK_DIR}")"
  git clone --depth 1 --branch "${ORANIF_REPO_REF}" "${ORANIF_REPO_URL}" "${ORANIF_FORK_DIR}"
}

build_oranif_fork() {
  echo "[setup] building oranif runtime"
  cd "${ORANIF_FORK_DIR}"

  if [[ "${ORANIF_LINK_ODPI}" == "true" ]]; then
    LINKODPI=true ODPI_TAG="${ORANIF_ODPI_TAG}" rebar3 compile
  else
    rebar3 compile
  fi

  if [[ ! -d "${ORANIF_FORK_DIR}/_build/default/lib/oranif/ebin" ]]; then
    echo "oranif ebin output missing after build: ${ORANIF_FORK_DIR}/_build/default/lib/oranif/ebin" >&2
    exit 1
  fi

  if [[ -d "${ORANIF_FORK_DIR}/c_src/odpi/lib" ]]; then
    ORANIF_ODPI_LIB_DIR="${ORANIF_FORK_DIR}/c_src/odpi/lib"
  fi
}

ensure_oranif_fork
build_oranif_fork

cd "${ROOT_DIR}"
echo "[1/3] Building wrapper library"
gleam build

cd "${EXAMPLE_DIR}"
echo "[2/3] Building example"
gleam build

echo "[3/3] Running example"
LD_LIBRARY_PATH_ENTRIES=(
  "/opt/instantclient_21_20"
  "/usr/lib/x86_64-linux-gnu"
  "/lib/x86_64-linux-gnu"
)

if [[ -n "${ORANIF_ODPI_LIB_DIR}" ]]; then
  LD_LIBRARY_PATH_ENTRIES=("${ORANIF_ODPI_LIB_DIR}" "${LD_LIBRARY_PATH_ENTRIES[@]}")
fi

LD_LIBRARY_PATH="$(IFS=:; printf '%s' "${LD_LIBRARY_PATH_ENTRIES[*]}")${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
"${ERL_BIN}" \
  -pa "${ORANIF_FORK_DIR}/_build/default/lib/oranif/ebin" \
  -pa "${ROOT_DIR}/build/dev/erlang/oranif_gleam/ebin" \
  -pa "${ROOT_DIR}/build/dev/erlang/gleam_stdlib/ebin" \
  -pa "${EXAMPLE_DIR}/build/dev/erlang/proxy_wrapper_smoke/ebin" \
  -pa "${EXAMPLE_DIR}/build/dev/erlang/gleam_stdlib/ebin" \
  -noshell \
  -eval 'main:main(), halt().'
