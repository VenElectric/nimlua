import std/logging
import lvalue, ltypes

proc disassembleChunk*(chunk: Chunk, name: string = "Unknown") =
  debug "=== ", name, " ==="
  var i = 0
  debug "len: ", chunk.code.len
  while i < chunk.code.high:
    let byte = chunk.code[i]
    let opcode = OpCode(byte)
    # Print instruction with line info (no sprintf needed)
    let line = if i < chunk.lines.len: $chunk.lines[i] else: "?"
    debug "  ", i, "  ", $opcode, "  line ", line
    inc(i)
    # Handle instruction operands
    case opcode
    of opConstant:
      let constIdx = int(chunk.code[i])
      if constIdx < chunk.constants.len:
        debug "    constant[", constIdx, "] = ", $chunk.constants[constIdx]
      else:
        debug "    constant[", constIdx, "] = ???"
      inc(i)
    of opGetLocal, opSetLocal:
      let slot = int(chunk.code[i])
      debug "    slot: ", slot
      inc(i)
    of opMarkGlobalConst:
      let constIdx = int(chunk.code[i])
      if constIdx < chunk.constants.len:
        debug "    marking const: ", chunk.constants[constIdx].sval
      else:
        debug "    marking const: ???"
      inc(i)
    of opGetMethod:
      let constIdx = int(chunk.code[i])
      if constIdx < chunk.constants.len:
        debug "    method name: ", chunk.constants[constIdx].sval
      else:
        debug "    method name: ???"
      inc(i)
    of opCall:
      let argCount = int(chunk.code[i])
      debug "    args: ", argCount
      inc(i)
    of opCallSpread, opReturnSpread:
      let prefixCount = int(chunk.code[i])
      debug "    prefix count: ", prefixCount
      inc(i)
    of opReturn:
      let count = int(chunk.code[i])
      debug "    return count: ", count
      inc(i)
    of opAdjust:
      let want = int(chunk.code[i])
      debug "    want: ", want
      inc(i)
    of opCloseValue:
      let slot = int(chunk.code[i])
      debug "    slot: ", slot
      inc(i)
    of opSpreadVararg:
      let startIdx = int(chunk.code[i])
      debug "    start index: ", startIdx
      inc(i)
    of opJump, opJumpIfFalse:
      let highByte = int(chunk.code[i])
      let lowByte = int(chunk.code[i + 1])
      let offset = (highByte shl 8) or lowByte
      debug "    jump offset: ", offset, " -> ", i + 2 + offset
      inc(i, 2)
    of opLoop:
      let highByte = int(chunk.code[i])
      let lowByte = int(chunk.code[i + 1])
      let offset = (highByte shl 8) or lowByte
      debug "    loop offset: ", offset, " -> ", i + 2 - offset
      inc(i, 2)
    of opClosure:
      let constIdx = int(chunk.code[i])
      inc(i)
      debug "    constant[", constIdx, "] = ", $chunk.constants[constIdx]
      let protoClosure = chunk.constants[constIdx].fnVal
      for uvIdx in 0 ..< protoClosure.upvalues.len:
        let isLocal = chunk.code[i]
        let idx = chunk.code[i + 1]
        debug "    upvalue ", uvIdx, ": ", (if isLocal ==
            1: "local" else: "upvalue"), " #", idx
        inc(i, 2)
    of opGetUpvalue, opSetUpvalue:
      let slot = int(chunk.code[i])
      debug "    upvalue slot: ", slot
      inc(i)
    of opNewTable, opAdd, opSubtract, opMultiply, opDivide,
         opGetTable, opSetTable, opPop, opCloseUpvalue, opFloorDiv,
             opModulo,
         opExponent, opNegate, opBitAnd, opBitOr, opBitXor, opShr, opShl,
             opBitNot,
         opNot, opEquals, opLess, opLessEqual, opGreater, opGreaterEqual,
             opNotEqual,
         opLen, opConcat, opVararg, opSpreadVarargValues:
      # Genuinely no operands
      discard
  debug "=== END ==="