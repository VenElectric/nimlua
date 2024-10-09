##
## * $Id: lobject.c,v 2.58.1.1 2013/04/12 18:48:47 roberto Exp $
## * Some generic functions over Lua objects
## * See Copyright Notice in lua.h
##

import
  lua, lctype, ldebug, ldo, lmem, lobject, lstate, lstring, lvm

## !!!Ignored construct:  LUAI_DDEF const TValue luaO_nilobject_ = { NILCONSTANT } ;
## Error: token expected: ; but got: [identifier]!!!

##
## * converts an integer to a "floating point byte", represented as
## * (eeeeexxx), where the real value is (1xxx) * 2^(eeeee - 1) if
## * eeeee != 0 and (xxx) otherwise.
##

proc luaO_int2fb*(x: cuint): cint =
  var e: cint = 0
  ##  exponent
  if x < 8:
    return x
  while x >= 0x10:
    x = (x + 1) shr 1
    inc(e)
  return ((e + 1) shl 3) or (cast_int(x) - 8)

##  converts back

proc luaO_fb2int*(x: cint): cint =
  var e: cint = (x shr 3) and 0x1f
  if e == 0:
    return x
  else:
    return ((x and 7) + 8) shl (e - 1)

proc luaO_ceillog2*(x: cuint): cint =
  let log_2: array[256, lu_byte] = [0, 1, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5,
                               5, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
                               6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7,
                               7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
                               7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
                               7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
                               8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
                               8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
                               8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
                               8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
                               8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8]
  var l: cint = 0
  dec(x)
  while x >= 256:
    inc(l, 8)
    x = x shr 8
  return l + log_2[x]

proc luaO_arith*(op: cint; v1: lua_Number; v2: lua_Number): lua_Number =
  case op
  of LUA_OPADD:
    return luai_numadd(nil, v1, v2)
  of LUA_OPSUB:
    return luai_numsub(nil, v1, v2)
  of LUA_OPMUL:
    return luai_nummul(nil, v1, v2)
  of LUA_OPDIV:
    return luai_numdiv(nil, v1, v2)
  of LUA_OPMOD:
    return luai_nummod(nil, v1, v2)
  of LUA_OPPOW:
    return luai_numpow(nil, v1, v2)
  of LUA_OPUNM:
    return luai_numunm(nil, v1)
  else:
    lua_assert(0)
    return 0

proc luaO_hexavalue*(c: cint): cint =
  if lisdigit(c):
    return c - '0'
  else:
    return ltolower(c) - 'a' + 10

when not defined(lua_strx2number):
  proc isneg*(s: cstringArray): cint =
    if s[][] == '-':
      inc((s[]))
      return 1
    elif s[][] == '+':
      inc((s[]))
    return 0

  proc readhexa*(s: cstringArray; r: lua_Number; count: ptr cint): lua_Number =
    while lisxdigit(cast_uchar(s[][])):
      ##  read integer part
      r = (r * cast_num(16.0)) + cast_num(luaO_hexavalue(cast_uchar(s[][])))
      inc((count[]))
      inc((s[]))
    return r

  ##
  ## * convert an hexadecimal numeric string to a number, following
  ## * C99 specification for 'strtod'
  ##
  proc lua_strx2number*(s: cstring; endptr: cstringArray): lua_Number =
    var r: lua_Number = 0.0
    var
      e: cint = 0
      i: cint = 0
    var neg: cint = 0
    ##  1 if number is negative
    ## !!!Ignored construct:  * endptr = cast ( char * , s ) ;
    ## Error: did not expect ,!!!
    ##  nothing is valid yet
    while lisspace(cast_uchar(s[])):
      inc(s)
    ##  skip initial spaces
    neg = isneg(addr(s))
    ##  check signal
    if not (s[] == '0' and ((s + 1)[] == 'x' or (s + 1)[] == 'X')):
      return 0.0
    inc(s, 2)
    ##  skip '0x'
    r = readhexa(addr(s), r, addr(i))
    ##  read integer part
    if s[] == '.':
      inc(s)
      ##  skip dot
      r = readhexa(addr(s), r, addr(e))
      ##  read fractional part
    if i == 0 and e == 0:
      return 0.0
    e = e * -4
    ##  each fractional digit divides value by 2^-4
    ## !!!Ignored construct:  * endptr = cast ( char * , s ) ;
    ## Error: did not expect ,!!!
    ##  valid up to here
    if s[] == 'p' or s[] == 'P':
      ##  exponent part?
      var exp1: cint = 0
      var neg1: cint
      inc(s)
      ##  skip 'p'
      neg1 = isneg(addr(s))
      ##  signal
      if not lisdigit(cast_uchar(s[])):
        break ret
      while lisdigit(cast_uchar(s[])): ##  read exponent
        exp1 = exp1 * 10 + (inc(s))[] - '0'
      if neg1:
        exp1 = -exp1
      inc(e, exp1)
    ## !!!Ignored construct:  * endptr = cast ( char * , s ) ;
    ## Error: did not expect ,!!!
    ##  valid up to here
    if neg:
      r = -r
    return l_mathop(ldexp)(r, e)

proc luaO_str2d*(s: cstring; len: csize_t; result: ptr lua_Number): cint =
  var endptr: cstring
  if strpbrk(s, "nN"):
    return 0
  elif strpbrk(s, "xX"):        ##  hexa?
    result[] = lua_strx2number(s, addr(endptr))
  else:
    result[] = lua_str2number(s, addr(endptr))
  if endptr == s:
    return 0
  while lisspace(cast_uchar(endptr[])):
    inc(endptr)
  return endptr == s + len
  ##  OK if no trailing characters

proc pushstr*(L: ptr lua_State; str: cstring; l: csize_t) =
  setsvalue2s(L, inc(L.top), luaS_newlstr(L, str, l))

##  this function handles only `%d', `%c', %f, %p, and `%s' formats

proc luaO_pushvfstring*(L: ptr lua_State; fmt: cstring; argp: va_list): cstring =
  var n: cint = 0
  while true:
    let e: cstring = strchr(fmt, '%')
    if e == nil:
      break
    luaD_checkstack(L, 2)
    ##  fmt + item
    pushstr(L, fmt, e - fmt)
    case (e + 1)[]
    of 's':
      ## !!!Ignored construct:  const char * s = va_arg ( argp , char * ) ;
      ## Error: did not expect )!!!
      if s == nil:
        s = "(null)"
      pushstr(L, s, strlen(s))
      break
    of 'c':
      var buff: char
      buff = `cast`(char, va_arg(argp, int))
      pushstr(L, addr(buff), 1)
      break
    of 'd':
      setnvalue(inc(L.top), cast_num(va_arg(argp, int)))
      break
    of 'f':
      setnvalue(inc(L.top), cast_num(va_arg(argp, l_uacNumber)))
      break
    of 'p':
      var buff: array[4 * sizeof(cast[pointer](+8)), char]
      ##  should be enough space for a `%p'
      ## !!!Ignored construct:  int l = sprintf ( buff , %p , va_arg ( argp , void * ) ) ;
      ## Error: did not expect )!!!
      pushstr(L, buff, l)
      break
    of '%':
      pushstr(L, "%", 1)
      break
    else:
      luaG_runerror(L, "invalid option ", LUA_QL("%%%c"), " to ",
                    LUA_QL("lua_pushfstring"), (e + 1)[])
    inc(n, 2)
    fmt = e + 2
  luaD_checkstack(L, 1)
  pushstr(L, fmt, strlen(fmt))
  if n > 0:
    luaV_concat(L, n + 1)
  return svalue(L.top - 1)

proc luaO_pushfstring*(L: ptr lua_State; fmt: cstring): cstring {.varargs.} =
  let msg: cstring
  var argp: va_list
  va_start(argp, fmt)
  msg = luaO_pushvfstring(L, fmt, argp)
  va_end(argp)
  return msg

##  number of chars of a literal string without the ending \0

template LL*(x: untyped): untyped =
  (sizeof((x) div sizeof((char))) - 1)

const
  RETS* = "..."
  PRE* = "[string \""
  POS* = "\"]"

template addstr*(a, b, l: untyped): untyped =
  (
    memcpy(a, b, (l) * sizeof((char)))
    inc(a, (l)))

proc luaO_chunkid*(`out`: cstring; source: cstring; bufflen: csize_t) =
  var l: csize_t = strlen(source)
  if source[] == '=':
    ##  'literal' source
    if l <= bufflen:
      memcpy(`out`, source + 1, l * sizeof((char)))
    else:
      ##  truncate it
      addstr(`out`, source + 1, bufflen - 1)
      `out`[] = '\x00'
  elif source[] == '@':
    ##  file name
    if l <= bufflen:
      memcpy(`out`, source + 1, l * sizeof((char)))
    else:
      ##  add '...' before rest of name
      addstr(`out`, RETS, LL(RETS))
      dec(bufflen, LL(RETS))
      memcpy(`out`, source + 1 + l - bufflen, bufflen * sizeof((char)))
  else:
    ##  string; format as [string "source"]
    let nl: cstring = strchr(source, '\n')
    ##  find first new line (if any)
    addstr(`out`, PRE, LL(PRE))
    ##  add prefix
    dec(bufflen, LL(PRE, RETS, POS) + 1)
    ##  save space for prefix+suffix+'\0'
    if l < bufflen and nl == nil:
      ##  small one-line source?
      addstr(`out`, source, l)
      ##  keep it
    else:
      if nl != nil:
        l = nl - source
      if l > bufflen:
        l = bufflen
      addstr(`out`, source, l)
      addstr(`out`, RETS, LL(RETS))
    memcpy(`out`, POS, (LL(POS) + 1) * sizeof((char)))
