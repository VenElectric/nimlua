import llex
from lua import lua_State
from std/streams import StringStream

const MAX_VARS = 200

type
    ExprKind = enum
        VVOID,
        VNIL,
        VTRUE,
        VFALSE,
        VK,
        VKNUM,
        VNONRELOC,
        VLOCAL,
        VUPVAL,
        VINDEXED,
        VJMP,
        VRELOCABLE,
        VCALL,
        VVARARG

type 
    FuncState = object
        pc: int
        lasttarget: int
        jpc: int
        nk: int
        np: int
        firstlocal: int
        nlocvars: int 
        nactvar: char
        nups: char
        freereg: char

proc compile_error(ls:LexState,kind:TokenKind) = raise newException(CatchableError,"Compile Error Placeholder")

proc checkToken(ls:LexState,kind:TokenKind) =
    if (getCurToken(ls).kind != kind):
        compile_error(ls,kind) 

proc lua_parser(L:lua_State,contents:string) = 
    let ls = initWithString(contents)

