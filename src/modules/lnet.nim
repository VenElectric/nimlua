import std/[tables,json,logging]
import puppy
import ../ltypes,../lvalue,../lerror,../lutil

const HTTPMETHODS = ["get","post","put","patch","delete","head"]
let HTTPENUM = newLuaEnum(HTTPMETHODS)

# url
# method
# headers
# body
# query params table
# multipart data out of scope
# timeout puppy uses float32...we would need to cap this. Out of scope for now
proc luaNetRequest(vm: var VM,args:varargs[LuaValue]): seq[LuaValue] =
  if len(args) == 0:
    raise newException(LuaRuntimeError,moduleArgNumErrorFmt("request","1 to 5"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError,moduleArgKindErrorFmt(1,"request","string"))
  var url = args[0].sval
  var mthd = "get"
  var headers:HttpHeaders
  var body = newLuaNil()
  var hasContentType = false
  if len(args) >= 2 and not isNumber(args[1]):
    raise newException(LuaRuntimeError,moduleArgKindErrorFmt(2,"request","HttpMethod"))
  elif len(args) >= 2 and isNumber(args[1]):
    let eVal = enumGet(HTTPENUM,args[1])
    if isString(eVal):
      mthd = eVal.sval
    else:
      raise newException(LuaRuntimeError,"Argument should be an HttpMethod value. Received: " & $args[1])
  if len(args) >= 3 and not isLuaNil(args[2]) and not isTable(args[2]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(3, "request", "table"))
  elif len(args) >= 3 and isTable(args[2]):
    for k,v in args[2].tval.pairs:
      if isString(k):
        if $k == "Content-Type":
          hasContentType = true
        headers[$k] = $v
  if len(args) >= 4 and not isLuaNil(args[3]) and not (isTable(args[3]) or isString(args[3])):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(4, "request", "table or string"))
  elif len(args) >= 4 and (isTable(args[3]) or isString(args[3])):
    body = args[3]

  if len(args) == 5 and not isLuaNil(args[4]) and not isTable(args[4]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(5, "request", "table"))
  elif len(args) == 5 and isTable(args[4]):
    var params:QueryParams
    for k,v in args[4].tval.pairs:
      if isString(k):
        params[$k] = $v
    url = url & "?" & $params
  
  var req = newRequest(url,mthd,headers)
  if not isLuaNil(body):
    if isTable(body):
      req.body = $(%body)
      if not hasContentType:
        req.headers["Content-Type"] = "application/json"
    else:
      req.body = body.sval
      if not hasContentType:
        req.headers["Content-Type"] = "text/plain"
  try:
    let res = fetch(req)
    var tab = newLuaTable()
    tab.tval[newLuaString("status")] = newLuaInteger(res.code)
    try:
      tab.tval[newLuaString("body")] = toLua(parseJson(res.body))
    except JsonParsingError:
      tab.tval[newLuaString("body")] = newLuaString(res.body)   # not JSON -- hand back the raw text instead
    return @[tab, newLuaNil()]
  except CatchableError:
    return @[newLuaNil(), newLuaString(getCurrentExceptionMsg())]





proc newNetLib*(vm: var VM) =

  var net =  newLuaTable()
  net.tval[newLuaString("request")] = newNimFnVM(luaNetRequest)

  vm.globals["HttpMethod"] = HTTPENUM
  vm.globals["net"] = net
