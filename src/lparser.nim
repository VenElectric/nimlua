import llex,types,lfunc
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


using
    ls:var LexState

proc expression(ls) = discard
  
proc returnstmt(ls) = discard

proc gotostmt(ls) = discard
  
proc localstmt(ls) = discard
  
proc functionstmt(ls) = discard

proc forstmt(ls) = discard

proc repeatstmt(ls) = discard
  
proc whilestmt(ls) = discard

proc blockstmt(ls) = discard
  
proc ifstmt(ls) = discard

proc statement(ls) =

    case ls.currentToken.kind:
        of TK_SEMCOL: discard
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



proc statlist(ls) = discard
    # while not block_follow(ls,true):
    #     if ls.token.kind == TK_RETURN:
    #         statement(ls)
    #         return
    #     statement(ls)

# proc lua_parser(L:LuaState,contents:string): Closure =
#     let ls = initWithString(L,contents)
#     let cl = newLClosure(L,1)
#     L.stack
