
type
    Unimplemented* = object of CatchableError

proc raiseUnimplemented*(message:string) = raise newException(Unimplemented,message)
