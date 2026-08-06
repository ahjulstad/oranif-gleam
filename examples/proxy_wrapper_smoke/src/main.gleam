import gleam/int
import gleam/io
import gleam/list
import gleam/string
import oranif

const writers = ["TP_WRITER_1", "TP_WRITER_2"]
const readers = ["TP_READER_1", "TP_READER_2", "TP_READER_3", "TP_READER_4"]

pub fn main() -> Nil {
  let config =
    oranif.default_config()
    |> oranif.host("oracle")
    |> oranif.port(1521)
    |> oranif.service("FREEPDB1")
    |> oranif.user("TP_BACKEND_APP")
    |> oranif.password("BACKENDPROXYPWD1")

  case oranif.start(config) {
    Error(error) -> io.println("pool start failed: " <> oranif.error_message(error))
    Ok(pool) -> {
      let _ = oranif.execute("drop table gleam_wrapper_smoke purge", on: pool)
      let _ = oranif.execute(
        "create table gleam_wrapper_smoke (id number primary key, payload varchar2(64), updated_at timestamp default systimestamp)",
        on: pool,
      )

      let _ = grant("insert", writers, pool)
      let _ = grant("select", readers, pool)

      let trace = oranif.start_trace(pool, 10)

      write_rows(pool, 1, 80)
      read_rows(pool, 180)

      case trace {
        Ok(handle) ->
          case oranif.stop_trace(handle) {
            Ok(samples) -> {
              let metrics = oranif.session_metrics(samples)
              io.println("session metrics=" <> string.inspect(metrics))
            }
            Error(error) -> io.println("trace stop failed: " <> oranif.error_message(error))
          }
        Error(error) -> io.println("trace start failed: " <> oranif.error_message(error))
      }

      case oranif.scalar_as("TP_READER_1", "select count(*) from TP_BACKEND_APP.gleam_wrapper_smoke", on: pool) {
        Ok(value) -> io.println("rows=" <> string.inspect(value))
        Error(error) -> io.println("count failed: " <> oranif.error_message(error))
      }

      let _ = oranif.execute("drop table gleam_wrapper_smoke purge", on: pool)
      let _ = oranif.stop(pool)
      io.println("proxy wrapper smoke complete")
    }
  }
}

fn grant(privilege: String, users: List(String), pool: oranif.Pool) -> Nil {
  case users {
    [] -> Nil
    [user, ..rest] -> {
      let sql = "grant " <> privilege <> " on gleam_wrapper_smoke to " <> user
      let _ = oranif.execute(sql, on: pool)
      grant(privilege, rest, pool)
    }
  }
}

fn write_rows(pool: oranif.Pool, next_id: Int, remaining: Int) -> Nil {
  case remaining <= 0 {
    True -> Nil
    False -> {
      let idx = next_id % list.length(writers)
      let writer = nth_or_default(writers, idx, "TP_WRITER_1")
      let sql =
        "insert into TP_BACKEND_APP.gleam_wrapper_smoke (id, payload, updated_at) values ("
        <> int.to_string(next_id)
        <> ", 'p-"
        <> int.to_string(next_id)
        <> "', systimestamp)"
      let _ = oranif.execute_as(writer, sql, on: pool)
      write_rows(pool, next_id + 1, remaining - 1)
    }
  }
}

fn read_rows(pool: oranif.Pool, remaining: Int) -> Nil {
  case remaining <= 0 {
    True -> Nil
    False -> {
      let idx = remaining % list.length(readers)
      let reader = nth_or_default(readers, idx, "TP_READER_1")
      let _ = oranif.scalar_as(
        reader,
        "select id from TP_BACKEND_APP.gleam_wrapper_smoke order by updated_at desc fetch first 20 rows only",
        on: pool,
      )
      read_rows(pool, remaining - 1)
    }
  }
}

fn nth_or_default(items: List(String), index: Int, default: String) -> String {
  case items {
    [] -> default
    [first, ..rest] ->
      case index <= 0 {
        True -> first
        False -> nth_or_default(rest, index - 1, default)
      }
  }
}
