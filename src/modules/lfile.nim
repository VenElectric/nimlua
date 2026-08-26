import std/[tables,streams,files,appdirs,paths,times,random,tempfiles]
import ../ltypes, ../lvalue, ../lerror

type
  LuaFileHandleObj = object of LuaUserDataObj
    stream*: Stream
    path*: string
    isClosed*: bool
    isStandard*: bool
    deleteOnClose*: bool
  LuaFileHandle* = ref LuaFileHandleObj

proc `=destroy`(f: var LuaFileHandleObj) =
  if not f.isClosed:
    try: 
      f.stream.close()
    except: discard   # a destructor can't raise -- this really is best-effort  

const FileModeNames = ["read", "write", "append", "readWriteExisting", "readWrite"]

proc asFileHandle(v: LuaValue): LuaFileHandle =
  if not isUserData(v) or v.ud.isNil or not (v.ud of LuaFileHandle):
    raise newException(LuaRuntimeError, "bad argument (file handle expected)")
  return LuaFileHandle(v.ud)

# --- Methods: none of these need the shared metatable, only an existing handle ---

proc luaFileWrite(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1: raise newException(LuaRuntimeError, "bad argument #1 to 'write' (file expected)")
  let f = asFileHandle(args[0])
  if f.isClosed:
    raise newException(LuaRuntimeError, "attempt to use a closed file")
  for i in 1 ..< args.len:
    let a = args[i]
    case a.kind
    of ltString: f.stream.write(a.sval)
    of ltNumber: f.stream.write($a.nval)
    of ltInteger: f.stream.write($a.ival)
    else: raise newException(LuaRuntimeError, "invalid argument to 'write' (string expected, got " & $a.kind & ")")
  return @[args[0]]

proc luaFileClose(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1: raise newException(LuaRuntimeError, "bad argument #1 to 'close' (file expected)")
  let f = asFileHandle(args[0])
  if f.isStandard:
    return @[newLuaBool(true)]
  if not f.isClosed:
    f.stream.close()
    if f.deleteOnClose:
      try: removeFile(Path(f.path))
      except OSError: discard   # best-effort -- already gone is fine
    f.isClosed = true
  return @[newLuaBool(true)]

proc luaFileRead(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1: raise newException(LuaRuntimeError, "bad argument #1 to 'read' (file expected)")
  let f = asFileHandle(args[0])
  if f.isClosed:
    raise newException(LuaRuntimeError, "attempt to use a closed file")
  var fmt = "l"
  if args.len >= 2 and isString(args[1]): fmt = args[1].sval
  case fmt
  of "l", "*l":
    var line: string
    if f.stream.readLine(line):
      return @[newLuaString(line)]
    else:
      return @[newLuaNil()]
  of "a", "*a":
    return @[newLuaString(f.stream.readAll())]
  of "n", "*n":
    raise newException(LuaRuntimeError, "'n' format for file:read is not yet supported")
  else:
    raise newException(LuaRuntimeError, "invalid format to 'read': " & fmt)

proc luaFileLines(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1: raise newException(LuaRuntimeError, "bad argument #1 to 'lines' (file expected)")
  let f = asFileHandle(args[0])
  let iterFn = proc(iterArgs: varargs[LuaValue]): seq[LuaValue] =
    if f.isClosed: return @[newLuaNil()]
    var line: string
    if f.stream.readLine(line):
      return @[newLuaString(line)]
    else:
      return @[newLuaNil()]
  return @[newNimFn(iterFn)]

proc luaFileFlush(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1: raise newException(LuaRuntimeError, "bad argument #1 to 'flush' (file expected)")
  let f = asFileHandle(args[0])
  f.stream.flush()
  return @[args[0]]

# --- Library construction: self-registers BOTH `file` and `FileMode` on vm.globals ---

proc luaFileRemove(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1 or not isString(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'remove' (string expected)")
  try:
    removeFile(Path(args[0].sval))
    return @[newLuaBool(true)]
  except OSError as e:
    return @[newLuaNil(), newLuaString(args[0].sval & ": " & e.msg)]

proc luaFileRename(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2 or not isString(args[0]) or not isString(args[1]):
    raise newException(LuaRuntimeError, "bad arguments to 'rename' (strings expected)")
  try:
    moveFile(Path(args[0].sval), Path(args[1].sval))
    return @[newLuaBool(true)]
  except OSError as e:
    return @[newLuaNil(), newLuaString(e.msg)]

proc luaFileTmpname(args: varargs[LuaValue]): seq[LuaValue] =
  # Only generates a NAME -- matches real Lua's own os.tmpname exactly,
  # including its documented caveat: there's an inherent race between
  # getting this name and actually opening it, since nothing reserves it.
  let name = $getTempDir() & ("lua_" & $getTime().toUnix() & "_" & $rand(1_000_000) & ".tmp")
  return @[newLuaString(name)]



proc newFileLib*(vm: var VM) =
  let FileMode = newLuaEnum(FileModeNames)

  let FileMethods = newLuaTable()
  FileMethods.tval[newLuaString("write")] = newNimFn(luaFileWrite)
  FileMethods.tval[newLuaString("read")] = newNimFn(luaFileRead)
  FileMethods.tval[newLuaString("close")] = newNimFn(luaFileClose)
  FileMethods.tval[newLuaString("lines")] = newNimFn(luaFileLines)
  FileMethods.tval[newLuaString("flush")] = newNimFn(luaFileFlush)

  let fileMT = newLuaTable()
  fileMT.tval[MTINDEX] = FileMethods
  fileMT.tval[MTCLOSE] = newNimFn(luaFileClose)
  fileMT.tval[MTTYPE] = newLuaString("file")
  fileMT.tval[MTMETA] = newLuaBool(false)

  proc wrap(stream: Stream, path: string, isStandard: bool = false, deleteOnClose: bool = false): LuaValue =
    let handle = LuaFileHandle(stream: stream, path: path, isClosed: false,
                             isStandard: isStandard, deleteOnClose: deleteOnClose)
    result = newUserData(handle)
    result.mt = fileMT

  let luaFileOpen = proc(args: varargs[LuaValue]): seq[LuaValue] =
    if args.len < 1 or not isString(args[0]):
      raise newException(LuaRuntimeError, "bad argument #1 to 'open' (string expected)")
    let path = args[0].sval

    if not isInteger(args[1]) or isLuaNil(enumGet(FileMode, args[1])):
      raise newException(LuaRuntimeError, "bad argument #2 to 'open' (FileMode.xxx expected)")
    let modeInt = args[1].ival
  

    let fm = case modeInt
    of 1: fmRead               # FileMode.read
    of 2: fmWrite              # FileMode.write
    of 3: fmAppend             # FileMode.append
    of 4: fmReadWriteExisting  # FileMode.readWriteExisting
    of 5: fmReadWrite          # FileMode.readWrite
    else: fmRead

    try:
      let stream = newFileStream(path, fm)
      if stream.isNil:
        return @[newLuaNil(), newLuaString(path & ": cannot open file")]
      return @[wrap(stream, path)]
    except IOError as e:
      return @[newLuaNil(), newLuaString(path & ": " & e.msg)]

  let luaFileTmpFile = proc(args: varargs[LuaValue]): seq[LuaValue] =
    try:
      let (cfile, path) = createTempFile("lua_tmp_", ".tmp")
      let stream = newFileStream(cfile)
      return @[wrap(stream, path, deleteOnClose = true)]
    except OSError as e:
      return @[newLuaNil(), newLuaString("Unable to create temp file: " & e.msg)]


  let fileTable = newLuaTable()
  fileTable.tval[newLuaString("open")] = newNimFn(luaFileOpen)
  fileTable.tval[newLuaString("stdout")] = wrap(vm.output, "stdout", isStandard = true)
  fileTable.tval[newLuaString("stderr")] = wrap(newFileStream(stderr), "stderr", isStandard = true)
  fileTable.tval[newLuaString("stdin")] = wrap(newFileStream(stdin), "stdin", isStandard = true)
  fileTable.tval[newLuaString("remove")] = newNimFn(luaFileRemove)
  fileTable.tval[newLuaString("rename")] = newNimFn(luaFileRename)
  fileTable.tval[newLuaString("tmpname")] = newNimFn(luaFileTmpname)
  fileTable.tval[newLuaString("tmpfile")] = newNimFn(luaFileTmpFile)

  vm.globals["file"] = fileTable
  vm.globals["FileMode"] = FileMode

