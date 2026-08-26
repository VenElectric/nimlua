import std/unittest
import helpers/testutils
import ../src/lerror

# These tests make REAL network calls to httpbin.org, a stable public
# service purpose-built for exactly this kind of testing (it echoes back
# whatever it receives). This is a genuinely different kind of flakiness
# risk than anything else in this suite: a failure here could mean the
# code regressed, or it could just mean httpbin.org is temporarily down,
# slow, or unreachable. Worth checking that possibility first before
# assuming a real regression if these ever fail unexpectedly.

suite "HttpMethod enum":
  test "members are registered and distinct":
    check runLua("""
      print(HttpMethod.get ~= HttpMethod.post)
      print(HttpMethod.post ~= HttpMethod.put)
    """) == "true\ntrue\n"

  test "reverse lookup gives the method name back":
    check runLua("""print(HttpMethod[HttpMethod.get])""") == "get\n"

suite "net.request: argument validation":
  test "zero arguments raises":
    expect LuaRuntimeError:
      discard runLua("""net.request()""")

  test "a non-string URL raises":
    expect LuaRuntimeError:
      discard runLua("""net.request(42)""")

  test "a non-number method argument raises":
    expect LuaRuntimeError:
      discard runLua("""net.request("https://httpbin.org/get", "get")""")

  test "a non-table headers argument raises":
    expect LuaRuntimeError:
      discard runLua("""net.request("https://httpbin.org/get", HttpMethod.get, "not a table")""")

  test "a body that is neither table nor string raises":
    expect LuaRuntimeError:
      discard runLua("""net.request("https://httpbin.org/get", HttpMethod.get, nil, 42)""")

  test "a non-table query-params argument raises":
    expect LuaRuntimeError:
      discard runLua("""net.request("https://httpbin.org/get", HttpMethod.get, nil, nil, "not a table")""")

suite "net.request: basic GET":
  test "a plain GET returns status 200 and a decoded JSON table":
    check runLua("""
      local res, err = net.request("https://httpbin.org/get")
      print(err)
      print(res.status)
      print(type(res.body))
    """) == "nil\n200\ntable\n"

  test "query parameters are appended to the URL and echoed back by httpbin":
    check runLua("""
      local res = net.request("https://httpbin.org/get", HttpMethod.get, nil, nil, {foo = "bar"})
      print(res.body.args.foo)
    """) == "bar\n"

suite "net.request: bodies and Content-Type":
  test "a table body is JSON-encoded, and Content-Type defaults to application/json":
    check runLua("""
      local res = net.request("https://httpbin.org/post", HttpMethod.post, nil, {hello = "world"})
      print(res.body.json.hello)
      print(res.body.headers["Content-Type"])
    """) == "world\napplication/json\n"

  test "a string body is sent verbatim, without forcing a JSON Content-Type":
    check runLua("""
      local res = net.request("https://httpbin.org/post", HttpMethod.post, nil, "plain text body")
      print(res.body.data)
      print(res.body.headers["Content-Type"] ~= "application/json")
    """) == "plain text body\ntrue\n"

  test "an explicit Content-Type header is not overridden by the default":
    check runLua("""
      local res = net.request("https://httpbin.org/post", HttpMethod.post,
        {["Content-Type"] = "application/x-custom"}, {hello = "world"})
      print(res.body.headers["Content-Type"])
    """) == "application/x-custom\n"

suite "net.request: custom headers":
  test "a custom header is sent and echoed back":
    check runLua("""
      local res = net.request("https://httpbin.org/headers", HttpMethod.get, {["X-Test-Header"] = "hello"})
      print(res.body.headers["X-Test-Header"])
    """) == "hello\n"

suite "net.request: response body decoding":
  test "a non-JSON response body falls back to a raw string instead of erroring":
    check runLua("""
      local res, err = net.request("https://httpbin.org/html")
      print(err)
      print(res.status)
      print(type(res.body))
    """) == "nil\n200\nstring\n"

  test "a non-2xx status still returns normally, without raising":
    check runLua("""
      local res, err = net.request("https://httpbin.org/status/404")
      print(err)
      print(res.status)
    """) == "nil\n404\n"

suite "net.request: failure handling":
  test "an unsupported URL scheme returns nil plus an error, rather than raising or crashing":
    check runLua("""
      local res, err = net.request("not-a-url-at-all")
      print(res, err ~= nil)
    """) == "nil\ttrue\n"
