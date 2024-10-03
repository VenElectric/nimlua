import std/distros


when sizeof(int) >= 32:
    const LUAI_BITSINT = 32
elif sizeof(int) < 17:
    const LUAI_BITSINT = 16
else:
    throw newException(CatchableError,"bleh")

if detectOs(Windows):
    const LUA_LDIR = "!\\lua\\"
    const LUA_CDIR = "!\\"
