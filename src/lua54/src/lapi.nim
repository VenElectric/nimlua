

import
  lua, lapi, ldebug, ldo, lfunc, lgc, lmem, lobject, lstate, lstring, ltable, ltm, lundump,
  lvm


proc index2addr*(L: ptr lua_State; idx: cint): ptr TValue =
  var ci: ptr CallInfo = L.ci
  if idx > 0:
    var o: ptr TValue = ci.`func` + idx
    api_check(L, idx <= ci.top - (ci.`func` + 1), "unacceptable index")
    if o >= L.top:
      return NONVALIDVALUE
    else:
      return o
  elif not ispseudo(idx):
    api_check(L, idx != 0 and -idx <= L.top - (ci.`func` + 1), "invalid index")
    return L.top + idx
  elif idx == LUA_REGISTRYINDEX:
    return addr(G(L).l_registry)
  else:
    idx = LUA_REGISTRYINDEX - idx
    api_check(L, idx <= MAXUPVAL + 1, "upvalue index too large")
    if ttislcf(ci.`func`):
      return NONVALIDVALUE
    else:
      var `func`: ptr CClosure = clCvalue(ci.`func`)
      return if (idx <= `func`.nupvalues): addr(`func`.upvalue[idx - 1]) else: NONVALIDVALUE


proc growstack*(L: ptr lua_State; ud: pointer) =
  var size: cint = cast[ptr cint](ud)[]
  luaD_growstack(L, size)

proc lua_checkstack*(L: ptr lua_State; size: cint): cint =
  var res: cint = 0
  var ci: ptr CallInfo = L.ci
  lua_lock(L)
  if L.stack_last - L.top > size:
    res = 1
  else:
    var inuse: cint = cast_int(L.top - L.stack) + EXTRA_STACK
    if inuse > LUAI_MAXSTACK - size:
      res = 0
    else:
      res = (luaD_rawrunprotected(L, addr(growstack), addr(size)) == LUA_OK)
  if res and ci.top < L.top + size:
    ci.top = L.top + size
  lua_unlock(L)
  return res

proc lua_xmove*(`from`: ptr lua_State; to: ptr lua_State; n: cint) =
  var i: cint
  if `from` == to:
    return
  lua_lock(to)
  api_checknelems(`from`, n)
  api_check(`from`, G(`from`) == G(to), "moving among independent states")
  api_check(`from`, to.ci.top - to.top >= n, "not enough elements to move")
  dec(`from`.top, n)
  i = 0
  while i < n:
    setobj2s(to, inc(to.top), `from`.top + i)
    inc(i)
  lua_unlock(to)

proc lua_atpanic*(L: ptr lua_State; panicf: lua_CFunction): lua_CFunction =
  var old: lua_CFunction
  lua_lock(L)
  old = G(L).panic
  G(L).panic = panicf
  lua_unlock(L)
  return old

proc lua_version*(L: ptr lua_State): ptr lua_Number =
  let version: lua_Number = LUA_VERSION_NUM
  if L == nil:
    return addr(version)
  else:
    return G(L).version


proc lua_absindex*(L: ptr lua_State; idx: cint): cint =
  return if (idx > 0 or ispseudo(idx)): idx else: cast_int(L.top - L.ci.`func` + idx)

proc lua_gettop*(L: ptr lua_State): cint =
  return cast_int(L.top - (L.ci.`func` + 1))

proc lua_settop*(L: ptr lua_State; idx: cint) =
  var `func`: StkId = L.ci.`func`
  lua_lock(L)
  if idx >= 0:
    api_check(L, idx <= L.stack_last - (`func` + 1), "new top too large")
    while L.top < (`func` + 1) + idx:
      setnilvalue(inc(L.top))
    L.top = (`func` + 1) + idx
  else:
    api_check(L, -(idx + 1) <= (L.top - (`func` + 1)), "invalid new top")
    inc(L.top, idx + 1)
  lua_unlock(L)

proc lua_remove*(L: ptr lua_State; idx: cint) =
  var p: StkId
  lua_lock(L)
  p = index2addr(L, idx)
  api_checkstackindex(L, idx, p)
  while inc(p) < L.top:
    setobjs2s(L, p - 1, p)
  dec(L.top)
  lua_unlock(L)

proc lua_insert*(L: ptr lua_State; idx: cint) =
  var p: StkId
  var q: StkId
  lua_lock(L)
  p = index2addr(L, idx)
  api_checkstackindex(L, idx, p)
  q = L.top
  while q > p:
    setobjs2s(L, q, q - 1)
    dec(q)
  setobjs2s(L, p, L.top)
  lua_unlock(L)

proc moveto*(L: ptr lua_State; fr: ptr TValue; idx: cint) =
  var to: ptr TValue = index2addr(L, idx)
  api_checkvalidindex(L, to)
  setobj(L, to, fr)
  if idx < LUA_REGISTRYINDEX:
    luaC_barrier(L, clCvalue(L.ci.`func`), fr)

proc lua_replace*(L: ptr lua_State; idx: cint) =
  lua_lock(L)
  api_checknelems(L, 1)
  moveto(L, L.top - 1, idx)
  dec(L.top)
  lua_unlock(L)

proc lua_copy*(L: ptr lua_State; fromidx: cint; toidx: cint) =
  var fr: ptr TValue
  lua_lock(L)
  fr = index2addr(L, fromidx)
  moveto(L, fr, toidx)
  lua_unlock(L)

proc lua_pushvalue*(L: ptr lua_State; idx: cint) =
  lua_lock(L)
  setobj2s(L, L.top, index2addr(L, idx))
  api_incr_top(L)
  lua_unlock(L)


proc lua_type*(L: ptr lua_State; idx: cint): cint =
  var o: StkId = index2addr(L, idx)
  return if isvalid(o): ttypenv(o) else: LUA_TNONE

proc lua_typename*(L: ptr lua_State; t: cint): cstring =
  UNUSED(L)
  return ttypename(t)

proc lua_iscfunction*(L: ptr lua_State; idx: cint): cint =
  var o: StkId = index2addr(L, idx)
  return ttislcf(o) or (ttisCclosure(o))

proc lua_isnumber*(L: ptr lua_State; idx: cint): cint =
  var n: TValue
  let o: ptr TValue = index2addr(L, idx)
  return tonumber(o, addr(n))

proc lua_isstring*(L: ptr lua_State; idx: cint): cint =
  var t: cint = lua_type(L, idx)
  return t == LUA_TSTRING or t == LUA_TNUMBER

proc lua_isuserdata*(L: ptr lua_State; idx: cint): cint =
  let o: ptr TValue = index2addr(L, idx)
  return ttisuserdata(o) or ttislightuserdata(o)

proc lua_rawequal*(L: ptr lua_State; index1: cint; index2: cint): cint =
  var o1: StkId = index2addr(L, index1)
  var o2: StkId = index2addr(L, index2)
  return if (isvalid(o1) and isvalid(o2)): luaV_rawequalobj(o1, o2) else: 0

proc lua_arith*(L: ptr lua_State; op: cint) =
  var o1: StkId
  var o2: StkId
  lua_lock(L)
  if op != LUA_OPUNM:
    api_checknelems(L, 2)
  else:
    api_checknelems(L, 1)
    setobjs2s(L, L.top, L.top - 1)
    inc(L.top)
  o1 = L.top - 2
  o2 = L.top - 1
  if ttisnumber(o1) and ttisnumber(o2):
    setnvalue(o1, luaO_arith(op, nvalue(o1), nvalue(o2)))
  else:
    luaV_arith(L, o1, o1, o2, `cast`(TMS, op - LUA_OPADD + TM_ADD))
  dec(L.top)
  lua_unlock(L)

proc lua_compare*(L: ptr lua_State; index1: cint; index2: cint; op: cint): cint =
  var
    o1: StkId
    o2: StkId
  var i: cint = 0
  lua_lock(L)
  o1 = index2addr(L, index1)
  o2 = index2addr(L, index2)
  if isvalid(o1) and isvalid(o2):
    case op
    of LUA_OPEQ:
      i = equalobj(L, o1, o2)
    of LUA_OPLT:
      i = luaV_lessthan(L, o1, o2)
    of LUA_OPLE:
      i = luaV_lessequal(L, o1, o2)
    else:
      api_check(L, 0, "invalid option")
  lua_unlock(L)
  return i

proc lua_tonumberx*(L: ptr lua_State; idx: cint; isnum: ptr cint): lua_Number =
  var n: TValue
  let o: ptr TValue = index2addr(L, idx)
  if tonumber(o, addr(n)):
    if isnum:
      isnum[] = 1
    return nvalue(o)
  else:
    if isnum:
      isnum[] = 0
    return 0

proc lua_tointegerx*(L: ptr lua_State; idx: cint; isnum: ptr cint): lua_Integer =
  var n: TValue
  let o: ptr TValue = index2addr(L, idx)
  if tonumber(o, addr(n)):
    var res: lua_Integer
    var num: lua_Number = nvalue(o)
    lua_number2integer(res, num)
    if isnum:
      isnum[] = 1
    return res
  else:
    if isnum:
      isnum[] = 0
    return 0

proc lua_tounsignedx*(L: ptr lua_State; idx: cint; isnum: ptr cint): lua_Unsigned =
  var n: TValue
  let o: ptr TValue = index2addr(L, idx)
  if tonumber(o, addr(n)):
    var res: lua_Unsigned
    var num: lua_Number = nvalue(o)
    lua_number2unsigned(res, num)
    if isnum:
      isnum[] = 1
    return res
  else:
    if isnum:
      isnum[] = 0
    return 0

proc lua_toboolean*(L: ptr lua_State; idx: cint): cint =
  let o: ptr TValue = index2addr(L, idx)
  return not l_isfalse(o)

proc lua_tolstring*(L: ptr lua_State; idx: cint; len: ptr csize_t): cstring =
  var o: StkId = index2addr(L, idx)
  if not ttisstring(o):
    lua_lock(L)
    if not luaV_tostring(L, o):
      if len != nil:
        len[] = 0
      lua_unlock(L)
      return nil
    luaC_checkGC(L)
    o = index2addr(L, idx)
    lua_unlock(L)
  if len != nil:
    len[] = tsvalue(o).len
  return svalue(o)

proc lua_rawlen*(L: ptr lua_State; idx: cint): csize_t =
  var o: StkId = index2addr(L, idx)
  case ttypenv(o)
  of LUA_TSTRING:
    return tsvalue(o).len
  of LUA_TUSERDATA:
    return uvalue(o).len
  of LUA_TTABLE:
    return luaH_getn(hvalue(o))
  else:
    return 0

proc lua_tocfunction*(L: ptr lua_State; idx: cint): lua_CFunction =
  var o: StkId = index2addr(L, idx)
  if ttislcf(o):
    return fvalue(o)
  elif ttisCclosure(o):
    return clCvalue(o).f
  else:
    return nil

proc lua_touserdata*(L: ptr lua_State; idx: cint): pointer =
  var o: StkId = index2addr(L, idx)
  case ttypenv(o)
  of LUA_TUSERDATA:
    return rawuvalue(o) + 1
  of LUA_TLIGHTUSERDATA:
    return pvalue(o)
  else:
    return nil

proc lua_tothread*(L: ptr lua_State; idx: cint): ptr lua_State =
  var o: StkId = index2addr(L, idx)
  return if (not ttisthread(o)): nil else: thvalue(o)

proc lua_topointer*(L: ptr lua_State; idx: cint): pointer =
  var o: StkId = index2addr(L, idx)
  ## !!!Ignored construct:  switch ( ttype ( o ) ) { case LUA_TTABLE : return hvalue ( o ) ; case LUA_TLCL : return clLvalue ( o ) ; case LUA_TCCL : return clCvalue ( o ) ; case LUA_TLCF : return cast ( void * , cast ( size_t , fvalue ( o ) ) ) ; case LUA_TTHREAD : return thvalue ( o ) ; case LUA_TUSERDATA : case LUA_TLIGHTUSERDATA : return lua_touserdata ( L , idx ) ; default : return NULL ; } }
  ## Error: did not expect ,!!!


proc lua_pushnil*(L: ptr lua_State) =
  lua_lock(L)
  setnilvalue(L.top)
  api_incr_top(L)
  lua_unlock(L)

proc lua_pushnumber*(L: ptr lua_State; n: lua_Number) =
  lua_lock(L)
  setnvalue(L.top, n)
  luai_checknum(L, L.top,
                luaG_runerror(L, "C API - attempt to push a signaling NaN"))
  api_incr_top(L)
  lua_unlock(L)

proc lua_pushinteger*(L: ptr lua_State; n: lua_Integer) =
  lua_lock(L)
  setnvalue(L.top, cast_num(n))
  api_incr_top(L)
  lua_unlock(L)

proc lua_pushunsigned*(L: ptr lua_State; u: lua_Unsigned) =
  var n: lua_Number
  lua_lock(L)
  n = lua_unsigned2number(u)
  setnvalue(L.top, n)
  api_incr_top(L)
  lua_unlock(L)

proc lua_pushlstring*(L: ptr lua_State; s: cstring; len: csize_t): cstring =
  var ts: ptr TString
  lua_lock(L)
  luaC_checkGC(L)
  ts = luaS_newlstr(L, s, len)
  setsvalue2s(L, L.top, ts)
  api_incr_top(L)
  lua_unlock(L)
  return getstr(ts)

proc lua_pushstring*(L: ptr lua_State; s: cstring): cstring =
  if s == nil:
    lua_pushnil(L)
    return nil
  else:
    var ts: ptr TString
    lua_lock(L)
    luaC_checkGC(L)
    ts = luaS_new(L, s)
    setsvalue2s(L, L.top, ts)
    api_incr_top(L)
    lua_unlock(L)
    return getstr(ts)

proc lua_pushvfstring*(L: ptr lua_State; fmt: cstring; argp: va_list): cstring =
  let ret: cstring
  lua_lock(L)
  luaC_checkGC(L)
  ret = luaO_pushvfstring(L, fmt, argp)
  lua_unlock(L)
  return ret

proc lua_pushfstring*(L: ptr lua_State; fmt: cstring): cstring {.varargs.} =
  let ret: cstring
  var argp: va_list
  lua_lock(L)
  luaC_checkGC(L)
  va_start(argp, fmt)
  ret = luaO_pushvfstring(L, fmt, argp)
  va_end(argp)
  lua_unlock(L)
  return ret

proc lua_pushcclosure*(L: ptr lua_State; fn: lua_CFunction; n: cint) =
  lua_lock(L)
  if n == 0:
    setfvalue(L.top, fn)
  else:
    var cl: ptr Closure
    api_checknelems(L, n)
    api_check(L, n <= MAXUPVAL, "upvalue index too large")
    luaC_checkGC(L)
    cl = luaF_newCclosure(L, n)
    cl.c.f = fn
    dec(L.top, n)
    while dec(n):
      setobj2n(L, addr(cl.c.upvalue[n]), L.top + n)
    setclCvalue(L, L.top, cl)
  api_incr_top(L)
  lua_unlock(L)

proc lua_pushboolean*(L: ptr lua_State; b: cint) =
  lua_lock(L)
  setbvalue(L.top, (b != 0))
  api_incr_top(L)
  lua_unlock(L)

proc lua_pushlightuserdata*(L: ptr lua_State; p: pointer) =
  lua_lock(L)
  setpvalue(L.top, p)
  api_incr_top(L)
  lua_unlock(L)

proc lua_pushthread*(L: ptr lua_State): cint =
  lua_lock(L)
  setthvalue(L, L.top, L)
  api_incr_top(L)
  lua_unlock(L)
  return G(L).mainthread == L


proc lua_getglobal*(L: ptr lua_State; `var`: cstring) =
  var reg: ptr Table = hvalue(addr(G(L).l_registry))
  let gt: ptr TValue
  lua_lock(L)
  gt = luaH_getint(reg, LUA_RIDX_GLOBALS)
  setsvalue2s(L, inc(L.top), luaS_new(L, `var`))
  luaV_gettable(L, gt, L.top - 1, L.top - 1)
  lua_unlock(L)

proc lua_gettable*(L: ptr lua_State; idx: cint) =
  var t: StkId
  lua_lock(L)
  t = index2addr(L, idx)
  luaV_gettable(L, t, L.top - 1, L.top - 1)
  lua_unlock(L)

proc lua_getfield*(L: ptr lua_State; idx: cint; k: cstring) =
  var t: StkId
  lua_lock(L)
  t = index2addr(L, idx)
  setsvalue2s(L, L.top, luaS_new(L, k))
  api_incr_top(L)
  luaV_gettable(L, t, L.top - 1, L.top - 1)
  lua_unlock(L)

proc lua_rawget*(L: ptr lua_State; idx: cint) =
  var t: StkId
  lua_lock(L)
  t = index2addr(L, idx)
  api_check(L, ttistable(t), "table expected")
  setobj2s(L, L.top - 1, luaH_get(hvalue(t), L.top - 1))
  lua_unlock(L)

proc lua_rawgeti*(L: ptr lua_State; idx: cint; n: cint) =
  var t: StkId
  lua_lock(L)
  t = index2addr(L, idx)
  api_check(L, ttistable(t), "table expected")
  setobj2s(L, L.top, luaH_getint(hvalue(t), n))
  api_incr_top(L)
  lua_unlock(L)

proc lua_rawgetp*(L: ptr lua_State; idx: cint; p: pointer) =
  var t: StkId
  var k: TValue
  lua_lock(L)
  t = index2addr(L, idx)
  api_check(L, ttistable(t), "table expected")
  ## !!!Ignored construct:  setpvalue ( & k , cast ( void * , p ) ) ;
  ## Error: did not expect ,!!!
  setobj2s(L, L.top, luaH_get(hvalue(t), addr(k)))
  api_incr_top(L)
  lua_unlock(L)

proc lua_createtable*(L: ptr lua_State; narray: cint; nrec: cint) =
  var t: ptr Table
  lua_lock(L)
  luaC_checkGC(L)
  t = luaH_new(L)
  sethvalue(L, L.top, t)
  api_incr_top(L)
  if narray > 0 or nrec > 0:
    luaH_resize(L, t, narray, nrec)
  lua_unlock(L)

proc lua_getmetatable*(L: ptr lua_State; objindex: cint): cint =
  let obj: ptr TValue
  var mt: ptr Table = nil
  var res: cint
  lua_lock(L)
  obj = index2addr(L, objindex)
  case ttypenv(obj)
  of LUA_TTABLE:
    mt = hvalue(obj).metatable
  of LUA_TUSERDATA:
    mt = uvalue(obj).metatable
  else:
    mt = G(L).mt[ttypenv(obj)]
  if mt == nil:
    res = 0
  else:
    sethvalue(L, L.top, mt)
    api_incr_top(L)
    res = 1
  lua_unlock(L)
  return res

proc lua_getuservalue*(L: ptr lua_State; idx: cint) =
  var o: StkId
  lua_lock(L)
  o = index2addr(L, idx)
  api_check(L, ttisuserdata(o), "userdata expected")
  if uvalue(o).env:
    sethvalue(L, L.top, uvalue(o).env)
  else:
    setnilvalue(L.top)
  api_incr_top(L)
  lua_unlock(L)


proc lua_setglobal*(L: ptr lua_State; `var`: cstring) =
  var reg: ptr Table = hvalue(addr(G(L).l_registry))
  let gt: ptr TValue
  lua_lock(L)
  api_checknelems(L, 1)
  gt = luaH_getint(reg, LUA_RIDX_GLOBALS)
  setsvalue2s(L, inc(L.top), luaS_new(L, `var`))
  luaV_settable(L, gt, L.top - 1, L.top - 2)
  dec(L.top, 2)
  lua_unlock(L)

proc lua_settable*(L: ptr lua_State; idx: cint) =
  var t: StkId
  lua_lock(L)
  api_checknelems(L, 2)
  t = index2addr(L, idx)
  luaV_settable(L, t, L.top - 2, L.top - 1)
  dec(L.top, 2)
  lua_unlock(L)

proc lua_setfield*(L: ptr lua_State; idx: cint; k: cstring) =
  var t: StkId
  lua_lock(L)
  api_checknelems(L, 1)
  t = index2addr(L, idx)
  setsvalue2s(L, inc(L.top), luaS_new(L, k))
  luaV_settable(L, t, L.top - 1, L.top - 2)
  dec(L.top, 2)
  lua_unlock(L)

proc lua_rawset*(L: ptr lua_State; idx: cint) =
  var t: StkId
  lua_lock(L)
  api_checknelems(L, 2)
  t = index2addr(L, idx)
  api_check(L, ttistable(t), "table expected")
  setobj2t(L, luaH_set(L, hvalue(t), L.top - 2), L.top - 1)
  invalidateTMcache(hvalue(t))
  luaC_barrierback(L, gcvalue(t), L.top - 1)
  dec(L.top, 2)
  lua_unlock(L)

proc lua_rawseti*(L: ptr lua_State; idx: cint; n: cint) =
  var t: StkId
  lua_lock(L)
  api_checknelems(L, 1)
  t = index2addr(L, idx)
  api_check(L, ttistable(t), "table expected")
  luaH_setint(L, hvalue(t), n, L.top - 1)
  luaC_barrierback(L, gcvalue(t), L.top - 1)
  dec(L.top)
  lua_unlock(L)

proc lua_rawsetp*(L: ptr lua_State; idx: cint; p: pointer) =
  var t: StkId
  var k: TValue
  lua_lock(L)
  api_checknelems(L, 1)
  t = index2addr(L, idx)
  api_check(L, ttistable(t), "table expected")
  ## !!!Ignored construct:  setpvalue ( & k , cast ( void * , p ) ) ;
  ## Error: did not expect ,!!!
  setobj2t(L, luaH_set(L, hvalue(t), addr(k)), L.top - 1)
  luaC_barrierback(L, gcvalue(t), L.top - 1)
  dec(L.top)
  lua_unlock(L)

proc lua_setmetatable*(L: ptr lua_State; objindex: cint): cint =
  var obj: ptr TValue
  var mt: ptr Table
  lua_lock(L)
  api_checknelems(L, 1)
  obj = index2addr(L, objindex)
  if ttisnil(L.top - 1):
    mt = nil
  else:
    api_check(L, ttistable(L.top - 1), "table expected")
    mt = hvalue(L.top - 1)
  case ttypenv(obj)
  of LUA_TTABLE:
    hvalue(obj).metatable = mt
    if mt:
      luaC_objbarrierback(L, gcvalue(obj), mt)
      luaC_checkfinalizer(L, gcvalue(obj), mt)
    break
  of LUA_TUSERDATA:
    uvalue(obj).metatable = mt
    if mt:
      luaC_objbarrier(L, rawuvalue(obj), mt)
      luaC_checkfinalizer(L, gcvalue(obj), mt)
    break
  else:
    G(L).mt[ttypenv(obj)] = mt
    break
  dec(L.top)
  lua_unlock(L)
  return 1

proc lua_setuservalue*(L: ptr lua_State; idx: cint) =
  var o: StkId
  lua_lock(L)
  api_checknelems(L, 1)
  o = index2addr(L, idx)
  api_check(L, ttisuserdata(o), "userdata expected")
  if ttisnil(L.top - 1):
    uvalue(o).env = nil
  else:
    api_check(L, ttistable(L.top - 1), "table expected")
    uvalue(o).env = hvalue(L.top - 1)
    luaC_objbarrier(L, gcvalue(o), hvalue(L.top - 1))
  dec(L.top)
  lua_unlock(L)


template checkresults*(L, na, nr: untyped): untyped =
  api_check(L, (nr) == LUA_MULTRET or (L.ci.top - L.top >= (nr) - (na)),
            "results from function overflow current stack size")

proc lua_getctx*(L: ptr lua_State; ctx: ptr cint): cint =
  if L.ci.callstatus and CIST_YIELDED:
    if ctx:
      ctx[] = L.ci.u.c.ctx
    return L.ci.u.c.status
  else:
    return LUA_OK

proc lua_callk*(L: ptr lua_State; nargs: cint; nresults: cint; ctx: cint; k: lua_CFunction) =
  var `func`: StkId
  lua_lock(L)
  api_check(L, k == nil or not isLua(L.ci), "cannot use continuations inside hooks")
  api_checknelems(L, nargs + 1)
  api_check(L, L.status == LUA_OK, "cannot do calls on non-normal thread")
  checkresults(L, nargs, nresults)
  `func` = L.top - (nargs + 1)
  if k != nil and L.nny == 0:
    L.ci.u.c.k = k
    L.ci.u.c.ctx = ctx
    luaD_call(L, `func`, nresults, 1)
  else:
    luaD_call(L, `func`, nresults, 0)
  adjustresults(L, nresults)
  lua_unlock(L)


type
  CallS* {.bycopy.} = object
    `func`*: StkId
    nresults*: cint


proc f_call*(L: ptr lua_State; ud: pointer) =
  ## !!!Ignored construct:  struct CallS * c = cast ( struct CallS * , ud ) ;
  ## Error: did not expect ,!!!
  luaD_call(L, c.`func`, c.nresults, 0)

proc lua_pcallk*(L: ptr lua_State; nargs: cint; nresults: cint; errfunc: cint; ctx: cint;
                k: lua_CFunction): cint =
  var c: CallS
  var status: cint
  var `func`: ptrdiff_t
  lua_lock(L)
  api_check(L, k == nil or not isLua(L.ci), "cannot use continuations inside hooks")
  api_checknelems(L, nargs + 1)
  api_check(L, L.status == LUA_OK, "cannot do calls on non-normal thread")
  checkresults(L, nargs, nresults)
  if errfunc == 0:
    `func` = 0
  else:
    var o: StkId = index2addr(L, errfunc)
    api_checkstackindex(L, errfunc, o)
    `func` = savestack(L, o)
  c.`func` = L.top - (nargs + 1)
  if k == nil or L.nny > 0:
    c.nresults = nresults
    status = luaD_pcall(L, f_call, addr(c), savestack(L, c.`func`), `func`)
  else:
    var ci: ptr CallInfo = L.ci
    ci.u.c.k = k
    ci.u.c.ctx = ctx
    ci.extra = savestack(L, c.`func`)
    ci.u.c.old_allowhook = L.allowhook
    ci.u.c.old_errfunc = L.errfunc
    L.errfunc = `func`
    ci.callstatus = ci.callstatus or CIST_YPCALL
    luaD_call(L, c.`func`, nresults, 1)
    ci.callstatus = ci.callstatus and not CIST_YPCALL
    L.errfunc = ci.u.c.old_errfunc
    status = LUA_OK
  adjustresults(L, nresults)
  lua_unlock(L)
  return status

proc lua_load*(L: ptr lua_State; reader: lua_Reader; data: pointer; chunkname: cstring;
              mode: cstring): cint =
  var z: ZIO
  var status: cint
  lua_lock(L)
  if not chunkname:
    chunkname = "?"
  luaZ_init(L, addr(z), reader, data)
  status = luaD_protectedparser(L, addr(z), chunkname, mode)
  if status == LUA_OK:
    var f: ptr LClosure = clLvalue(L.top - 1)
    if f.nupvalues == 1:
      var reg: ptr Table = hvalue(addr(G(L).l_registry))
      let gt: ptr TValue = luaH_getint(reg, LUA_RIDX_GLOBALS)
      setobj(L, f.upvals[0].v, gt)
      luaC_barrier(L, f.upvals[0], gt)
  lua_unlock(L)
  return status

proc lua_dump*(L: ptr lua_State; writer: lua_Writer; data: pointer): cint =
  var status: cint
  var o: ptr TValue
  lua_lock(L)
  api_checknelems(L, 1)
  o = L.top - 1
  if isLfunction(o):
    status = luaU_dump(L, getproto(o), writer, data, 0)
  else:
    status = 1
  lua_unlock(L)
  return status

proc lua_status*(L: ptr lua_State): cint =
  return L.status


proc lua_gc*(L: ptr lua_State; what: cint; data: cint): cint =
  var res: cint = 0
  var g: ptr global_State
  lua_lock(L)
  g = G(L)
  case what
  of LUA_GCSTOP:
    g.gcrunning = 0
    break
  of LUA_GCRESTART:
    luaE_setdebt(g, 0)
    g.gcrunning = 1
    break
  of LUA_GCCOLLECT:
    luaC_fullgc(L, 0)
    break
  of LUA_GCCOUNT:
    res = cast_int(gettotalbytes(g) shr 10)
    break
  of LUA_GCCOUNTB:
    res = cast_int(gettotalbytes(g) and 0x3ff)
    break
  of LUA_GCSTEP:
    if g.gckind == KGC_GEN:
      res = (g.GCestimate == 0)
      luaC_forcestep(L)
    else:
      var debt: lu_mem = `cast`(lu_mem, data) * 1024 - GCSTEPSIZE
      if g.gcrunning:
        inc(debt, g.GCdebt)
      luaE_setdebt(g, debt)
      luaC_forcestep(L)
      if g.gcstate == GCSpause:
        res = 1
    break
  of LUA_GCSETPAUSE:
    res = g.gcpause
    g.gcpause = data
    break
  of LUA_GCSETMAJORINC:
    res = g.gcmajorinc
    g.gcmajorinc = data
    break
  of LUA_GCSETSTEPMUL:
    res = g.gcstepmul
    g.gcstepmul = data
    break
  of LUA_GCISRUNNING:
    res = g.gcrunning
    break
  of LUA_GCGEN:
    luaC_changemode(L, KGC_GEN)
    break
  of LUA_GCINC:
    luaC_changemode(L, KGC_NORMAL)
    break
  else:
    res = -1
  lua_unlock(L)
  return res


proc lua_error*(L: ptr lua_State): cint =
  lua_lock(L)
  api_checknelems(L, 1)
  luaG_errormsg(L)
  return 0

proc lua_next*(L: ptr lua_State; idx: cint): cint =
  var t: StkId
  var more: cint
  lua_lock(L)
  t = index2addr(L, idx)
  api_check(L, ttistable(t), "table expected")
  more = luaH_next(L, hvalue(t), L.top - 1)
  if more:
    api_incr_top(L)
  else:
    dec(L.top, 1)
  lua_unlock(L)
  return more

proc lua_concat*(L: ptr lua_State; n: cint) =
  lua_lock(L)
  api_checknelems(L, n)
  if n >= 2:
    luaC_checkGC(L)
    luaV_concat(L, n)
  elif n == 0:
    setsvalue2s(L, L.top, luaS_newlstr(L, "", 0))
    api_incr_top(L)
  lua_unlock(L)

proc lua_len*(L: ptr lua_State; idx: cint) =
  var t: StkId
  lua_lock(L)
  t = index2addr(L, idx)
  luaV_objlen(L, L.top, t)
  api_incr_top(L)
  lua_unlock(L)

proc lua_getallocf*(L: ptr lua_State; ud: ptr pointer): lua_Alloc =
  var f: lua_Alloc
  lua_lock(L)
  if ud:
    ud[] = G(L).ud
  f = G(L).frealloc
  lua_unlock(L)
  return f

proc lua_setallocf*(L: ptr lua_State; f: lua_Alloc; ud: pointer) =
  lua_lock(L)
  G(L).ud = ud
  G(L).frealloc = f
  lua_unlock(L)

proc lua_newuserdata*(L: ptr lua_State; size: csize_t): pointer =
  var u: ptr Udata
  lua_lock(L)
  luaC_checkGC(L)
  u = luaS_newudata(L, size, nil)
  setuvalue(L, L.top, u)
  api_incr_top(L)
  lua_unlock(L)
  return u + 1

proc aux_upvalue*(fi: StkId; n: cint; val: ptr ptr TValue; owner: ptr ptr GCObject): cstring =
  case ttype(fi)
  of LUA_TCCL:
    var f: ptr CClosure = clCvalue(fi)
    if not (1 <= n and n <= f.nupvalues):
      return nil
    val[] = addr(f.upvalue[n - 1])
    if owner:
      owner[] = obj2gco(f)
    return ""
  of LUA_TLCL:
    var f: ptr LClosure = clLvalue(fi)
    var name: ptr TString
    var p: ptr Proto = f.p
    if not (1 <= n and n <= p.sizeupvalues):
      return nil
    val[] = f.upvals[n - 1].v
    if owner:
      owner[] = obj2gco(f.upvals[n - 1])
    name = p.upvalues[n - 1].name
    return if (name == nil): "" else: getstr(name)
  else:
    return nil

proc lua_getupvalue*(L: ptr lua_State; funcindex: cint; n: cint): cstring =
  let name: cstring
  var val: ptr TValue = nil
  lua_lock(L)
  name = aux_upvalue(index2addr(L, funcindex), n, addr(val), nil)
  if name:
    setobj2s(L, L.top, val)
    api_incr_top(L)
  lua_unlock(L)
  return name

proc lua_setupvalue*(L: ptr lua_State; funcindex: cint; n: cint): cstring =
  let name: cstring
  var val: ptr TValue = nil
  var owner: ptr GCObject = nil
  var fi: StkId
  lua_lock(L)
  fi = index2addr(L, funcindex)
  api_checknelems(L, 1)
  name = aux_upvalue(fi, n, addr(val), addr(owner))
  if name:
    dec(L.top)
    setobj(L, val, L.top)
    luaC_barrier(L, owner, L.top)
  lua_unlock(L)
  return name

proc getupvalref*(L: ptr lua_State; fidx: cint; n: cint; pf: ptr ptr LClosure): ptr ptr UpVal =
  var f: ptr LClosure
  var fi: StkId = index2addr(L, fidx)
  api_check(L, ttisLclosure(fi), "Lua function expected")
  f = clLvalue(fi)
  api_check(L, (1 <= n and n <= f.p.sizeupvalues), "invalid upvalue index")
  if pf:
    pf[] = f
  return addr(f.upvals[n - 1])

proc lua_upvalueid*(L: ptr lua_State; fidx: cint; n: cint): pointer =
  var fi: StkId = index2addr(L, fidx)
  case ttype(fi)
  of LUA_TLCL:
    return getupvalref(L, fidx, n, nil)[]
  of LUA_TCCL:
    var f: ptr CClosure = clCvalue(fi)
    api_check(L, 1 <= n and n <= f.nupvalues, "invalid upvalue index")
    return addr(f.upvalue[n - 1])
  else:
    api_check(L, 0, "closure expected")
    return nil

proc lua_upvaluejoin*(L: ptr lua_State; fidx1: cint; n1: cint; fidx2: cint; n2: cint) =
  var f1: ptr LClosure
  var up1: ptr ptr UpVal = getupvalref(L, fidx1, n1, addr(f1))
  var up2: ptr ptr UpVal = getupvalref(L, fidx2, n2, nil)
  up1[] = up2[]
  luaC_objbarrier(L, f1, up2[])
