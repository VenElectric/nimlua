import std/[strscans,strutils]
import llex

when isMainModule:
    var lex = initWithFile("test.lua")
    lex.next()
    
    while lex.currentToken.kind != TK_EOF:
      echo "Lexeme: ",lex.currentToken.lexeme
      echo "Kind: ",lex.currentToken.kind
      lex.next()
      
    # let buff = "print(899000.3e-2)"
    # var pos = 6
    # var lexeme = ""
    # let r = scanp(buff,pos,(+`Digits`,?{'.',','},(*`Digits`,?'e',?{'+','-'},*`Digits`)) -> lexeme.add($_))
    # echo "R is: ",r
    # echo "lexeme: ",lexeme
    
    echo "done"