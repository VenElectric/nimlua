
type
    UnimplementedError* = object of CatchableError
    SyntaxError* = object of CatchableError
    TableAccessException* = object of Defect
    TypeError* = object of CatchableError
    

proc raiseUnimplemented*(message:string) = raise newException(UnimplementedError,message)
proc raiseSyntaxError*(message:string) = raise newException(SyntaxError,message)

