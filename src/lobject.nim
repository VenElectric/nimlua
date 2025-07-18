import types

using
    lv: LuaValue
    lvk: LuaValueKind

func checkKind*(one,two:LuaValueKind): bool = one == two
func k*(lv): LuaValueKind = lv.kind

func newLNil*(): LuaValue = LuaValue(kind: LUA_TNIL)
func newLBool*(v:bool): LuaValue = LuaValue(kind: LUA_TBOOLEAN, boolv: v)
func newLLightUD*(v:UserData): LuaValue = LuaValue(kind: LUA_TLIGHTUSERDATA, luserv: v)
func newLInteger*(v:LuaInteger): LuaValue = LuaValue(kind: LUA_TINTEGER, intv: v)
func newLFloat*(v:LuaFloat): LuaValue = LuaValue(kind: LUA_TFLOAT, floatv: v)
func newLString*(v:LuaString): LuaValue = LuaValue(kind: LUA_TSTRING, strv: v)
func newLTable*(v:LuaTable): LuaValue = LuaValue(kind: LUA_TTABLE, tablev: v)
func newLThread*(v:LuaState): LuaValue = LuaValue(kind: LUA_TTHREAD, threadv: v)


func kisNil*(lv): bool = checkKind(lv.k,LUA_TNIL)
func kisBoolean*(lv): bool = checkKind(lv.k,LUA_TBOOLEAN)
func kisLightUD*(lv): bool = checkKind(lv.k,LUA_TLIGHTUSERDATA)
func kisInteger*(lv): bool = checkKind(lv.k,LUA_TINTEGER)
func kisFloat*(lv): bool = checkKind(lv.k,LUA_TFLOAT)
func kisString*(lv): bool = checkKind(lv.k,LUA_TSTRING)
func kisTable*(lv): bool = checkKind(lv.k,LUA_TTABLE)
func kisClosure*(lv): bool = checkKind(lv.k,LUA_TFUNCTION)
func kisUserData*(lv): bool = checkKind(lv.k,LUA_TUSERDATA)
func kisThread*(lv): bool = checkKind(lv.k,LUA_TTHREAD)
func kisProto*(lv): bool = checkKind(lv.k,LUA_TPROTO)

converter toLBool*(lv): bool = 
    if checkKind(v.kind,LUA_TBOOLEAN):
        return v.boolv
    else:
        return false

converter toLInteger*(lv): LuaInteger =
    if checkKind(lv.kind,LUA_TINTEGER):
        return lv.intv
    else:
        return LuaInteger(0)

converter toLFloat*(lv): LuaFloat =
    if checkKind(lv.kind,LUA_TFLOAT):
        return lv.floatv
    else:
        return LuaFloat(NaN)

converter toFloat*(v:LuaFloat): float64 = float64(v)

converter toLString*(lv): LuaString = 
    if checkKind(lv.kind,LUA_TSTRING):
        return lv.strv
    else:
        return LuaString("")

converter toString*(v:LuaString): string = string(v)
















