import lcore,lfile,lmath,lpackage,ltable,lprocess,ltime,ldir,lset,lstring,lcoro,lunicode
import ../ltypes,../lvm,../lvalue
import std/tables

proc openCore*(vm: var VM) = 
  vm.registerGC()
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("string"), newLuaString("string"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("bool"), newLuaString("bool"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("nil"), newLuaString("nil"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("number"), newLuaString("number"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("integer"), newLuaString("integer"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("table"), newLuaString("table"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("nim function"), newLuaString("nim function"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("lua function"), newLuaString("lua function"))
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("user data"), newLuaString("user data"))
  vm.globals["assert"] = newNimFnVM(luaAssert)
  vm.globals["rawget"] = newNimFn(luaRawGet)
  vm.globals["rawset"] = newNimFn(luaRawSet)
  vm.globals["rawequal"] = newNimFn(luaRawEqual)
  vm.globals["rawlen"] = newNimFn(luaRawLen)
  vm.globals["setmetatable"] = newNimFn(luaSetMetatable)
  vm.globals["getmetatable"] = newNimFn(luaGetMetatable)
  vm.globals["print"] = newNimFnVM(luaPrint)
  vm.globals["next"] = newNimFn(luaNext)
  vm.globals["pairs"] = newNimFnVM(luaPairs)
  vm.globals["ipairs"] = newNimFn(luaIPairs)
  vm.globals["tonumber"] = newNimFn(luaToNumber)
  vm.globals["tostring"] = newNimFn(luaToString)
  vm.globals["type"] = newNimFn(luaType)
  vm.globals["select"] = newNimFn(luaSelect)
  vm.globals["require"] = newNimFnVM(luaRequire)
  vm.globals["error"] = newNimFnVM(luaError)
  vm.globals["pcall"] = newNimFnVM(luaPCall)
  vm.globals["xpcall"] = newNimFnVM(luaXPCall)

proc openTable*(vm: var VM) = vm.globals["table"] = newTabLib()

proc openFile*(vm: var VM) = 
  vm.newFileLib()
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("file"), newLuaString("file"))

proc openMath*(vm: var VM) = vm.globals["math"] = newMathLib()

proc openPackage*(vm: var VM) = vm.globals["package"] = newPackageLib()

proc openProcess*(vm: var VM) = vm.globals["process"] = newProcessLib()

proc openTime*(vm: var VM) = vm.newTimeLib()

proc openDir*(vm: var VM) = 
  vm.newDirLib()
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("tempdir"), newLuaString("tempdir"))
  
proc openSet*(vm: var VM) =
  vm.globals["set"] = newSetLib()
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("set"), newLuaString("set"))

proc openString*(vm: var VM) =
  vm.globals["string"] = newStringLib()

proc openCoroutine*(vm: var VM) =
  vm.globals["coroutine"] = newCoroutineLib()
  vm.luaIndexSet(vm.globals["TypeKind"], newLuaString("thread"), newLuaString("thread"))

proc openUnicode*(vm: var VM) = vm.globals["unicode"] = newUnicodeLib()