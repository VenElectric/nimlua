import std/[strscans,strutils]
import llex


# type 
#     UserData = ref object of RootObj
#     MyTestData = ref object of UserData
#       x,y: int
#       b: string

when isMainModule:
  # let d = new MyTestData
  # d.x = 0
  # d.y = 1
  # d.b = "hello userdata"

  # var mySeq: seq[UserData] = @[]

  # mySeq.add(d)
  # var y = cast[MyTestData](mySeq[0])
  # echo y.x
  # echo y.y
  # echo y.b
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