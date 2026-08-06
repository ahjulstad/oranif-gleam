# oranif_gleam

Standalone Gleam wrapper around the Erlang oranif runtime (`dpi` module).

## Scope

- Composable query API inspired by patterns from pog
- Pool-first usage
- Optional proxy end-user routing (`base_user[end_user]`)
- Optional high-resolution pool tracing and session reuse stats

## Ergonomic query API

The wrapper now uses a composable query object with parameter binding-style builders.

```gleam
import oranif

let insert_user =
	oranif.command("insert into app_users (id, display_name, active) values (?, ?, ?)")
	|> oranif.bind_int(42)
	|> oranif.bind_string("Ada")
	|> oranif.bind_bool(True)
	|> oranif.as_proxy_user("TP_WRITER_1")

let _ = oranif.run_affected(insert_user, on: pool)

let count_users =
	oranif.scalar_query("select count(*) from app_users")
	|> oranif.as_proxy_user("TP_READER_1")

let total = oranif.run_scalar_int(count_users, on: pool)

let latest_user =
	oranif.row_query("select id, display_name from app_users where id = ?")
	|> oranif.bind_int(42)
	|> oranif.run_decode_row(
		on: pool,
		using: oranif.pair_decoder(
			first: oranif.int_decoder(),
			second: oranif.string_decoder(),
		),
	)

let active_ids =
	oranif.rows_query("select id from app_users where active = ? order by id")
	|> oranif.bind_bool(True)
	|> oranif.run_decode_rows(on: pool, using: oranif.first_int_decoder())

let reader = oranif.scope_as(pool, "TP_READER_1")

let total =
	oranif.scalar_query("select count(*) from app_users")
	|> oranif.run_scalar_int_in(within: reader)

let maybe_user =
	oranif.row_query("select id, display_name from app_users where id = ?")
	|> oranif.bind_int(99999)
	|> oranif.run_maybe_decode_row(
		on: pool,
		using: oranif.pair_decoder(
			first: oranif.int_decoder(),
			second: oranif.string_decoder(),
		),
	)

let person_decoder =
	oranif.decode2(
		first: oranif.int_decoder(),
		second: oranif.string_decoder(),
		with: Person,
	)

let debug_sql =
	oranif.scalar_query("select count(*) from app_users")
	|> oranif.label("dashboard:user-count")
	|> oranif.inspect_query
```

### Core concepts

- `Query` carries SQL, params, identity context, and expected result mode.
- `bind_int`, `bind_string`, `bind_bool`, `bind_float`, and `bind_null` cover common `?` placeholder values.
- `with_param` / `with_params` remain available for lower-level composition.
- `command`, `scalar_query`, `row_query`, and `rows_query` declare query intent up front.
- `label` and `inspect_query` add lightweight query annotations for debugging and future instrumentation.
- `run`, `run_affected`, `run_scalar`, and typed scalar helpers execute queries.
- `run_decode` and reusable scalar decoders support type-directed result decoding.
- `run_row` and `run_decode_row` fetch and decode the first returned row.
- `run_rows` and `run_decode_rows` fetch and decode whole result sets.
- `run_maybe_scalar`, `run_maybe_row`, and `run_maybe_decode_row` turn `NotFound` lookups into `Option` values.
- `scope_as` plus `run_*_in` let you reuse pool and proxy identity context across many queries.
- `decode2` and `decode3` build row decoders directly into your own record or value constructors.
- `map_scalar_decoder`, `map_row_decoder`, `pair_decoder`, and `triple_decoder` support reusable record-style decoders.
- `to_sql` renders a query and validates placeholder/parameter counts.

### Error mapping

Common backend failures are mapped into semantic wrapper errors where possible:

- `ORA-00942` -> `MissingTable`
- `ORA-00001` -> `ConstraintViolation`
- `ORA-01017` -> `AuthenticationError`
- `ORA-01031` -> `PermissionDenied`
- `DPI-1080` -> `PoolTimeout`
- `ORA-24418` -> `PoolExhausted`

## CI

GitHub Actions workflow runs on push and pull requests and enforces:

- `gleam format --check` for package and example.
- `gleam build` for package and example.
- `gleam test` for unit tests in this package.

An additional Oracle-backed integration workflow is available in GitHub Actions.
It reuses the existing devcontainer Compose setup, starts Oracle Free, and runs:

- `gleam format --check src test`
- `gleam test`
- `./scripts/run_proxy_wrapper_smoke.sh`

For local database validation, run:

- [scripts/run_proxy_wrapper_smoke.sh](scripts/run_proxy_wrapper_smoke.sh)

## Runtime dependency

This package requires the Erlang `dpi` module at runtime (from oranif).

## Integration example

See [examples/proxy_wrapper_smoke](examples/proxy_wrapper_smoke) and run with:

- [scripts/run_proxy_wrapper_smoke.sh](scripts/run_proxy_wrapper_smoke.sh)
