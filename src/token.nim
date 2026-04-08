
type
    TokenKind* = enum
        TK_AND = "and"
        TK_BREAK = "break"
        TK_DO = "do"
        TK_ELSE = "else"
        TK_ELSEIF = "elseif"
        TK_END = "end"
        TK_FALSE = "false"
        TK_FOR = "for"
        TK_FUNCTION = "function"
        TK_GOTO = "goto"
        TK_IF = "if"
        TK_IN = "in"
        TK_LOCAL = "local"
        TK_NIL = "nil"
        TK_NOT = "not"
        TK_OR = "or"
        TK_REPEAT = "repeat"
        TK_RETURN = "return"
        TK_THEN = "then"
        TK_TRUE = "true"
        TK_UNTIL = "until"
        TK_WHILE = "while"
        TK_TILDE = "~"
        TK_CONCAT = ".."
        TK_DOTS = "..."
        TK_EQ = "="
        TK_GE = ">="
        TK_LE = "<="
        TK_NE = "~="
        TK_DBCOLON = "::"
        TK_EOF = "<EOF>"
        TK_NUMBER = "{NUMBER}"
        TK_NAME
        TK_STRING
        TK_LEFTPAREN = "("
        TK_CARROT = "^"
        TK_STAR = "*"
        TK_SLASH = "/"
        TK_PLUS = "+"
        TK_MINUS = "-"
        TK_LESS = "<"
        TK_GREATER = ">"
        TK_MOD = "%"
        TK_EQEQ = "=="
        TK_COMMA = ","
        TK_DOT = "."
        TK_SEMCOL = ";"
        TK_COLON = ":"
        TK_RIGHTPAREN = ")"
        TK_LEFTBRACKET = "{"
        TK_RIGHTBRACKET = "}"
        TK_LEFTSTAPLE = "["
        TK_RIGHTSTAPLE = "]"
        TK_HASH = "#"
        TK_BOR = "|"
        TK_BAND = "&"
        TK_DBSLASH = "\\\\"
        TK_ERROR

type
    Token* = object
        kind*: TokenKind
        lexeme*: string
        linenumber*: int


func createToken*(linenumber: int, kind: TokenKind, lexeme: string): Token =
    result = Token(kind: kind, lexeme: lexeme, linenumber: linenumber)

func createEOFToken*(linenumber: int): Token = result = createToken(linenumber,
        TK_EOF, "eof")

func createErrorToken*(linenumber: int, msg: string): Token = createToken(
        linenumber, TK_ERROR, msg)