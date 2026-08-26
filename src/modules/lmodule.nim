import lcore,lfile,lmath,lpackage,ltable,lprocess,ltime,ldir,lset,lcoro,lunicode,ljson,lnet,lstring
import ../ltypes,../lvm,../lvalue
import std/tables

proc openCore*(vm: var VM) = 
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("string"), newLuaString("string"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("bool"), newLuaString("bool"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("nil"), newLuaString("nil"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("number"), newLuaString("number"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("integer"), newLuaString("integer"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("table"), newLuaString("table"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("nim function"), newLuaString("nim function"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("lua function"), newLuaString("lua function"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("user data"), newLuaString("user data"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("enumeration"), newLuaString("enumeration"))
  if mCore notin vm.openModules:
    return
  vm.registerGC()
  
  vm.globals["assert"] = newNimFnVM(luaAssert)
  vm.globals["rawget"] = newNimFn(luaRawGet)
  vm.globals["rawset"] = newNimFn(luaRawSet)
  vm.globals["rawtype"] = newNimFn(luaRawType)
  vm.globals["rawequal"] = newNimFn(luaRawEqual)
  vm.globals["rawlen"] = newNimFn(luaRawLen)
  vm.globals["setmetatable"] = newNimFn(luaSetMetatable)
  vm.globals["getmetatable"] = newNimFn(luaGetMetatable)
  vm.globals["print"] = newNimFnVM(luaPrint)
  vm.globals["next"] = newNimFn(luaNext)
  vm.globals["pairs"] = newNimFnVM(luaPairs)
  vm.globals["ipairs"] = newNimFn(luaIPairs)
  vm.globals["tonumber"] = newNimFn(luaToNumber)
  vm.globals["tostring"] = newNimFnVM(luaToString)
  vm.globals["type"] = newNimFn(luaType)
  vm.globals["select"] = newNimFn(luaSelect)
  vm.globals["require"] = newNimFnVM(luaRequire)
  vm.globals["error"] = newNimFnVM(luaError)
  vm.globals["pcall"] = newNimFnVM(luaPCall)
  vm.globals["xpcall"] = newNimFnVM(luaXPCall)

proc openTable*(vm: var VM) = 
  if mTable notin vm.openModules:
    return
  vm.globals["table"] = newTabLib()

proc openFile*(vm: var VM) = 
  if mFile notin vm.openModules:
    return
  vm.newFileLib()
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("file"), newLuaString("file"))

proc openMath*(vm: var VM) = 
  if mMath notin vm.openModules:
    return
  vm.globals["math"] = newMathLib()

proc openPackage*(vm: var VM) = 
  if mPackage notin vm.openModules:
    return
  vm.globals["package"] = newPackageLib()

proc openProcess*(vm: var VM) = 
  if mProcess notin vm.openModules:
    return
  vm.globals["process"] = newProcessLib()

proc openTime*(vm: var VM) = 
  if mTime notin vm.openModules:
    return
  vm.newTimeLib()

proc openDir*(vm: var VM) = 
  if mDir notin vm.openModules:
    return
  vm.newDirLib()
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("tempdir"), newLuaString("tempdir"))
  
proc openSet*(vm: var VM) =
  if mSet notin vm.openModules:
    return
  vm.globals["set"] = newSetLib()
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("set"), newLuaString("set"))

proc openString*(vm: var VM) =
  if mString notin vm.openModules:
    return
  let stringLib = newStringLib()
  vm.globals["string"] = stringLib
  let mt = newLuaTable()
  mt.tval[MTINDEX] = stringLib   # x:rep(...) and string.rep(x, ...) resolve to the SAME function
  vm.stringMT = mt

proc openCoroutine*(vm: var VM) =
  if mCoro notin vm.openModules:
    return
  vm.globals["coroutine"] = newCoroutineLib()
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("thread"), newLuaString("thread"))

proc openUnicode*(vm: var VM) = 
  if mUnicode notin vm.openModules:
    return
  vm.globals["unicode"] = newUnicodeLib()

proc openJson*(vm: var VM) = 
  if mJson notin vm.openModules:
    return
  vm.globals["json"] = newJsonLib()

proc openNet*(vm: var VM) = 
  if mNet notin vm.openModules:
    return
  vm.newNetLib()