# oranif (Gleam wrapper)

Standalone Gleam wrapper around the Erlang oranif runtime (`dpi` module).

## Scope

- Idiomatic Gleam API inspired by patterns from pog
- Pool-first usage
- Optional proxy end-user routing (`base_user[end_user]`)
- Optional high-resolution pool tracing and session reuse stats

## Runtime dependency

This package requires the Erlang `dpi` module at runtime (from oranif).

## Integration example

See [examples/proxy_wrapper_smoke](examples/proxy_wrapper_smoke) and run with:

- [scripts/run_proxy_wrapper_smoke.sh](scripts/run_proxy_wrapper_smoke.sh)
