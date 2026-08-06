# Contributing

## Source Of Truth

This repository is the source of truth for the published `oranif_gleam` package.
Do not continue feature work in older local clones that were used during extraction or migration.

## Development Setup

The recommended development environment is the repo-local devcontainer:

1. Open the repository root in VS Code.
2. Reopen in container.
3. Use the included Oracle sidecar for integration testing.

See [.devcontainer/README.md](.devcontainer/README.md) for details.

## Validation Expectations

For pure API, refactoring, or documentation changes:

```bash
gleam format --check src test
gleam test
```

For any database-facing change, also run:

```bash
./scripts/run_proxy_wrapper_smoke.sh
```

## CI

The repository currently uses two validation tiers:

- fast package checks in [.github/workflows/ci.yml](.github/workflows/ci.yml)
- Oracle-backed integration checks in [.github/workflows/oracle-integration.yml](.github/workflows/oracle-integration.yml)

Keep both working when changing API shape, devcontainer files, or the smoke script.

## Commit Style

- Prefer small, reviewable commits.
- Keep commit messages focused on one change slice.
- Validate before each commit.

## API Guidance

- Prefer composable, builder-oriented additions over one-off helpers.
- Keep Oracle-specific behavior at the wrapper boundary when possible.
- Preserve existing naming style unless a change clearly improves ergonomics.