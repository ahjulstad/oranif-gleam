-ifndef(_DPI_POOL_HRL_).
-define(_DPI_POOL_HRL_, true).

-include("dpi.hrl").

% see: https://oracle.github.io/odpi/doc/public_functions/dpiPool.html

-nifs({dpiPool, [
    {pool_create, [reference, binary, binary, binary, {map, null}, {map, null}]},
    {pool_acquireConnection, [reference, term, term]},
    {pool_acquireConnection, [reference, term, term, {map, null}]},
    {pool_close, [reference, list]},
    {pool_getBusyCount, [reference]},
    {pool_getOpenCount, [reference]}
]}).

-endif. % _DPI_POOL_HRL_
