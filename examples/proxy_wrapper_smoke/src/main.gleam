import gleam/int
import gleam/io
import gleam/list
import gleam/string
import oranif

const writers = ["TP_WRITER_1", "TP_WRITER_2"]

const readers = ["TP_READER_1", "TP_READER_2", "TP_READER_3", "TP_READER_4"]

type SessionOption {
  SessionOption(tag: String, module: String)
}

pub fn main() -> Nil {
  let config =
    oranif.default_config()
    |> oranif.host("oracle")
    |> oranif.port(1521)
    |> oranif.service("FREEPDB1")
    |> oranif.user("TP_BACKEND_APP")
    |> oranif.password("BACKENDPROXYPWD1")

  case oranif.start(config) {
    Error(error) ->
      io.println("pool start failed: " <> oranif.error_message(error))
    Ok(pool) -> {
      let _ = oranif.execute("drop table gleam_wrapper_smoke purge", on: pool)
      let _ =
        oranif.execute(
          "create table gleam_wrapper_smoke (id number primary key, payload varchar2(64), updated_at timestamp default systimestamp)",
          on: pool,
        )

      let _ = grant("insert", writers, pool)
      let _ = grant("select", readers, pool)
      let reader_scope = oranif.scope_as(pool, "TP_READER_1")

      run_tagged_session_smoke(pool)

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
            Error(error) ->
              io.println("trace stop failed: " <> oranif.error_message(error))
          }
        Error(error) ->
          io.println("trace start failed: " <> oranif.error_message(error))
      }

      case
        oranif.scalar_query(
          "select count(*) from TP_BACKEND_APP.gleam_wrapper_smoke",
        )
        |> oranif.scalar_as_type_in(
          within: reader_scope,
          using: oranif.int_decoder(),
        )
      {
        Ok(value) -> io.println("rows=" <> string.inspect(value))
        Error(error) ->
          io.println("count failed: " <> oranif.error_message(error))
      }

      case
        oranif.rows_query(
          "select id from TP_BACKEND_APP.gleam_wrapper_smoke order by updated_at desc fetch first 3 rows only",
        )
        |> oranif.all_in(
          within: reader_scope,
          using: oranif.first_int_decoder(),
        )
      {
        Ok(values) -> io.println("latest_ids=" <> format_ints(values))
        Error(error) ->
          io.println("latest ids failed: " <> oranif.error_message(error))
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
      let _ = oranif.query(sql) |> oranif.run_affected(on: pool)
      grant(privilege, rest, pool)
    }
  }
}

fn write_rows(pool: oranif.Pool, next_id: Int, remaining: Int) -> Nil {
  case remaining <= 0 {
    True -> Nil
    False -> {
      let idx = next_id % list.length(writers)
      let writer_scope =
        oranif.scope_as(pool, nth_or_default(writers, idx, "TP_WRITER_1"))
      let sql =
        oranif.command(
          "insert into TP_BACKEND_APP.gleam_wrapper_smoke (id, payload, updated_at) values (?, ?, systimestamp)",
        )
        |> oranif.bind_int(next_id)
        |> oranif.bind_string("p-" <> int.to_string(next_id))
      let _ = oranif.exec_in(sql, within: writer_scope)
      write_rows(pool, next_id + 1, remaining - 1)
    }
  }
}

fn read_rows(pool: oranif.Pool, remaining: Int) -> Nil {
  case remaining <= 0 {
    True -> Nil
    False -> {
      let idx = remaining % list.length(readers)
      let reader_scope =
        oranif.scope_as(pool, nth_or_default(readers, idx, "TP_READER_1"))
      let _ =
        oranif.rows_query(
          "select id from TP_BACKEND_APP.gleam_wrapper_smoke order by updated_at desc fetch first 20 rows only",
        )
        |> oranif.all_in(
          within: reader_scope,
          using: oranif.first_int_decoder(),
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

fn format_ints(values: List(Int)) -> String {
  "[" <> string.join(list.map(values, int.to_string), with: ",") <> "]"
}

fn run_tagged_session_smoke(pool: oranif.Pool) -> Nil {
  let initializer =
    oranif.session_init(
      fn(option) {
        let SessionOption(tag, _module) = option
        "SESSION=" <> tag
      },
      fn(option) {
        let SessionOption(_tag, module) = option
        [
          oranif.SetModule(module, "SESSION_INIT"),
        ]
      },
    )
  let prepared = oranif.prepare_pool(pool, with: initializer)
  let scope_a =
    oranif.scope_as_with(
      prepared,
      "TP_READER_1",
      SessionOption(tag: "A", module: "SESSION_A"),
    )
  let scope_a_again =
    oranif.scope_as_with(
      prepared,
      "TP_READER_1",
      SessionOption(tag: "A", module: "SESSION_A"),
    )
  let scope_b =
    oranif.scope_as_with(
      prepared,
      "TP_READER_1",
      SessionOption(tag: "B", module: "SESSION_B"),
    )

  let trace = case oranif.start_trace(pool, 5) {
    Ok(handle) -> handle
    Error(error) -> {
      io.println("tagged trace start failed: " <> oranif.error_message(error))
      panic as "tagged trace start failed"
    }
  }

  assert_module(scope_a, "SESSION_A")
  assert_module(scope_a_again, "SESSION_A")
  assert_module(scope_b, "SESSION_B")

  let samples = case oranif.stop_trace(trace) {
    Ok(samples) -> samples
    Error(error) -> {
      io.println("tagged trace stop failed: " <> oranif.error_message(error))
      panic as "tagged trace stop failed"
    }
  }
  let #(reader_init_delta, reader_hit_delta) = reader_metrics_delta(samples)

  let total_events = reader_init_delta + reader_hit_delta

  case total_events == 3 && reader_init_delta >= 2 && reader_init_delta <= 3 {
    True ->
      io.println(
        "tagged session deltas=init:"
        <> int.to_string(reader_init_delta)
        <> ",hit:"
        <> int.to_string(reader_hit_delta),
      )
    False -> {
      io.println(
        "expected tagged transitions across three probes, got init="
        <> int.to_string(reader_init_delta)
        <> " hit="
        <> int.to_string(reader_hit_delta),
      )
      panic as "tagged init/hit transition assertion failed"
    }
  }
}

fn assert_module(scope: oranif.Scope, expected: String) -> Nil {
  let actual = case
    oranif.scalar_query("select sys_context('USERENV','MODULE') from dual")
    |> oranif.run_scalar_in(within: scope)
  {
    Ok(module) -> module
    Error(error) -> {
      io.println("module probe failed: " <> oranif.error_message(error))
      panic as "module probe failed"
    }
  }

  case actual == expected {
    True -> Nil
    False -> {
      io.println("expected module " <> expected <> " but got " <> actual)
      panic as "module assertion failed"
    }
  }
}

fn reader_metrics_delta(samples: List(oranif.TraceSample)) -> #(Int, Int) {
  case samples {
    [] -> #(0, 0)
    [first, ..] -> {
      let last = case list.reverse(samples) {
        [value, ..] -> value
        [] -> first
      }
      let oranif.TraceSample(_, _, _, _, first_reader_init, _, first_reader_hit) =
        first
      let oranif.TraceSample(_, _, _, _, last_reader_init, _, last_reader_hit) =
        last
      #(
        last_reader_init - first_reader_init,
        last_reader_hit - first_reader_hit,
      )
    }
  }
}
