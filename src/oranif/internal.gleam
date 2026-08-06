import gleam/dynamic
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
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

@external(erlang, "oranif_bridge", "pool_exec_sql_with_session")
fn pool_exec_sql_with_session_ffi(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
  requested_tag: String,
  setup_sql: List(String),
) -> Result(String, dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_probe_sql")
fn pool_probe_sql_ffi(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_probe_sql_with_session")
fn pool_probe_sql_with_session_ffi(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
  requested_tag: String,
  setup_sql: List(String),
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_probe_row")
fn pool_probe_row_ffi(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
) -> Result(List(dynamic.Dynamic), dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_probe_row_with_session")
fn pool_probe_row_with_session_ffi(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
  requested_tag: String,
  setup_sql: List(String),
) -> Result(List(dynamic.Dynamic), dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_probe_rows")
fn pool_probe_rows_ffi(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
) -> Result(List(List(dynamic.Dynamic)), dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_probe_rows_with_session")
fn pool_probe_rows_with_session_ffi(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
  requested_tag: String,
  setup_sql: List(String),
) -> Result(List(List(dynamic.Dynamic)), dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_stats")
fn pool_stats_ffi(pool: dynamic.Dynamic) -> Result(#(Int, Int), dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_trace_start")
fn pool_trace_start_ffi(
  pool: dynamic.Dynamic,
  interval_ms: Int,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "oranif_bridge", "pool_trace_stop")
fn pool_trace_stop_ffi(
  tracer: dynamic.Dynamic,
) -> Result(List(#(Int, Int, Int, Int, Int, Int, Int)), dynamic.Dynamic)

pub fn probe_user(
  host: String,
  port: Int,
  service: String,
  user: String,
  password: String,
) -> Result(String, String) {
  case
    probe_user_ffi(host, port, service, user, password, "select user from dual")
  {
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
  case
    pool_create_ffi(
      host,
      port,
      service,
      user,
      password,
      homogeneous,
      min_sessions,
      timeout_sec,
      wait_timeout_ms,
    )
  {
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

pub fn pool_exec_sql_with_session(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
  requested_tag: String,
  setup_sql: List(String),
) -> Result(Nil, String) {
  case
    pool_exec_sql_with_session_ffi(
      pool,
      user,
      password,
      sql,
      requested_tag,
      setup_sql,
    )
  {
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
    Ok(value) -> to_text(value)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_probe_sql_with_session(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
  requested_tag: String,
  setup_sql: List(String),
) -> Result(String, String) {
  case
    pool_probe_sql_with_session_ffi(
      pool,
      user,
      password,
      sql,
      requested_tag,
      setup_sql,
    )
  {
    Ok(value) -> to_text(value)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_probe_row(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
) -> Result(List(String), String) {
  case pool_probe_row_ffi(pool, user, password, sql) {
    Ok(values) -> values |> list.map(to_text) |> collect_results([])
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_probe_row_with_session(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
  requested_tag: String,
  setup_sql: List(String),
) -> Result(List(String), String) {
  case
    pool_probe_row_with_session_ffi(
      pool,
      user,
      password,
      sql,
      requested_tag,
      setup_sql,
    )
  {
    Ok(values) -> values |> list.map(to_text) |> collect_results([])
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_probe_rows(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
) -> Result(List(List(String)), String) {
  case pool_probe_rows_ffi(pool, user, password, sql) {
    Ok(rows) -> rows |> list.map(normalize_row) |> collect_row_results([])
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_probe_rows_with_session(
  pool: dynamic.Dynamic,
  user: String,
  password: String,
  sql: String,
  requested_tag: String,
  setup_sql: List(String),
) -> Result(List(List(String)), String) {
  case
    pool_probe_rows_with_session_ffi(
      pool,
      user,
      password,
      sql,
      requested_tag,
      setup_sql,
    )
  {
    Ok(rows) -> rows |> list.map(normalize_row) |> collect_row_results([])
    Error(reason) -> Error(string.inspect(reason))
  }
}

fn collect_results(
  values: List(Result(String, String)),
  acc: List(String),
) -> Result(List(String), String) {
  case values {
    [] -> Ok(list.reverse(acc))
    [Ok(value), ..rest] -> collect_results(rest, [value, ..acc])
    [Error(reason), ..] -> Error(reason)
  }
}

fn normalize_row(row: List(dynamic.Dynamic)) -> Result(List(String), String) {
  row |> list.map(to_text) |> collect_results([])
}

fn collect_row_results(
  rows: List(Result(List(String), String)),
  acc: List(List(String)),
) -> Result(List(List(String)), String) {
  case rows {
    [] -> Ok(list.reverse(acc))
    [Ok(row), ..rest] -> collect_row_results(rest, [row, ..acc])
    [Error(reason), ..] -> Error(reason)
  }
}

fn to_text(value: dynamic.Dynamic) -> Result(String, String) {
  let decoder =
    decode.one_of(decode.string, or: [
      decode.int |> decode.map(int.to_string),
      decode.float |> decode.map(float.to_string),
      decode.bool
        |> decode.map(fn(flag) {
          case flag {
            True -> "true"
            False -> "false"
          }
        }),
    ])

  case decode.run(value, decoder) {
    Ok(text) -> Ok(text)
    Error(_) -> Ok(string.inspect(value))
  }
}

pub fn pool_stats(pool: dynamic.Dynamic) -> Result(#(Int, Int), String) {
  case pool_stats_ffi(pool) {
    Ok(stats) -> Ok(stats)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_trace_start(
  pool: dynamic.Dynamic,
  interval_ms: Int,
) -> Result(dynamic.Dynamic, String) {
  case pool_trace_start_ffi(pool, interval_ms) {
    Ok(tracer) -> Ok(tracer)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pool_trace_stop(
  tracer: dynamic.Dynamic,
) -> Result(List(#(Int, Int, Int, Int, Int, Int, Int)), String) {
  case pool_trace_stop_ffi(tracer) {
    Ok(samples) -> Ok(samples)
    Error(reason) -> Error(string.inspect(reason))
  }
}
