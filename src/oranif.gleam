import gleam/dynamic
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import oranif/internal

pub type Error {
  DbError(message: String)
  MissingTable(message: String)
  ConstraintViolation(message: String)
  AuthenticationError(message: String)
  PermissionDenied(message: String)
  PoolTimeout(message: String)
  PoolExhausted(message: String)
  QueryBuildError(message: String)
  DecodeError(message: String)
  NotFound
}

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
    DecodeError(message) -> message
    NotFound -> "query returned no rows"
  }
}

pub fn classify_db_error(message: String) -> Error {
  let normalized = string.uppercase(message)
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
                  case string.contains(does: normalized, contain: "DPI-1080") {
                    True -> PoolTimeout(message)
                    False ->
                      case
                        string.contains(does: normalized, contain: "ORA-24418")
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

pub type PoolConfig {
  PoolConfig(
    min_sessions: Int,
    idle_timeout_sec: Int,
    wait_timeout_ms: Int,
    homogeneous: Bool,
  )
}

pub opaque type Pool {
  Pool(handle: dynamic.Dynamic, base_user: String, base_password: String)
}

pub opaque type Scope {
  Scope(pool: Pool, identity: Identity)
}

pub opaque type Trace {
  Trace(handle: dynamic.Dynamic)
}

pub type PoolStats {
  PoolStats(open: Int, busy: Int)
}

pub type SessionMetrics {
  SessionMetrics(
    writer_init_total: Int,
    reader_init_total: Int,
    writer_hit_total: Int,
    reader_hit_total: Int,
  )
}

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

pub type Param {
  StringParam(value: String)
  IntParam(value: Int)
  FloatParam(value: Float)
  BoolParam(value: Bool)
  NullParam
}

pub type Identity {
  Direct
  Proxy(end_user: String)
}

pub type Expectation {
  ExpectAffected
  ExpectScalar
  ExpectRow
  ExpectRows
}

pub type ScalarDecoder(a) {
  ScalarDecoder(decode: fn(String) -> Result(a, Error))
}

pub type RowDecoder(a) {
  RowDecoder(decode: fn(List(String)) -> Result(a, Error))
}

pub opaque type Query {
  Query(
    sql: String,
    params: List(Param),
    identity: Identity,
    expectation: Expectation,
  )
}

pub type QueryResult {
  Affected
  Scalar(value: String)
  Row(values: List(String))
  Rows(values: List(List(String)))
}

pub fn query(sql: String) -> Query {
  Query(sql:, params: [], identity: Direct, expectation: ExpectAffected)
}

pub fn with_param(query: Query, param: Param) -> Query {
  let Query(sql, params, identity, expectation) = query
  Query(sql:, params: list.append(params, [param]), identity:, expectation:)
}

pub fn with_params(query: Query, params: List(Param)) -> Query {
  let Query(sql, existing_params, identity, expectation) = query
  Query(
    sql:,
    params: list.append(existing_params, params),
    identity:,
    expectation:,
  )
}

pub fn bind_string(query: Query, value: String) -> Query {
  with_param(query, string_param(value))
}

pub fn bind_int(query: Query, value: Int) -> Query {
  with_param(query, int_param(value))
}

pub fn bind_float(query: Query, value: Float) -> Query {
  with_param(query, float_param(value))
}

pub fn bind_bool(query: Query, value: Bool) -> Query {
  with_param(query, bool_param(value))
}

pub fn bind_null(query: Query) -> Query {
  with_param(query, null_param())
}

pub fn as_end_user(query: Query, end_user: String) -> Query {
  as_proxy_user(query, end_user)
}

pub fn as_proxy_user(query: Query, end_user: String) -> Query {
  let Query(sql, params, _identity, expectation) = query
  Query(sql:, params:, identity: Proxy(end_user), expectation:)
}

pub fn scope(pool: Pool) -> Scope {
  Scope(pool:, identity: Direct)
}

pub fn scope_as(pool: Pool, end_user: String) -> Scope {
  Scope(pool:, identity: Proxy(end_user))
}

pub fn returning_scalar(query: Query) -> Query {
  expect_scalar(query)
}

pub fn expect_scalar(query: Query) -> Query {
  let Query(sql, params, identity, _expectation) = query
  Query(sql:, params:, identity:, expectation: ExpectScalar)
}

pub fn expect_row(query: Query) -> Query {
  let Query(sql, params, identity, _expectation) = query
  Query(sql:, params:, identity:, expectation: ExpectRow)
}

pub fn expect_rows(query: Query) -> Query {
  let Query(sql, params, identity, _expectation) = query
  Query(sql:, params:, identity:, expectation: ExpectRows)
}

pub fn expect_affected(query: Query) -> Query {
  let Query(sql, params, identity, _expectation) = query
  Query(sql:, params:, identity:, expectation: ExpectAffected)
}

pub fn string_param(value: String) -> Param {
  StringParam(value)
}

pub fn int_param(value: Int) -> Param {
  IntParam(value)
}

pub fn float_param(value: Float) -> Param {
  FloatParam(value)
}

pub fn bool_param(value: Bool) -> Param {
  BoolParam(value)
}

pub fn null_param() -> Param {
  NullParam
}

pub fn string_decoder() -> ScalarDecoder(String) {
  ScalarDecoder(fn(value) { Ok(value) })
}

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

pub fn float_decoder() -> ScalarDecoder(Float) {
  ScalarDecoder(fn(value) {
    case float.parse(value) {
      Ok(parsed) -> Ok(parsed)
      Error(_) ->
        Error(DecodeError("unable to parse float from scalar value: " <> value))
    }
  })
}

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

pub fn row_decoder(
  decode: fn(List(String)) -> Result(a, Error),
) -> RowDecoder(a) {
  RowDecoder(decode)
}

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

pub fn first_string_decoder() -> RowDecoder(String) {
  RowDecoder(fn(values) {
    case values {
      [first, ..] -> Ok(first)
      [] -> Error(NotFound)
    }
  })
}

pub fn first_int_decoder() -> RowDecoder(Int) {
  RowDecoder(fn(values) {
    case values {
      [first, ..] -> decode_scalar(first, using: int_decoder())
      [] -> Error(NotFound)
    }
  })
}

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

pub fn default_pool_config() -> PoolConfig {
  PoolConfig(
    min_sessions: 2,
    idle_timeout_sec: 30,
    wait_timeout_ms: 60_000,
    homogeneous: False,
  )
}

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

pub fn host(config: Config, host: String) -> Config {
  Config(..config, host:)
}

pub fn port(config: Config, port: Int) -> Config {
  Config(..config, port:)
}

pub fn service(config: Config, service: String) -> Config {
  Config(..config, service:)
}

pub fn user(config: Config, user: String) -> Config {
  Config(..config, user:)
}

pub fn password(config: Config, password: String) -> Config {
  Config(..config, password:)
}

pub fn pool_config(config: Config, pool: PoolConfig) -> Config {
  Config(..config, pool:)
}

pub fn min_sessions(config: PoolConfig, min_sessions: Int) -> PoolConfig {
  PoolConfig(..config, min_sessions:)
}

pub fn idle_timeout_sec(
  config: PoolConfig,
  idle_timeout_sec: Int,
) -> PoolConfig {
  PoolConfig(..config, idle_timeout_sec:)
}

pub fn wait_timeout_ms(config: PoolConfig, wait_timeout_ms: Int) -> PoolConfig {
  PoolConfig(..config, wait_timeout_ms:)
}

pub fn homogeneous(config: PoolConfig, homogeneous: Bool) -> PoolConfig {
  PoolConfig(..config, homogeneous:)
}

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

pub fn stop(pool: Pool) -> Result(Nil, Error) {
  let Pool(handle, _base_user, _base_password) = pool
  case internal.pool_close(handle) {
    Ok(_) -> Ok(Nil)
    Error(message) -> Error(classify_db_error(message))
  }
}

pub fn execute(sql: String, on pool: Pool) -> Result(Nil, Error) {
  let Pool(handle, base_user, base_password) = pool
  case internal.pool_exec_sql(handle, base_user, base_password, sql) {
    Ok(_) -> Ok(Nil)
    Error(message) -> Error(classify_db_error(message))
  }
}

pub fn scalar(sql: String, on pool: Pool) -> Result(String, Error) {
  let Pool(handle, base_user, base_password) = pool
  case internal.pool_probe_sql(handle, base_user, base_password, sql) {
    Ok(value) -> Ok(value)
    Error(message) -> Error(classify_db_error(message))
  }
}

pub fn row(sql: String, on pool: Pool) -> Result(List(String), Error) {
  let Pool(handle, base_user, base_password) = pool
  case internal.pool_probe_row(handle, base_user, base_password, sql) {
    Ok(values) -> Ok(values)
    Error(message) -> Error(classify_db_error(message))
  }
}

pub fn rows(sql: String, on pool: Pool) -> Result(List(List(String)), Error) {
  let Pool(handle, base_user, base_password) = pool
  case internal.pool_probe_rows(handle, base_user, base_password, sql) {
    Ok(values) -> Ok(values)
    Error(message) -> Error(classify_db_error(message))
  }
}

pub fn execute_query(
  query: Query,
  on pool: Pool,
) -> Result(QueryResult, Error) {
  run(query, on: pool)
}

pub fn run_in(query: Query, within scope: Scope) -> Result(QueryResult, Error) {
  let Scope(pool, identity) = scope
  run(apply_scope_identity(query, identity), on: pool)
}

pub fn run(query: Query, on pool: Pool) -> Result(QueryResult, Error) {
  let Query(sql, params, identity, expectation) = query
  case render_sql(sql, params) {
    Error(reason) -> Error(reason)
    Ok(compiled_sql) ->
      case identity, expectation {
        Direct, ExpectAffected ->
          case execute(compiled_sql, on: pool) {
            Ok(_) -> Ok(Affected)
            Error(reason) -> Error(reason)
          }
        Direct, ExpectScalar ->
          case scalar(compiled_sql, on: pool) {
            Ok(value) -> Ok(Scalar(value))
            Error(reason) -> Error(reason)
          }
        Direct, ExpectRow ->
          case row(compiled_sql, on: pool) {
            Ok(values) -> Ok(Row(values))
            Error(reason) -> Error(reason)
          }
        Direct, ExpectRows ->
          case rows(compiled_sql, on: pool) {
            Ok(values) -> Ok(Rows(values))
            Error(reason) -> Error(reason)
          }
        Proxy(end_user), ExpectAffected ->
          case execute_as(end_user, compiled_sql, on: pool) {
            Ok(_) -> Ok(Affected)
            Error(reason) -> Error(reason)
          }
        Proxy(end_user), ExpectScalar ->
          case scalar_as(end_user, compiled_sql, on: pool) {
            Ok(value) -> Ok(Scalar(value))
            Error(reason) -> Error(reason)
          }
        Proxy(end_user), ExpectRow ->
          case row_as(end_user, compiled_sql, on: pool) {
            Ok(values) -> Ok(Row(values))
            Error(reason) -> Error(reason)
          }
        Proxy(end_user), ExpectRows ->
          case rows_as(end_user, compiled_sql, on: pool) {
            Ok(values) -> Ok(Rows(values))
            Error(reason) -> Error(reason)
          }
      }
  }
}

pub fn run_affected(query: Query, on pool: Pool) -> Result(Nil, Error) {
  case run(expect_affected(query), on: pool) {
    Ok(Affected) -> Ok(Nil)
    Ok(Scalar(_)) -> Error(DecodeError("expected affected rows result"))
    Ok(Row(_)) -> Error(DecodeError("expected affected rows result"))
    Ok(Rows(_)) -> Error(DecodeError("expected affected rows result"))
    Error(reason) -> Error(reason)
  }
}

pub fn run_affected_in(
  query: Query,
  within scope: Scope,
) -> Result(Nil, Error) {
  let Scope(pool, identity) = scope
  run_affected(apply_scope_identity(query, identity), on: pool)
}

pub fn run_scalar(query: Query, on pool: Pool) -> Result(String, Error) {
  case run(expect_scalar(query), on: pool) {
    Ok(Scalar(value)) -> Ok(value)
    Ok(Affected) -> Error(DecodeError("expected scalar result"))
    Ok(Row(_)) -> Error(DecodeError("expected scalar result"))
    Ok(Rows(_)) -> Error(DecodeError("expected scalar result"))
    Error(reason) -> Error(reason)
  }
}

pub fn run_scalar_in(
  query: Query,
  within scope: Scope,
) -> Result(String, Error) {
  let Scope(pool, identity) = scope
  run_scalar(apply_scope_identity(query, identity), on: pool)
}

pub fn run_row(query: Query, on pool: Pool) -> Result(List(String), Error) {
  case run(expect_row(query), on: pool) {
    Ok(Row(values)) -> Ok(values)
    Ok(Affected) -> Error(DecodeError("expected row result"))
    Ok(Scalar(_)) -> Error(DecodeError("expected row result"))
    Ok(Rows(_)) -> Error(DecodeError("expected row result"))
    Error(reason) -> Error(reason)
  }
}

pub fn run_row_in(
  query: Query,
  within scope: Scope,
) -> Result(List(String), Error) {
  let Scope(pool, identity) = scope
  run_row(apply_scope_identity(query, identity), on: pool)
}

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

pub fn run_rows_in(
  query: Query,
  within scope: Scope,
) -> Result(List(List(String)), Error) {
  let Scope(pool, identity) = scope
  run_rows(apply_scope_identity(query, identity), on: pool)
}

pub fn decode_scalar(
  value: String,
  using decoder: ScalarDecoder(a),
) -> Result(a, Error) {
  let ScalarDecoder(decode) = decoder
  decode(value)
}

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

pub fn run_decode_in(
  query: Query,
  within scope: Scope,
  using decoder: ScalarDecoder(a),
) -> Result(a, Error) {
  let Scope(pool, identity) = scope
  run_decode(apply_scope_identity(query, identity), on: pool, using: decoder)
}

pub fn decode_row(
  values: List(String),
  using decoder: RowDecoder(a),
) -> Result(a, Error) {
  let RowDecoder(decode) = decoder
  decode(values)
}

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

pub fn run_decode_row_in(
  query: Query,
  within scope: Scope,
  using decoder: RowDecoder(a),
) -> Result(a, Error) {
  let Scope(pool, identity) = scope
  run_decode_row(
    apply_scope_identity(query, identity),
    on: pool,
    using: decoder,
  )
}

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

pub fn run_decode_rows_in(
  query: Query,
  within scope: Scope,
  using decoder: RowDecoder(a),
) -> Result(List(a), Error) {
  let Scope(pool, identity) = scope
  run_decode_rows(
    apply_scope_identity(query, identity),
    on: pool,
    using: decoder,
  )
}

pub fn run_scalar_int(query: Query, on pool: Pool) -> Result(Int, Error) {
  run_decode(query, on: pool, using: int_decoder())
}

pub fn run_scalar_int_in(
  query: Query,
  within scope: Scope,
) -> Result(Int, Error) {
  run_decode_in(query, within: scope, using: int_decoder())
}

pub fn run_scalar_float(query: Query, on pool: Pool) -> Result(Float, Error) {
  run_decode(query, on: pool, using: float_decoder())
}

pub fn run_scalar_float_in(
  query: Query,
  within scope: Scope,
) -> Result(Float, Error) {
  run_decode_in(query, within: scope, using: float_decoder())
}

pub fn run_scalar_bool(query: Query, on pool: Pool) -> Result(Bool, Error) {
  run_decode(query, on: pool, using: bool_decoder())
}

pub fn run_scalar_bool_in(
  query: Query,
  within scope: Scope,
) -> Result(Bool, Error) {
  run_decode_in(query, within: scope, using: bool_decoder())
}

pub fn to_sql(query: Query) -> Result(String, Error) {
  let Query(sql, params, _identity, _expectation) = query
  render_sql(sql, params)
}

pub fn execute_as(
  end_user: String,
  sql: String,
  on pool: Pool,
) -> Result(Nil, Error) {
  let Pool(handle, base_user, base_password) = pool
  let proxy_user = proxy_user(base_user, end_user)
  case internal.pool_exec_sql(handle, proxy_user, base_password, sql) {
    Ok(_) -> Ok(Nil)
    Error(message) -> Error(classify_db_error(message))
  }
}

pub fn scalar_as(
  end_user: String,
  sql: String,
  on pool: Pool,
) -> Result(String, Error) {
  let Pool(handle, base_user, base_password) = pool
  let proxy_user = proxy_user(base_user, end_user)
  case internal.pool_probe_sql(handle, proxy_user, base_password, sql) {
    Ok(value) -> Ok(value)
    Error(message) -> Error(classify_db_error(message))
  }
}

pub fn row_as(
  end_user: String,
  sql: String,
  on pool: Pool,
) -> Result(List(String), Error) {
  let Pool(handle, base_user, base_password) = pool
  let proxy_user = proxy_user(base_user, end_user)
  case internal.pool_probe_row(handle, proxy_user, base_password, sql) {
    Ok(values) -> Ok(values)
    Error(message) -> Error(classify_db_error(message))
  }
}

pub fn rows_as(
  end_user: String,
  sql: String,
  on pool: Pool,
) -> Result(List(List(String)), Error) {
  let Pool(handle, base_user, base_password) = pool
  let proxy_user = proxy_user(base_user, end_user)
  case internal.pool_probe_rows(handle, proxy_user, base_password, sql) {
    Ok(values) -> Ok(values)
    Error(message) -> Error(classify_db_error(message))
  }
}

pub fn pool_stats(pool: Pool) -> Result(PoolStats, Error) {
  let Pool(handle, _base_user, _base_password) = pool
  case internal.pool_stats(handle) {
    Ok(#(open, busy)) -> Ok(PoolStats(open:, busy:))
    Error(message) -> Error(classify_db_error(message))
  }
}

pub fn start_trace(pool: Pool, interval_ms: Int) -> Result(Trace, Error) {
  let Pool(handle, _base_user, _base_password) = pool
  case internal.pool_trace_start(handle, interval_ms) {
    Ok(trace_handle) -> Ok(Trace(trace_handle))
    Error(message) -> Error(classify_db_error(message))
  }
}

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

fn apply_scope_identity(query: Query, identity: Identity) -> Query {
  let Query(sql, params, query_identity, expectation) = query
  case query_identity {
    Direct -> Query(sql:, params:, identity:, expectation:)
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
