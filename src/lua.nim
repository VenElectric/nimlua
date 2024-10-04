

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

proc lua_upvalueindex(i:int): int64 = return LUA_REGISTRYINDEX - i

type 
    ThreadStatus* = enum
        LUA_OK = 0
        LUA_YIELD = 1
        LUA_ERRRUN = 2
        LUA_ERRSYNTAX = 3
        LUA_ERRMEM = 4
        LUA_ERRGCMM = 5
        LUA_ERRERR = 6
    lua_State* = distinct pointer
    lua_CFunction = proc(L:lua_State):int
    lua_Reader = proc(l:lua_State,sz:int,ud:auto):string
    lua_Writer = proc(l:lua_State,p:pointer,sz:int,ud:auto):int
    lua_Alloc = proc(ud:auto,pt:pointer,osize:int,nsize:int)
    LuaBasicTypes = enum
        LUA_TNONE = -1
        LUA_TNIL = 0
        LUA_TBOOLEAN = 1
        LUA_TLIGHTUSERDATA = 2
        LUA_TNUMBER = 3
        LUA_TSTRING = 4
        LUA_TTABLE = 5
        LUA_TFUNCTION = 6
        LUA_TUSERDATA = 7
        LUA_TTHREAD = 8
        LUA_NUMTAGS = 9

# if defined lua_user_h
# include lua_user_h
# end
# is this needed?

proc lua_newstate(f:lua_Alloc,ud:auto):lua_State = discard

proc lua_close(L:lua_State) = discard

proc lua_newthread(L:lua_State):lua_State = discard






