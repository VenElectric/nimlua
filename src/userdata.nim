
type
    UserData = ref object of RootObj

using
    ud: UserData

method get_item(ud) = raise newException(CatchableError,"unimplemented")

method set_item(ud) = raise newException(CatchableError,"unimplemented")