import std/[unittest, strformat]
from std/strutils import strip
import ../src/llex

suite "Tests for the Lexer":
    echo "Running lex tests"

    test "Functions":
        var lex = initWithFile("tests/lua/functions.lua")

        checkpoint("Success with initializing lexer")

        let outFile = open("log.txt", fmAppend)

        let tokenStrings = [
            "local",
            "function",
            "hello",
            "(",
            ")",
            "return",
            "1",
            "+",
            "1",
            "end"
        ]

        var idx = 0

        for tok in getToken(lex):
            writeLine(outFile, fmt"Token: {tok.kind} | Lexeme: {tok.lexeme}")
            check(tok.kind != TK_ERROR)
            check(tok.lexeme == tokenStrings[idx])
            inc(idx)

    test "Strings":
        var lex = initWithFile("tests/lua/strings.lua")

        checkpoint("Success with initializing lexer")

        const long_one = "This is a very long string. It spans a couple of newlines. Very long. Much string. Feeling like a wow."

        const long_two= """Ipsum nostrud exercitation dolor ea ipsum quis deserunt pariatur consectetur.
Ut elit excepteur est occaecat non ullamco incididunt eu mollit cillum Lorem fugiat duis.
Aliquip dolore laboris excepteur labore reprehenderit id aute ullamco aliquip ad
enim reprehenderit sunt. Dolore exercitation ex reprehenderit amet occaecat aute cupidatat in nisi quis voluptate sunt qui.
"""
        const long_three = """Consequat culpa ullamco adipisicing proident est nisi. Ipsum enim proident dolor excepteur ex nisi culpa commodo ipsum pariatur labore. 
Dolor aute magna sit consectetur ullamco et est officia do Lorem non amet. Est quis ad mollit proident dolore id consequat est aliqua. Labore ad velit consectetur occaecat. 
    Est fugiat ullamco veniam aliquip sunt proident enim cillum ea sit.Lorem officia aliquip non id qui anim sunt. Excepteur anim ullamco incididunt adipisicing nisi exercitation qui magna et sint labore consectetur dolor 
    non. Sunt excepteur incididunt id id consequat in eiusmod consequat culpa deserunt aute. Minim anim incididunt anim ipsum sunt irure. Nostrud commodo aute commodo Lorem fugiat dolor magna occaecat officia id. 
    Proident quis ex dolore id sint pariatur anim laboris nulla irure ad dolor."""

        let string_tests = ["Hello World", "Hello Global",long_one,long_two,long_three]

        let outFile = open("log.txt", fmAppend)

        var idx = 0

        for tok in getToken(lex):
            writeLine(outFile, fmt"Token: {tok.kind} | Lexeme: {tok.lexeme}")
            check(tok.kind != TK_ERROR)
            if tok.kind == TK_STRING:
                check(tok.lexeme == strip(string_tests[idx]))
                checkpoint(fmt"Tok: {tok.kind} successful")
                inc(idx)

    test "Tables":
        var lex = initWithFile("tests/lua/tables.lua")

        checkpoint("Success with initializing lexer")

        let outFile = open("log.txt", fmAppend)

        #var idx = 0


        for tok in getToken(lex):
            writeLine(outFile, fmt"Token: {tok.kind} | Lexeme: {tok.lexeme}")
            check(tok.kind != TK_ERROR)
