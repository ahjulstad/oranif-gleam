import gleam/dynamic
import gleam/string

@external(erlang, "oranif_bridge", "exec_sql")
fn exec_sql_ffi(
  host: String,
  port: Int,
  service: String,
  user: String,
  password: String,
  sql: String,
) -> Result(String, dynamic.Dynamic)

@external(erlang, "oranif_bridge", "probe_user")
fn probe_user_ffi(
  host: String,
  port: Int,
  service: String,
  user: String,
  password: String,
  sql: String,
) -> Result(String, dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_create")
fn pool_create_ffi(
  host: String,
  port: Int,
  service: String,
  user: String,
  password: String,
  homogeneous: Bool,
  min_sessions: Int,
  timeout_sec: Int,
  wait_timeout_ms: Int,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_close")
fn pool_close_ffi(pool: dynamic.Dynamic) -> Result(String, dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_exec_sql")
fn pool_exec_sql_ffi(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
) -> Result(String, dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_probe_sql")
fn pool_probe_sql_ffi(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
) -> Result(String, dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_stats")
fn pool_stats_ffi(pool: dynamic.Dynamic) -> Result(#(Int, Int), dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_trace_start")
fn pool_trace_start_ffi(pool: dynamic.Dynamic, interval_ms: Int) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_trace_stop")
fn pool_trace_stop_ffi(tracer: dynamic.Dynamic) -> Result(List(#(Int, Int, Int, Int, Int, Int, Int)), dynamic.Dynamic)

pub fn probe_user(
  host: String,
  port: Int,
  service: String,
  user: String,
  password: String,
) -> Result(String, String) {
  case probe_user_ffi(host, port, service, user, password, "select user from dual") {
    Ok(value) -> Ok(value)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn probe_sql(
  host: String,
  port: Int,
  service: String,
  user: String,
  password: String,
  sql: String,
) -> Result(String, String) {
  case probe_user_ffi(host, port, service, user, password, sql) {
    Ok(value) -> Ok(value)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn exec_sql(
  host: String,
  port: Int,
  service: String,
  user: String,
  password: String,
  sql: String,
) -> Result(Nil, String) {
  case exec_sql_ffi(host, port, service, user, password, sql) {
    Ok(_) -> Ok(Nil)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_create(
  host: String,
  port: Int,
  service: String,
  user: String,
  password: String,
  homogeneous: Bool,
  min_sessions: Int,
  timeout_sec: Int,
  wait_timeout_ms: Int,
) -> Result(dynamic.Dynamic, String) {
  case pool_create_ffi(
    host,
    port,
    service,
    user,
    password,
    homogeneous,
    min_sessions,
    timeout_sec,
    wait_timeout_ms,
  ) {
    Ok(pool) -> Ok(pool)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_close(pool: dynamic.Dynamic) -> Result(Nil, String) {
  case pool_close_ffi(pool) {
    Ok(_) -> Ok(Nil)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_exec_sql(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
) -> Result(Nil, String) {
  case pool_exec_sql_ffi(pool, user, password, sql) {
    Ok(_) -> Ok(Nil)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_probe_sql(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
) -> Result(String, String) {
  case pool_probe_sql_ffi(pool, user, password, sql) {
    Ok(value) -> Ok(value)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_stats(pool: dynamic.Dynamic) -> Result(#(Int, Int), String) {
  case pool_stats_ffi(pool) {
    Ok(stats) -> Ok(stats)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_trace_start(pool: dynamic.Dynamic, interval_ms: Int) -> Result(dynamic.Dynamic, String) {
  case pool_trace_start_ffi(pool, interval_ms) {
    Ok(tracer) -> Ok(tracer)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_trace_stop(tracer: dynamic.Dynamic) -> Result(List(#(Int, Int, Int, Int, Int, Int, Int)), String) {
  case pool_trace_stop_ffi(tracer) {
    Ok(samples) -> Ok(samples)
    Error(reason) -> Error(string.inspect(reason))
  }
}
