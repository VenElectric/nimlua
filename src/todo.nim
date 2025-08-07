
type 
    TodoException = object of CatchableError

proc todo*(message:string) = raise newException(TodoException,message)