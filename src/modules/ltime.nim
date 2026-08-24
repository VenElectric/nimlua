import std/[times,tables]
import ../lerror,../lvalue,../ltypes

const MonthDayNames = ["January","February","March","April","May","June","July","August","September","October","November","December"]
const WeekDayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

let YEARKEY = newLuaString("year")
let MONTKEY = newLuaString("month")
let DAYKEY = newLuaString("day")
let HRKEY = newLuaString("hour")
let MINKEY = newLuaString("min")
let SECKEY = newLuaString("sec")

const HRDEFAULT = 12
const MINDEFAULT = 0
const SECDEFAULT = 0

const DATEFMT = "ddd MMM d HH:mm:ss yyyy"

proc luaClock(args:varargs[LuaValue]): seq[LuaValue] = 
  result = @[newLuaNumber(cpuTime())]

# year, month, day required
# hour = 12, minutes (min) = 0, seconds (sec) = 0, isdst = nil

proc getMonthEnum(v:int64): Month = 
  case v
  of 1: mJan
  of 2: mFeb
  of 3: mMar
  of 4: mApr
  of 5: mMay
  of 6: mJun
  of 7: mJul
  of 8: mAug
  of 9: mSep
  of 10: mOct
  of 11: mNov
  of 12: mDec
  else: raise newException(LuaRuntimeError, "invalid month value: " & $v & " (expected 1-12)")

proc luaTime(args:varargs[LuaValue]): seq[LuaValue] = 
  result = @[]
  if len(args) == 0:
    result.add(newLuaInteger(getTime().toUnix()))
  elif len(args) == 1 and isTable(args[0]):
    let tab = getTable(args[0])
    if not tab.hasKey(YEARKEY) or not tab.hasKey(MONTKEY) or not tab.hasKey(DAYKEY):
      raise newException(LuaRuntimeError,"Must provide year, date, and day in table to 'time' function")
    let year = intVal(tab[YEARKEY]).int
    let modeMnth = intVal(tab[MONTKEY])
    let month = getMonthEnum(modeMnth)
    let day = intVal(tab[DAYKEY]).int
    var hour = HRDEFAULT
    if tab.hasKey(HRKEY):
      hour = intVal(tab[HRKEY]).int
    var minutes = MINDEFAULT
    if tab.hasKey(MINKEY):
      minutes = intVal(tab[MINKEY]).int
    var seconds = SECDEFAULT
    if tab.hasKey(SECKEY):
      seconds = intVal(tab[SECKEY]).int
    # unable to set dst with nim 
    try:
      result.add(newLuaInteger(dateTime(year,month,day,hour,minutes,seconds).toTime().toUnix()))
    except:
      raise newException(LuaRuntimeError, "invalid date/time value passed to 'time'")
  elif len(args) >= 3:
    let year = intVal(args[0]).int
    let month = getMonthEnum(intVal(args[1]))
    let day = intVal(args[2]).int
    let hour = if len(args) >= 4: intVal(args[3]).int else: HRDEFAULT
    let minutes = if len(args) >= 5: intVal(args[4]).int else: MINDEFAULT
    let seconds = if len(args) >= 6: intVal(args[5]).int else: SECDEFAULT
    try:
      result.add(newLuaInteger(dateTime(year,month,day,hour,minutes,seconds).toTime().toUnix()))
    except:
      raise newException(LuaRuntimeError, "invalid date/time value passed to 'time'")
  else:
    raise newException(LuaRuntimeError,"Invalid number of arguments to 'time'. " & $len(args) & " provided, but expected at least 3")

proc buildDateTable(dt: DateTime): LuaValue =
  result = newLuaTable()
  result.tval[newLuaString("year")] = newLuaInteger(dt.year)
  result.tval[newLuaString("month")] = newLuaInteger(ord(dt.month))
  result.tval[newLuaString("day")] = newLuaInteger(dt.monthday)
  result.tval[newLuaString("hour")] = newLuaInteger(dt.hour)
  result.tval[newLuaString("min")] = newLuaInteger(dt.minute)
  result.tval[newLuaString("sec")] = newLuaInteger(dt.second)
  # same "verify against your actual Nim version" caveat as before --
  # this assumes WeekDay starts at Monday=0, converting to Lua's wday (1=Sunday)
  result.tval[newLuaString("wday")] = newLuaInteger(((ord(dt.weekday) + 1) mod 7) + 1)
  result.tval[newLuaString("yday")] = newLuaInteger(dt.yearday + 1)
  result.tval[newLuaString("isdst")] = newLuaBool(dt.isDst)

proc luaDate(args: varargs[LuaValue]): seq[LuaValue] =
  result = @[]
  var t = getTime()       # timezone-agnostic "now" -- decide local vs UTC later
  var fmtStr = DATEFMT

  if len(args) == 0:
    discard   # defaults above already cover this case
  elif len(args) == 1:
    if isString(args[0]):
      fmtStr = getString(args[0])
    else:
      raise newException(LuaRuntimeError, "Invalid argument #1 to 'date'. (expected string)")
  elif len(args) >= 2:
    if isString(args[0]):
      if isNumber(args[1]):
        fmtStr = getString(args[0])
        t = intVal(args[1]).fromUnix()
      else:
        raise newException(LuaRuntimeError, "Invalid argument #2 to 'date'. (expected number)")
    else:
      raise newException(LuaRuntimeError, "Invalid argument #1 to 'date'. (expected string)")

  # --- new: handle the leading '!' (UTC) and "*t" (table instead of string) ---
  var f = fmtStr
  var useUtc = false
  if f.len > 0 and f[0] == '!':
    useUtc = true
    f = f[1 .. ^1]

  let dt = if useUtc: t.utc() else: t.local()

  if f == "*t":
    result.add(buildDateTable(dt))
  else:
    let dFmt = initTimeFormat(f)
    result.add(newLuaString(dt.format(dFmt)))
    
proc luaDiffTime(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 2:
    raise newException(LuaRuntimeError, "Invalid number of arguments to 'difftime'. Expected two arguments")
  let t2 = intVal(args[0]).fromUnix
  let t1 = intVal(args[1]).fromUnix
  return @[newLuaInteger((t2 - t1).inSeconds)]

# todo maybe add accessors for month, day , year, minute, hour, seconds

proc newTimeLib*(vm: var VM) =
  let MonthMode = newLuaEnum(MonthDayNames)
  let WeekdayMode = newLuaEnum(WeekDayNames)
  var tTable = newLuaTable()
  tTable.tval[newLuaString("clock")] = newNimFn(luaClock)
  tTable.tval[newLuaString("time")] = newNimFn(luaTime)
  tTable.tval[newLuaString("date")] = newNimFn(luaDate)
  tTable.tval[newLuaString("difftime")] = newNimFn(luaDiffTime)
  vm.globals["time"] = tTable
  vm.globals["Month"] = MonthMode
  vm.globals["Weekday"] = WeekdayMode