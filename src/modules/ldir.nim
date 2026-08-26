import std/[tables,dirs,paths,tempfiles,logging]
import ../ltypes,../lvalue,../lerror,../lutil

const PathKindNames = ["file", "dir", "linkToFile", "linkToDir"]

type
  LuaTempDirObj = object of LuaUserDataObj
    path*: string
    isRemoved*: bool
  LuaTempDir* = ref LuaTempDirObj

proc `=destroy`(t: var LuaTempDirObj) =
  if not t.isRemoved:
    try: removeDir(Path(t.path))
    except OSError: discard
    t.isRemoved = true
    info "Removed temp dir"

proc luaCreateDir(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) == 1:
    if isString(args[0]):
      let dPath = Path(getString(args[0]))
      try:
        createDir(dPath)
        return @[newLuaBool(true)]
      except OSError as e:
        return @[newLuaNil(),newLuaString("Unable to create dir: " & $dPath & " (" & e.msg & ")")]
    else:
      raise newException(LuaRuntimeError,moduleArgKindErrorFmt(1,"createDir","string"))
  else:
    raise newException(LuaRuntimeError,moduleArgNumErrorFmt("createDir","one"))

proc luaRemoveDir(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) == 1:
    if isString(args[0]):
      let dPath = Path(getString(args[0]))
      try:
        removeDir(dPath)
        return @[newLuaBool(true)]
      except OSError as e:
        return @[newLuaNil(),newLuaString("Unable to remove dir: " & $dPath & " (" & e.msg & ")")]
    else:
      raise newException(LuaRuntimeError,moduleArgKindErrorFmt(1,"removeDir","string"))
  else:
    raise newException(LuaRuntimeError,moduleArgNumErrorFmt("removeDir","one"))

proc luaMoveDir(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) == 2:
    if isString(args[0]) and isString(args[1]):
      let source = Path(getString(args[0]))
      let dest = Path(getString(args[1]))
      try:
        moveDir(source,dest)
        return @[newLuaBool(true)]
      except OSError as e:
        return @[newLuaNil(),newLuaString("Unable to move dir from " & $source & " to " & $dest & " (" & e.msg & ")")]
    else:
      let pos = if not isString(args[0]): 1 else: 2
      raise newException(LuaRuntimeError,moduleArgKindErrorFmt(pos,"moveDir","string"))
  else:
    raise newException(LuaRuntimeError,moduleArgNumErrorFmt("moveDir","two"))

proc luaDirExists(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) == 1:
    if isString(args[0]):
      let dPath = Path(getString(args[0]))
      return @[newLuaBool(dirExists(dPath))]
    else:
      raise newException(LuaRuntimeError,moduleArgKindErrorFmt(1,"dirExists","string"))
  else:
    raise newException(LuaRuntimeError,moduleArgNumErrorFmt("dirExists","one"))

proc luaCopyDir(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) == 2:
    if isString(args[0]) and isString(args[1]):
      let source = Path(getString(args[0]))
      let dest = Path(getString(args[1]))
      try:
        copyDir(source,dest)
        return @[newLuaBool(true)]
      except OSError as e:
        return @[newLuaNil(),newLuaString("Unable to copy source dir " & $source & " to " & $dest & " (" & e.msg & ")")]
    else:
      let pos = if not isString(args[0]): 1 else: 2
      raise newException(LuaRuntimeError,moduleArgKindErrorFmt(pos,"copyDir","string"))
  else:
    raise newException(LuaRuntimeError,moduleArgNumErrorFmt("copyDir","two"))

proc asTempDir(v: LuaValue): LuaTempDir =
  if not isUserData(v) or v.ud.isNil or not (v.ud of LuaTempDir):
    raise newException(LuaRuntimeError, "bad argument (temp dir handle expected)")
  return LuaTempDir(v.ud)

proc luaTempDirRemove(args: varargs[LuaValue]): seq[LuaValue] =
  let t = asTempDir(args[0])
  if not t.isRemoved:
    try:
      removeDir(Path(t.path))
    except OSError: discard   # already gone is fine -- this is best-effort cleanup
    t.isRemoved = true
  return @[newLuaBool(true)]

proc luaTempDirPath(args: varargs[LuaValue]): seq[LuaValue] =
  return @[newLuaString(asTempDir(args[0]).path)]

proc luaCreateTempDir(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 2:
    raise newException(LuaRuntimeError, moduleArgNumErrorFmt("temp", "at least two"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(1, "temp", "string"))
  if not isString(args[1]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(2, "temp", "string"))

  let prefix = getString(args[0])
  let suffix = getString(args[1])
  var baseDir = ""   # empty string -> Nim's own default (the system temp directory)
  if len(args) >= 3:
    if not isString(args[2]):
      raise newException(LuaRuntimeError, moduleArgKindErrorFmt(3, "temp", "string"))
    baseDir = getString(args[2])

  try:
    let path = createTempDir(prefix, suffix, baseDir)
    return @[newLuaString(path)]
  except OSError as e:
    return @[newLuaNil(), newLuaString("Unable to create temp dir: " & e.msg)]
  except IOError as e:
    return @[newLuaNil(), newLuaString("Unable to create temp dir: " & e.msg)]

proc newDirLib*(vm: var VM) =
  let PathKind = newLuaEnum(PathKindNames)

  let luaWalkDir = proc(args: varargs[LuaValue]): seq[LuaValue] =
    if len(args) != 1:
      raise newException(LuaRuntimeError, moduleArgNumErrorFmt("walk", "one"))
    if not isString(args[0]):
      raise newException(LuaRuntimeError, moduleArgKindErrorFmt(1, "walk", "string"))

    let dPath = Path(getString(args[0]))
    if not dirExists(dPath):
      raise newException(LuaRuntimeError, "Unable to walk dir (does not exist): " & $dPath)

    var entries: seq[(LuaValue, string)] = @[]
    for kind, path in walkDir(dPath):
      let kindVal = case kind
        of pcFile: enumGet(PathKind, newLuaString("file"))
        of pcDir: enumGet(PathKind, newLuaString("dir"))
        of pcLinkToFile: enumGet(PathKind, newLuaString("linkToFile"))
        of pcLinkToDir: enumGet(PathKind, newLuaString("linkToDir"))
      entries.add((kindVal, $path))

    var idx = 0
    let iterFn = proc(iterArgs: varargs[LuaValue]): seq[LuaValue] =
      if idx >= entries.len: return @[newLuaNil()]
      let (kindVal, pathStr) = entries[idx]
      inc idx
      return @[kindVal, newLuaString(pathStr)]

    return @[newNimFn(iterFn), newLuaNil(), newLuaNil()]
  let TempDirMethods = newLuaTable()
  TempDirMethods.tval[newLuaString("remove")] = newNimFn(luaTempDirRemove)
  TempDirMethods.tval[newLuaString("path")] = newNimFn(luaTempDirPath)
  
  let tempDirMT = newLuaTable()
  tempDirMT.tval[MTINDEX] = TempDirMethods
  tempDirMT.tval[MTCLOSE] = newNimFn(luaTempDirRemove)   # <close> reuses the same removal logic
  tempDirMT.tval[MTTYPE] = newLuaString("tempdir")
  tempDirMT.tval[MTMETA] = newLuaBool(false)

  let luaTempScoped = proc(args: varargs[LuaValue]): seq[LuaValue] =
  # same argument validation as luaCreateTempDir
    if len(args) < 2:
      raise newException(LuaRuntimeError, moduleArgNumErrorFmt("tempScoped", "at least two"))
    if not isString(args[0]):
      raise newException(LuaRuntimeError, moduleArgKindErrorFmt(1, "tempScoped", "string"))
  
    if not isString(args[1]):
      raise newException(LuaRuntimeError, moduleArgKindErrorFmt(2, "tempScoped", "string"))
    var baseDir = ""
    if len(args) >= 3:
      if not isString(args[2]):
        raise newException(LuaRuntimeError, moduleArgKindErrorFmt(3, "tempScoped", "string"))
      baseDir = getString(args[2])

    try:
      let path = createTempDir(getString(args[0]), getString(args[1]), baseDir)
      let handle = LuaTempDir(path: path, isRemoved: false)
      let wrapped = newUserData(handle)
      wrapped.mt = tempDirMT
      return @[wrapped]
    except OSError as e:
      return @[newLuaNil(), newLuaString("Unable to create temp dir: " & e.msg)]
    except IOError as e:
      return @[newLuaNil(), newLuaString("Unable to create temp dir: " & e.msg)]

      
  let dirTable = newLuaTable()
  dirTable.tval[newLuaString("create")] = newNimFn(luaCreateDir)
  dirTable.tval[newLuaString("remove")] = newNimFn(luaRemoveDir)
  dirTable.tval[newLuaString("move")] = newNimFn(luaMoveDir)
  dirTable.tval[newLuaString("exists")] = newNimFn(luaDirExists)
  dirTable.tval[newLuaString("copy")] = newNimFn(luaCopyDir)
  dirTable.tval[newLuaString("walk")] = newNimFn(luaWalkDir)
  dirTable.tval[newLuaString("temp")] = newNimFn(luaCreateTempDir)
  dirTable.tval[newLuaString("tempScoped")] = newNimFn(luaTempScoped)

  vm.globals["dir"] = dirTable
  vm.globals["PathKind"] = PathKind