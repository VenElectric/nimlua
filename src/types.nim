

type 
    lua_Number* = distinct float64
    lua_Integer* = distinct int64
    lua_Unsigned* = distinct uint64
    lua_ident* = distinct string
    lua_State* = distinct pointer
    TString* = object
    FuncState* = distinct pointer
    ZIO* = distinct pointer
    Dyndata* = distinct pointer