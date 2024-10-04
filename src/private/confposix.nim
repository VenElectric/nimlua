from ../lua import LUA_VERSION_MAJOR,LUA_VERSION_MINOR

const LUA_VDIR* = LUA_VERSION_MAJOR & "." & LUA_VERSION_MINOR
const LUA_ROOT* = "/usr/local/"
const LUA_LDIR* = LUA_ROOT & "share/lua/" & LUA_VDIR
const LUA_CDIR* = LUA_ROOT & "lib/lua/" & LUA_VDIR
const LUA_PATH_DEFAULT* = LUA_LDIR & "?.lua;" & LUA_LDIR & "?/init.lua;" & LUA_CDIR & "?.lua;" & LUA_CDIR & "?/init.lua;" & "./?.lua"
const LUA_CPATH_DEFAULT* = ""