import types,lobject

proc readInstruction(L: var LuaState):Instruction = 
    inc(L.CI.savedpc)
    return L.CI.code[L.CI.savedpc]

template binary_op(op:untyped) = 
    let rhs: LuaValue = pop(vm)
    let lhs: LuaValue = pop(vm)
    if not kisNumber(lhs) or not kisNumber(lhs):
        runtimeError(vm,"Operands Must Be Numbers")
        result = RESULT_RUNTIME_ERROR
    push(vm,op(lhs,rhs))

proc lauV_execute*(L:var LuaState) = 

    var i:Instruction

    while true:
        i = readInstruction(L)

        case i.opcode:
            of OP_MOVE: discard
            of OP_LOADK: discard
            of OP_LOADKX: discard
            of OP_LOADBOOL: discard
            of OP_LOADNIL: discard
            of OP_GETUPVAL: discard
            of OP_GETTABUP: discard
            of OP_GETTABLE: discard
            of OP_SETTABUP: discard
            of OP_SETUPVAL: discard
            of OP_SETTABLE: discard
            of OP_NEWTABLE: discard
            of OP_SELF: discard
            of OP_ADD: discard
            of OP_SUB: discard
            of OP_MUL: discard
            of OP_DIV: discard
            of OP_MOD: discard
            of OP_POW: discard
            of OP_UNM: discard
            of OP_NOT: discard
            of OP_LEN: discard
            of OP_CONCAT: discard
            of OP_JMP: discard
            of OP_EQ: discard
            of OP_LT: discard
            of OP_LE: discard
            of OP_TEST: discard
            of OP_TESTSET: discard
            of OP_CALL: discard
            of OP_TAILCALL: discard
            of OP_RETURN: discard
            of OP_FORLOOP: discard
            of OP_FORPREP: discard
            of OP_TFORCALL: discard
            of OP_TFORLOOP: discard
            of OP_SETLIST: discard
            of OP_CLOSURE: discard
            of OP_VARARG: discard
            of OP_EXTRAARG: discard
