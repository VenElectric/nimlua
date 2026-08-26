import ../lerror,../ltypes,../lvalue
import std/strutils

const MaxCaptures* = 32       # matches real Lua's own limit
const CapUnfinished* = -1     # this capture's start is set, but its end isn't yet
const CapPosition* = -2       # a () position-capture -- captures a byte offset, not a substring
const MaxMatchDepth* = 200    # guards against pathological patterns blowing the real call stack

type CaptureInfo* = object
  start*: int
  len*: int   # CapUnfinished / CapPosition, or a real (>= 0) length once closed

type MatchState* = object
  subject*: string
  pattern*: string
  captures*: seq[CaptureInfo]
  matchDepth*: int

proc classEnd*(ms: MatchState, p: int): int =
  var p = p
  let c = ms.pattern[p]
  inc p
  if c == '%':
    if p >= ms.pattern.len:
      raise newException(LuaRuntimeError, "malformed pattern (ends with '%')")
    return p + 1
  if c == '[':
    if p < ms.pattern.len and ms.pattern[p] == '^': inc p
    # a ']' immediately after '[' (or '[^') is a LITERAL ']', not the closer
    var first = true
    while true:
      if p >= ms.pattern.len:
        raise newException(LuaRuntimeError, "malformed pattern (missing ']')")
      let sc = ms.pattern[p]
      inc p
      if sc == '%':
        if p >= ms.pattern.len:
          raise newException(LuaRuntimeError, "malformed pattern (ends with '%')")
        inc p
      elif sc == ']' and not first:
        return p
      first = false
  return p

proc matchClassChar(c: char, cl: char): bool =
  let res = case toLowerAscii(cl)
    of 'a': isAlphaAscii(c)
    of 'd': c in Digits
    of 'l': c in {'a'..'z'}
    of 's': c in {' ', '\t', '\n', '\r', '\v', '\f'}
    of 'u': c in {'A'..'Z'}
    of 'w': isAlphaAscii(c) or c in Digits
    of 'c': ord(c) < 32 or ord(c) == 127
    of 'p': c in {'!'..'/', ':'..'@', '['..'`', '{'..'~'}
    of 'x': c in HexDigits
    else: return cl == c   # %% and "% + any non-alnum" both fall here: literal match
  if isUpperAscii(cl): return not res   # %A/%D/%S/etc. are the negation of %a/%d/%s/etc.
  return res

proc matchSet*(ms: MatchState, c: char, p, ep: int): bool =
  var p = p + 1              # skip the '['
  var negate = false
  if ms.pattern[p] == '^':
    negate = true
    inc p
  var found = false
  while p < ep - 1:           # ep-1 excludes the closing ']' itself
    if ms.pattern[p] == '%':
      inc p
      if matchClassChar(c, ms.pattern[p]): found = true
      inc p
    elif p + 2 < ep - 1 and ms.pattern[p + 1] == '-':
      if ms.pattern[p] <= c and c <= ms.pattern[p + 2]: found = true
      p += 3
    else:
      if ms.pattern[p] == c: found = true
      inc p
  return found != negate

proc singleMatch*(ms: MatchState, sPos: int, p, ep: int): bool =
  if sPos >= ms.subject.len: return false
  let c = ms.subject[sPos]
  case ms.pattern[p]
  of '.': return true
  of '%': return matchClassChar(c, ms.pattern[p + 1])
  of '[': return matchSet(ms, c, p, ep)
  else: return ms.pattern[p] == c

proc doMatch*(ms: var MatchState, sPos, pPos: int): int
# Returns the subject position where the match ENDS on success, or -1 on failure.
# (Real Lua returns a real pointer/nil; here, -1 plays nil's role for "no match".)

proc maxExpand*(ms: var MatchState, sPos, pPos, ep: int): int =
  # Greedy '*'/'+'-style: consume as many matching characters as possible,
  # THEN try the rest of the pattern, backing off one at a time on failure.
  var i = 0
  while singleMatch(ms, sPos + i, pPos, ep):
    inc i
  while i >= 0:
    let r = doMatch(ms, sPos + i, ep + 1)
    if r != -1: return r
    dec i
  return -1

proc minExpand*(ms: var MatchState, sPos, pPos, ep: int): int =
  # Lazy '-': try the rest of the pattern FIRST, only consume one more
  # character of the class if that fails. No regex-flavor default I know
  # of works this way -- this exists specifically because Lua patterns
  # have no alternation to fall back on for "shortest match".
  var sPos = sPos
  while true:
    let r = doMatch(ms, sPos, ep + 1)
    if r != -1: return r
    if singleMatch(ms, sPos, pPos, ep): inc sPos
    else: return -1

proc startCapture*(ms: var MatchState, sPos, pPos: int, what: int): int =
  ms.captures.add(CaptureInfo(start: sPos, len: what))
  let r = doMatch(ms, sPos, pPos)
  if r == -1: discard ms.captures.pop()   # undo on failed backtrack
  return r

proc endCapture*(ms: var MatchState, sPos, pPos: int): int =
  var i = ms.captures.high
  while i >= 0 and ms.captures[i].len != CapUnfinished: dec i
  if i < 0: raise newException(LuaRuntimeError, "invalid pattern capture")
  ms.captures[i].len = sPos - ms.captures[i].start
  let r = doMatch(ms, sPos, pPos)
  if r == -1: ms.captures[i].len = CapUnfinished   # undo on failed backtrack
  return r

proc charAtOrZero(s: string, i: int): char =
  if i < 0 or i >= s.len: return '\0'
  return s[i]

proc matchFrontier(ms: var MatchState, sPos, fPos: int): int =
  if fPos + 1 >= ms.pattern.len or ms.pattern[fPos + 1] != '[':
    raise newException(LuaRuntimeError, "missing '[' after '%f' in pattern")
  let setStart = fPos + 1
  let setEnd = classEnd(ms, setStart)
  let prevInSet = matchSet(ms, charAtOrZero(ms.subject, sPos - 1), setStart, setEnd)
  let currInSet = matchSet(ms, charAtOrZero(ms.subject, sPos), setStart, setEnd)
  if (not prevInSet) and currInSet:
    return doMatch(ms, sPos, setEnd)   # zero-width -- sPos itself never advances
  return -1

proc matchBalance(ms: MatchState, sPos, bPos: int): int =
  if bPos + 2 >= ms.pattern.len:
    raise newException(LuaRuntimeError, "missing arguments to '%b'")
  let x = ms.pattern[bPos + 1]
  let y = ms.pattern[bPos + 2]
  if sPos >= ms.subject.len or ms.subject[sPos] != x:
    return -1
  var depth = 1
  var i = sPos + 1
  while i < ms.subject.len:
    if ms.subject[i] == y:
      dec depth
      if depth == 0: return i + 1
    elif ms.subject[i] == x:
      inc depth
    inc i
  return -1

proc matchCapture(ms: MatchState, sPos, capIdx: int): int =
  if capIdx < 0 or capIdx >= ms.captures.len or ms.captures[capIdx].len == CapUnfinished:
    raise newException(LuaRuntimeError, "invalid capture index %" & $(capIdx + 1))
  let cap = ms.captures[capIdx]
  if cap.len == CapPosition: return -1   # degenerate case -- a position capture has nothing to compare against
  if sPos + cap.len <= ms.subject.len and
     ms.subject[sPos ..< sPos + cap.len] == ms.subject[cap.start ..< cap.start + cap.len]:
    return sPos + cap.len
  return -1

proc doMatch*(ms: var MatchState, sPos, pPos: int): int =
  inc ms.matchDepth
  if ms.matchDepth > MaxMatchDepth:
    raise newException(LuaRuntimeError, "pattern too complex")
  defer: dec ms.matchDepth

  if pPos >= ms.pattern.len:
    return sPos   # end of pattern -- whatever we've consumed so far IS the match

  case ms.pattern[pPos]
  of '(':
    if pPos + 1 < ms.pattern.len and ms.pattern[pPos + 1] == ')':
      return startCapture(ms, sPos, pPos + 2, CapPosition)
    else:
      return startCapture(ms, sPos, pPos + 1, CapUnfinished)
  of ')':
    return endCapture(ms, sPos, pPos + 1)
  of '$':
    if pPos + 1 == ms.pattern.len:
      return (if sPos == ms.subject.len: sPos else: -1)
  of '%':
    if pPos + 1 < ms.pattern.len:
      case ms.pattern[pPos + 1]
      of 'b':
        let e = matchBalance(ms, sPos, pPos + 1)
        if e == -1: return -1
        return doMatch(ms, e, pPos + 4)
      of 'f':
        return matchFrontier(ms, sPos, pPos + 1)
      of '1'..'9':
        let e = matchCapture(ms, sPos, ord(ms.pattern[pPos + 1]) - ord('1'))
        if e == -1: return -1
        return doMatch(ms, e, pPos + 2)
      else: discard   
  else: discard

  let ep = classEnd(ms, pPos)
  let matched = singleMatch(ms, sPos, pPos, ep)
  let quant = if ep < ms.pattern.len: ms.pattern[ep] else: '\0'

  case quant
  of '?':
    if matched:
      let r = doMatch(ms, sPos + 1, ep + 1)
      if r != -1: return r
    return doMatch(ms, sPos, ep + 1)
  of '*': return maxExpand(ms, sPos, pPos, ep)
  of '+': return (if matched: maxExpand(ms, sPos + 1, pPos, ep) else: -1)
  of '-': return minExpand(ms, sPos, pPos, ep)
  else:
    if not matched: return -1
    return doMatch(ms, sPos + 1, ep)


proc findMatch*(pattern: string, subject: string, initPos: int): tuple[found: bool, ms: MatchState, matchStart: int, matchEnd: int] =
  let anchored = pattern.len > 0 and pattern[0] == '^'
  let pStart = if anchored: 1 else: 0   # skip the '^' itself -- it's a marker, not a real pattern item
  var sPos = initPos
  while sPos <= subject.len:   # <= , not < -- lets an empty-matching pattern succeed AT the very end
    var ms = MatchState(pattern: pattern, subject: subject)
    let e = doMatch(ms, sPos, pStart)
    if e != -1:
      return (true, ms, sPos, e)
    if anchored: break
    inc sPos
  return (false, MatchState(pattern: pattern, subject: subject), 0, 0)



proc capturesToLua*(ms: MatchState): seq[LuaValue] =
  result = @[]
  for cap in ms.captures:
    if cap.len == CapPosition:
      result.add(newLuaInteger(int64(cap.start + 1)))   # 1-based, matching Lua convention
    else:
      result.add(newLuaString(ms.subject[cap.start ..< cap.start + cap.len]))