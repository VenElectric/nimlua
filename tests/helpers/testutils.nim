import std/streams
import ../../src/llex
import ../../src/lparse
import ../../src/lcompiler
import ../../src/lvalue
import ../../src/ltypes
import ../../src/lauxlib
import ../../src/lvm

## Runs `source` through tokenize -> parse -> compile -> interpret, exactly
## the same pipeline nimlua.nim's executeString uses, and returns everything
## written to stdout (via vm.output) as a string.
##
## Requires:
##   - VM.output*: Stream added to ltypes.nim
##   - lauxlib.interpret() defaults vm.output to a real stdout stream when nil
##   - luaPrint is vm-aware (NativeFuncVM) and writes through vm.output
proc runLua*(source: string): string =
  let tokens = tokenize(source)
  var parser = LuaParser(tokens: tokens, current: 0)
  let ast = parser.parseBlock()

  var compiler = newCompiler()
  var chunk = initChunk()
  compiler.compile(ast, chunk, 1)
  chunk.writeChunk(uint8(opReturn), 1)
  chunk.writeChunk(0'u8, 1)

  var vm = newVM()
  vm.output = newStringStream()
  interpret(vm, chunk)
  result = StringStream(vm.output).data

## Same as runLua, but hands back the VM afterward too, for tests that need
## to inspect state beyond stdout (e.g. confirming a global got set).
proc runLuaVM*(source: string): (string, VM) =
  let tokens = tokenize(source)
  var parser = LuaParser(tokens: tokens, current: 0)
  let ast = parser.parseBlock()

  var compiler = newCompiler()
  var chunk = initChunk()
  compiler.compile(ast, chunk, 1)
  chunk.writeChunk(uint8(opReturn), 1)
  chunk.writeChunk(0'u8, 1)

  var vm = newVM()
  vm.output = newStringStream()
  interpret(vm, chunk)
  result = (StringStream(vm.output).data, vm)
