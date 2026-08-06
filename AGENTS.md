# AGENTS.md

## Scope

These instructions apply to the whole repository.

## Source Of Truth

- This repository is the publishable source of truth for `oranif_gleam`.
- Do not continue feature work in older workspace clones such as `oranif_gleam/`.

## Validation Expectations

- For pure API or documentation changes, run:
  - `gleam format --check src test`
  - `gleam test`
- For database-facing changes, also run:
  - `./scripts/run_proxy_wrapper_smoke.sh`

## Oracle Integration

- The smoke script is the required local Oracle-backed validation path.
- Keep the smoke example working when public APIs change.
- Prefer fixing runtime mismatches at the wrapper boundary before widening the bridge surface.

## Editing Guidance

- Keep the public API composable and builder-oriented.
- Prefer small, reviewable commits that each pass validation.
- Preserve existing naming style unless a change clearly improves ergonomics.

## CI

- Keep both workflows working:
  - `.github/workflows/ci.yml`
  - `.github/workflows/oracle-integration.yml`