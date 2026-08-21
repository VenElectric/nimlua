import std/[strutils, rdstdin] # rdstdin provides a nice prompt with line-editing capabilities
import lvm, lparse, llex, lvalue,ltypes
# Assume all your previous code (Lexer, Parser, Compiler, VM) is imported or pasted above this.

proc repl*(vm: var VM) =
  echo "Welcome to Nim-Lua v1.0!"
  echo "Type 'exit' or 'quit' to close."

  while true:
    var line: string
    # Read input from the terminal
    if not readLineFromStdin("> ", line):
      break # Exit if the user presses Ctrl+D (EOF)

    let input = line.strip()
    if input == "exit" or input == "quit":
      break
    if input == "":
      continue

    # --- THE PIPELINE ---
    try:
      # Phase 2: Lex
      let tokens = tokenize(input)

      # Phase 3: Parse (Assuming you set up a basic parser object)
      var parser = LuaParser(tokens: tokens, current: 0)
      var ast = parser.parseStatement()

      var compiler = newCompiler()
      # Phase 4: Compile
      var chunk = initChunk()
      compiler.compile(ast, chunk, 1) # 1 is the line number for the REPL
      
      # # For a REPL to print the result of expressions automatically, 
      # # we manually inject an opReturn at the end of the chunk.
      chunk.writeChunk(uint8(opReturn), 1)

      # # Phase 5: Execute
      vm.chunk = chunk
      vm.ip = 0

      interpret(vm, chunk)

    except CatchableError as e:
      # If the lexer, parser, or VM throws an error, catch it so the REPL doesn't crash
      echo "Error: ", e.msg

