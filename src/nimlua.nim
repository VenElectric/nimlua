import std/[options]
import llex,lobject


# type 
#     UserData = ref object of RootObj
#     MyTestData = ref object of UserData
#       x,y: int
#       b: string

when isMainModule:
  let x = newLInteger(92)
  let y = newLFloat(90.0)
  let z = x > y
  if isSome(z):
    echo "Um.. ",get(z).boolv
  
  let n = newLString("hello ")
  let h = newLString("world")
  let b = n .. h
  if isSome(b):
    echo "hmmm...",get(b).strv

  let axe = newLInteger(90)
  let r = not axe
  if isSome(r):
    echo "result is: ",get(r).intv