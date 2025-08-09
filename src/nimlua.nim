


type 
    UserData = ref object of RootObj
    MyTestData = ref object of UserData
      x,y: int
      b: string

method test(m:UserData) {.base.} = discard

method test(m:MyTestData) = 
  echo m.x
  echo "hello world"

proc useTest(m:UserData) = test(m)

when isMainModule:
  echo "test"
  let mtd = MyTestData(x:1,y:2,b:"ugh")
  useTest(mtd)