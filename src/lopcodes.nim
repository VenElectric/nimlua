import types

# iABC, iABx, iAsBx, iAx


proc createABC*(opcode:OpCodes,a,b,c:uint8):Instruction =
    result = Instruction(opcode:opcode,mode:OMABC,abc:(a,b,c))

proc createABx*(opcode:OpCodes,a:uint8,bx:uint16):Instruction =
    result = Instruction(opcode:opcode,mode:OMABx,abx:(a,bx))

proc createAsBx*(opcode:OpCodes,a:uint8,bx:int16):Instruction = 
    result = Instruction(opcode:opcode,mode:OMAsBx,asbx:(a,bx))

proc createAx*(opcode:OpCodes,ax:uint32): Instruction =
    result = Instruction(opcode:opcode,mode:OMAx,ax:ax)

proc isABC(i:Instruction): bool = i.mode == OMABC
proc isABx(i:Instruction): bool = i.mode == OMABx
proc isAsBx*(i:Instruction): bool = i.mode == OMAsBx
proc isAx*(i:Instruction): bool = i.mode == OMAx


