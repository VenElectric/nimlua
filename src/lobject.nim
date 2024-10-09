import types

type
    LuaValue* = ref LuaValueBase
    LuaValueBase = object
        case kind*: LuaValueKind
            of LUA_TNIL: discard
            of LUA_TBOOLEAN: boolv*:bool
            of LUA_TLIGHTUSERDATA: luserv*: UserData
            of LUA_TNUMBER: numv*: LuaNumber
            of LUA_TSTRING: strv*: LuaString
            of LUA_TTABLE: tablev*: LuaTable
            of LUA_TFUNCTION: funcv*: Closure
            of LUA_TUSERDATA: userv*: UserData
            of LUA_TTHREAD: threadv*: LuaState
            of LUA_TPROTO: protov*: Proto

func checkKind*(one,two:LuaValueKind): bool = one == two
func k*(lv: LuaValue): LuaValueKind = lv.kind

func newLNil*(): LuaValue = LuaValue(kind: LUA_TNIL)
func newLBool*(v:bool): LuaValue = LuaValue(kind: LUA_TBOOLEAN, boolv: v)
func newLLightUD*(v:UserData): LuaValue = LuaValue(kind: LUA_TLIGHTUSERDATA, luserv: v)
func newLNumber*(v:LuaNumber): LuaValue = LuaValue(kind: LUA_TNUMBER, numv: v)
func newLString*(v:LuaString): LuaValue = LuaValue(kind: LUA_TSTRING, strv: v)
func newLTable*(v:LuaTable): LuaValue = LuaValue(kind: LUA_TTABLE, tablev: v)
func newLThread*(v:LuaState): LuaValue = LuaValue(kind: LUA_TTHREAD, threadv: v)


func kisNil*(lv:LuaValue): bool = checkKind(lv.k,LUA_TNIL)
func kisBoolean*(lv:LuaValue): bool = checkKind(lv.k,LUA_TBOOLEAN)
func kisLightUD*(lv:LuaValue): bool = checkKind(lv.k,LUA_TLIGHTUSERDATA)
func kisNumber*(lv:LuaValue): bool = checkKind(lv.k,LUA_TNUMBER)
func kisString*(lv:LuaValue): bool = checkKind(lv.k,LUA_TSTRING)
func kisTable*(lv:LuaValue): bool = checkKind(lv.k,LUA_TTABLE)
func kisLClosure*(lv:LuaValue): bool = checkKind(lv.k,LUA_TFUNCTION)
func kisUserData*(lv:LuaValue): bool = checkKind(lv.k,LUA_TUSERDATA)
func kisThread*(lv:LuaValue): bool = checkKind(lv.k,LUA_TTHREAD)
func kisProto*(lv:LuaValue): bool = checkKind(lv.k,LUA_TPROTO)

converter toLBool*(v:LuaValue): bool = 
    if checkKind(v.kind,LUA_TBOOLEAN):
        return v.boolv
    else:
        return false

converter toLNumber*(v:LuaValue): LuaNumber =
    if checkKind(v.kind,LUA_TNUMBER):
        return v.numv
    else:
        return LuaNumber(NaN)

converter toFloat*(v:LuaNumber): float64 = float64(v)

converter toLString*(v:LuaValue): LuaString = 
    if checkKind(v.kind,LUA_TSTRING):
        return v.strv
    else:
        return LuaString("")

converter toString*(v:LuaString): string = string(v)













