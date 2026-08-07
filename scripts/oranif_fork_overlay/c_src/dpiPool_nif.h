#ifndef _DPIPOOL_NIF_H_
#define _DPIPOOL_NIF_H_

#include "dpi_nif.h"
#include "dpi.h"

typedef struct
{
    dpiPool *pool;
    dpiContext *context;
} dpiPool_res;

extern ErlNifResourceType *dpiPool_type;
extern void dpiPool_res_dtor(ErlNifEnv *env, void *resource);

extern DPI_NIF_FUN(pool_create);
extern DPI_NIF_FUN(pool_acquireConnection);
extern DPI_NIF_FUN(pool_close);
extern DPI_NIF_FUN(pool_getBusyCount);
extern DPI_NIF_FUN(pool_getOpenCount);

#define DPIPOOL_NIFS                        \
    IOB_NIF(pool_create, 6),               \
        IOB_NIF(pool_acquireConnection, 3),\
        IOB_NIF(pool_acquireConnection, 4),\
        DEF_NIF(pool_close, 2),            \
        DEF_NIF(pool_getBusyCount, 1),     \
        DEF_NIF(pool_getOpenCount, 1)

#define DPI_POOL_GET_MODE_FROM_ATOM(_atom, _assign)      \
    A2M(DPI_MODE_POOL_GET_WAIT, _atom, _assign);         \
    else A2M(DPI_MODE_POOL_GET_NOWAIT, _atom, _assign);  \
    else A2M(DPI_MODE_POOL_GET_FORCEGET, _atom, _assign);\
    else A2M(DPI_MODE_POOL_GET_TIMEDWAIT, _atom, _assign);\
    else BADARG_EXCEPTION(5, "DPI_MODE_POOL_GET atom")

#define DPI_POOL_CLOSE_MODE_FROM_ATOM(_atom, _assign)    \
    A2M(DPI_MODE_POOL_CLOSE_DEFAULT, _atom, _assign);    \
    else A2M(DPI_MODE_POOL_CLOSE_FORCE, _atom, _assign); \
    else BADARG_EXCEPTION(1, "DPI_MODE_POOL_CLOSE atom")

#define DPI_PURITY_FROM_ATOM(_atom, _assign)            \
    A2M(DPI_PURITY_DEFAULT, _atom, _assign);            \
    else A2M(DPI_PURITY_NEW, _atom, _assign);           \
    else A2M(DPI_PURITY_SELF, _atom, _assign);          \
    else BADARG_EXCEPTION(3, "DPI_PURITY atom")

#endif // _DPIPOOL_NIF_H_
