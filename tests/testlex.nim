import std/[unittest, strformat]
from std/strutils import strip
import ../src/llex

const MAX_ITER = 50000

suite "Tests for the Lexer":
    echo "Running lex tests"

    test "Functions":
        var lex = initWithFile("tests/lua/functions.lua")

        checkpoint("Success with initializing lexer")

        let outFile = open("log.txt", fmAppend)

        # let tokenStrings = [
        #     "local",
        #     "function",
        #     "hello",
        #     "(",
        #     ")",
        #     "return",
        #     "1",
        #     "+",
        #     "1",
        #     "end"
        # ]

        var idx = 0

        for tok in getToken(lex):
            writeLine(outFile, fmt"Token: {tok.kind} | Lexeme: {tok.lexeme}")
            check(tok.kind != TK_ERROR)
            inc(idx)

    test "Strings":
        const short_string = "local x = \"Hello World\""
        const string_sub_short = "Hello World"
        const short_len = len(string_sub_short)
        const long_str_one = "long = [[This is a very long string.\n It spans a couple of newlines.\n Very long. Much string. Feeling like a wow.]]"
        const string_sub_long_one = "This is a very long string.\n It spans a couple of newlines.\n Very long. Much string. Feeling like a wow."
        const long_str_one_len = len(string_sub_long_one)
        const long_str_two= """longer = [[Ipsum nostrud exercitation dolor ea ipsum quis deserunt pariatur consectetur. 
Ut elit excepteur est occaecat non ullamco incididunt eu mollit cillum Lorem fugiat duis. 
Aliquip dolore laboris excepteur labore reprehenderit id aute ullamco aliquip ad 
enim reprehenderit sunt. Dolore exercitation ex reprehenderit amet occaecat aute cupidatat in nisi quis voluptate sunt qui.]]"""
        const string_sub_long_two = """Ipsum nostrud exercitation dolor ea ipsum quis deserunt pariatur consectetur. 
Ut elit excepteur est occaecat non ullamco incididunt eu mollit cillum Lorem fugiat duis. 
Aliquip dolore laboris excepteur labore reprehenderit id aute ullamco aliquip ad 
enim reprehenderit sunt. Dolore exercitation ex reprehenderit amet occaecat aute cupidatat in nisi quis voluptate sunt qui."""
        const long_str_two_len = len(string_sub_long_two)
        const long_three = """longest = [[Consequat culpa ullamco adipisicing proident est nisi. Ipsum enim proident dolor excepteur ex nisi culpa commodo ipsum pariatur labore. 
Dolor aute magna sit consectetur ullamco et est officia do Lorem non amet. Est quis ad mollit proident dolore id consequat est aliqua. Labore ad velit consectetur occaecat. 
Est fugiat ullamco veniam aliquip sunt proident enim cillum ea sit.Lorem officia aliquip non id qui anim sunt. Excepteur anim ullamco incididunt adipisicing nisi exercitation qui magna et sint labore consectetur dolor 
non. Sunt excepteur incididunt id id consequat in eiusmod consequat culpa deserunt aute. Minim anim incididunt anim ipsum sunt irure. Nostrud commodo aute commodo Lorem fugiat dolor magna occaecat officia id. 
Proident quis ex dolore id sint pariatur anim laboris nulla irure ad dolor.]]"""
        const string_sub_long_three = """Consequat culpa ullamco adipisicing proident est nisi. Ipsum enim proident dolor excepteur ex nisi culpa commodo ipsum pariatur labore. 
Dolor aute magna sit consectetur ullamco et est officia do Lorem non amet. Est quis ad mollit proident dolore id consequat est aliqua. Labore ad velit consectetur occaecat. 
Est fugiat ullamco veniam aliquip sunt proident enim cillum ea sit.Lorem officia aliquip non id qui anim sunt. Excepteur anim ullamco incididunt adipisicing nisi exercitation qui magna et sint labore consectetur dolor 
non. Sunt excepteur incididunt id id consequat in eiusmod consequat culpa deserunt aute. Minim anim incididunt anim ipsum sunt irure. Nostrud commodo aute commodo Lorem fugiat dolor magna occaecat officia id. 
Proident quis ex dolore id sint pariatur anim laboris nulla irure ad dolor."""
        const long_three_len = len(string_sub_long_three)
        
        #let outFile = open("log.txt", fmAppend)

        var lex = initWithString(short_string)
        for tok in getToken(lex):
            if tok.kind == TK_STRING:
                check(len(tok.lexeme) == short_len)
        checkpoint("Finished Short String")

        lex = initWithString(long_str_one)
        for tok in getToken(lex):
            if tok.kind == TK_STRING:
                check(len(tok.lexeme) == long_str_one_len)
        checkpoint("Finished Long String One")

        lex = initWithString(long_str_two)
        for tok in getToken(lex):
            if tok.kind == TK_STRING:
                check(len(tok.lexeme) == long_str_two_len)
        checkpoint("Finished Long String Two")

        lex = initWithString(long_three)
        for tok in getToken(lex):
            if tok.kind == TK_STRING:
                check(len(tok.lexeme) == long_three_len)
        checkpoint("Finished Long String Three")


    test "Tables":
        var lex = initWithFile("tests/lua/tables.lua")

        checkpoint("Success with initializing lexer")

        let outFile = open("log.txt", fmAppend)

        var idx = 0


        for tok in getToken(lex):
            inc(idx)
            if idx > MAX_ITER:
                break
            writeLine(outFile, fmt"Token: {tok.kind} | Lexeme: {tok.lexeme}")
            check(tok.kind != TK_ERROR)
    
    test "Keywords":
        var lex = initWithFile("tests/lua/keywords.lua")

        checkpoint("Success with initializing lexer")

        let outFile = open("log.txt", fmAppend)

        var idx = 0


        for tok in getToken(lex):
            inc(idx)
            if idx > MAX_ITER:
                break
            writeLine(outFile, fmt"Token: {tok.kind} | Lexeme: {tok.lexeme}")
            check(tok.kind != TK_ERROR)
    
    test "Numbers":
        var lex = initWithFile("tests/lua/numbers.lua")

        checkpoint("Success with initializing lexer")

        let outFile = open("log.txt", fmAppend)

        var idx = 0


        for tok in getToken(lex):
            inc(idx)
            if idx > MAX_ITER:
                break
            writeLine(outFile, fmt"Token: {tok.kind} | Lexeme: {tok.lexeme}")
            check(tok.kind != TK_ERROR)
