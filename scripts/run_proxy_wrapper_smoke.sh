#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXAMPLE_DIR="${ROOT_DIR}/examples/proxy_wrapper_smoke"
ORANIF_OVERLAY_DIR="${ROOT_DIR}/scripts/oranif_fork_overlay"
ORANIF_FORK_DIR="${ORANIF_FORK_DIR:-/workspaces/20260805 gleam/oranif_demo/oranif_fork}"
ORANIF_REPO_URL="${ORANIF_REPO_URL:-https://github.com/KonnexionsGmbH/oranif.git}"
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

overlay_oranif_fork() {
  if [[ ! -d "${ORANIF_OVERLAY_DIR}" ]]; then
    echo "oranif overlay directory not found: ${ORANIF_OVERLAY_DIR}" >&2
    exit 1
  fi

  mkdir -p "${ORANIF_FORK_DIR}/c_src" "${ORANIF_FORK_DIR}/src"

  if ! rg -q 'ODPI_TAG \?=' "${ORANIF_FORK_DIR}/c_src/Makefile"; then
    perl -0pi -e 's/ODPI_REPO = https:\/\/github\.com\/oracle\/odpi\n/ODPI_REPO = https:\/\/github.com\/oracle\/odpi\nODPI_TAG ?= v5.6.4\n/' "${ORANIF_FORK_DIR}/c_src/Makefile"
  fi
  perl -0pi -e 's/git clone -b v3\.0\.0 --single-branch -c advice\.detachedHead=false \$\(ODPI_REPO\)/git clone -b \$\(ODPI_TAG\) --single-branch -c advice.detachedHead=false \$\(ODPI_REPO\)/' "${ORANIF_FORK_DIR}/c_src/Makefile"

  if ! rg -q 'dpiPool_nif.h' "${ORANIF_FORK_DIR}/c_src/dpi_nif.c"; then
    perl -0pi -e 's/#include "dpiConn_nif\.h"\n/#include "dpiConn_nif.h"\n#include "dpiPool_nif.h"\n/' "${ORANIF_FORK_DIR}/c_src/dpi_nif.c"
    perl -0pi -e 's/    DPICONN_NIFS,\n/    DPICONN_NIFS,\n    DPIPOOL_NIFS,\n/' "${ORANIF_FORK_DIR}/c_src/dpi_nif.c"
    perl -0pi -e 's/        env, ret, enif_make_atom\(env, "connection"\),\n        enif_make_ulong\(env, st->dpiConn_count\), &ret\);/        env, ret, enif_make_atom(env, "connection"),\n        enif_make_ulong(env, st->dpiConn_count), &ret);\n    enif_make_map_put(\n        env, ret, enif_make_atom(env, "pool"),\n        enif_make_ulong(env, st->dpiPool_count), &ret);/' "${ORANIF_FORK_DIR}/c_src/dpi_nif.c"
    perl -0pi -e 's/    st->dpiConn_count = 0;\n/    st->dpiConn_count = 0;\n    st->dpiPool_count = 0;\n/' "${ORANIF_FORK_DIR}/c_src/dpi_nif.c"
    perl -0pi -e 's/    DEF_RES\(dpiConn\);\n/    DEF_RES(dpiConn);\n    DEF_RES(dpiPool);\n/' "${ORANIF_FORK_DIR}/c_src/dpi_nif.c"
    perl -0pi -e 's/    st->dpiConn_count = old_st->dpiConn_count;\n/    st->dpiConn_count = old_st->dpiConn_count;\n    st->dpiPool_count = old_st->dpiPool_count;\n/' "${ORANIF_FORK_DIR}/c_src/dpi_nif.c"
  fi

  if ! rg -q 'dpiPool_count' "${ORANIF_FORK_DIR}/c_src/dpi_nif.h"; then
    perl -0pi -e 's/    unsigned long dpiConn_count;\n/    unsigned long dpiConn_count;\n    unsigned long dpiPool_count;\n/' "${ORANIF_FORK_DIR}/c_src/dpi_nif.h"
  fi

  if ! rg -q 'dpiPool.hrl' "${ORANIF_FORK_DIR}/src/dpi.erl"; then
    perl -0pi -e 's/-include\("dpiConn\.hrl"\)\.\n/-include("dpiConn.hrl").\n-include("dpiPool.hrl").\n/' "${ORANIF_FORK_DIR}/src/dpi.erl"
  fi

  cp "${ORANIF_OVERLAY_DIR}/c_src/dpiPool_nif.c" "${ORANIF_FORK_DIR}/c_src/dpiPool_nif.c"
  cp "${ORANIF_OVERLAY_DIR}/c_src/dpiPool_nif.h" "${ORANIF_FORK_DIR}/c_src/dpiPool_nif.h"
  cp "${ORANIF_OVERLAY_DIR}/src/dpiPool.hrl" "${ORANIF_FORK_DIR}/src/dpiPool.hrl"
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
overlay_oranif_fork
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
