import llex,lstate

when isMainModule:
  var s = newLuaState()
  loadFile(s,"test.lua")
  lex(s.lexer)
  for tk in s.lexer.tokens:
    echo tk
  
  