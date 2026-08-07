#include "dpiPool_nif.h"
#include "dpiContext_nif.h"
#include "dpiConn_nif.h"
#include <string.h>

static ERL_NIF_TERM ATOM_min_sessions = 0;
static ERL_NIF_TERM ATOM_max_sessions = 0;
static ERL_NIF_TERM ATOM_session_increment = 0;
static ERL_NIF_TERM ATOM_ping_interval = 0;
static ERL_NIF_TERM ATOM_ping_timeout = 0;
static ERL_NIF_TERM ATOM_homogeneous = 0;
static ERL_NIF_TERM ATOM_external_auth = 0;
static ERL_NIF_TERM ATOM_get_mode = 0;
static ERL_NIF_TERM ATOM_timeout = 0;
static ERL_NIF_TERM ATOM_wait_timeout = 0;
static ERL_NIF_TERM ATOM_max_lifetime_session = 0;
static ERL_NIF_TERM ATOM_max_sessions_per_shard = 0;
static ERL_NIF_TERM ATOM_tag = 0;
static ERL_NIF_TERM ATOM_match_any_tag = 0;
static ERL_NIF_TERM ATOM_purity = 0;
static ERL_NIF_TERM ATOM_conn = 0;
static ERL_NIF_TERM ATOM_out_tag = 0;
static ERL_NIF_TERM ATOM_out_tag_found = 0;
static ERL_NIF_TERM ATOM_out_new_session = 0;

ErlNifResourceType *dpiPool_type;

void dpiPool_res_dtor(ErlNifEnv *env, void *resource)
{
    CALL_TRACE;
    RETURNED_TRACE;
}

DPI_NIF_FUN(pool_create)
{
    CHECK_ARGCOUNT(6);

    dpiContext_res *contextRes = NULL;
    ErlNifBinary userName, password, connectString;
    size_t commonParamsMapSize = 0;
    size_t poolParamsMapSize = 0;

    if (!enif_get_resource(env, argv[0], dpiContext_type, (void **)&contextRes))
        BADARG_EXCEPTION(0, "resource context");
    if (!enif_inspect_binary(env, argv[1], &userName))
        BADARG_EXCEPTION(1, "binary userName");
    if (!enif_inspect_binary(env, argv[2], &password))
        BADARG_EXCEPTION(2, "binary password");
    if (!enif_inspect_binary(env, argv[3], &connectString))
        BADARG_EXCEPTION(3, "binary connectString");
    if (!enif_get_map_size(env, argv[4], &commonParamsMapSize))
        BADARG_EXCEPTION(4, "map commonParams");
    if (!enif_get_map_size(env, argv[5], &poolParamsMapSize))
        BADARG_EXCEPTION(5, "map poolParams");

    dpiCommonCreateParams commonParams;
    dpiPoolCreateParams poolParams;
    char encodeStr[128] = {0};
    char nencodeStr[128] = {0};

    RAISE_EXCEPTION_ON_DPI_ERROR(
        contextRes->context,
        dpiContext_initCommonCreateParams(contextRes->context, &commonParams));
    RAISE_EXCEPTION_ON_DPI_ERROR(
        contextRes->context,
        dpiContext_initPoolCreateParams(contextRes->context, &poolParams));

    if (!(ATOM_min_sessions | ATOM_max_sessions | ATOM_session_increment |
          ATOM_ping_interval | ATOM_ping_timeout | ATOM_homogeneous |
          ATOM_external_auth | ATOM_get_mode | ATOM_timeout |
          ATOM_wait_timeout | ATOM_max_lifetime_session |
          ATOM_max_sessions_per_shard))
    {
        ATOM_min_sessions = enif_make_atom(env, "min_sessions");
        ATOM_max_sessions = enif_make_atom(env, "max_sessions");
        ATOM_session_increment = enif_make_atom(env, "session_increment");
        ATOM_ping_interval = enif_make_atom(env, "ping_interval");
        ATOM_ping_timeout = enif_make_atom(env, "ping_timeout");
        ATOM_homogeneous = enif_make_atom(env, "homogeneous");
        ATOM_external_auth = enif_make_atom(env, "external_auth");
        ATOM_get_mode = enif_make_atom(env, "get_mode");
        ATOM_timeout = enif_make_atom(env, "timeout");
        ATOM_wait_timeout = enif_make_atom(env, "wait_timeout");
        ATOM_max_lifetime_session =
            enif_make_atom(env, "max_lifetime_session");
        ATOM_max_sessions_per_shard =
            enif_make_atom(env, "max_sessions_per_shard");
    }

    if (commonParamsMapSize > 0)
    {
        ERL_NIF_TERM mapval;

        ERL_NIF_TERM atom_encoding = enif_make_atom(env, "encoding");
        ERL_NIF_TERM atom_nencoding = enif_make_atom(env, "nencoding");

        if (enif_get_map_value(env, argv[4], atom_encoding, &mapval))
        {
            if (!enif_get_string(
                    env, mapval, encodeStr, sizeof(encodeStr), ERL_NIF_LATIN1))
                BADARG_EXCEPTION(4, "string commonParams.encoding");
            commonParams.encoding = encodeStr;
        }

        if (enif_get_map_value(env, argv[4], atom_nencoding, &mapval))
        {
            if (!enif_get_string(
                    env, mapval, nencodeStr, sizeof(nencodeStr),
                    ERL_NIF_LATIN1))
                BADARG_EXCEPTION(4, "string commonParams.nencoding");
            commonParams.nencoding = nencodeStr;
        }
    }

    if (poolParamsMapSize > 0)
    {
        ERL_NIF_TERM mapval;
        unsigned uval;
        int ival;
        dpiPoolGetMode getMode = DPI_MODE_POOL_GET_WAIT;

        if (enif_get_map_value(env, argv[5], ATOM_min_sessions, &mapval))
        {
            if (!enif_get_uint(env, mapval, &uval))
                BADARG_EXCEPTION(5, "uint poolParams.min_sessions");
            poolParams.minSessions = uval;
        }
        if (enif_get_map_value(env, argv[5], ATOM_max_sessions, &mapval))
        {
            if (!enif_get_uint(env, mapval, &uval))
                BADARG_EXCEPTION(5, "uint poolParams.max_sessions");
            poolParams.maxSessions = uval;
        }
        if (enif_get_map_value(env, argv[5], ATOM_session_increment, &mapval))
        {
            if (!enif_get_uint(env, mapval, &uval))
                BADARG_EXCEPTION(5, "uint poolParams.session_increment");
            poolParams.sessionIncrement = uval;
        }
        if (enif_get_map_value(env, argv[5], ATOM_ping_interval, &mapval))
        {
            if (!enif_get_int(env, mapval, &ival))
                BADARG_EXCEPTION(5, "int poolParams.ping_interval");
            poolParams.pingInterval = ival;
        }
        if (enif_get_map_value(env, argv[5], ATOM_ping_timeout, &mapval))
        {
            if (!enif_get_int(env, mapval, &ival))
                BADARG_EXCEPTION(5, "int poolParams.ping_timeout");
            poolParams.pingTimeout = ival;
        }
        if (enif_get_map_value(env, argv[5], ATOM_homogeneous, &mapval))
        {
            if (enif_compare(mapval, ATOM_TRUE) == 0)
                poolParams.homogeneous = 1;
            else if (enif_compare(mapval, ATOM_FALSE) == 0)
                poolParams.homogeneous = 0;
            else
                BADARG_EXCEPTION(5, "bool poolParams.homogeneous");
        }
        if (enif_get_map_value(env, argv[5], ATOM_external_auth, &mapval))
        {
            if (enif_compare(mapval, ATOM_TRUE) == 0)
                poolParams.externalAuth = 1;
            else if (enif_compare(mapval, ATOM_FALSE) == 0)
                poolParams.externalAuth = 0;
            else
                BADARG_EXCEPTION(5, "bool poolParams.external_auth");
        }
        if (enif_get_map_value(env, argv[5], ATOM_get_mode, &mapval))
        {
            DPI_POOL_GET_MODE_FROM_ATOM(mapval, getMode);
            poolParams.getMode = getMode;
        }
        if (enif_get_map_value(env, argv[5], ATOM_timeout, &mapval))
        {
            if (!enif_get_uint(env, mapval, &uval))
                BADARG_EXCEPTION(5, "uint poolParams.timeout");
            poolParams.timeout = uval;
        }
        if (enif_get_map_value(env, argv[5], ATOM_wait_timeout, &mapval))
        {
            if (!enif_get_uint(env, mapval, &uval))
                BADARG_EXCEPTION(5, "uint poolParams.wait_timeout");
            poolParams.waitTimeout = uval;
        }
        if (enif_get_map_value(env, argv[5], ATOM_max_lifetime_session, &mapval))
        {
            if (!enif_get_uint(env, mapval, &uval))
                BADARG_EXCEPTION(5, "uint poolParams.max_lifetime_session");
            poolParams.maxLifetimeSession = uval;
        }
        if (enif_get_map_value(env, argv[5], ATOM_max_sessions_per_shard, &mapval))
        {
            if (!enif_get_uint(env, mapval, &uval))
                BADARG_EXCEPTION(5, "uint poolParams.max_sessions_per_shard");
            poolParams.maxSessionsPerShard = uval;
        }
    }

    dpiPool_res *poolRes;
    ALLOC_RESOURCE(poolRes, dpiPool);

    RAISE_EXCEPTION_ON_DPI_ERROR_RESOURCE(
        contextRes->context,
        dpiPool_create(
            contextRes->context,
            (const char *)userName.data, userName.size,
            (const char *)password.data, password.size,
            (const char *)connectString.data, connectString.size,
            &commonParams,
            &poolParams,
            &poolRes->pool),
        poolRes, dpiPool);

    poolRes->context = contextRes->context;

    RETURNED_TRACE;
    return enif_make_resource(env, poolRes);
}

DPI_NIF_FUN(pool_acquireConnection)
{
    if (!(argc == 3 || argc == 4))
        BADARG_EXCEPTION(0, "pool_acquireConnection expects arity 3 or 4");

    dpiPool_res *poolRes = NULL;
    ErlNifBinary userName, password;
    const char *userNamePtr = NULL;
    const char *passwordPtr = NULL;
    uint32_t userNameLen = 0;
    uint32_t passwordLen = 0;
    int hasConnParams = 0;
    size_t connParamsMapSize = 0;
    dpiConnCreateParams connParams;
    char *outTagPtr = NULL;
    uint32_t outTagLen = 0;

    if (!enif_get_resource(env, argv[0], dpiPool_type, (void **)&poolRes))
        BADARG_EXCEPTION(0, "resource pool");

    if (enif_compare(argv[1], ATOM_NULL) == 0)
    {
        userNamePtr = NULL;
        userNameLen = 0;
    }
    else if (enif_inspect_binary(env, argv[1], &userName))
    {
        userNamePtr = (const char *)userName.data;
        userNameLen = userName.size;
    }
    else
        BADARG_EXCEPTION(1, "binary or null userName");

    if (enif_compare(argv[2], ATOM_NULL) == 0)
    {
        passwordPtr = NULL;
        passwordLen = 0;
    }
    else if (enif_inspect_binary(env, argv[2], &password))
    {
        passwordPtr = (const char *)password.data;
        passwordLen = password.size;
    }
    else
        BADARG_EXCEPTION(2, "binary or null password");

    if (argc == 4)
    {
        hasConnParams = 1;
        if (!enif_get_map_size(env, argv[3], &connParamsMapSize))
            BADARG_EXCEPTION(3, "map connCreateParams");

        RAISE_EXCEPTION_ON_DPI_ERROR(
            poolRes->context,
            dpiContext_initConnCreateParams(poolRes->context, &connParams));

        if (!(ATOM_tag | ATOM_match_any_tag | ATOM_purity | ATOM_conn |
              ATOM_out_tag | ATOM_out_tag_found | ATOM_out_new_session))
        {
            ATOM_tag = enif_make_atom(env, "tag");
            ATOM_match_any_tag = enif_make_atom(env, "match_any_tag");
            ATOM_purity = enif_make_atom(env, "purity");
            ATOM_conn = enif_make_atom(env, "conn");
            ATOM_out_tag = enif_make_atom(env, "out_tag");
            ATOM_out_tag_found = enif_make_atom(env, "out_tag_found");
            ATOM_out_new_session = enif_make_atom(env, "out_new_session");
        }

        if (connParamsMapSize > 0)
        {
            ERL_NIF_TERM mapval;
            ErlNifBinary tag;
            dpiPurity purity = DPI_PURITY_DEFAULT;

            if (enif_get_map_value(env, argv[3], ATOM_tag, &mapval))
            {
                if (!enif_inspect_binary(env, mapval, &tag))
                    BADARG_EXCEPTION(3, "binary connCreateParams.tag");
                connParams.tag = (const char *)tag.data;
                connParams.tagLength = tag.size;
            }

            if (enif_get_map_value(env, argv[3], ATOM_match_any_tag, &mapval))
            {
                if (enif_compare(mapval, ATOM_TRUE) == 0)
                    connParams.matchAnyTag = 1;
                else if (enif_compare(mapval, ATOM_FALSE) == 0)
                    connParams.matchAnyTag = 0;
                else
                    BADARG_EXCEPTION(3, "bool connCreateParams.match_any_tag");
            }

            if (enif_get_map_value(env, argv[3], ATOM_purity, &mapval))
            {
                DPI_PURITY_FROM_ATOM(mapval, purity);
                connParams.purity = purity;
            }
        }
    }

    dpiConn_res *connRes;
    ALLOC_RESOURCE(connRes, dpiConn);

    RAISE_EXCEPTION_ON_DPI_ERROR_RESOURCE(
        poolRes->context,
        dpiPool_acquireConnection(
            poolRes->pool,
            userNamePtr, userNameLen,
            passwordPtr, passwordLen,
            hasConnParams ? &connParams : NULL,
            &connRes->conn),
        connRes, dpiConn);

    connRes->context = poolRes->context;

    RETURNED_TRACE;
    if (!hasConnParams)
        return enif_make_resource(env, connRes);

    ERL_NIF_TERM connResTerm = enif_make_resource(env, connRes);
    ERL_NIF_TERM result = enif_make_new_map(env);

    enif_make_map_put(env, result, ATOM_conn, connResTerm, &result);

    outTagPtr = (char *)connParams.outTag;
    outTagLen = connParams.outTagLength;
    if (outTagPtr != NULL && outTagLen > 0)
    {
        ErlNifBinary outTag;
        if (!enif_alloc_binary(outTagLen, &outTag))
            RAISE_STR_EXCEPTION("cannot allocate out_tag binary");
        memcpy(outTag.data, outTagPtr, outTagLen);
        enif_make_map_put(
            env, result, ATOM_out_tag,
            enif_make_binary(env, &outTag),
            &result);
    }
    else
    {
        enif_make_map_put(env, result, ATOM_out_tag, ATOM_NULL, &result);
    }

    enif_make_map_put(
        env, result, ATOM_out_tag_found,
        connParams.outTagFound ? ATOM_TRUE : ATOM_FALSE, &result);
    enif_make_map_put(
        env, result, ATOM_out_new_session,
        connParams.outNewSession ? ATOM_TRUE : ATOM_FALSE, &result);

    return result;
}

DPI_NIF_FUN(pool_close)
{
    CHECK_ARGCOUNT(2);

    dpiPool_res *poolRes = NULL;

    if (!enif_get_resource(env, argv[0], dpiPool_type, (void **)&poolRes))
        BADARG_EXCEPTION(0, "resource pool");

    ERL_NIF_TERM head, tail;
    unsigned len;
    if (!enif_get_list_length(env, argv[1], &len))
        BADARG_EXCEPTION(1, "list of atoms");
    if (len > 0)
        enif_get_list_cell(env, argv[1], &head, &tail);

    dpiPoolCloseMode m = 0, mode = 0;
    if (len > 0)
        do
        {
            if (!enif_is_atom(env, head))
                RAISE_STR_EXCEPTION("mode must be a list of atoms");
            DPI_POOL_CLOSE_MODE_FROM_ATOM(head, m);
            mode |= m;
        } while (enif_get_list_cell(env, tail, &head, &tail));

    RAISE_EXCEPTION_ON_DPI_ERROR_RESOURCE(
        poolRes->context,
        dpiPool_close(poolRes->pool, mode),
        poolRes, dpiPool);

    RELEASE_RESOURCE(poolRes, dpiPool);

    RETURNED_TRACE;
    return ATOM_OK;
}

DPI_NIF_FUN(pool_getBusyCount)
{
    CHECK_ARGCOUNT(1);

    dpiPool_res *poolRes = NULL;
    uint32_t value = 0;

    if (!enif_get_resource(env, argv[0], dpiPool_type, (void **)&poolRes))
        BADARG_EXCEPTION(0, "resource pool");

    RAISE_EXCEPTION_ON_DPI_ERROR(
        poolRes->context,
        dpiPool_getBusyCount(poolRes->pool, &value));

    RETURNED_TRACE;
    return enif_make_uint(env, value);
}

DPI_NIF_FUN(pool_getOpenCount)
{
    CHECK_ARGCOUNT(1);

    dpiPool_res *poolRes = NULL;
    uint32_t value = 0;

    if (!enif_get_resource(env, argv[0], dpiPool_type, (void **)&poolRes))
        BADARG_EXCEPTION(0, "resource pool");

    RAISE_EXCEPTION_ON_DPI_ERROR(
        poolRes->context,
        dpiPool_getOpenCount(poolRes->pool, &value));

    RETURNED_TRACE;
    return enif_make_uint(env, value);
}
