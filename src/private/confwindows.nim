const LUA_LDIR = "!\\lua\\"
const LUA_CDIR = "!\\"

const LUA_PATH_DEFAULT* = LUA_LDIR & "?.lua;" &  LUA_LDIR & "?\\init.lua;" & LUA_CDIR & "?.lua;" & LUA_CDIR & "?\\init.lua;" & ".\\?.lua" 
const LUA_CPATH_DEFAULT* = LUA_CDIR & "?.dll;" & LUA_CDIR & "loadall.dll;" & ".\\?.dll"

const LUA_DIR_SEP* = "\\"

