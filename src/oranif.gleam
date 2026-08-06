import gleam/dynamic
import gleam/list
import gleam/option.{type Option, None, Some}
import oranif/internal

pub type Error {
  DbError(message: String)
}

pub fn error_message(error: Error) -> String {
  let DbError(message) = error
  message
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

pub opaque type Query {
  Query(sql: String, end_user: Option(String), scalar: Bool)
}

pub type Returned {
  Affected
  Scalar(value: String)
}

pub fn query(sql: String) -> Query {
  Query(sql:, end_user: None, scalar: False)
}

pub fn as_end_user(query: Query, end_user: String) -> Query {
  Query(..query, end_user: Some(end_user))
}

pub fn returning_scalar(query: Query) -> Query {
  Query(..query, scalar: True)
}

pub fn default_pool_config() -> PoolConfig {
  PoolConfig(min_sessions: 2, idle_timeout_sec: 30, wait_timeout_ms: 60_000, homogeneous: False)
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

pub fn idle_timeout_sec(config: PoolConfig, idle_timeout_sec: Int) -> PoolConfig {
  PoolConfig(..config, idle_timeout_sec:)
}

pub fn wait_timeout_ms(config: PoolConfig, wait_timeout_ms: Int) -> PoolConfig {
  PoolConfig(..config, wait_timeout_ms:)
}

pub fn homogeneous(config: PoolConfig, homogeneous: Bool) -> PoolConfig {
  PoolConfig(..config, homogeneous:)
}

pub fn start(config: Config) -> Result(Pool, Error) {
  let Config(host, port, service, user, password, PoolConfig(min_sessions, idle_timeout_sec, wait_timeout_ms, homogeneous)) = config
  case internal.pool_create(
    host,
    port,
    service,
    user,
    password,
    homogeneous,
    min_sessions,
    idle_timeout_sec,
    wait_timeout_ms,
  ) {
    Ok(handle) -> Ok(Pool(handle, user, password))
    Error(message) -> Error(DbError(message))
  }
}

pub fn stop(pool: Pool) -> Result(Nil, Error) {
  let Pool(handle, _base_user, _base_password) = pool
  case internal.pool_close(handle) {
    Ok(_) -> Ok(Nil)
    Error(message) -> Error(DbError(message))
  }
}

pub fn execute(sql: String, on pool: Pool) -> Result(Nil, Error) {
  let Pool(handle, base_user, base_password) = pool
  case internal.pool_exec_sql(handle, base_user, base_password, sql) {
    Ok(_) -> Ok(Nil)
    Error(message) -> Error(DbError(message))
  }
}

pub fn scalar(sql: String, on pool: Pool) -> Result(String, Error) {
  let Pool(handle, base_user, base_password) = pool
  case internal.pool_probe_sql(handle, base_user, base_password, sql) {
    Ok(value) -> Ok(value)
    Error(message) -> Error(DbError(message))
  }
}

pub fn execute_query(query: Query, on pool: Pool) -> Result(Returned, Error) {
  let Query(sql, end_user, scalar_mode) = query
  case end_user, scalar_mode {
    None, False ->
      case execute(sql, on: pool) {
        Ok(_) -> Ok(Affected)
        Error(reason) -> Error(reason)
      }
    None, True ->
      case scalar(sql, on: pool) {
        Ok(value) -> Ok(Scalar(value))
        Error(reason) -> Error(reason)
      }
    Some(end_user), False ->
      case execute_as(end_user, sql, on: pool) {
        Ok(_) -> Ok(Affected)
        Error(reason) -> Error(reason)
      }
    Some(end_user), True ->
      case scalar_as(end_user, sql, on: pool) {
        Ok(value) -> Ok(Scalar(value))
        Error(reason) -> Error(reason)
      }
  }
}

pub fn execute_as(end_user: String, sql: String, on pool: Pool) -> Result(Nil, Error) {
  let Pool(handle, base_user, base_password) = pool
  let proxy_user = proxy_user(base_user, end_user)
  case internal.pool_exec_sql(handle, proxy_user, base_password, sql) {
    Ok(_) -> Ok(Nil)
    Error(message) -> Error(DbError(message))
  }
}

pub fn scalar_as(end_user: String, sql: String, on pool: Pool) -> Result(String, Error) {
  let Pool(handle, base_user, base_password) = pool
  let proxy_user = proxy_user(base_user, end_user)
  case internal.pool_probe_sql(handle, proxy_user, base_password, sql) {
    Ok(value) -> Ok(value)
    Error(message) -> Error(DbError(message))
  }
}

pub fn pool_stats(pool: Pool) -> Result(PoolStats, Error) {
  let Pool(handle, _base_user, _base_password) = pool
  case internal.pool_stats(handle) {
    Ok(#(open, busy)) -> Ok(PoolStats(open:, busy:))
    Error(message) -> Error(DbError(message))
  }
}

pub fn start_trace(pool: Pool, interval_ms: Int) -> Result(Trace, Error) {
  let Pool(handle, _base_user, _base_password) = pool
  case internal.pool_trace_start(handle, interval_ms) {
    Ok(trace_handle) -> Ok(Trace(trace_handle))
    Error(message) -> Error(DbError(message))
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
    Error(message) -> Error(DbError(message))
  }
}

pub fn session_metrics(samples: List(TraceSample)) -> SessionMetrics {
  case list.reverse(samples) {
    [TraceSample(_, _, _, writer_init_total, reader_init_total, writer_hit_total, reader_hit_total), .._] ->
      SessionMetrics(
        writer_init_total:,
        reader_init_total:,
        writer_hit_total:,
        reader_hit_total:,
      )
    [] ->
      SessionMetrics(writer_init_total: 0, reader_init_total: 0, writer_hit_total: 0, reader_hit_total: 0)
  }
}

fn proxy_user(base_user: String, end_user: String) -> String {
  base_user <> "[" <> end_user <> "]"
}
