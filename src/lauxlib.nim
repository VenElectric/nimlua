import std/[tables]
import ltypes,lvm,lvalue
import modules/[lcore,ltable,lpackage]

proc interpret*(vm: var VM, chunk: var Chunk) =
  vm.stack = @[]
  vm.frames = @[]
  vm.globals["table"] = newTabLib()
  vm.globals["print"] = newNimFn(luaPrint)
  vm.globals["setmetatable"] = newNimFn(luaSetMetatable)
  vm.globals["getmetatable"] = newNimFn(luaGetMetatable)
  vm.globals["pairs"] = newNimFn(luaPairs)
  vm.globals["ipairs"] = newNimFn(luaIPairs)
  vm.globals["next"] = newNimFn(luaNext)
  vm.globals["rawset"] = newNimFn(luaRawSet)
  vm.globals["rawget"] = newNimFn(luaRawGet)
  vm.globals["rawequal"] = newNimFn(luaRawEqual)
  vm.globals["rawlen"] = newNimFn(luaRawLen)
  vm.globals["tonumber"] = newNimFn(luaToNumber)
  vm.globals["package"] = newPackageLib()
  vm.globals["require"] = newNimFnVM(luaRequire)

  let mainVal = newLuaClosure("<main>", 0, chunk)
  vm.stack.add(wrapLuaClosure(mainVal))

  let rootFrame = CallFrame(
    closure: mainVal,
    ip: 0,
    slotBase: 0 
  )
  vm.frames.add(rootFrame)

  discard vm.run()