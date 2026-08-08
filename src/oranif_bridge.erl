-module(oranif_bridge).

-export([
    load/0,
    exec_sql/6,
    probe_user/6,
    probe_user_once/6,
    probe_sql_external_auth/2,
    pool_create/10,
    pool_close/1,
    pool_exec_sql/5,
    pool_exec_sql_with_session/7,
    pool_exec_sql_metric/4,
    pool_probe_sql/5,
    pool_probe_sql_with_session/7,
    pool_probe_row/5,
    pool_probe_row_with_session/7,
    pool_probe_rows/5,
    pool_probe_rows_with_session/7,
    pool_probe_sql_metric/4,
    pool_probe_burst_metric/5,
    pool_probe_burst_metric_hold/6,
    pool_stats/1,
    pool_trace_start/2,
    pool_trace_stop/1,
    pool_session_metrics/0
]).

-define(DPI_MAJOR_VERSION, 5).
-define(DPI_MINOR_VERSION, 0).

load() ->
    dpi:load_unsafe().

exec_sql(Host, Port, Service, User, Password, Sql)
    when is_binary(Host),
         is_integer(Port),
         is_binary(Service),
         is_binary(User),
         is_binary(Password),
         is_binary(Sql) ->
    case ensure_loaded() of
        ok ->
            case catch dpi:context_create(?DPI_MAJOR_VERSION, ?DPI_MINOR_VERSION) of
                Context when is_reference(Context) ->
                    ConnectString = tns(Host, Port, Service),
                    CommonParams = #{encoding => "AL32UTF8", nencoding => "AL32UTF8"},
                    case dpi:conn_create(Context, User, Password, ConnectString, CommonParams, #{}) of
                        Conn when is_reference(Conn) ->
                            Result = execute_no_fetch(Conn, Sql),
                            _ = safe_conn_close(Conn),
                            _ = safe_context_destroy(Context),
                            Result;
                        Error ->
                            _ = safe_context_destroy(Context),
                            {error, Error}
                    end;
                {'EXIT', Reason} ->
                    {error, {context_create_failed, Reason}};
                Other ->
                    {error, {context_create_failed, Other}}
            end;
        Error ->
            Error
    end.

probe_user(Host, Port, Service, User, Password, Sql) ->
    probe_user_once(Host, Port, Service, User, Password, Sql).

pool_create(Host, Port, Service, User, Password, ExternalAuth, Homogeneous, MinSessions, TimeoutSec, WaitTimeoutMs)
    when is_binary(Host),
         is_integer(Port),
         is_binary(Service),
         is_binary(User),
         is_binary(Password),
         is_boolean(ExternalAuth),
         is_boolean(Homogeneous),
         is_integer(MinSessions),
         is_integer(TimeoutSec),
         is_integer(WaitTimeoutMs) ->
    case ensure_loaded() of
        ok ->
            case catch dpi:context_create(?DPI_MAJOR_VERSION, ?DPI_MINOR_VERSION) of
                Context when is_reference(Context) ->
                    ConnectString = tns(Host, Port, Service),
                    CommonParams = #{encoding => "AL32UTF8", nencoding => "AL32UTF8"},
                    PoolParams = #{
                        min_sessions => MinSessions,
                        max_sessions => 50,
                        session_increment => 1,
                        homogeneous => Homogeneous,
                        external_auth => ExternalAuth,
                        get_mode => 'DPI_MODE_POOL_GET_WAIT',
                        timeout => TimeoutSec,
                        wait_timeout => WaitTimeoutMs
                    },
                    {UserArg, PasswordArg} = case ExternalAuth of
                        true -> {null, null};
                        false -> {User, Password}
                    end,
                    case dpi:pool_create(Context, UserArg, PasswordArg, ConnectString, CommonParams, PoolParams) of
                        Pool when is_reference(Pool) ->
                            _ = init_pool_metrics_table(),
                            {ok, {Context, Pool}};
                        Error ->
                            _ = safe_context_destroy(Context),
                            {error, {pool_create_failed, Error}}
                    end;
                {'EXIT', Reason} ->
                    {error, {context_create_failed, Reason}};
                Other ->
                    {error, {context_create_failed, Other}}
            end;
        Error ->
            Error
    end.

pool_close({Context, Pool}) when is_reference(Context), is_reference(Pool) ->
    _ = catch dpi:pool_close(Pool, []),
    _ = safe_context_destroy(Context),
    {ok, ok};
pool_close(Other) ->
    {error, {invalid_pool_handle, Other}}.

pool_exec_sql({Context, Pool}, ExternalAuth, AcquireUser, AcquirePassword, Sql)
    when is_reference(Context),
         is_reference(Pool),
         is_boolean(ExternalAuth),
         is_binary(AcquireUser),
         is_binary(AcquirePassword),
         is_binary(Sql) ->
    {AcquireUserArg, AcquirePasswordArg} = case ExternalAuth of
        true -> {AcquireUser, null};
        false -> {AcquireUser, AcquirePassword}
    end,
    case with_pool_connection(Pool, AcquireUserArg, AcquirePasswordArg, fun(Conn) ->
        execute_no_fetch(Conn, Sql)
    end, undefined, []) of
        {ok, Result, _BusySample} ->
            Result;
        {error, _} = Error ->
            Error
    end;
pool_exec_sql(Other, _ExternalAuth, _AcquireUser, _AcquirePassword, _Sql) ->
    {error, {invalid_pool_handle, Other}}.

pool_exec_sql_with_session({Context, Pool}, ExternalAuth, AcquireUser, AcquirePassword, Sql, RequestedTag, SetupSql)
    when is_reference(Context),
         is_reference(Pool),
         is_boolean(ExternalAuth),
         is_binary(AcquireUser),
         is_binary(AcquirePassword),
         is_binary(Sql),
         is_binary(RequestedTag),
         is_list(SetupSql) ->
    {AcquireUserArg, AcquirePasswordArg} = case ExternalAuth of
        true -> {AcquireUser, null};
        false -> {AcquireUser, AcquirePassword}
    end,
    case with_pool_connection(Pool, AcquireUserArg, AcquirePasswordArg, fun(Conn) ->
        execute_no_fetch(Conn, Sql)
    end, RequestedTag, SetupSql) of
        {ok, Result, _BusySample} ->
            Result;
        {error, _} = Error ->
            Error
    end;
pool_exec_sql_with_session(Other, _ExternalAuth, _AcquireUser, _AcquirePassword, _Sql, _RequestedTag, _SetupSql) ->
    {error, {invalid_pool_handle, Other}}.

pool_exec_sql_metric({Context, Pool}, AcquireUser, AcquirePassword, Sql)
    when is_reference(Context),
         is_reference(Pool),
         is_binary(AcquireUser),
         is_binary(AcquirePassword),
         is_binary(Sql) ->
    case with_pool_connection(Pool, AcquireUser, AcquirePassword, fun(Conn) ->
        execute_no_fetch(Conn, Sql)
    end, undefined, []) of
        {ok, {ok, _Value}, BusySample} ->
            {ok, BusySample};
        {ok, {error, _} = Error, _BusySample} ->
            Error;
        {error, _} = Error ->
            Error
    end;
pool_exec_sql_metric(Other, _AcquireUser, _AcquirePassword, _Sql) ->
    {error, {invalid_pool_handle, Other}}.

pool_probe_sql({Context, Pool}, ExternalAuth, AcquireUser, AcquirePassword, Sql)
    when is_reference(Context),
         is_reference(Pool),
         is_boolean(ExternalAuth),
         is_binary(AcquireUser),
         is_binary(AcquirePassword),
         is_binary(Sql) ->
    {AcquireUserArg, AcquirePasswordArg} = case ExternalAuth of
        true -> {AcquireUser, null};
        false -> {AcquireUser, AcquirePassword}
    end,
    case with_pool_connection(Pool, AcquireUserArg, AcquirePasswordArg, fun(Conn) ->
        execute_and_fetch_first(Conn, Sql)
    end, undefined, []) of
        {ok, Result, _BusySample} ->
            Result;
        {error, _} = Error ->
            Error
    end;
pool_probe_sql(Other, _ExternalAuth, _AcquireUser, _AcquirePassword, _Sql) ->
    {error, {invalid_pool_handle, Other}}.

pool_probe_sql_with_session({Context, Pool}, ExternalAuth, AcquireUser, AcquirePassword, Sql, RequestedTag, SetupSql)
    when is_reference(Context),
         is_reference(Pool),
         is_boolean(ExternalAuth),
         is_binary(AcquireUser),
         is_binary(AcquirePassword),
         is_binary(Sql),
         is_binary(RequestedTag),
         is_list(SetupSql) ->
    {AcquireUserArg, AcquirePasswordArg} = case ExternalAuth of
        true -> {AcquireUser, null};
        false -> {AcquireUser, AcquirePassword}
    end,
    case with_pool_connection(Pool, AcquireUserArg, AcquirePasswordArg, fun(Conn) ->
        execute_and_fetch_first(Conn, Sql)
    end, RequestedTag, SetupSql) of
        {ok, Result, _BusySample} ->
            Result;
        {error, _} = Error ->
            Error
    end;
pool_probe_sql_with_session(Other, _ExternalAuth, _AcquireUser, _AcquirePassword, _Sql, _RequestedTag, _SetupSql) ->
    {error, {invalid_pool_handle, Other}}.

pool_probe_row({Context, Pool}, ExternalAuth, AcquireUser, AcquirePassword, Sql)
    when is_reference(Context),
         is_reference(Pool),
         is_boolean(ExternalAuth),
         is_binary(AcquireUser),
         is_binary(AcquirePassword),
         is_binary(Sql) ->
    {AcquireUserArg, AcquirePasswordArg} = case ExternalAuth of
        true -> {AcquireUser, null};
        false -> {AcquireUser, AcquirePassword}
    end,
    case with_pool_connection(Pool, AcquireUserArg, AcquirePasswordArg, fun(Conn) ->
        execute_and_fetch_row(Conn, Sql)
    end, undefined, []) of
        {ok, Result, _BusySample} ->
            Result;
        {error, _} = Error ->
            Error
    end;
pool_probe_row(Other, _ExternalAuth, _AcquireUser, _AcquirePassword, _Sql) ->
    {error, {invalid_pool_handle, Other}}.

pool_probe_row_with_session({Context, Pool}, ExternalAuth, AcquireUser, AcquirePassword, Sql, RequestedTag, SetupSql)
    when is_reference(Context),
         is_reference(Pool),
         is_boolean(ExternalAuth),
         is_binary(AcquireUser),
         is_binary(AcquirePassword),
         is_binary(Sql),
         is_binary(RequestedTag),
         is_list(SetupSql) ->
    {AcquireUserArg, AcquirePasswordArg} = case ExternalAuth of
        true -> {AcquireUser, null};
        false -> {AcquireUser, AcquirePassword}
    end,
    case with_pool_connection(Pool, AcquireUserArg, AcquirePasswordArg, fun(Conn) ->
        execute_and_fetch_row(Conn, Sql)
    end, RequestedTag, SetupSql) of
        {ok, Result, _BusySample} ->
            Result;
        {error, _} = Error ->
            Error
    end;
pool_probe_row_with_session(Other, _ExternalAuth, _AcquireUser, _AcquirePassword, _Sql, _RequestedTag, _SetupSql) ->
    {error, {invalid_pool_handle, Other}}.

pool_probe_rows({Context, Pool}, ExternalAuth, AcquireUser, AcquirePassword, Sql)
    when is_reference(Context),
         is_reference(Pool),
         is_boolean(ExternalAuth),
         is_binary(AcquireUser),
         is_binary(AcquirePassword),
         is_binary(Sql) ->
    {AcquireUserArg, AcquirePasswordArg} = case ExternalAuth of
        true -> {AcquireUser, null};
        false -> {AcquireUser, AcquirePassword}
    end,
    case with_pool_connection(Pool, AcquireUserArg, AcquirePasswordArg, fun(Conn) ->
        execute_and_fetch_rows(Conn, Sql)
    end, undefined, []) of
        {ok, Result, _BusySample} ->
            Result;
        {error, _} = Error ->
            Error
    end;
pool_probe_rows(Other, _ExternalAuth, _AcquireUser, _AcquirePassword, _Sql) ->
    {error, {invalid_pool_handle, Other}}.

pool_probe_rows_with_session({Context, Pool}, ExternalAuth, AcquireUser, AcquirePassword, Sql, RequestedTag, SetupSql)
    when is_reference(Context),
         is_reference(Pool),
         is_boolean(ExternalAuth),
         is_binary(AcquireUser),
         is_binary(AcquirePassword),
         is_binary(Sql),
         is_binary(RequestedTag),
         is_list(SetupSql) ->
    {AcquireUserArg, AcquirePasswordArg} = case ExternalAuth of
        true -> {AcquireUser, null};
        false -> {AcquireUser, AcquirePassword}
    end,
    case with_pool_connection(Pool, AcquireUserArg, AcquirePasswordArg, fun(Conn) ->
        execute_and_fetch_rows(Conn, Sql)
    end, RequestedTag, SetupSql) of
        {ok, Result, _BusySample} ->
            Result;
        {error, _} = Error ->
            Error
    end;
pool_probe_rows_with_session(Other, _ExternalAuth, _AcquireUser, _AcquirePassword, _Sql, _RequestedTag, _SetupSql) ->
    {error, {invalid_pool_handle, Other}}.

pool_probe_sql_metric({Context, Pool}, AcquireUser, AcquirePassword, Sql)
    when is_reference(Context),
         is_reference(Pool),
         is_binary(AcquireUser),
         is_binary(AcquirePassword),
         is_binary(Sql) ->
    case with_pool_connection(Pool, AcquireUser, AcquirePassword, fun(Conn) ->
        execute_and_fetch_first(Conn, Sql)
    end, undefined, []) of
        {ok, {ok, Value}, BusySample} ->
            {ok, {Value, BusySample}};
        {ok, {error, _} = Error, _BusySample} ->
            Error;
        {error, _} = Error ->
            Error
    end;
pool_probe_sql_metric(Other, _AcquireUser, _AcquirePassword, _Sql) ->
    {error, {invalid_pool_handle, Other}}.

pool_probe_burst_metric({Context, Pool}, AcquireUsers, AcquirePassword, Sql, Count)
    when is_reference(Context),
         is_reference(Pool),
         is_list(AcquireUsers),
         is_binary(AcquirePassword),
         is_binary(Sql),
         is_integer(Count),
         Count >= 0 ->
    case valid_binary_list(AcquireUsers) of
        true ->
            case {AcquireUsers, Count} of
                {[], _} ->
                    {ok, {0, 0}};
                {_, 0} ->
                    {ok, {0, 0}};
                _ ->
                    do_pool_probe_burst_metric(Pool, AcquireUsers, AcquirePassword, Sql, Count)
            end;
        false ->
            {error, {invalid_users, AcquireUsers}}
    end;
pool_probe_burst_metric(Other, _AcquireUsers, _AcquirePassword, _Sql, _Count) ->
    {error, {invalid_pool_handle, Other}}.

pool_probe_burst_metric_hold({Context, Pool}, AcquireUsers, AcquirePassword, Sql, Count, HoldMs)
    when is_reference(Context),
         is_reference(Pool),
         is_list(AcquireUsers),
         is_binary(AcquirePassword),
         is_binary(Sql),
         is_integer(Count),
         Count >= 0,
         is_integer(HoldMs),
         HoldMs >= 0 ->
    case valid_binary_list(AcquireUsers) of
        true ->
            case {AcquireUsers, Count} of
                {[], _} ->
                    {ok, {0, 0}};
                {_, 0} ->
                    {ok, {0, 0}};
                _ ->
                    do_pool_probe_burst_metric(Pool, AcquireUsers, AcquirePassword, Sql, Count, HoldMs)
            end;
        false ->
            {error, {invalid_users, AcquireUsers}}
    end;
pool_probe_burst_metric_hold(Other, _AcquireUsers, _AcquirePassword, _Sql, _Count, _HoldMs) ->
    {error, {invalid_pool_handle, Other}}.

pool_stats({Context, Pool}) when is_reference(Context), is_reference(Pool) ->
    try
        {ok, {dpi:pool_getOpenCount(Pool), dpi:pool_getBusyCount(Pool)}}
    catch
        Class:Reason -> {error, {pool_stats_failed, {Class, Reason}}}
    end;
pool_stats(Other) ->
    {error, {invalid_pool_handle, Other}}.

pool_trace_start({Context, Pool}, IntervalMs)
    when is_reference(Context),
         is_reference(Pool),
         is_integer(IntervalMs),
         IntervalMs > 0 ->
    StartMs = erlang:monotonic_time(millisecond),
    TracerPid = spawn_link(fun() ->
        pool_trace_loop(Pool, StartMs, IntervalMs, [])
    end),
    {ok, TracerPid};
pool_trace_start(Other, _IntervalMs) ->
    {error, {invalid_pool_handle, Other}}.

pool_trace_stop(TracerPid) when is_pid(TracerPid) ->
    TracerPid ! {stop, self()},
    receive
        {pool_trace_stopped, Samples} -> {ok, Samples}
    after 5000 ->
        {error, pool_trace_stop_timeout}
    end;
pool_trace_stop(Other) ->
    {error, {invalid_tracer_pid, Other}}.

pool_session_metrics() ->
    {ok, pool_metrics_snapshot()}.

probe_user_once(Host, Port, Service, User, Password, Sql)
    when is_binary(Host),
         is_integer(Port),
         is_binary(Service),
         is_binary(User),
         is_binary(Password),
         is_binary(Sql) ->
    case ensure_loaded() of
        ok ->
            case catch dpi:context_create(?DPI_MAJOR_VERSION, ?DPI_MINOR_VERSION) of
                Context when is_reference(Context) ->
                    ConnectString = tns(Host, Port, Service),
                    CommonParams = #{encoding => "AL32UTF8", nencoding => "AL32UTF8"},
                    case dpi:conn_create(Context, User, Password, ConnectString, CommonParams, #{}) of
                        Conn when is_reference(Conn) ->
                            Result = execute_and_fetch_first(Conn, Sql),
                            _ = safe_conn_close(Conn),
                            _ = safe_context_destroy(Context),
                            Result;
                        Error ->
                            _ = safe_context_destroy(Context),
                            {error, Error}
                    end;
                {'EXIT', Reason} ->
                    {error, {context_create_failed, Reason}};
                Other ->
                    {error, {context_create_failed, Other}}
            end;
        Error ->
            Error
    end.

probe_sql_external_auth(Dsn, Sql)
    when is_binary(Dsn),
         is_binary(Sql) ->
    case ensure_loaded() of
        ok ->
            case catch dpi:context_create(?DPI_MAJOR_VERSION, ?DPI_MINOR_VERSION) of
                Context when is_reference(Context) ->
                    CommonParams = #{encoding => "AL32UTF8", nencoding => "AL32UTF8"},
                    ConnParams = #{external_auth => true},
                    case dpi:conn_create(Context, <<>>, <<>>, Dsn, CommonParams, ConnParams) of
                        Conn when is_reference(Conn) ->
                            Result = execute_and_fetch_first(Conn, Sql),
                            _ = safe_conn_close(Conn),
                            _ = safe_context_destroy(Context),
                            Result;
                        Error ->
                            _ = safe_context_destroy(Context),
                            {error, Error}
                    end;
                {'EXIT', Reason} ->
                    {error, {context_create_failed, Reason}};
                Other ->
                    {error, {context_create_failed, Other}}
            end;
        Error ->
            Error
    end.

ensure_loaded() ->
    case catch dpi:resource_count() of
        {'EXIT', _} ->
            case dpi:load_unsafe() of
                ok -> ok;
                {error, Reason} -> {error, Reason};
                Other -> {error, Other}
            end;
        _ ->
            ok
    end.

execute_and_fetch_first(Conn, Sql) ->
    case dpi:conn_prepareStmt(Conn, false, Sql, <<>>) of
        Stmt when is_reference(Stmt) ->
            case catch dpi:stmt_execute(Stmt, []) of
                1 ->
                    case dpi:stmt_fetch(Stmt) of
                        #{found := true} ->
                            case dpi:stmt_getQueryValue(Stmt, 1) of
                                #{data := DataRef} ->
                                    Value = dpi:data_get(DataRef),
                                    _ = dpi:data_release(DataRef),
                                    _ = dpi:stmt_close(Stmt, <<>>),
                                    {ok, Value};
                                Other ->
                                    _ = dpi:stmt_close(Stmt, <<>>),
                                    {error, {unexpected_query_value, Other}}
                            end;
                        _ ->
                            _ = dpi:stmt_close(Stmt, <<>>),
                            {error, no_rows}
                    end;
                {'EXIT', Reason} ->
                    _ = catch dpi:stmt_close(Stmt, <<>>),
                    {error, {execute_failed, Reason}};
                ExecResult ->
                    _ = dpi:stmt_close(Stmt, <<>>),
                    {error, {unexpected_exec_result, ExecResult}}
            end;
        Error ->
            {error, {prepare_failed, Error}}
    end.

execute_and_fetch_row(Conn, Sql) ->
    case dpi:conn_prepareStmt(Conn, false, Sql, <<>>) of
        Stmt when is_reference(Stmt) ->
            case catch dpi:stmt_execute(Stmt, []) of
                ExecResult when is_integer(ExecResult), ExecResult >= 1 ->
                    case dpi:stmt_fetch(Stmt) of
                        #{found := true} ->
                            case catch dpi:stmt_getNumQueryColumns(Stmt) of
                                ColumnCount when is_integer(ColumnCount), ColumnCount >= 1 ->
                                    Result = fetch_row_values(Stmt, ColumnCount, 1, []),
                                    _ = dpi:stmt_close(Stmt, <<>>),
                                    Result;
                                {'EXIT', Reason} ->
                                    _ = dpi:stmt_close(Stmt, <<>>),
                                    {error, {column_count_failed, Reason}};
                                Other ->
                                    _ = dpi:stmt_close(Stmt, <<>>),
                                    {error, {unexpected_column_count, Other}}
                            end;
                        _ ->
                            _ = dpi:stmt_close(Stmt, <<>>),
                            {error, no_rows}
                    end;
                {'EXIT', Reason} ->
                    _ = catch dpi:stmt_close(Stmt, <<>>),
                    {error, {execute_failed, Reason}};
                Other ->
                    _ = catch dpi:stmt_close(Stmt, <<>>),
                    {error, {unexpected_exec_result, Other}}
            end;
        Error ->
            {error, {prepare_failed, Error}}
    end.

execute_and_fetch_rows(Conn, Sql) ->
    case dpi:conn_prepareStmt(Conn, false, Sql, <<>>) of
        Stmt when is_reference(Stmt) ->
            case catch dpi:stmt_execute(Stmt, []) of
                ExecResult when is_integer(ExecResult), ExecResult >= 1 ->
                    case catch dpi:stmt_getNumQueryColumns(Stmt) of
                        ColumnCount when is_integer(ColumnCount), ColumnCount >= 1 ->
                            Result = fetch_all_rows(Stmt, ColumnCount, []),
                            _ = dpi:stmt_close(Stmt, <<>>),
                            Result;
                        {'EXIT', Reason} ->
                            _ = dpi:stmt_close(Stmt, <<>>),
                            {error, {column_count_failed, Reason}};
                        Other ->
                            _ = dpi:stmt_close(Stmt, <<>>),
                            {error, {unexpected_column_count, Other}}
                    end;
                {'EXIT', Reason} ->
                    _ = catch dpi:stmt_close(Stmt, <<>>),
                    {error, {execute_failed, Reason}};
                Other ->
                    _ = catch dpi:stmt_close(Stmt, <<>>),
                    {error, {unexpected_exec_result, Other}}
            end;
        Error ->
            {error, {prepare_failed, Error}}
    end.

fetch_row_values(_Stmt, ColumnCount, Position, Acc) when Position > ColumnCount ->
    {ok, lists:reverse(Acc)};
fetch_row_values(Stmt, ColumnCount, Position, Acc) ->
    case dpi:stmt_getQueryValue(Stmt, Position) of
        #{data := DataRef} ->
            Value = dpi:data_get(DataRef),
            _ = dpi:data_release(DataRef),
            fetch_row_values(Stmt, ColumnCount, Position + 1, [Value | Acc]);
        Other ->
            {error, {unexpected_query_value, Position, Other}}
    end.

fetch_all_rows(Stmt, ColumnCount, Acc) ->
    case dpi:stmt_fetch(Stmt) of
        #{found := true} ->
            case fetch_row_values(Stmt, ColumnCount, 1, []) of
                {ok, Row} -> fetch_all_rows(Stmt, ColumnCount, [Row | Acc]);
                {error, _} = Error -> Error
            end;
        #{found := false} ->
            {ok, lists:reverse(Acc)};
        Other ->
            {error, {unexpected_fetch_result, Other}}
    end.

execute_no_fetch(Conn, Sql) ->
    case dpi:conn_prepareStmt(Conn, false, Sql, <<>>) of
        Stmt when is_reference(Stmt) ->
            case catch dpi:stmt_execute(Stmt, []) of
                ExecResult when is_integer(ExecResult), ExecResult >= 0 ->
                    _ = catch dpi:stmt_close(Stmt, <<>>),
                    _ = catch dpi:conn_commit(Conn),
                    {ok, <<"ok">>};
                {'EXIT', Reason} ->
                    _ = catch dpi:stmt_close(Stmt, <<>>),
                    {error, {execute_failed, Reason}};
                Other ->
                    _ = catch dpi:stmt_close(Stmt, <<>>),
                    {error, {unexpected_exec_result, Other}}
            end;
        Error ->
            {error, {prepare_failed, Error}}
    end.

safe_conn_close(Conn) ->
    safe_conn_close(Conn, <<>>).

safe_conn_close(Conn, Tag) when is_binary(Tag) ->
    catch dpi:conn_close(Conn, [], Tag);
safe_conn_close(Conn, _Tag) ->
    catch dpi:conn_close(Conn, [], <<>>).

safe_context_destroy(Context) ->
    catch dpi:context_destroy(Context).

with_pool_connection(Pool, AcquireUser, AcquirePassword, Fun, RequestedTagInput, SetupSqlInput) ->
    Role = role_from_user(AcquireUser),
    RoleTag = role_tag(Role),
    CustomTag = normalize_requested_tag(RequestedTagInput),
    RequestedTag = compose_tags(RoleTag, CustomTag),
    ExpectedClientId = role_client_identifier(Role),
    ConnParams = role_conn_params(RequestedTag),
    SetupSql = normalize_setup_sql(SetupSqlInput),
    case valid_binary_list(SetupSql) of
        false ->
            {error, {invalid_setup_sql, SetupSqlInput}};
        true ->
            try
                case dpi:pool_acquireConnection(Pool, AcquireUser, AcquirePassword, ConnParams) of
                    Conn when is_reference(Conn) ->
                        run_with_checked_connection(
                            Pool,
                            Conn,
                            false,
                            <<>>,
                            Fun,
                            Role,
                            ExpectedClientId,
                            RequestedTag,
                            SetupSql
                        );
                    #{conn := Conn, out_tag_found := TagFound, out_tag := OutTag} when is_reference(Conn) ->
                        run_with_checked_connection(
                            Pool,
                            Conn,
                            TagFound,
                            OutTag,
                            Fun,
                            Role,
                            ExpectedClientId,
                            RequestedTag,
                            SetupSql
                        );
                    #{conn := Conn} when is_reference(Conn) ->
                        run_with_checked_connection(
                            Pool,
                            Conn,
                            false,
                            <<>>,
                            Fun,
                            Role,
                            ExpectedClientId,
                            RequestedTag,
                            SetupSql
                        );
                    Other ->
                        {error, {pool_acquire_failed, Other}}
                end
            catch
                Class:Reason ->
                    {error, {pool_acquire_exception, {Class, Reason}}}
            end
    end.

run_with_checked_connection(
    Pool,
    Conn,
    TagFound,
    OutTag,
    Fun,
    Role,
    ExpectedClientId,
    RequestedTag,
    SetupSql
) ->
    BusySample = safe_pool_busy(Pool),
    HasMatchingTag = role_tag_match(TagFound, RequestedTag, OutTag),
    HasRoleInitialized = session_has_client_id(Conn, ExpectedClientId),
    NeedsRoleInit = role_needs_init(Role, HasRoleInitialized),
    NeedsCustomInit = custom_needs_init(RequestedTag, SetupSql, HasMatchingTag),
    Event = case NeedsRoleInit orelse NeedsCustomInit of
        true -> init;
        false -> hit
    end,
    case maybe_initialize_role_session(Conn, Role, not NeedsRoleInit) of
        ok ->
            case maybe_initialize_custom_session(Conn, NeedsCustomInit, SetupSql) of
                ok ->
                    try
                        case Fun(Conn) of
                            Result -> {ok, Result, BusySample}
                        end
                    after
                        _ = safe_conn_close(Conn, RequestedTag),
                        _ = record_affinity_event(Role, Event)
                    end;
                {error, Reason} ->
                    _ = safe_conn_close(Conn, <<>>),
                    {error, {session_init_failed, Reason}}
            end;
        {error, Reason} ->
            _ = safe_conn_close(Conn, <<>>),
            {error, {session_init_failed, Reason}}
    end.

normalize_requested_tag(Tag) when is_binary(Tag) ->
    Tag;
normalize_requested_tag(_Tag) ->
    <<>>.

normalize_setup_sql(SetupSql) when is_list(SetupSql) ->
    SetupSql;
normalize_setup_sql(_SetupSql) ->
    [].

compose_tags(<<>>, <<>>) ->
    <<>>;
compose_tags(Left, <<>>) when is_binary(Left) ->
    Left;
compose_tags(<<>>, Right) when is_binary(Right) ->
    Right;
compose_tags(Left, Right) when is_binary(Left), is_binary(Right) ->
    <<Left/binary, "|", Right/binary>>.

role_needs_init(writer, HasRoleInitialized) ->
    not HasRoleInitialized;
role_needs_init(reader, HasRoleInitialized) ->
    not HasRoleInitialized;
role_needs_init(_Role, _HasRoleInitialized) ->
    false.

custom_needs_init(<<>>, _SetupSql, _HasMatchingTag) ->
    false;
custom_needs_init(_RequestedTag, SetupSql, HasMatchingTag) ->
    case SetupSql of
        [] -> false;
        _ -> not HasMatchingTag
    end.

maybe_initialize_custom_session(_Conn, false, _SetupSql) ->
    ok;
maybe_initialize_custom_session(Conn, true, SetupSql) ->
    run_setup_sql(Conn, SetupSql).

run_setup_sql(_Conn, []) ->
    ok;
run_setup_sql(Conn, [Sql | Rest]) when is_binary(Sql) ->
    case execute_no_fetch_no_commit_strict(Conn, Sql) of
        ok -> run_setup_sql(Conn, Rest);
        {error, _} = Error -> Error
    end;
run_setup_sql(_Conn, [Other | _Rest]) ->
    {error, {invalid_setup_statement, Other}}.

safe_pool_busy(Pool) ->
    try
        dpi:pool_getBusyCount(Pool)
    catch
        _:_ ->
            -1
    end.

do_pool_probe_burst_metric(Pool, AcquireUsers, AcquirePassword, Sql, Count) ->
    do_pool_probe_burst_metric(Pool, AcquireUsers, AcquirePassword, Sql, Count, 0).

do_pool_probe_burst_metric(Pool, AcquireUsers, AcquirePassword, Sql, Count, HoldMs) ->
    Parent = self(),
    _ = [
        spawn(fun() ->
            User = pick_user(AcquireUsers, Index),
            Result = case with_pool_connection(Pool, User, AcquirePassword, fun(Conn) ->
                case execute_and_fetch_first(Conn, Sql) of
                    {ok, _Value} = Ok ->
                        maybe_sleep_ms(HoldMs),
                        Ok;
                    Error ->
                        Error
                end
            end, undefined, []) of
                {ok, {ok, _Value}, BusySample} -> {ok, BusySample};
                {ok, {error, Reason}, _BusySample} -> {error, Reason};
                {error, Reason} -> {error, Reason}
            end,
            Parent ! {pool_probe_burst_worker, Result}
        end)
        || Index <- lists:seq(0, Count - 1)
    ],
    gather_probe_burst_results(Count, 0, 0).

gather_probe_burst_results(0, OkCount, PeakBusy) ->
    {ok, {OkCount, PeakBusy}};
gather_probe_burst_results(Remaining, OkCount, PeakBusy) ->
    receive
        {pool_probe_burst_worker, {ok, BusySample}} ->
            gather_probe_burst_results(
                Remaining - 1,
                OkCount + 1,
                max(PeakBusy, BusySample)
            );
        {pool_probe_burst_worker, {error, _Reason}} ->
            gather_probe_burst_results(Remaining - 1, OkCount, PeakBusy)
    end.

pick_user([User | _], 0) ->
    User;
pick_user(Users, Index) when is_list(Users), Index >= 0 ->
    case length(Users) of
        0 ->
            <<>>;
        Size ->
            pick_user_nth(Users, Index rem Size)
    end.

pick_user_nth([User | _], 0) ->
    User;
pick_user_nth([_ | Rest], Index) when Index > 0 ->
    pick_user_nth(Rest, Index - 1);
pick_user_nth([], _Index) ->
    <<>>.

valid_binary_list([]) ->
    true;
valid_binary_list([Value | Rest]) when is_binary(Value) ->
    valid_binary_list(Rest);
valid_binary_list(_Other) ->
    false.

maybe_sleep_ms(HoldMs) when HoldMs > 0 ->
    timer:sleep(HoldMs);
maybe_sleep_ms(_HoldMs) ->
    ok.

pool_trace_loop(Pool, StartMs, IntervalMs, SamplesRev) ->
    receive
        {stop, Caller} ->
            {OpenCount, BusyCount} = safe_pool_stats(Pool),
            Metrics = pool_metrics_snapshot(),
            Elapsed = erlang:monotonic_time(millisecond) - StartMs,
            Samples = lists:reverse([
                {
                    Elapsed,
                    OpenCount,
                    BusyCount,
                    maps:get(writer_init, Metrics),
                    maps:get(reader_init, Metrics),
                    maps:get(writer_hit, Metrics),
                    maps:get(reader_hit, Metrics)
                }
                | SamplesRev
            ]),
            Caller ! {pool_trace_stopped, Samples},
            ok
    after IntervalMs ->
        {OpenCount, BusyCount} = safe_pool_stats(Pool),
        Metrics = pool_metrics_snapshot(),
        Elapsed = erlang:monotonic_time(millisecond) - StartMs,
        pool_trace_loop(
            Pool,
            StartMs,
            IntervalMs,
            [
                {
                    Elapsed,
                    OpenCount,
                    BusyCount,
                    maps:get(writer_init, Metrics),
                    maps:get(reader_init, Metrics),
                    maps:get(writer_hit, Metrics),
                    maps:get(reader_hit, Metrics)
                }
                | SamplesRev
            ]
        )
    end.

safe_pool_stats(Pool) ->
    try
        {dpi:pool_getOpenCount(Pool), dpi:pool_getBusyCount(Pool)}
    catch
        _:_ ->
            {-1, -1}
    end.

role_from_user(User) when is_binary(User) ->
    case {binary:match(User, <<"[TP_WRITER_">>), binary:match(User, <<"[TP_READER_">>)} of
        {{_, _}, _} -> writer;
        {_, {_, _}} -> reader;
        _ -> unknown
    end;
role_from_user(_User) ->
    unknown.

role_tag(writer) -> <<"ROLE=writer">>;
role_tag(reader) -> <<"ROLE=reader">>;
role_tag(_Role) -> <<>>.

role_client_identifier(writer) -> <<"gleam_proxy_writer">>;
role_client_identifier(reader) -> <<"gleam_proxy_reader">>;
role_client_identifier(_Role) -> <<>>.

role_conn_params(<<>>) -> #{};
role_conn_params(Tag) -> #{tag => Tag, match_any_tag => true, purity => 'DPI_PURITY_SELF'}.

role_tag_match(true, _RequestedTag, _OutTag) ->
    true;
role_tag_match(false, RequestedTag, OutTag) when is_binary(OutTag) ->
    OutTag =:= RequestedTag;
role_tag_match(false, _RequestedTag, _OutTag) ->
    false.

maybe_initialize_role_session(_Conn, _Role, true) ->
    ok;
maybe_initialize_role_session(Conn, writer, false) ->
    timer:sleep(100),
    initialize_session_role(Conn, <<"gleam_proxy_writer">>, <<"begin dbms_application_info.set_module('GLEAM_PROXY','WRITER'); end;">>);
maybe_initialize_role_session(Conn, reader, false) ->
    timer:sleep(100),
    initialize_session_role(Conn, <<"gleam_proxy_reader">>, <<"begin dbms_application_info.set_module('GLEAM_PROXY','READER'); end;">>);
maybe_initialize_role_session(_Conn, _Role, false) ->
    ok.

session_has_client_id(_Conn, <<>>) ->
    false;
session_has_client_id(Conn, ExpectedClientId) ->
    case execute_and_fetch_first(Conn, <<"select sys_context('USERENV','CLIENT_IDENTIFIER') from dual">>) of
        {ok, Value} ->
            normalize_binary(Value) =:= ExpectedClientId;
        _ ->
            false
    end.

normalize_binary(Value) when is_binary(Value) ->
    Value;
normalize_binary(Value) when is_list(Value) ->
    unicode:characters_to_binary(Value);
normalize_binary(_Value) ->
    <<>>.

initialize_session_role(Conn, ClientId, ModuleSql) ->
    case dpi:conn_setClientIdentifier(Conn, ClientId) of
        ok ->
            execute_no_fetch_no_commit(Conn, ModuleSql);
        _Other ->
            ok
    end.

execute_no_fetch_no_commit(Conn, Sql) ->
    case dpi:conn_prepareStmt(Conn, false, Sql, <<>>) of
        Stmt when is_reference(Stmt) ->
            Result = catch dpi:stmt_execute(Stmt, []),
            _ = catch dpi:stmt_close(Stmt, <<>>),
            case Result of
                Exec when is_integer(Exec), Exec >= 0 -> ok;
                _ -> ok
            end;
        _ ->
            ok
    end.

execute_no_fetch_no_commit_strict(Conn, Sql) ->
    case dpi:conn_prepareStmt(Conn, false, Sql, <<>>) of
        Stmt when is_reference(Stmt) ->
            Result = catch dpi:stmt_execute(Stmt, []),
            _ = catch dpi:stmt_close(Stmt, <<>>),
            case Result of
                Exec when is_integer(Exec), Exec >= 0 -> ok;
                {'EXIT', Reason} -> {error, {execute_failed, Reason}};
                Other -> {error, {unexpected_exec_result, Other}}
            end;
        Error ->
            {error, {prepare_failed, Error}}
    end.

init_pool_metrics_table() ->
    case ets:info(pool_trace_metrics) of
        undefined ->
            _ = ets:new(pool_trace_metrics, [named_table, public, set]),
            _ = ets:insert(pool_trace_metrics, [
                {writer_init, 0},
                {reader_init, 0},
                {writer_hit, 0},
                {reader_hit, 0}
            ]),
            ok;
        _ ->
            _ = ets:insert(pool_trace_metrics, [
                {writer_init, 0},
                {reader_init, 0},
                {writer_hit, 0},
                {reader_hit, 0}
            ]),
            ok
    end.

record_affinity_event(Role, Event) ->
    case ets:info(pool_trace_metrics) of
        undefined ->
            ok;
        _ ->
            Key = case {Role, Event} of
                {writer, init} -> writer_init;
                {reader, init} -> reader_init;
                {writer, hit} -> writer_hit;
                {reader, hit} -> reader_hit;
                _ -> undefined
            end,
            case Key of
                undefined -> ok;
                _ ->
                    _ = ets:update_counter(pool_trace_metrics, Key, 1),
                    ok
            end
    end.

pool_metrics_snapshot() ->
    case ets:info(pool_trace_metrics) of
        undefined ->
            #{writer_init => 0, reader_init => 0, writer_hit => 0, reader_hit => 0};
        _ ->
            #{
                writer_init => ets_lookup_counter(writer_init),
                reader_init => ets_lookup_counter(reader_init),
                writer_hit => ets_lookup_counter(writer_hit),
                reader_hit => ets_lookup_counter(reader_hit)
            }
    end.

ets_lookup_counter(Key) ->
    case ets:lookup(pool_trace_metrics, Key) of
        [{_, Value}] -> Value;
        _ -> 0
    end.

tns(Host, Port, Service) ->
    list_to_binary([
        "(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=tcp)(HOST=",
        binary_to_list(Host),
        ")(PORT=",
        integer_to_list(Port),
        ")))(CONNECT_DATA=(SERVICE_NAME=",
        binary_to_list(Service),
        ")))"
    ]).