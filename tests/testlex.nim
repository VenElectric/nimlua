import std/[unittest, streams,lexbase]
# from std/strutils import strip
import ../src/llex

const MAX_ITER = 50000

proc resetLexer(ls:var LexState,newSource:string) = 
    ls.close()
    ls.open(newStringStream(newSource))

suite "Tests for the Lexer":
    echo "Running lex tests"

    test "Token Test":
        let TokenTests = [
            ("and",TK_AND),
            ("break",TK_BREAK),
            ("do",TK_DO),
            ("else",TK_ELSE),
            ("elseif", TK_ELSEIF),
            ("false",TK_FALSE),
            ("for",TK_FOR),
            ("function",TK_FUNCTION),
            ("goto",TK_GOTO),
            ("if",TK_IF),
            ("in",TK_IN),
            ("local",TK_LOCAL),
            ("nil",TK_NIL),
            ("not",TK_NOT),
            ("or",TK_OR),
            ("repeat",TK_REPEAT),
            ("return",TK_RETURN),
            ("then",TK_THEN),
            ("true",TK_TRUE),
            ("until",TK_UNTIL),
            ("while",TK_WHILE),
            ("..",TK_CONCAT),
            ("...",TK_DOTS),
            ("=",TK_EQ),
            (">=",TK_GE),
            ("<=",TK_LE),
            ("~=",TK_NE),
            ("::",TK_DBCOLON),
            ("variable",TK_NAME),
            ("\"Hello World\"",TK_STRING),
            ("[[Hello World]]",TK_STRING),
            ("<",TK_LESS),
            (">",TK_GREATER),
            ("+",TK_PLUS),
            ("-",TK_MINUS),
            ("/",TK_SLASH),
            ("*",TK_STAR),
            ("%",TK_MOD),
            ("^",TK_CARROT),
            ("==",TK_EQEQ),
            (",",TK_COMMA),
            (".",TK_DOT),
            (";",TK_SEMCOL),
            (":",TK_COLON),
            ("(",TK_LEFTPAREN),
            (")",TK_RIGHTPAREN),
            ("{",TK_LEFTBRACKET),
            ("}",TK_RIGHTBRACKET),
            ("[",TK_LEFTSTAPLE),
            ("]",TK_RIGHTSTAPLE),
            ("#",TK_HASH),
             ("--[[this is a long comment]]",TK_COMMENT),
             ("--[[this is a long comment\n with a newline]]",TK_COMMENT),
            ("--this is a comment\n",TK_COMMENT),
            ("?",TK_ERROR)
        ]

        # ("--[[this is a long comment]]",TK_COMMENT),
        #     ("--this is a comment",TK_COMMENT),
        #     ("?",TK_ERROR)
        var ls: LexState
        for x in 0..(len(TokenTests)-1):
            let tup = TokenTests[x]
            ls = initWithString(tup[0])
            defer: ls.close()
            let tk = getToken(ls)
            check(tk.kind == tup[1])
