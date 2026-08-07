//// Pool-first Oracle access for Gleam on the Erlang runtime.
////
//// This module provides a composable query API over the Erlang `oranif`
//// runtime, with a focus on three things:
////
//// - explicit query construction and result expectations
//// - proxy-user and scope-based execution
//// - typed decoding of scalar, row, and row-set results
////
//// The typical flow is:
////
//// 1. Build a `Config` and `start` a `Pool`.
//// 2. Construct queries with `query`, `command`, `scalar_query`,
////    `row_query`, or `rows_query`.
//// 3. Bind parameters, choose an execution scope if needed, and run.
//// 4. Decode results using the built-in decoders or your own combinators.
////
//// For repeated proxy-user or session-initialized work, build a `Scope`
//// and use the `*_in` execution helpers.
////
import gleam/dynamic
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import oranif/internal

/// The semantic error variants returned by this wrapper.
pub type Error {
  DbError(message: String)
  MissingTable(message: String)
  ConstraintViolation(message: String)
  AuthenticationError(message: String)
  PermissionDenied(message: String)
  PoolTimeout(message: String)
  PoolExhausted(message: String)
  QueryBuildError(message: String)
  SessionInitError(message: String)
  DecodeError(message: String)
  NotFound
}

/// Extract the human-readable message from an error value.
pub fn error_message(error: Error) -> String {
  case error {
    DbError(message) -> message
    MissingTable(message) -> message
    ConstraintViolation(message) -> message
    AuthenticationError(message) -> message
    PermissionDenied(message) -> message
    PoolTimeout(message) -> message
    PoolExhausted(message) -> message
    QueryBuildError(message) -> message
    SessionInitError(message) -> message
    DecodeError(message) -> message
    NotFound -> "query returned no rows"
  }
}

/// Map backend and bridge error text into a richer public error variant.
pub fn classify_db_error(message: String) -> Error {
  let normalized = string.uppercase(message)
  case string.contains(does: normalized, contain: "SESSION_INIT_FAILED") {
    True -> SessionInitError(message)
    False ->
      case string.contains(does: normalized, contain: "ORA-00942") {
        True -> MissingTable(message)
        False ->
          case string.contains(does: normalized, contain: "ORA-00001") {
            True -> ConstraintViolation(message)
            False ->
              case string.contains(does: normalized, contain: "ORA-01017") {
                True -> AuthenticationError(message)
                False ->
                  case string.contains(does: normalized, contain: "ORA-01031") {
                    True -> PermissionDenied(message)
                    False ->
                      case
                        string.contains(does: normalized, contain: "DPI-1080")
                      {
                        True -> PoolTimeout(message)
                        False ->
                          case
                            string.contains(
                              does: normalized,
                              contain: "ORA-24418",
                            )
                          {
                            True -> PoolExhausted(message)
                            False -> DbError(message)
                          }
                      }
                  }
              }
          }
      }
  }
}

/// Connection settings for starting a pool-backed client.
pub type Config {
  Config(
    host: String,
    port: Int,
    service: String,
    user: String,
    password: String,
    pool: PoolConfig,
  )
}

/// Pool sizing and timeout settings used when opening a pool.
pub type PoolConfig {
  PoolConfig(
    min_sessions: Int,
    idle_timeout_sec: Int,
    wait_timeout_ms: Int,
    homogeneous: Bool,
  )
}

/// A started connection pool.
pub opaque type Pool {
  Pool(handle: dynamic.Dynamic, base_user: String, base_password: String)
}

/// A reusable execution scope carrying identity and optional session setup.
pub opaque type Scope {
  Scope(pool: Pool, identity: Identity, session_profile: Option(SessionProfile))
}

/// A pool bundled with a typed session initializer.
pub opaque type PreparedPool(option) {
  PreparedPool(pool: Pool, session_init: SessionInit(option))
}

/// A handle for collecting pool trace samples.
pub opaque type Trace {
  Trace(handle: dynamic.Dynamic)
}

/// Snapshot counts for open and busy pool sessions.
pub type PoolStats {
  PoolStats(open: Int, busy: Int)
}

/// Aggregated session affinity counters derived from trace samples.
pub type SessionMetrics {
  SessionMetrics(
    writer_init_total: Int,
    reader_init_total: Int,
    writer_hit_total: Int,
    reader_hit_total: Int,
  )
}

/// One sample emitted while tracing pool and session reuse activity.
pub type TraceSample {
  TraceSample(
    elapsed_ms: Int,
    pool_open: Int,
    pool_busy: Int,
    writer_init_total: Int,
    reader_init_total: Int,
    writer_hit_total: Int,
    reader_hit_total: Int,
  )
}

/// A typed session initialization plan keyed by a per-checkout option value.
pub type SessionInit(option) {
  SessionInit(
    tag_of: fn(option) -> String,
    setup_sql: fn(option) -> List(String),
  )
}

/// High-level session setup operations rendered into Oracle session SQL.
pub type SessionAction {
  SetClientIdentifier(value: String)
  SetClientInfo(value: String)
  SetModule(module: String, action: String)
  SetAction(action: String)
  SetNlsDateFormat(value: String)
  Exec(sql: String)
}

type SessionProfile {
  SessionProfile(requested_tag: String, setup_sql: List(String))
}

/// A positional query parameter value.
pub type Param {
  StringParam(value: String)
  IntParam(value: Int)
  FloatParam(value: Float)
  BoolParam(value: Bool)
  NullParam
}

/// The identity to use when acquiring a connection from the pool.
pub type Identity {
  Direct
  Proxy(end_user: String)
}

/// The shape of result a query is expected to return.
pub type Expectation {
  ExpectAffected
  ExpectScalar
  ExpectRow
  ExpectRows
}

/// A decoder for a single scalar string value.
pub type ScalarDecoder(a) {
  ScalarDecoder(decode: fn(String) -> Result(a, Error))
}

/// A decoder for a row represented as a list of string values.
pub type RowDecoder(a) {
  RowDecoder(decode: fn(List(String)) -> Result(a, Error))
}

/// An immutable query builder carrying SQL, params, identity, and expectation.
pub opaque type Query {
  Query(
    sql: String,
    params: List(Param),
    identity: Identity,
    expectation: Expectation,
    label: Option(String),
  )
}

/// The raw execution result variants returned by `run`.
pub type QueryResult {
  Affected
  Scalar(value: String)
  Row(values: List(String))
  Rows(values: List(List(String)))
}

/// Start building a query from SQL text.
pub fn query(sql: String) -> Query {
  Query(
    sql:,
    params: [],
    identity: Direct,
    expectation: ExpectAffected,
    label: None,
  )
}

/// Alias for `query` when the SQL is primarily a command.
pub fn command(sql: String) -> Query {
  query(sql)
}

/// Start a query that is expected to return a scalar value.
pub fn scalar_query(sql: String) -> Query {
  query(sql) |> expect_scalar
}

/// Start a query that is expected to return a single row.
pub fn row_query(sql: String) -> Query {
  query(sql) |> expect_row
}

/// Start a query that is expected to return many rows.
pub fn rows_query(sql: String) -> Query {
  query(sql) |> expect_rows
}

/// Append one positional parameter to a query.
pub fn with_param(query: Query, param: Param) -> Query {
  let Query(sql, params, identity, expectation, label) = query
  Query(
    sql:,
    params: list.append(params, [param]),
    identity:,
    expectation:,
    label:,
  )
}

/// Append many positional parameters to a query.
pub fn with_params(query: Query, params: List(Param)) -> Query {
  let Query(sql, existing_params, identity, expectation, label) = query
  Query(
    sql:,
    params: list.append(existing_params, params),
    identity:,
    expectation:,
    label:,
  )
}

/// Alias for `with_params` for mixed prebuilt parameter lists.
pub fn bind_all(query: Query, params: List(Param)) -> Query {
  with_params(query, params)
}

/// Attach a descriptive label to a query for debugging or instrumentation.
pub fn label(query: Query, name: String) -> Query {
  let Query(sql, params, identity, expectation, _label) = query
  Query(sql:, params:, identity:, expectation:, label: Some(name))
}

/// Read the label attached to a query, if any.
pub fn query_label(query: Query) -> Option(String) {
  let Query(_sql, _params, _identity, _expectation, label) = query
  label
}

/// Append a string parameter to a query.
pub fn bind_string(query: Query, value: String) -> Query {
  with_param(query, string_param(value))
}

/// Append an integer parameter to a query.
pub fn bind_int(query: Query, value: Int) -> Query {
  with_param(query, int_param(value))
}

/// Append a float parameter to a query.
pub fn bind_float(query: Query, value: Float) -> Query {
  with_param(query, float_param(value))
}

/// Append a boolean parameter to a query.
pub fn bind_bool(query: Query, value: Bool) -> Query {
  with_param(query, bool_param(value))
}

/// Append a null parameter to a query.
pub fn bind_null(query: Query) -> Query {
  with_param(query, null_param())
}

/// Append many string parameters to a query.
pub fn bind_strings(query: Query, values: List(String)) -> Query {
  with_params(query, list.map(values, string_param))
}

/// Append many integer parameters to a query.
pub fn bind_ints(query: Query, values: List(Int)) -> Query {
  with_params(query, list.map(values, int_param))
}

/// Append many float parameters to a query.
pub fn bind_floats(query: Query, values: List(Float)) -> Query {
  with_params(query, list.map(values, float_param))
}

/// Append many boolean parameters to a query.
pub fn bind_bools(query: Query, values: List(Bool)) -> Query {
  with_params(query, list.map(values, bool_param))
}

/// Alias for `as_proxy_user`.
pub fn as_end_user(query: Query, end_user: String) -> Query {
  as_proxy_user(query, end_user)
}

/// Mark a query to run as a proxy user when executed.
pub fn as_proxy_user(query: Query, end_user: String) -> Query {
  let Query(sql, params, _identity, expectation, label) = query
  Query(sql:, params:, identity: Proxy(end_user), expectation:, label:)
}

/// Build a direct execution scope for a pool.
pub fn scope(pool: Pool) -> Scope {
  Scope(pool:, identity: Direct, session_profile: None)
}

/// Build a proxy-user execution scope for a pool.
pub fn scope_as(pool: Pool, end_user: String) -> Scope {
  Scope(pool:, identity: Proxy(end_user), session_profile: None)
}

/// Build a typed session initializer from high-level session actions.
pub fn session_init(
  tag_of: fn(option) -> String,
  setup_sql: fn(option) -> List(SessionAction),
) -> SessionInit(option) {
  session_init_sql(tag_of, fn(option) {
    setup_sql(option) |> list.map(render_session_action)
  })
}

/// Build a typed session initializer from raw setup SQL.
pub fn session_init_sql(
  tag_of: fn(option) -> String,
  setup_sql: fn(option) -> List(String),
) -> SessionInit(option) {
  SessionInit(tag_of:, setup_sql:)
}

/// Combine a started pool with a typed session initializer.
pub fn prepare_pool(
  pool: Pool,
  with session_initializer: SessionInit(option),
) -> PreparedPool(option) {
  PreparedPool(pool:, session_init: session_initializer)
}

/// Build a direct scope that also applies typed session initialization.
pub fn scope_with(
  prepared_pool: PreparedPool(option),
  option: option,
) -> Scope {
  let PreparedPool(pool, session_initializer) = prepared_pool
  Scope(
    pool:,
    identity: Direct,
    session_profile: Some(build_session_profile(session_initializer, option)),
  )
}

/// Build a proxy-user scope that also applies typed session initialization.
pub fn scope_as_with(
  prepared_pool: PreparedPool(option),
  end_user: String,
  option: option,
) -> Scope {
  let PreparedPool(pool, session_initializer) = prepared_pool
  Scope(
    pool:,
    identity: Proxy(end_user),
    session_profile: Some(build_session_profile(session_initializer, option)),
  )
}

/// Alias for `expect_scalar`.
pub fn returning_scalar(query: Query) -> Query {
  expect_scalar(query)
}

/// Change a query expectation to a scalar result.
pub fn expect_scalar(query: Query) -> Query {
  let Query(sql, params, identity, _expectation, label) = query
  Query(sql:, params:, identity:, expectation: ExpectScalar, label:)
}

/// Change a query expectation to a single-row result.
pub fn expect_row(query: Query) -> Query {
  let Query(sql, params, identity, _expectation, label) = query
  Query(sql:, params:, identity:, expectation: ExpectRow, label:)
}

/// Change a query expectation to a multi-row result.
pub fn expect_rows(query: Query) -> Query {
  let Query(sql, params, identity, _expectation, label) = query
  Query(sql:, params:, identity:, expectation: ExpectRows, label:)
}

/// Change a query expectation to an affected-rows command result.
pub fn expect_affected(query: Query) -> Query {
  let Query(sql, params, identity, _expectation, label) = query
  Query(sql:, params:, identity:, expectation: ExpectAffected, label:)
}

/// Create a string parameter value.
pub fn string_param(value: String) -> Param {
  StringParam(value)
}

/// Create an integer parameter value.
pub fn int_param(value: Int) -> Param {
  IntParam(value)
}

/// Create a float parameter value.
pub fn float_param(value: Float) -> Param {
  FloatParam(value)
}

/// Create a boolean parameter value.
pub fn bool_param(value: Bool) -> Param {
  BoolParam(value)
}

/// Create a null parameter value.
pub fn null_param() -> Param {
  NullParam
}

/// A scalar decoder that returns the raw string unchanged.
pub fn string_decoder() -> ScalarDecoder(String) {
  ScalarDecoder(fn(value) { Ok(value) })
}

/// Transform the successful output of a scalar decoder.
pub fn map_scalar_decoder(
  decoder: ScalarDecoder(a),
  with mapper: fn(a) -> b,
) -> ScalarDecoder(b) {
  ScalarDecoder(fn(value) {
    case decode_scalar(value, using: decoder) {
      Ok(decoded) -> Ok(mapper(decoded))
      Error(reason) -> Error(reason)
    }
  })
}

/// Decode integers, accepting whole-number float strings such as `80.0`.
pub fn int_decoder() -> ScalarDecoder(Int) {
  ScalarDecoder(fn(value) {
    case int.parse(value) {
      Ok(parsed) -> Ok(parsed)
      Error(_) ->
        case float.parse(value) {
          Ok(parsed) ->
            case parsed == float.floor(parsed) {
              True -> Ok(float.round(parsed))
              False ->
                Error(DecodeError(
                  "unable to parse int from scalar value: " <> value,
                ))
            }
          Error(_) ->
            Error(DecodeError(
              "unable to parse int from scalar value: " <> value,
            ))
        }
    }
  })
}

/// Decode floating-point numbers from scalar strings.
pub fn float_decoder() -> ScalarDecoder(Float) {
  ScalarDecoder(fn(value) {
    case float.parse(value) {
      Ok(parsed) -> Ok(parsed)
      Error(_) ->
        Error(DecodeError("unable to parse float from scalar value: " <> value))
    }
  })
}

/// Decode common truthy and falsy scalar string representations.
pub fn bool_decoder() -> ScalarDecoder(Bool) {
  ScalarDecoder(fn(value) {
    case string.lowercase(value) {
      "true" -> Ok(True)
      "t" -> Ok(True)
      "yes" -> Ok(True)
      "y" -> Ok(True)
      "1" -> Ok(True)
      "false" -> Ok(False)
      "f" -> Ok(False)
      "no" -> Ok(False)
      "n" -> Ok(False)
      "0" -> Ok(False)
      _ ->
        Error(DecodeError("unable to parse bool from scalar value: " <> value))
    }
  })
}

/// Build a row decoder from a custom row decoding function.
pub fn row_decoder(
  decode: fn(List(String)) -> Result(a, Error),
) -> RowDecoder(a) {
  RowDecoder(decode)
}

/// Transform the successful output of a row decoder.
pub fn map_row_decoder(
  decoder: RowDecoder(a),
  with mapper: fn(a) -> b,
) -> RowDecoder(b) {
  RowDecoder(fn(values) {
    case decode_row(values, using: decoder) {
      Ok(decoded) -> Ok(mapper(decoded))
      Error(reason) -> Error(reason)
    }
  })
}

/// Decode the first column of a row as a string.
pub fn first_string_decoder() -> RowDecoder(String) {
  RowDecoder(fn(values) {
    case values {
      [first, ..] -> Ok(first)
      [] -> Error(NotFound)
    }
  })
}

/// Decode the first column of a row as an integer.
pub fn first_int_decoder() -> RowDecoder(Int) {
  RowDecoder(fn(values) {
    case values {
      [first, ..] -> decode_scalar(first, using: int_decoder())
      [] -> Error(NotFound)
    }
  })
}

/// Decode the first two columns of a row with independent scalar decoders.
pub fn pair_decoder(
  first first_decoder: ScalarDecoder(a),
  second second_decoder: ScalarDecoder(b),
) -> RowDecoder(#(a, b)) {
  RowDecoder(fn(values) {
    case values {
      [first, second, ..] ->
        case decode_scalar(first, using: first_decoder) {
          Ok(decoded_first) ->
            case decode_scalar(second, using: second_decoder) {
              Ok(decoded_second) -> Ok(#(decoded_first, decoded_second))
              Error(reason) -> Error(reason)
            }
          Error(reason) -> Error(reason)
        }
      [] -> Error(NotFound)
      [_] -> Error(DecodeError("expected at least 2 columns in row"))
    }
  })
}

/// Decode the first two columns and build a custom value.
pub fn decode2(
  first first_decoder: ScalarDecoder(a),
  second second_decoder: ScalarDecoder(b),
  with builder: fn(a, b) -> c,
) -> RowDecoder(c) {
  pair_decoder(first: first_decoder, second: second_decoder)
  |> map_row_decoder(with: fn(pair) {
    let #(first, second) = pair
    builder(first, second)
  })
}

/// Decode the first three columns of a row with independent scalar decoders.
pub fn triple_decoder(
  first first_decoder: ScalarDecoder(a),
  second second_decoder: ScalarDecoder(b),
  third third_decoder: ScalarDecoder(c),
) -> RowDecoder(#(a, b, c)) {
  RowDecoder(fn(values) {
    case values {
      [first, second, third, ..] ->
        case decode_scalar(first, using: first_decoder) {
          Ok(decoded_first) ->
            case decode_scalar(second, using: second_decoder) {
              Ok(decoded_second) ->
                case decode_scalar(third, using: third_decoder) {
                  Ok(decoded_third) ->
                    Ok(#(decoded_first, decoded_second, decoded_third))
                  Error(reason) -> Error(reason)
                }
              Error(reason) -> Error(reason)
            }
          Error(reason) -> Error(reason)
        }
      [] -> Error(NotFound)
      [_] -> Error(DecodeError("expected at least 3 columns in row"))
      [_, _] -> Error(DecodeError("expected at least 3 columns in row"))
    }
  })
}

/// Decode the first three columns and build a custom value.
pub fn decode3(
  first first_decoder: ScalarDecoder(a),
  second second_decoder: ScalarDecoder(b),
  third third_decoder: ScalarDecoder(c),
  with builder: fn(a, b, c) -> d,
) -> RowDecoder(d) {
  triple_decoder(
    first: first_decoder,
    second: second_decoder,
    third: third_decoder,
  )
  |> map_row_decoder(with: fn(tuple) {
    let #(first, second, third) = tuple
    builder(first, second, third)
  })
}

/// Default pool sizing and timeout settings.
pub fn default_pool_config() -> PoolConfig {
  PoolConfig(
    min_sessions: 2,
    idle_timeout_sec: 30,
    wait_timeout_ms: 60_000,
    homogeneous: False,
  )
}

/// Default connection settings for local Oracle development.
pub fn default_config() -> Config {
  Config(
    host: "127.0.0.1",
    port: 1521,
    service: "FREEPDB1",
    user: "",
    password: "",
    pool: default_pool_config(),
  )
}

/// Set the Oracle host for a config value.
pub fn host(config: Config, host: String) -> Config {
  Config(..config, host:)
}

/// Set the Oracle port for a config value.
pub fn port(config: Config, port: Int) -> Config {
  Config(..config, port:)
}

/// Set the Oracle service name for a config value.
pub fn service(config: Config, service: String) -> Config {
  Config(..config, service:)
}

/// Set the base database user for a config value.
pub fn user(config: Config, user: String) -> Config {
  Config(..config, user:)
}

/// Set the base database password for a config value.
pub fn password(config: Config, password: String) -> Config {
  Config(..config, password:)
}

/// Replace the pool settings inside a config value.
pub fn pool_config(config: Config, pool: PoolConfig) -> Config {
  Config(..config, pool:)
}

/// Set the minimum number of sessions kept in the pool.
pub fn min_sessions(config: PoolConfig, min_sessions: Int) -> PoolConfig {
  PoolConfig(..config, min_sessions:)
}

/// Set the idle timeout, in seconds, for pooled sessions.
pub fn idle_timeout_sec(
  config: PoolConfig,
  idle_timeout_sec: Int,
) -> PoolConfig {
  PoolConfig(..config, idle_timeout_sec:)
}

/// Set the wait timeout, in milliseconds, for pool acquisition.
pub fn wait_timeout_ms(config: PoolConfig, wait_timeout_ms: Int) -> PoolConfig {
  PoolConfig(..config, wait_timeout_ms:)
}

/// Control whether the pool is homogeneous.
pub fn homogeneous(config: PoolConfig, homogeneous: Bool) -> PoolConfig {
  PoolConfig(..config, homogeneous:)
}

/// Start a pool from the supplied config.
pub fn start(config: Config) -> Result(Pool, Error) {
  let Config(
    host,
    port,
    service,
    user,
    password,
    PoolConfig(min_sessions, idle_timeout_sec, wait_timeout_ms, homogeneous),
  ) = config
  case
    internal.pool_create(
      host,
      port,
      service,
      user,
      password,
      homogeneous,
      min_sessions,
      idle_timeout_sec,
      wait_timeout_ms,
    )
  {
    Ok(handle) -> Ok(Pool(handle, user, password))
    Error(message) -> Error(classify_db_error(message))
  }
}

/// Close a started pool.
pub fn stop(pool: Pool) -> Result(Nil, Error) {
  let Pool(handle, _base_user, _base_password) = pool
  case internal.pool_close(handle) {
    Ok(_) -> Ok(Nil)
    Error(message) -> Error(classify_db_error(message))
  }
}

/// Execute command SQL directly against a pool.
pub fn execute(sql: String, on pool: Pool) -> Result(Nil, Error) {
  execute_with_session_profile(sql, pool, None)
}

fn execute_with_session_profile(
  sql: String,
  pool: Pool,
  session_profile: Option(SessionProfile),
) -> Result(Nil, Error) {
  let Pool(handle, base_user, base_password) = pool
  case session_profile {
    None ->
      case internal.pool_exec_sql(handle, base_user, base_password, sql) {
        Ok(_) -> Ok(Nil)
        Error(message) -> Error(classify_db_error(message))
      }
    Some(SessionProfile(requested_tag, setup_sql)) ->
      case
        internal.pool_exec_sql_with_session(
          handle,
          base_user,
          base_password,
          sql,
          requested_tag,
          setup_sql,
        )
      {
        Ok(_) -> Ok(Nil)
        Error(message) -> Error(classify_db_error(message))
      }
  }
}

/// Run scalar SQL directly against a pool and return the first column.
pub fn scalar(sql: String, on pool: Pool) -> Result(String, Error) {
  scalar_with_session_profile(sql, pool, None)
}

fn scalar_with_session_profile(
  sql: String,
  pool: Pool,
  session_profile: Option(SessionProfile),
) -> Result(String, Error) {
  let Pool(handle, base_user, base_password) = pool
  case session_profile {
    None ->
      case internal.pool_probe_sql(handle, base_user, base_password, sql) {
        Ok(value) -> Ok(value)
        Error(message) -> Error(classify_db_error(message))
      }
    Some(SessionProfile(requested_tag, setup_sql)) ->
      case
        internal.pool_probe_sql_with_session(
          handle,
          base_user,
          base_password,
          sql,
          requested_tag,
          setup_sql,
        )
      {
        Ok(value) -> Ok(value)
        Error(message) -> Error(classify_db_error(message))
      }
  }
}

/// Run SQL directly against a pool and return the first row.
pub fn row(sql: String, on pool: Pool) -> Result(List(String), Error) {
  row_with_session_profile(sql, pool, None)
}

fn row_with_session_profile(
  sql: String,
  pool: Pool,
  session_profile: Option(SessionProfile),
) -> Result(List(String), Error) {
  let Pool(handle, base_user, base_password) = pool
  case session_profile {
    None ->
      case internal.pool_probe_row(handle, base_user, base_password, sql) {
        Ok(values) -> Ok(values)
        Error(message) -> Error(classify_db_error(message))
      }
    Some(SessionProfile(requested_tag, setup_sql)) ->
      case
        internal.pool_probe_row_with_session(
          handle,
          base_user,
          base_password,
          sql,
          requested_tag,
          setup_sql,
        )
      {
        Ok(values) -> Ok(values)
        Error(message) -> Error(classify_db_error(message))
      }
  }
}

/// Run SQL directly against a pool and return all rows.
pub fn rows(sql: String, on pool: Pool) -> Result(List(List(String)), Error) {
  rows_with_session_profile(sql, pool, None)
}

fn rows_with_session_profile(
  sql: String,
  pool: Pool,
  session_profile: Option(SessionProfile),
) -> Result(List(List(String)), Error) {
  let Pool(handle, base_user, base_password) = pool
  case session_profile {
    None ->
      case internal.pool_probe_rows(handle, base_user, base_password, sql) {
        Ok(values) -> Ok(values)
        Error(message) -> Error(classify_db_error(message))
      }
    Some(SessionProfile(requested_tag, setup_sql)) ->
      case
        internal.pool_probe_rows_with_session(
          handle,
          base_user,
          base_password,
          sql,
          requested_tag,
          setup_sql,
        )
      {
        Ok(values) -> Ok(values)
        Error(message) -> Error(classify_db_error(message))
      }
  }
}

/// Alias for `run`.
pub fn execute_query(
  query: Query,
  on pool: Pool,
) -> Result(QueryResult, Error) {
  run(query, on: pool)
}

/// Run a query within a reusable scope.
pub fn run_in(query: Query, within scope: Scope) -> Result(QueryResult, Error) {
  let Scope(pool, identity, session_profile) = scope
  run_with_session_profile(
    apply_scope_identity(query, identity),
    pool,
    session_profile,
  )
}

/// Render and execute a query against a pool.
pub fn run(query: Query, on pool: Pool) -> Result(QueryResult, Error) {
  run_with_session_profile(query, pool, None)
}

fn run_with_session_profile(
  query: Query,
  pool: Pool,
  session_profile: Option(SessionProfile),
) -> Result(QueryResult, Error) {
  let Query(sql, params, identity, expectation, _label) = query
  case render_sql(sql, params) {
    Error(reason) -> Error(reason)
    Ok(compiled_sql) ->
      case identity, expectation {
        Direct, ExpectAffected ->
          case
            execute_with_session_profile(compiled_sql, pool, session_profile)
          {
            Ok(_) -> Ok(Affected)
            Error(reason) -> Error(reason)
          }
        Direct, ExpectScalar ->
          case
            scalar_with_session_profile(compiled_sql, pool, session_profile)
          {
            Ok(value) -> Ok(Scalar(value))
            Error(reason) -> Error(reason)
          }
        Direct, ExpectRow ->
          case row_with_session_profile(compiled_sql, pool, session_profile) {
            Ok(values) -> Ok(Row(values))
            Error(reason) -> Error(reason)
          }
        Direct, ExpectRows ->
          case rows_with_session_profile(compiled_sql, pool, session_profile) {
            Ok(values) -> Ok(Rows(values))
            Error(reason) -> Error(reason)
          }
        Proxy(end_user), ExpectAffected ->
          case
            execute_as_with_session_profile(
              end_user,
              compiled_sql,
              pool,
              session_profile,
            )
          {
            Ok(_) -> Ok(Affected)
            Error(reason) -> Error(reason)
          }
        Proxy(end_user), ExpectScalar ->
          case
            scalar_as_with_session_profile(
              end_user,
              compiled_sql,
              pool,
              session_profile,
            )
          {
            Ok(value) -> Ok(Scalar(value))
            Error(reason) -> Error(reason)
          }
        Proxy(end_user), ExpectRow ->
          case
            row_as_with_session_profile(
              end_user,
              compiled_sql,
              pool,
              session_profile,
            )
          {
            Ok(values) -> Ok(Row(values))
            Error(reason) -> Error(reason)
          }
        Proxy(end_user), ExpectRows ->
          case
            rows_as_with_session_profile(
              end_user,
              compiled_sql,
              pool,
              session_profile,
            )
          {
            Ok(values) -> Ok(Rows(values))
            Error(reason) -> Error(reason)
          }
      }
  }
}

/// Run a query expecting an affected-rows command result.
pub fn run_affected(query: Query, on pool: Pool) -> Result(Nil, Error) {
  case run(expect_affected(query), on: pool) {
    Ok(Affected) -> Ok(Nil)
    Ok(Scalar(_)) -> Error(DecodeError("expected affected rows result"))
    Ok(Row(_)) -> Error(DecodeError("expected affected rows result"))
    Ok(Rows(_)) -> Error(DecodeError("expected affected rows result"))
    Error(reason) -> Error(reason)
  }
}

/// Short alias for `run_affected`.
pub fn exec(query: Query, on pool: Pool) -> Result(Nil, Error) {
  run_affected(query, on: pool)
}

/// Run a query within a scope expecting an affected-rows command result.
pub fn run_affected_in(
  query: Query,
  within scope: Scope,
) -> Result(Nil, Error) {
  case run_in(expect_affected(query), within: scope) {
    Ok(Affected) -> Ok(Nil)
    Ok(Scalar(_)) -> Error(DecodeError("expected affected rows result"))
    Ok(Row(_)) -> Error(DecodeError("expected affected rows result"))
    Ok(Rows(_)) -> Error(DecodeError("expected affected rows result"))
    Error(reason) -> Error(reason)
  }
}

/// Short alias for `run_affected_in`.
pub fn exec_in(query: Query, within scope: Scope) -> Result(Nil, Error) {
  run_affected_in(query, within: scope)
}

/// Run a query expecting a scalar string result.
pub fn run_scalar(query: Query, on pool: Pool) -> Result(String, Error) {
  case run(expect_scalar(query), on: pool) {
    Ok(Scalar(value)) -> Ok(value)
    Ok(Affected) -> Error(DecodeError("expected scalar result"))
    Ok(Row(_)) -> Error(DecodeError("expected scalar result"))
    Ok(Rows(_)) -> Error(DecodeError("expected scalar result"))
    Error(reason) -> Error(reason)
  }
}

/// Run a scalar query and map `NotFound` to `None`.
pub fn run_maybe_scalar(
  query: Query,
  on pool: Pool,
) -> Result(Option(String), Error) {
  case run_scalar(query, on: pool) {
    Ok(value) -> Ok(Some(value))
    Error(NotFound) -> Ok(None)
    Error(reason) -> Error(reason)
  }
}

/// Run a scoped scalar query and map `NotFound` to `None`.
pub fn run_maybe_scalar_in(
  query: Query,
  within scope: Scope,
) -> Result(Option(String), Error) {
  case run_scalar_in(query, within: scope) {
    Ok(value) -> Ok(Some(value))
    Error(NotFound) -> Ok(None)
    Error(reason) -> Error(reason)
  }
}

/// Run a scoped query expecting a scalar string result.
pub fn run_scalar_in(
  query: Query,
  within scope: Scope,
) -> Result(String, Error) {
  case run_in(expect_scalar(query), within: scope) {
    Ok(Scalar(value)) -> Ok(value)
    Ok(Affected) -> Error(DecodeError("expected scalar result"))
    Ok(Row(_)) -> Error(DecodeError("expected scalar result"))
    Ok(Rows(_)) -> Error(DecodeError("expected scalar result"))
    Error(reason) -> Error(reason)
  }
}

/// Run a query expecting the first row.
pub fn run_row(query: Query, on pool: Pool) -> Result(List(String), Error) {
  case run(expect_row(query), on: pool) {
    Ok(Row(values)) -> Ok(values)
    Ok(Affected) -> Error(DecodeError("expected row result"))
    Ok(Scalar(_)) -> Error(DecodeError("expected row result"))
    Ok(Rows(_)) -> Error(DecodeError("expected row result"))
    Error(reason) -> Error(reason)
  }
}

/// Run a row query and map `NotFound` to `None`.
pub fn run_maybe_row(
  query: Query,
  on pool: Pool,
) -> Result(Option(List(String)), Error) {
  case run_row(query, on: pool) {
    Ok(values) -> Ok(Some(values))
    Error(NotFound) -> Ok(None)
    Error(reason) -> Error(reason)
  }
}

/// Run a scoped row query and map `NotFound` to `None`.
pub fn run_maybe_row_in(
  query: Query,
  within scope: Scope,
) -> Result(Option(List(String)), Error) {
  case run_row_in(query, within: scope) {
    Ok(values) -> Ok(Some(values))
    Error(NotFound) -> Ok(None)
    Error(reason) -> Error(reason)
  }
}

/// Run a scoped query expecting the first row.
pub fn run_row_in(
  query: Query,
  within scope: Scope,
) -> Result(List(String), Error) {
  case run_in(expect_row(query), within: scope) {
    Ok(Row(values)) -> Ok(values)
    Ok(Affected) -> Error(DecodeError("expected row result"))
    Ok(Scalar(_)) -> Error(DecodeError("expected row result"))
    Ok(Rows(_)) -> Error(DecodeError("expected row result"))
    Error(reason) -> Error(reason)
  }
}

/// Run a query expecting all rows.
pub fn run_rows(
  query: Query,
  on pool: Pool,
) -> Result(List(List(String)), Error) {
  case run(expect_rows(query), on: pool) {
    Ok(Rows(values)) -> Ok(values)
    Ok(Affected) -> Error(DecodeError("expected rows result"))
    Ok(Scalar(_)) -> Error(DecodeError("expected rows result"))
    Ok(Row(_)) -> Error(DecodeError("expected rows result"))
    Error(reason) -> Error(reason)
  }
}

/// Run a scoped query expecting all rows.
pub fn run_rows_in(
  query: Query,
  within scope: Scope,
) -> Result(List(List(String)), Error) {
  case run_in(expect_rows(query), within: scope) {
    Ok(Rows(values)) -> Ok(values)
    Ok(Affected) -> Error(DecodeError("expected rows result"))
    Ok(Scalar(_)) -> Error(DecodeError("expected rows result"))
    Ok(Row(_)) -> Error(DecodeError("expected rows result"))
    Error(reason) -> Error(reason)
  }
}

/// Decode a scalar string with a scalar decoder.
pub fn decode_scalar(
  value: String,
  using decoder: ScalarDecoder(a),
) -> Result(a, Error) {
  let ScalarDecoder(decode) = decoder
  decode(value)
}

/// Run a scalar query and decode the result.
pub fn run_decode(
  query: Query,
  on pool: Pool,
  using decoder: ScalarDecoder(a),
) -> Result(a, Error) {
  case run_scalar(query, on: pool) {
    Ok(value) -> decode_scalar(value, using: decoder)
    Error(reason) -> Error(reason)
  }
}

/// Alias for `run_decode`.
pub fn scalar_as_type(
  query: Query,
  on pool: Pool,
  using decoder: ScalarDecoder(a),
) -> Result(a, Error) {
  run_decode(query, on: pool, using: decoder)
}

/// Scoped alias for `run_decode_in`.
pub fn scalar_as_type_in(
  query: Query,
  within scope: Scope,
  using decoder: ScalarDecoder(a),
) -> Result(a, Error) {
  run_decode_in(query, within: scope, using: decoder)
}

/// Run and decode a scalar query, mapping `NotFound` to `None`.
pub fn run_maybe_decode(
  query: Query,
  on pool: Pool,
  using decoder: ScalarDecoder(a),
) -> Result(Option(a), Error) {
  case run_maybe_scalar(query, on: pool) {
    Ok(Some(value)) ->
      case decode_scalar(value, using: decoder) {
        Ok(decoded) -> Ok(Some(decoded))
        Error(reason) -> Error(reason)
      }
    Ok(None) -> Ok(None)
    Error(reason) -> Error(reason)
  }
}

/// Alias for `run_maybe_decode`.
pub fn maybe_scalar_as_type(
  query: Query,
  on pool: Pool,
  using decoder: ScalarDecoder(a),
) -> Result(Option(a), Error) {
  run_maybe_decode(query, on: pool, using: decoder)
}

/// Scoped alias for `run_maybe_decode_in`.
pub fn maybe_scalar_as_type_in(
  query: Query,
  within scope: Scope,
  using decoder: ScalarDecoder(a),
) -> Result(Option(a), Error) {
  run_maybe_decode_in(query, within: scope, using: decoder)
}

/// Run and decode a scoped scalar query, mapping `NotFound` to `None`.
pub fn run_maybe_decode_in(
  query: Query,
  within scope: Scope,
  using decoder: ScalarDecoder(a),
) -> Result(Option(a), Error) {
  case run_maybe_scalar_in(query, within: scope) {
    Ok(Some(value)) ->
      case decode_scalar(value, using: decoder) {
        Ok(decoded) -> Ok(Some(decoded))
        Error(reason) -> Error(reason)
      }
    Ok(None) -> Ok(None)
    Error(reason) -> Error(reason)
  }
}

/// Run and decode a scoped scalar query.
pub fn run_decode_in(
  query: Query,
  within scope: Scope,
  using decoder: ScalarDecoder(a),
) -> Result(a, Error) {
  case run_scalar_in(query, within: scope) {
    Ok(value) -> decode_scalar(value, using: decoder)
    Error(reason) -> Error(reason)
  }
}

/// Decode a row with a row decoder.
pub fn decode_row(
  values: List(String),
  using decoder: RowDecoder(a),
) -> Result(a, Error) {
  let RowDecoder(decode) = decoder
  decode(values)
}

/// Run a row query and decode the first row.
pub fn run_decode_row(
  query: Query,
  on pool: Pool,
  using decoder: RowDecoder(a),
) -> Result(a, Error) {
  case run_row(query, on: pool) {
    Ok(values) -> decode_row(values, using: decoder)
    Error(reason) -> Error(reason)
  }
}

/// Short alias for `run_decode_row`.
pub fn one(
  query: Query,
  on pool: Pool,
  using decoder: RowDecoder(a),
) -> Result(a, Error) {
  run_decode_row(query, on: pool, using: decoder)
}

/// Run and decode a row query, mapping `NotFound` to `None`.
pub fn run_maybe_decode_row(
  query: Query,
  on pool: Pool,
  using decoder: RowDecoder(a),
) -> Result(Option(a), Error) {
  case run_maybe_row(query, on: pool) {
    Ok(Some(values)) ->
      case decode_row(values, using: decoder) {
        Ok(decoded) -> Ok(Some(decoded))
        Error(reason) -> Error(reason)
      }
    Ok(None) -> Ok(None)
    Error(reason) -> Error(reason)
  }
}

/// Short alias for `run_maybe_decode_row`.
pub fn maybe_one(
  query: Query,
  on pool: Pool,
  using decoder: RowDecoder(a),
) -> Result(Option(a), Error) {
  run_maybe_decode_row(query, on: pool, using: decoder)
}

/// Run and decode a scoped row query, mapping `NotFound` to `None`.
pub fn run_maybe_decode_row_in(
  query: Query,
  within scope: Scope,
  using decoder: RowDecoder(a),
) -> Result(Option(a), Error) {
  case run_maybe_row_in(query, within: scope) {
    Ok(Some(values)) ->
      case decode_row(values, using: decoder) {
        Ok(decoded) -> Ok(Some(decoded))
        Error(reason) -> Error(reason)
      }
    Ok(None) -> Ok(None)
    Error(reason) -> Error(reason)
  }
}

/// Scoped alias for `run_maybe_decode_row_in`.
pub fn maybe_one_in(
  query: Query,
  within scope: Scope,
  using decoder: RowDecoder(a),
) -> Result(Option(a), Error) {
  run_maybe_decode_row_in(query, within: scope, using: decoder)
}

/// Run a scoped row query and decode the first row.
pub fn run_decode_row_in(
  query: Query,
  within scope: Scope,
  using decoder: RowDecoder(a),
) -> Result(a, Error) {
  case run_row_in(query, within: scope) {
    Ok(values) -> decode_row(values, using: decoder)
    Error(reason) -> Error(reason)
  }
}

/// Scoped short alias for `run_decode_row_in`.
pub fn one_in(
  query: Query,
  within scope: Scope,
  using decoder: RowDecoder(a),
) -> Result(a, Error) {
  run_decode_row_in(query, within: scope, using: decoder)
}

/// Decode every row in a result set with the same row decoder.
pub fn decode_rows(
  rows: List(List(String)),
  using decoder: RowDecoder(a),
) -> Result(List(a), Error) {
  decode_rows_loop(rows, decoder, [])
}

fn decode_rows_loop(
  rows: List(List(String)),
  decoder: RowDecoder(a),
  acc: List(a),
) -> Result(List(a), Error) {
  case rows {
    [] -> Ok(list.reverse(acc))
    [row, ..rest] ->
      case decode_row(row, using: decoder) {
        Ok(value) -> decode_rows_loop(rest, decoder, [value, ..acc])
        Error(reason) -> Error(reason)
      }
  }
}

/// Run a rows query and decode all rows.
pub fn run_decode_rows(
  query: Query,
  on pool: Pool,
  using decoder: RowDecoder(a),
) -> Result(List(a), Error) {
  case run_rows(query, on: pool) {
    Ok(values) -> decode_rows(values, using: decoder)
    Error(reason) -> Error(reason)
  }
}

/// Short alias for `run_decode_rows`.
pub fn all(
  query: Query,
  on pool: Pool,
  using decoder: RowDecoder(a),
) -> Result(List(a), Error) {
  run_decode_rows(query, on: pool, using: decoder)
}

/// Run a scoped rows query and decode all rows.
pub fn run_decode_rows_in(
  query: Query,
  within scope: Scope,
  using decoder: RowDecoder(a),
) -> Result(List(a), Error) {
  case run_rows_in(query, within: scope) {
    Ok(values) -> decode_rows(values, using: decoder)
    Error(reason) -> Error(reason)
  }
}

/// Scoped short alias for `run_decode_rows_in`.
pub fn all_in(
  query: Query,
  within scope: Scope,
  using decoder: RowDecoder(a),
) -> Result(List(a), Error) {
  run_decode_rows_in(query, within: scope, using: decoder)
}

/// Run and decode a scalar query as an integer.
pub fn run_scalar_int(query: Query, on pool: Pool) -> Result(Int, Error) {
  run_decode(query, on: pool, using: int_decoder())
}

/// Run and decode a scoped scalar query as an integer.
pub fn run_scalar_int_in(
  query: Query,
  within scope: Scope,
) -> Result(Int, Error) {
  run_decode_in(query, within: scope, using: int_decoder())
}

/// Run and decode a scalar query as a float.
pub fn run_scalar_float(query: Query, on pool: Pool) -> Result(Float, Error) {
  run_decode(query, on: pool, using: float_decoder())
}

/// Run and decode a scoped scalar query as a float.
pub fn run_scalar_float_in(
  query: Query,
  within scope: Scope,
) -> Result(Float, Error) {
  run_decode_in(query, within: scope, using: float_decoder())
}

/// Run and decode a scalar query as a boolean.
pub fn run_scalar_bool(query: Query, on pool: Pool) -> Result(Bool, Error) {
  run_decode(query, on: pool, using: bool_decoder())
}

/// Run and decode a scoped scalar query as a boolean.
pub fn run_scalar_bool_in(
  query: Query,
  within scope: Scope,
) -> Result(Bool, Error) {
  run_decode_in(query, within: scope, using: bool_decoder())
}

/// Render a query into executable SQL, validating placeholder counts.
pub fn to_sql(query: Query) -> Result(String, Error) {
  let Query(sql, params, _identity, _expectation, _label) = query
  render_sql(sql, params)
}

/// Render a query into SQL, prefixing any label for easier inspection.
pub fn inspect_query(query: Query) -> Result(String, Error) {
  case to_sql(query) {
    Ok(rendered) ->
      case query_label(query) {
        Some(name) -> Ok("[" <> name <> "] " <> rendered)
        None -> Ok(rendered)
      }
    Error(reason) -> Error(reason)
  }
}

/// Execute command SQL as a proxy user.
pub fn execute_as(
  end_user: String,
  sql: String,
  on pool: Pool,
) -> Result(Nil, Error) {
  execute_as_with_session_profile(end_user, sql, pool, None)
}

fn execute_as_with_session_profile(
  end_user: String,
  sql: String,
  pool: Pool,
  session_profile: Option(SessionProfile),
) -> Result(Nil, Error) {
  let Pool(handle, base_user, base_password) = pool
  let proxy_user = proxy_user(base_user, end_user)
  case session_profile {
    None ->
      case internal.pool_exec_sql(handle, proxy_user, base_password, sql) {
        Ok(_) -> Ok(Nil)
        Error(message) -> Error(classify_db_error(message))
      }
    Some(SessionProfile(requested_tag, setup_sql)) ->
      case
        internal.pool_exec_sql_with_session(
          handle,
          proxy_user,
          base_password,
          sql,
          requested_tag,
          setup_sql,
        )
      {
        Ok(_) -> Ok(Nil)
        Error(message) -> Error(classify_db_error(message))
      }
  }
}

/// Run scalar SQL as a proxy user.
pub fn scalar_as(
  end_user: String,
  sql: String,
  on pool: Pool,
) -> Result(String, Error) {
  scalar_as_with_session_profile(end_user, sql, pool, None)
}

fn scalar_as_with_session_profile(
  end_user: String,
  sql: String,
  pool: Pool,
  session_profile: Option(SessionProfile),
) -> Result(String, Error) {
  let Pool(handle, base_user, base_password) = pool
  let proxy_user = proxy_user(base_user, end_user)
  case session_profile {
    None ->
      case internal.pool_probe_sql(handle, proxy_user, base_password, sql) {
        Ok(value) -> Ok(value)
        Error(message) -> Error(classify_db_error(message))
      }
    Some(SessionProfile(requested_tag, setup_sql)) ->
      case
        internal.pool_probe_sql_with_session(
          handle,
          proxy_user,
          base_password,
          sql,
          requested_tag,
          setup_sql,
        )
      {
        Ok(value) -> Ok(value)
        Error(message) -> Error(classify_db_error(message))
      }
  }
}

/// Run SQL as a proxy user and return the first row.
pub fn row_as(
  end_user: String,
  sql: String,
  on pool: Pool,
) -> Result(List(String), Error) {
  row_as_with_session_profile(end_user, sql, pool, None)
}

fn row_as_with_session_profile(
  end_user: String,
  sql: String,
  pool: Pool,
  session_profile: Option(SessionProfile),
) -> Result(List(String), Error) {
  let Pool(handle, base_user, base_password) = pool
  let proxy_user = proxy_user(base_user, end_user)
  case session_profile {
    None ->
      case internal.pool_probe_row(handle, proxy_user, base_password, sql) {
        Ok(values) -> Ok(values)
        Error(message) -> Error(classify_db_error(message))
      }
    Some(SessionProfile(requested_tag, setup_sql)) ->
      case
        internal.pool_probe_row_with_session(
          handle,
          proxy_user,
          base_password,
          sql,
          requested_tag,
          setup_sql,
        )
      {
        Ok(values) -> Ok(values)
        Error(message) -> Error(classify_db_error(message))
      }
  }
}

/// Run SQL as a proxy user and return all rows.
pub fn rows_as(
  end_user: String,
  sql: String,
  on pool: Pool,
) -> Result(List(List(String)), Error) {
  rows_as_with_session_profile(end_user, sql, pool, None)
}

fn rows_as_with_session_profile(
  end_user: String,
  sql: String,
  pool: Pool,
  session_profile: Option(SessionProfile),
) -> Result(List(List(String)), Error) {
  let Pool(handle, base_user, base_password) = pool
  let proxy_user = proxy_user(base_user, end_user)
  case session_profile {
    None ->
      case internal.pool_probe_rows(handle, proxy_user, base_password, sql) {
        Ok(values) -> Ok(values)
        Error(message) -> Error(classify_db_error(message))
      }
    Some(SessionProfile(requested_tag, setup_sql)) ->
      case
        internal.pool_probe_rows_with_session(
          handle,
          proxy_user,
          base_password,
          sql,
          requested_tag,
          setup_sql,
        )
      {
        Ok(values) -> Ok(values)
        Error(message) -> Error(classify_db_error(message))
      }
  }
}

/// Read the current open and busy counts for a pool.
pub fn pool_stats(pool: Pool) -> Result(PoolStats, Error) {
  let Pool(handle, _base_user, _base_password) = pool
  case internal.pool_stats(handle) {
    Ok(#(open, busy)) -> Ok(PoolStats(open:, busy:))
    Error(message) -> Error(classify_db_error(message))
  }
}

/// Start collecting periodic trace samples for a pool.
pub fn start_trace(pool: Pool, interval_ms: Int) -> Result(Trace, Error) {
  let Pool(handle, _base_user, _base_password) = pool
  case internal.pool_trace_start(handle, interval_ms) {
    Ok(trace_handle) -> Ok(Trace(trace_handle))
    Error(message) -> Error(classify_db_error(message))
  }
}

/// Stop a running trace and return the collected samples.
pub fn stop_trace(trace: Trace) -> Result(List(TraceSample), Error) {
  let Trace(trace_handle) = trace
  case internal.pool_trace_stop(trace_handle) {
    Ok(samples) ->
      Ok(
        samples
        |> list.map(fn(sample) {
          let #(
            elapsed_ms,
            pool_open,
            pool_busy,
            writer_init_total,
            reader_init_total,
            writer_hit_total,
            reader_hit_total,
          ) = sample
          TraceSample(
            elapsed_ms:,
            pool_open:,
            pool_busy:,
            writer_init_total:,
            reader_init_total:,
            writer_hit_total:,
            reader_hit_total:,
          )
        }),
      )
    Error(message) -> Error(classify_db_error(message))
  }
}

/// Derive aggregate session affinity counters from trace samples.
pub fn session_metrics(samples: List(TraceSample)) -> SessionMetrics {
  case list.reverse(samples) {
    [
      TraceSample(
        _,
        _,
        _,
        writer_init_total,
        reader_init_total,
        writer_hit_total,
        reader_hit_total,
      ),
      ..
    ] ->
      SessionMetrics(
        writer_init_total:,
        reader_init_total:,
        writer_hit_total:,
        reader_hit_total:,
      )
    [] ->
      SessionMetrics(
        writer_init_total: 0,
        reader_init_total: 0,
        writer_hit_total: 0,
        reader_hit_total: 0,
      )
  }
}

fn proxy_user(base_user: String, end_user: String) -> String {
  base_user <> "[" <> end_user <> "]"
}

fn build_session_profile(
  session_initializer: SessionInit(option),
  option: option,
) -> SessionProfile {
  let SessionInit(tag_of, setup_sql) = session_initializer
  let raw_tag = tag_of(option)
  let requested_tag = case raw_tag == "" {
    True -> "SESSION=default"
    False -> raw_tag
  }
  SessionProfile(requested_tag:, setup_sql: setup_sql(option))
}

fn render_session_action(action: SessionAction) -> String {
  case action {
    SetClientIdentifier(value) ->
      "begin dbms_session.set_identifier('" <> sql_escape(value) <> "'); end;"
    SetClientInfo(value) ->
      "begin dbms_application_info.set_client_info('"
      <> sql_escape(value)
      <> "'); end;"
    SetModule(module, step) ->
      "begin dbms_application_info.set_module('"
      <> sql_escape(module)
      <> "', '"
      <> sql_escape(step)
      <> "'); end;"
    SetAction(step) ->
      "begin dbms_application_info.set_action('"
      <> sql_escape(step)
      <> "'); end;"
    SetNlsDateFormat(value) ->
      "alter session set nls_date_format = '" <> sql_escape(value) <> "'"
    Exec(sql) -> sql
  }
}

fn sql_escape(value: String) -> String {
  string.replace(in: value, each: "'", with: "''")
}

fn apply_scope_identity(query: Query, identity: Identity) -> Query {
  let Query(sql, params, query_identity, expectation, label) = query
  case query_identity {
    Direct -> Query(sql:, params:, identity:, expectation:, label:)
    Proxy(_) -> query
  }
}

fn render_sql(statement: String, params: List(Param)) -> Result(String, Error) {
  let parts = string.split(statement, on: "?")
  case parts {
    [] -> Ok(statement)
    [first, ..rest] ->
      case stitch_sql(first, rest, params) {
        Ok(rendered) -> Ok(rendered)
        Error(reason) -> Error(reason)
      }
  }
}

fn stitch_sql(
  acc: String,
  remaining_parts: List(String),
  remaining_params: List(Param),
) -> Result(String, Error) {
  case remaining_parts, remaining_params {
    [], [] -> Ok(acc)
    [], [_, ..] ->
      Error(QueryBuildError("too many params provided for SQL placeholders"))
    [_, ..], [] ->
      Error(QueryBuildError("not enough params provided for SQL placeholders"))
    [part, ..rest_parts], [param, ..rest_params] -> {
      let next = acc <> render_param(param) <> part
      stitch_sql(next, rest_parts, rest_params)
    }
  }
}

fn render_param(param: Param) -> String {
  case param {
    StringParam(value) ->
      "'" <> string.replace(in: value, each: "'", with: "''") <> "'"
    IntParam(value) -> int.to_string(value)
    FloatParam(value) -> float.to_string(value)
    BoolParam(value) ->
      case value {
        True -> "1"
        False -> "0"
      }
    NullParam -> "null"
  }
}
