# Devcontainer

This repository includes a standalone development container for Oracle-backed Gleam development.

## What it starts

- `main`: the developer container used for editing and running commands
- `oracle`: an Oracle Free database container used by the smoke test and integration workflow

## Tooling inside the container

- Gleam
- source-built Erlang/OTP
- Rebar3
- Oracle Instant Client and SDK
- Docker CLI / Docker socket access

## Opening the repo

Open the repository root in VS Code and use **Reopen in Container**.

The container workspace path is:

- `/workspaces/oranif-gleam`

The companion Oracle container is named `oracle` inside the compose network, which is why the smoke example uses `oracle` as the host name.

## Validation flow

For normal package validation:

```bash
gleam format --check src test
gleam test
```

For Oracle-backed validation:

```bash
./scripts/run_proxy_wrapper_smoke.sh
```

## GitHub Actions parity

The Oracle integration workflow reuses this same devcontainer configuration through `devcontainers/ci`.
If the local devcontainer stops working, treat that as likely to affect `.github/workflows/oracle-integration.yml` as well.

## Files

- `devcontainer.json` — VS Code devcontainer entrypoint
- `docker-compose.yml` — starts the dev container and Oracle sidecar
- `Dockerfile` — installs Gleam, OTP, Rebar3, Instant Client, and supporting tools
- `oracle-startup/` — startup hook directory mounted into the Oracle image