import llex

when isMainModule:
    var ls = initWithFile("test.lua")
    ls.next()
    while ls.currentToken.kind != TK_EOF:
        echo ls.currentToken.lexeme
        echo ls.currentToken.kind
        ls.next()

    