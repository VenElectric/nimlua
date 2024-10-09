import types

const
    LUA_VERSION_MAJOR* = "5"
    LUA_VERSION_MINOR* = "4"
    LUA_VERSION_NUM = 504
    LUA_VERSION_RELEASE = "4"
    LUA_VERSION = "Lua" & LUA_VERSION_MAJOR & "." & LUA_VERSION_MINOR
    LUA_RELEASE = LUA_VERSION & "." & LUA_VERSION_RELEASE
    LUA_AUTHORS = "R. Ierusalimschy, L. H. de Figueiredo, W. Celes"
    LUA_SIGNATURE = "\033Lua"
    LUA_MULTRET = -1
    LUA_REGISTRYINDEX = 23423423423 # LUAI_FIRSTPSUEDOIDX
    LUA_MINSTACK = 20
    LUA_RIDX_MAINTHREAD = 1
    LUA_RIDX_GLOBALS = 2
    LUA_RIDX_LAST = LUA_RIDX_GLOBALS
    LUA_NUMTAGS* = 9

proc lua_upvalueindex(i:int): int64 = return LUA_REGISTRYINDEX - i

proc lua_newstate(f:LuaAlloc,ud:auto):LuaState = discard

proc lua_close(L:LuaState) = discard

proc lua_newthread(L:LuaState):LuaState = discard






