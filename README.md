# oranif_gleam

Standalone Gleam wrapper around the Erlang oranif runtime (`dpi` module).

## Disclaimer

AI-authored, but supervised by me. I wanted to test Oracle OCI behaviour, and Gleam was a nice language. Hence, "can I make AI write an driver wrapping the Oracle driver that is nice to use?"

I don't know yet, but am about to find out. 


## Scope

- Composable query API inspired by patterns from pog
- Pool-first usage
- Optional proxy end-user routing (`base_user[end_user]`)
- Optional high-resolution pool tracing and session reuse stats

## Getting Started

### Prerequisites

You need the Erlang `dpi` runtime available at execution time.
For local development, the easiest path is the included devcontainer.

### Recommended local setup

1. Open the repository root in VS Code.
2. Choose **Reopen in Container**.
3. Wait for the `main` devcontainer and the `oracle` sidecar container to start.
4. Run the smoke test:

```bash
./scripts/run_proxy_wrapper_smoke.sh
```

The devcontainer is documented in [.devcontainer/README.md](.devcontainer/README.md).

### Non-devcontainer setup

If you do not use the devcontainer, you are responsible for providing:

- Gleam
- Erlang/OTP
- Rebar3
- Oracle Instant Client
- a build of the Erlang `oranif` runtime used by the smoke script

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

let _ = oranif.exec(insert_user, on: pool)

let count_users =
	oranif.scalar_query("select count(*) from app_users")
	|> oranif.as_proxy_user("TP_READER_1")

let total = oranif.scalar_as_type(count_users, on: pool, using: oranif.int_decoder())

let latest_user =
	oranif.row_query("select id, display_name from app_users where id = ?")
	|> oranif.bind_int(42)
	|> oranif.one(
		on: pool,
		using: oranif.pair_decoder(
			first: oranif.int_decoder(),
			second: oranif.string_decoder(),
		),
	)

let active_ids =
	oranif.rows_query("select id from app_users where active = ? order by id")
	|> oranif.bind_bool(True)
	|> oranif.all(on: pool, using: oranif.first_int_decoder())

let reader = oranif.scope_as(pool, "TP_READER_1")

let total =
	oranif.scalar_query("select count(*) from app_users")
	|> oranif.scalar_as_type_in(within: reader, using: oranif.int_decoder())

let maybe_user =
	oranif.row_query("select id, display_name from app_users where id = ?")
	|> oranif.bind_int(99999)
	|> oranif.maybe_one(
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

## API map

The public API is easiest to read in four layers:

- pool lifecycle: `default_config`, `start`, `stop`, `pool_stats`, `start_trace`, `stop_trace`
- query building: `query`, `command`, `scalar_query`, `row_query`, `rows_query`, bind helpers, identity helpers
- execution: `run_*`, `exec*`, `one*`, `all*`, direct `*_as` helpers, and scoped `*_in` helpers
- decoding: scalar decoders, row decoders, `decode2`, `decode3`, and row-set decoding helpers

If you are new to the package, start with `query` plus `run_scalar`, `one`, or `all`, then move to scopes and session initialization once the basic flow is familiar.

## Generating docs

To build the package documentation locally, run:

```bash
gleam docs build
```

The module-level overview and public API docstrings in [src/oranif.gleam](src/oranif.gleam) are intended to make the generated docs usable without needing to read the implementation first.

## Published docs

The generated API docs are intended to be published on GitHub Pages at:

- `https://ahjulstad.github.io/oranif-gleam/`

Deployment is handled by [.github/workflows/docs-pages.yml](.github/workflows/docs-pages.yml).
It rebuilds the docs on pushes to `main` that touch package docs or source files, and it can also be run manually with `workflow_dispatch`.

If GitHub Pages has not been enabled for the repository yet, set the Pages source to `GitHub Actions` in the repository settings.

## Development Flow

Typical work on this repository should follow this order:

1. Make a small API or runtime change.
2. Run package validation:

```bash
gleam format --check src test
gleam test
```

3. For any database-facing change, also run:

```bash
./scripts/run_proxy_wrapper_smoke.sh
```

4. Commit only after the relevant checks pass.

### Core concepts

- `Query` carries SQL, params, identity context, and expected result mode.
- `bind_int`, `bind_string`, `bind_bool`, `bind_float`, and `bind_null` cover common `?` placeholder values.
- `bind_ints`, `bind_strings`, `bind_bools`, and `bind_floats` help with repeated positional binding.
- `bind_all` is a clearer mixed-parameter alias for `with_params`.
- `with_param` / `with_params` remain available for lower-level composition.
- `command`, `scalar_query`, `row_query`, and `rows_query` declare query intent up front.
- `label` and `inspect_query` add lightweight query annotations for debugging and future instrumentation.
- `run`, `run_affected`, `run_scalar`, and typed scalar helpers execute queries.
- `run_decode` and reusable scalar decoders support type-directed result decoding.
- `run_row` and `run_decode_row` fetch and decode the first returned row.
- `run_rows` and `run_decode_rows` fetch and decode whole result sets.
- `run_maybe_scalar`, `run_maybe_row`, and `run_maybe_decode_row` turn `NotFound` lookups into `Option` values.
- `scope_as` plus `run_*_in` let you reuse pool and proxy identity context across many queries.
- `session_init`, `session_init_sql`, `prepare_pool`, `scope_with`, and `scope_as_with` let you define pool-level session setup once and pass typed per-checkout options.
- `decode2` and `decode3` build row decoders directly into your own record or value constructors.
- `map_scalar_decoder`, `map_row_decoder`, `pair_decoder`, and `triple_decoder` support reusable record-style decoders.
- `to_sql` renders a query and validates placeholder/parameter counts.

### Parameterized session initialization

You can define a typed option model for session setup, map each option to a stable tag, and provide setup actions to run when a checked-out session does not already match that tag.

```gleam
type SessionOption {
	SessionOption(tenant: String, role: String)
}

let initializer =
	oranif.session_init(
		fn(option) {
			let SessionOption(tenant, role) = option
			"tenant=" <> tenant <> "|role=" <> role
		},
		fn(option) {
			let SessionOption(tenant, role) = option
			[
				oranif.SetClientIdentifier("tenant:" <> tenant),
				oranif.SetClientInfo("service:proxy-wrapper"),
				oranif.SetModule("ORANIF", role),
				oranif.SetAction("QUERY"),
				oranif.SetNlsDateFormat("YYYY-MM-DD"),
			]
		},
	)

let prepared = oranif.prepare_pool(pool, with: initializer)
let scoped =
	oranif.scope_with(prepared, SessionOption(tenant: "acme", role: "reader"))

let _ =
	oranif.query("select count(*) from test_data")
	|> oranif.run_scalar_int_in(within: scoped)
```

If you already build session SQL yourself, use `session_init_sql` directly with `fn(option) -> List(String)`.

Tagging behavior:

- Acquire requests a composed tag that includes existing built-in role affinity plus your option-derived tag.
- If the acquired session already matches that effective tag, setup actions are skipped.
- If not, setup actions run and the session is closed with the effective tag.
- If setup fails, the session is closed untagged and the checkout returns an error.

### Error mapping

Common backend failures are mapped into semantic wrapper errors where possible:

- `ORA-00942` -> `MissingTable`
- `ORA-00001` -> `ConstraintViolation`
- `ORA-01017` -> `AuthenticationError`
- `ORA-01031` -> `PermissionDenied`
- `DPI-1080` -> `PoolTimeout`
- `ORA-24418` -> `PoolExhausted`
- `session_init_failed` bridge errors -> `SessionInitError`

## CI

GitHub Actions workflow runs on push and pull requests and enforces:

- `gleam format --check` for package and example.
- `gleam build` for package and example.
- `gleam test` for unit tests in this package.

This workflow is defined in [.github/workflows/ci.yml](.github/workflows/ci.yml).

An additional Oracle-backed integration workflow is available in GitHub Actions.
It reuses the existing devcontainer Compose setup, starts Oracle Free, and runs:

- `gleam format --check src test`
- `gleam test`
- `./scripts/run_proxy_wrapper_smoke.sh`

This workflow is defined in [.github/workflows/oracle-integration.yml](.github/workflows/oracle-integration.yml).

For local database validation, run:

- [scripts/run_proxy_wrapper_smoke.sh](scripts/run_proxy_wrapper_smoke.sh)

The smoke script uses a local `oranif` checkout if `ORANIF_FORK_DIR` exists.
If it does not, the script clones and builds the public fork from `https://github.com/ahjulstad/oranif.git`.

You can override the source explicitly with:

- `ORANIF_FORK_DIR` — existing local checkout to use
- `ORANIF_REPO_URL` — git URL to clone when no local checkout is present
- `ORANIF_REPO_REF` — git branch or tag to clone
- `ORANIF_ODPI_TAG` — ODPI release tag used when compiling the public fork
- `ORANIF_LINK_ODPI` — set to `true` to build against a linked ODPI checkout

## Devcontainer

This repository includes its own `.devcontainer` setup for local Oracle-backed development and for the Oracle integration GitHub workflow.

Open the repository root in VS Code and choose **Reopen in Container** to start:

- a development container with Gleam, OTP, Rebar3, Instant Client, and Docker installed
- an `oracle` sidecar container based on `gvenzl/oracle-free`

Once the container is up, the main local validation command is:

```bash
./scripts/run_proxy_wrapper_smoke.sh
```

That script builds the package, builds the smoke example, and runs it against the Oracle sidecar.

For container-specific details, see [.devcontainer/README.md](.devcontainer/README.md).

## Repository Layout

- `src/` — public Gleam API and Erlang runtime bridge
- `test/` — pure package tests for builders, decoders, and error mapping
- `examples/proxy_wrapper_smoke/` — Oracle-backed integration example
- `scripts/run_proxy_wrapper_smoke.sh` — main local Oracle-backed validation command
- `.devcontainer/` — standalone local development and integration environment
- `.github/workflows/` — CI and Oracle integration workflows

## Runtime dependency

This package requires the Erlang `dpi` module at runtime (from oranif).

## Integration example

See [examples/proxy_wrapper_smoke](examples/proxy_wrapper_smoke) and run with:

- [scripts/run_proxy_wrapper_smoke.sh](scripts/run_proxy_wrapper_smoke.sh)
