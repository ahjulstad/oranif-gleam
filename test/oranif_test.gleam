import gleam/int
import gleam/option.{Some}
import oranif

type Person {
  Person(id: Int, name: String)
}

pub fn to_sql_renders_positional_params_test() {
  let built =
    oranif.query("insert into t (id, name, active) values (?, ?, ?)")
    |> oranif.bind_int(10)
    |> oranif.bind_string("o'hara")
    |> oranif.bind_bool(True)
    |> oranif.to_sql

  assert built
    == Ok("insert into t (id, name, active) values (10, 'o''hara', 1)")
}

pub fn to_sql_fails_for_missing_params_test() {
  let built =
    oranif.query("select * from t where id = ? and name = ?")
    |> oranif.bind_int(7)
    |> oranif.to_sql

  case built {
    Error(oranif.QueryBuildError(_)) -> Nil
    _ -> panic as "expected QueryBuildError"
  }
}

pub fn to_sql_fails_for_extra_params_test() {
  let built =
    oranif.query("select 1 from dual")
    |> oranif.bind_int(7)
    |> oranif.to_sql

  case built {
    Error(oranif.QueryBuildError(_)) -> Nil
    _ -> panic as "expected QueryBuildError"
  }
}

pub fn bind_ints_and_strings_render_in_order_test() {
  let built =
    oranif.query("select ?, ?, ?, ? from dual")
    |> oranif.bind_ints([7, 8])
    |> oranif.bind_strings(["Ada", "Lin"])
    |> oranif.to_sql

  assert built == Ok("select 7, 8, 'Ada', 'Lin' from dual")
}

pub fn bind_bools_and_floats_render_in_order_test() {
  let built =
    oranif.query("select ?, ?, ? from dual")
    |> oranif.bind_bools([True, False])
    |> oranif.bind_floats([3.5])
    |> oranif.to_sql

  assert built == Ok("select 1, 0, 3.5 from dual")
}

pub fn bind_all_accepts_mixed_param_lists_test() {
  let built =
    oranif.query("select ?, ?, ?, ? from dual")
    |> oranif.bind_all([
      oranif.int_param(7),
      oranif.string_param("Ada"),
      oranif.bool_param(True),
      oranif.null_param(),
    ])
    |> oranif.to_sql

  assert built == Ok("select 7, 'Ada', 1, null from dual")
}

pub fn query_label_is_preserved_across_builders_test() {
  let built =
    oranif.scalar_query("select ? from dual")
    |> oranif.label("health-check")
    |> oranif.bind_int(7)

  assert oranif.query_label(built) == Some("health-check")
}

pub fn inspect_query_prefixes_rendered_sql_with_label_test() {
  let built =
    oranif.query("select ? from dual")
    |> oranif.label("latest-users")
    |> oranif.bind_int(7)

  assert oranif.inspect_query(built) == Ok("[latest-users] select 7 from dual")
}

pub fn classify_db_error_maps_missing_table_test() {
  case oranif.classify_db_error("ORA-00942: table or view does not exist") {
    oranif.MissingTable(_) -> Nil
    _ -> panic as "expected MissingTable"
  }
}

pub fn classify_db_error_maps_constraint_violation_test() {
  case oranif.classify_db_error("ORA-00001: unique constraint violated") {
    oranif.ConstraintViolation(_) -> Nil
    _ -> panic as "expected ConstraintViolation"
  }
}

pub fn classify_db_error_maps_pool_timeout_test() {
  case oranif.classify_db_error("DPI-1080: connection request timeout") {
    oranif.PoolTimeout(_) -> Nil
    _ -> panic as "expected PoolTimeout"
  }
}

pub fn classify_db_error_falls_back_to_db_error_test() {
  case oranif.classify_db_error("some unexpected backend failure") {
    oranif.DbError(_) -> Nil
    _ -> panic as "expected DbError"
  }
}

pub fn int_decoder_parses_integer_test() {
  assert oranif.decode_scalar("42", using: oranif.int_decoder()) == Ok(42)
}

pub fn int_decoder_parses_whole_number_float_test() {
  assert oranif.decode_scalar("80.0", using: oranif.int_decoder()) == Ok(80)
}

pub fn bool_decoder_parses_trueish_value_test() {
  assert oranif.decode_scalar("YES", using: oranif.bool_decoder()) == Ok(True)
}

pub fn float_decoder_rejects_invalid_value_test() {
  case oranif.decode_scalar("abc", using: oranif.float_decoder()) {
    Error(oranif.DecodeError(_)) -> Nil
    _ -> panic as "expected DecodeError"
  }
}

pub fn first_int_row_decoder_reads_first_column_test() {
  assert oranif.decode_row(["42", "ignored"], using: oranif.first_int_decoder())
    == Ok(42)
}

pub fn pair_decoder_reads_two_columns_test() {
  assert oranif.decode_row(
      ["7", "Ada"],
      using: oranif.pair_decoder(
        first: oranif.int_decoder(),
        second: oranif.string_decoder(),
      ),
    )
    == Ok(#(7, "Ada"))
}

pub fn pair_decoder_rejects_short_rows_test() {
  case
    oranif.decode_row(
      ["7"],
      using: oranif.pair_decoder(
        first: oranif.int_decoder(),
        second: oranif.string_decoder(),
      ),
    )
  {
    Error(oranif.DecodeError(_)) -> Nil
    _ -> panic as "expected DecodeError"
  }
}

pub fn map_scalar_decoder_transforms_decoded_value_test() {
  let decoder =
    oranif.int_decoder() |> oranif.map_scalar_decoder(with: fn(x) { x + 1 })

  assert oranif.decode_scalar("41", using: decoder) == Ok(42)
}

pub fn triple_decoder_reads_three_columns_test() {
  assert oranif.decode_row(
      ["7", "Ada", "true"],
      using: oranif.triple_decoder(
        first: oranif.int_decoder(),
        second: oranif.string_decoder(),
        third: oranif.bool_decoder(),
      ),
    )
    == Ok(#(7, "Ada", True))
}

pub fn map_row_decoder_builds_custom_shape_test() {
  let decoder =
    oranif.pair_decoder(
      first: oranif.int_decoder(),
      second: oranif.string_decoder(),
    )
    |> oranif.map_row_decoder(with: fn(pair) {
      let #(id, name) = pair
      name <> ":" <> int.to_string(id)
    })

  assert oranif.decode_row(["7", "Ada"], using: decoder) == Ok("Ada:7")
}

pub fn decode_rows_maps_each_row_test() {
  assert oranif.decode_rows(
      [["7", "Ada"], ["8", "Lin"]],
      using: oranif.pair_decoder(
        first: oranif.int_decoder(),
        second: oranif.string_decoder(),
      ),
    )
    == Ok([#(7, "Ada"), #(8, "Lin")])
}

pub fn decode_rows_stops_on_first_decode_error_test() {
  case
    oranif.decode_rows(
      [["7", "Ada"], ["oops", "Lin"]],
      using: oranif.pair_decoder(
        first: oranif.int_decoder(),
        second: oranif.string_decoder(),
      ),
    )
  {
    Error(oranif.DecodeError(_)) -> Nil
    _ -> panic as "expected DecodeError"
  }
}

pub fn first_string_decoder_returns_first_value_test() {
  assert oranif.decode_row(
      ["Ada", "ignored"],
      using: oranif.first_string_decoder(),
    )
    == Ok("Ada")
}

pub fn first_string_decoder_returns_not_found_for_empty_row_test() {
  case oranif.decode_row([], using: oranif.first_string_decoder()) {
    Error(oranif.NotFound) -> Nil
    _ -> panic as "expected NotFound"
  }
}

pub fn decode2_builds_custom_record_test() {
  let decoder =
    oranif.decode2(
      first: oranif.int_decoder(),
      second: oranif.string_decoder(),
      with: Person,
    )

  assert oranif.decode_row(["7", "Ada"], using: decoder) == Ok(Person(7, "Ada"))
}

pub fn decode3_builds_custom_value_test() {
  let decoder =
    oranif.decode3(
      first: oranif.int_decoder(),
      second: oranif.string_decoder(),
      third: oranif.bool_decoder(),
      with: fn(id, name, active) {
        name <> ":" <> int.to_string(id) <> ":" <> string_from_bool(active)
      },
    )

  assert oranif.decode_row(["7", "Ada", "true"], using: decoder)
    == Ok("Ada:7:true")
}

fn string_from_bool(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
