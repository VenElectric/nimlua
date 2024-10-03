

import
  lua, lctype, ldo, llex, lobject, lparser, lstate, lstring, ltable, lzio

template next*(ls: untyped): untyped =
  (ls.current = zgetc(ls.z))

template currIsNewline*(ls: untyped): untyped =
  (ls.current == '\n' or ls.current == '\r')


let luaX_tokens* = ["and", "break", "do", "else", "elseif",
    "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or",
    "repeat", "return", "then", "true", "until", "while", "..", "...", "==", ">=", "<=",
    "~=", "::", "<eof>", "<number>", "<name>", "<string>"]

template save_and_next*(ls: untyped): untyped =
  (
    save(ls, ls.current)
    next(ls))

proc lexerror*(ls: ptr LexState; msg: cstring; token: cint): l_noret
proc save*(ls: ptr LexState; c: cint) =
  var b: ptr Mbuffer = ls.buff
  if luaZ_bufflen(b) + 1 > luaZ_sizebuffer(b):
    var newsize: csize_t
    if luaZ_sizebuffer(b) >= MAX_SIZET div 2:
      lexerror(ls, "lexical element too long", 0)
    newsize = luaZ_sizebuffer(b) * 2
    luaZ_resizebuffer(ls.L, b, newsize)
  b.buffer[inc(luaZ_bufflen(b))] = `cast`(char, c)

proc luaX_init*(L: ptr lua_State) =
  var i: cint
  i = 0
  while i < NUM_RESERVED:
    var ts: ptr TString = luaS_new(L, luaX_tokens[i])
    luaS_fix(ts)
    ts.tsv.extra = cast_byte(i + 1)
    inc(i)

proc luaX_token2str*(ls: ptr LexState; token: cint): cstring =
  if token < FIRST_RESERVED:
    lua_assert(token == `cast`(unsigned, char, token))
    return if (lisprint(token)): luaO_pushfstring(ls.L, LUA_QL("%c"), token) else: luaO_pushfstring(
        ls.L, "char(%d)", token)
  else:
    let s: cstring = luaX_tokens[token - FIRST_RESERVED]
    if token < TK_EOS:
      return luaO_pushfstring(ls.L, LUA_QS, s)
    else:
      return s

proc txtToken*(ls: ptr LexState; token: cint): cstring =
  case token
  of TK_NAME, TK_STRING, TK_NUMBER:
    save(ls, '\x00')
    return luaO_pushfstring(ls.L, LUA_QS, luaZ_buffer(ls.buff))
  else:
    return luaX_token2str(ls, token)

proc lexerror*(ls: ptr LexState; msg: cstring; token: cint): l_noret =
  var buff: array[LUA_IDSIZE, char]
  luaO_chunkid(buff, getstr(ls.source), LUA_IDSIZE)
  msg = luaO_pushfstring(ls.L, "%s:%d: %s", buff, ls.linenumber, msg)
  if token:
    luaO_pushfstring(ls.L, "%s near %s", msg, txtToken(ls, token))
  luaD_throw(ls.L, LUA_ERRSYNTAX)

proc luaX_syntaxerror*(ls: ptr LexState; msg: cstring): l_noret =
  lexerror(ls, msg, ls.t.token)


proc luaX_newstring*(ls: ptr LexState; str: cstring; l: csize_t): ptr TString =
  var L: ptr lua_State = ls.L
  var o: ptr TValue
  var ts: ptr TString = luaS_newlstr(L, str, l)
  setsvalue2s(L, inc(L.top), ts)
  o = luaH_set(L, ls.fs.h, L.top - 1)
  if ttisnil(o):
    setbvalue(o, 1)
    luaC_checkGC(L)
  else:
    ts = rawtsvalue(keyfromval(o))
  dec(L.top)
  return ts


proc inclinenumber*(ls: ptr LexState) =
  var old: cint = ls.current
  lua_assert(currIsNewline(ls))
  next(ls)
  if currIsNewline(ls) and ls.current != old:
    next(ls)
  if inc(ls.linenumber) >= MAX_INT:
    lexerror(ls, "chunk has too many lines", 0)

proc luaX_setinput*(L: ptr lua_State; ls: ptr LexState; z: ptr ZIO; source: ptr TString;
                   firstchar: cint) =
  ls.decpoint = '.'
  ls.L = L
  ls.current = firstchar
  ls.lookahead.token = TK_EOS
  ls.z = z
  ls.fs = nil
  ls.linenumber = 1
  ls.lastline = 1
  ls.source = source
  ls.envn = luaS_new(L, LUA_ENV)
  luaS_fix(ls.envn)
  luaZ_resizebuffer(ls.L, ls.buff, LUA_MINBUFFER)


proc check_next*(ls: ptr LexState; set: cstring): cint =
  if ls.current == '\x00' or not strchr(set, ls.current):
    return 0
  save_and_next(ls)
  return 1


proc buffreplace*(ls: ptr LexState; `from`: char; to: char) =
  var n: csize_t = luaZ_bufflen(ls.buff)
  var p: cstring = luaZ_buffer(ls.buff)
  while dec(n):
    if p[n] == `from`:
      p[n] = to

when not defined(getlocaledecpoint):
  template getlocaledecpoint*(): untyped =
    (localeconv().decimal_point[0])

template buff2d*(b, e: untyped): untyped =
  luaO_str2d(luaZ_buffer(b), luaZ_bufflen(b) - 1, e)


proc trydecpoint*(ls: ptr LexState; seminfo: ptr SemInfo) =
  var old: char = ls.decpoint
  ls.decpoint = getlocaledecpoint()
  buffreplace(ls, old, ls.decpoint)
  if not buff2d(ls.buff, addr(seminfo.r)):
    buffreplace(ls, ls.decpoint, '.')
    lexerror(ls, "malformed number", TK_NUMBER)


proc read_numeral*(ls: ptr LexState; seminfo: ptr SemInfo) =
  let expo: cstring = "Ee"
  var first: cint = ls.current
  lua_assert(lisdigit(ls.current))
  save_and_next(ls)
  if first == '0' and check_next(ls, "Xx"):
    expo = "Pp"
  while true:
    if check_next(ls, expo):
      check_next(ls, "+-")
    if lisxdigit(ls.current) or ls.current == '.':
      save_and_next(ls)
    else:
      break
  save(ls, '\x00')
  buffreplace(ls, '.', ls.decpoint)
  if not buff2d(ls.buff, addr(seminfo.r)):
    trydecpoint(ls, seminfo)


proc skip_sep*(ls: ptr LexState): cint =
  var count: cint = 0
  var s: cint = ls.current
  lua_assert(s == '[' or s == ']')
  save_and_next(ls)
  while ls.current == '=':
    save_and_next(ls)
    inc(count)
  return if (ls.current == s): count else: (-count) - 1

proc read_long_string*(ls: ptr LexState; seminfo: ptr SemInfo; sep: cint) =
  save_and_next(ls)
  if currIsNewline(ls):
    inclinenumber(ls)
  while true:
    case ls.current
    of EOZ:
      lexerror(ls, if (seminfo): "unfinished long string" else: "unfinished long comment",
               TK_EOS)
    of ']':
      if skip_sep(ls) == sep:
        save_and_next(ls)
        break endloop
      break
    of '\n', '\r':
      save(ls, '\n')
      inclinenumber(ls)
      if not seminfo:
        luaZ_resetbuffer(ls.buff)
      break
    else:
      if seminfo:
        save_and_next(ls)
      else:
        next(ls)
  if seminfo:
    seminfo.ts = luaX_newstring(ls, luaZ_buffer(ls.buff) + (2 + sep),
                              luaZ_bufflen(ls.buff) - 2 * (2 + sep))

proc escerror*(ls: ptr LexState; c: ptr cint; n: cint; msg: cstring) =
  var i: cint
  luaZ_resetbuffer(ls.buff)
  save(ls, '\\')
  i = 0
  while i < n and c[i] != EOZ:
    save(ls, c[i])
    inc(i)
  lexerror(ls, msg, TK_STRING)

proc readhexaesc*(ls: ptr LexState): cint =
  var
    c: array[3, cint]
    i: cint
  var r: cint = 0
  c[0] = 'x'
  i = 1
  while i < 3:
    c[i] = next(ls)
    if not lisxdigit(c[i]):
      escerror(ls, c, i + 1, "hexadecimal digit expected")
    r = (r shl 4) + luaO_hexavalue(c[i])
    inc(i)
  return r

proc readdecesc*(ls: ptr LexState): cint =
  var
    c: array[3, cint]
    i: cint
  var r: cint = 0
  i = 0
  while i < 3 and lisdigit(ls.current):
    c[i] = ls.current
    r = 10 * r + c[i] - '0'
    next(ls)
    inc(i)
  if r > UCHAR_MAX:
    escerror(ls, c, i, "decimal escape too large")
  return r

proc read_string*(ls: ptr LexState; del: cint; seminfo: ptr SemInfo) =
  save_and_next(ls)
  while ls.current != del:
    case ls.current
    of EOZ:
      lexerror(ls, "unfinished string", TK_EOS)
    of '\n', '\r':
      lexerror(ls, "unfinished string", TK_STRING)
    of '\\':
      var c: cint
      next(ls)
      ## !!!Ignored construct:  switch ( ls -> current ) { case [char literal] : c = 7 ; goto read_save ; case [char literal] : c = [char literal] ; goto read_save ; case [char literal] : c = [char literal] ; goto read_save ; case [char literal] : c = [char literal] ; goto read_save ; case [char literal] : c = [char literal] ; goto read_save ; case [char literal] : c = [char literal] ; goto read_save ; case [char literal] : c = 11 ; goto read_save ; case [char literal] : c = readhexaesc ( ls ) ; goto read_save ; case [char literal] : case [char literal] : inclinenumber ( ls ) ; c = [char literal] ; goto only_save ; case [char literal] : case [char literal] : case [char literal] : c = ls -> current ; goto read_save ; case EOZ : goto no_save ;  will raise an error next loop case [char literal] : {  zap following span of spaces next ( ls ) ;  skip the 'z' while ( lisspace ( ls -> current ) ) { if ( currIsNewline ( ls ) ) inclinenumber ( ls ) ; else next ( ls ) ; } goto no_save ; } default : { if ( ! lisdigit ( ls -> current ) ) escerror ( ls , & ls -> current , 1 , invalid escape sequence ) ;  digital escape \ddd c = readdecesc ( ls ) ; goto only_save ; } } read_save : next ( ls ) ;
      ## Error: 'case' expected!!!
      save(ls, c)
      break
    else:
      save_and_next(ls)
  save_and_next(ls)
  seminfo.ts = luaX_newstring(ls, luaZ_buffer(ls.buff) + 1, luaZ_bufflen(ls.buff) - 2)

proc llex*(ls: ptr LexState; seminfo: ptr SemInfo): cint =
  luaZ_resetbuffer(ls.buff)
  while true:
    case ls.current
    of '\n', '\r':
      inclinenumber(ls)
      break
    of ' ', '\f', '\t', 11:
      next(ls)
      break
    of '-':
      next(ls)
      if ls.current != '-':
        return '-'
      next(ls)
      if ls.current == '[':
        var sep: cint = skip_sep(ls)
        luaZ_resetbuffer(ls.buff)
        if sep >= 0:
          read_long_string(ls, nil, sep)
          luaZ_resetbuffer(ls.buff)
          break
      while not currIsNewline(ls) and ls.current != EOZ:
        next(ls)
      break
    of '[':
      var sep: cint = skip_sep(ls)
      if sep >= 0:
        read_long_string(ls, seminfo, sep)
        return TK_STRING
      elif sep == -1:
        return '['
      else:
        lexerror(ls, "invalid long string delimiter", TK_STRING)
    of '=':
      next(ls)
      if ls.current != '=':
        return '='
      else:
        next(ls)
        return TK_EQ
    of '<':
      next(ls)
      if ls.current != '=':
        return '<'
      else:
        next(ls)
        return TK_LE
    of '>':
      next(ls)
      if ls.current != '=':
        return '>'
      else:
        next(ls)
        return TK_GE
    of '~':
      next(ls)
      if ls.current != '=':
        return '~'
      else:
        next(ls)
        return TK_NE
    of ':':
      next(ls)
      if ls.current != ':':
        return ':'
      else:
        next(ls)
        return TK_DBCOLON
    of '\"', '\'':
      read_string(ls, ls.current, seminfo)
      return TK_STRING
    of '.':
      save_and_next(ls)
      if check_next(ls, "."):
        if check_next(ls, "."):
          return TK_DOTS
        else:
          return TK_CONCAT
      elif not lisdigit(ls.current):
        return '.'
    of '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
      read_numeral(ls, seminfo)
      return TK_NUMBER
    of EOZ:
      return TK_EOS
    else:
      if lislalpha(ls.current):
        var ts: ptr TString
        while true:
          save_and_next(ls)
          if not lislalnum(ls.current):
            break
        ts = luaX_newstring(ls, luaZ_buffer(ls.buff), luaZ_bufflen(ls.buff))
        seminfo.ts = ts
        if isreserved(ts):
          return ts.tsv.extra - 1 + FIRST_RESERVED
        else:
          return TK_NAME
      else:
        var c: cint = ls.current
        next(ls)
        return c

proc luaX_next*(ls: ptr LexState) =
  ls.lastline = ls.linenumber
  if ls.lookahead.token != TK_EOS:
    ls.t = ls.lookahead
    ls.lookahead.token = TK_EOS
  else:
    ls.t.token = llex(ls, addr(ls.t.seminfo))

proc luaX_lookahead*(ls: ptr LexState): cint =
  lua_assert(ls.lookahead.token == TK_EOS)
  ls.lookahead.token = llex(ls, addr(ls.lookahead.seminfo))
  return ls.lookahead.token
