# This is just an example to get you started. A typical binary package
# uses this file as the main entry point of the application.
import std/strutils
when isMainModule:
  
  const one:int8 = 82
  const two:int8 = 55

  var both:int16 = 0

  both = int16(one) shl 8 or two

  echo both

