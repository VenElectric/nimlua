import llex,types
import std/strformat

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
    ExprDesc = object

using 
    vls:var LexState
    ls: LexState

proc compile_error(ls:LexState,k:TokenKind) = lexerror(CatchableError,"Compile Error",k,ls.lineNumber)

proc statement(vls)
proc expression(vls;v:ExprDesc)

# proc anchortoken()

proc semerror(vls;msg:string) = syntax_error(msg,vls.token.kind,vls.lineNumber)

proc errorexpected(vls;k:TokenKind) = syntax_error(fmt"{k} expected",k,vls.lineNumber)

proc testnext(vls;k:TokenKind): bool =
    if vls.token.kind == k:
        lua_next(vls)
        return true
    else: return false

proc check(vls;k:TokenKind) = 
    if vls.token.kind != k: 
        errorexpected(vls,k)

proc checknext(vls;k:TokenKind) =
    check(vls,k)
    lua_next(vls)

proc checkmatch(vls;what:TokenKind,who:TokenKind,where:int) =
    if not testnext(vls,what):
        if where == vls.linenumber:
            errorexpected(vls,what)
        else:
            syntax_error(fmt"{what} expected to close {who} at line {where}",what,where)





proc enterlevel(vls) = discard

proc checkToken(vls;kind:TokenKind) =
    if (vls.token.kind != kind):
        compile_error(vls,kind) 

proc subexpr(vls;v:ExprDesc,limit:int): BinOpr =
    enterlevel(vls)


proc expression(vls;v:ExprDesc) = discard subexpr(vls,v,0)

proc block_follow(vls;withuntil:bool): bool = 
    case vls.token.kind:
        of TK_ELSE,TK_ELSEIF,TK_END,TK_EOS: return true
        of TK_UNTIL: return withuntil
        else: return false

proc testthenblock*(vls;escapelist:seq[int]) =
    let fs = vls.funcstate
    var exp = ExprDesc()
    lua_next(vls)
    expression(vls,exp)

proc ifstatement(vls;line:int) =
    let fs = vls.funcstate


proc retstatement(vls) = discard


proc statement(vls) = 

    case vls.token.kind:
        of TK_SEMCOL: lua_next(vls)
        of TK_IF:
            discard
        of TK_WHILE: discard
        of TK_DO: discard
        of TK_FOR: discard
        of TK_REPEAT: discard
        of TK_FUNCTION: discard
        of TK_LOCAL: discard
        of TK_DBCOLON: discard
        of TK_RETURN: discard
        of TK_BREAK,TK_GOTO: discard
        else: discard



proc statlist(vls) =
    while not block_follow(vls,true):
        if vls.token.kind == TK_RETURN:
            statement(vls)
            return
        statement(vls)

proc lua_parser(L:LuaState,contents:string) = 
    let ls = initWithString(contents)

