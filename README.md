# The Kuu Language Reference

Kuu is a Lua-based scripting language, implemented from scratch. It is
**mostly compatible with standard Lua** (roughly Lua 5.5 in spirit), with a
number of deliberate extensions and a handful of deliberate divergences.
Everywhere kuu differs from real Lua, it's called out explicitly in this
document — nothing is meant to surprise you silently.

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [Syntax](#2-syntax)
3. [Core Language Semantics](#3-core-language-semantics)
4. [Standard Library](#4-standard-library)
5. [Sandboxing and Capabilities](#5-sandboxing-and-capabilities)
6. [Quick-Reference: Divergences from Standard Lua](#6-quick-reference-divergences-from-standard-lua)

---

## 1. Getting Started

### Installing

Kuu installs like any Nim CLI tool, via `nimble`:

```bash
nimble install
```

This compiles the interpreter and links it into `~/.nimble/bin/kuu`. Add
that directory to your shell's `PATH` once, in your shell's startup file
(e.g. `~/.zprofile` for zsh):

```bash
echo 'export PATH="$HOME/.nimble/bin:$PATH"' >> ~/.zprofile
source ~/.zprofile
```

### Running a script

```bash
kuu myscript.lua
```

Pass `-t`/`--trace` to enable opcode-level execution tracing (very
verbose; mainly useful for debugging the interpreter itself, not scripts).

### Reusable modules

`require("mymodule")` searches, in order:

1. `./?.lua` — a sibling file in the current directory
2. `./?/init.lua` — a directory with an `init.lua`
3. `~/.kuu/lua/?.lua`
4. `~/.kuu/lua/?/init.lua`

The `~/.kuu/lua/` directory is created automatically on startup if it
doesn't already exist — a good place to keep modules you want available
from any script, regardless of working directory. If a module can't be
found, the error message lists every path that was actually tried.

---

## 2. Syntax

### 2.1 Comments

```lua
-- a line comment
--[[
  a long/block comment
]]
```

### 2.2 Variables and Scoping

```lua
local x = 5          -- ordinary local
x = 10                -- plain assignment: prefers an existing local/upvalue,
                      -- otherwise falls through to a global
```

**`global` (kuu extension).** Real Lua has no dedicated keyword for
declaring a global — you just assign to an undeclared name. Kuu adds an
explicit `global` keyword as a deliberate escape hatch:

```lua
global y = 20
```

Unlike a plain assignment, `global` **always** routes through `_ENV`,
ignoring any local or upvalue of the same name that might otherwise
shadow it. This makes it useful specifically when you want to guarantee
you're writing the *real* global, not whatever's currently shadowing it.

**Attributes** (real Lua 5.4 syntax, fully supported):

```lua
local PI <const> = 3.14159       -- reassignment raises a compile error
local f <close> = io_like_thing  -- __close runs when this local's scope ends
global LIMIT <const> = 100        -- <const> also works with `global`
```

**`_ENV` and sandboxing.** Every chunk has an implicit `_ENV` upvalue,
seeded from `_G`. Rebinding it locally genuinely sandboxes subsequent
global access in that scope — this is real, working isolation, not a
convenience alias:

```lua
do
  local _ENV = setmetatable({}, {__index = _G})  -- fall through to real globals for reads
  print("still works")   -- resolved via __index
  secretValue = 42        -- written into the SANDBOX table, not the real globals
end
print(type(secretValue))  -- nil -- never touched the real global table
```

A bare `local _ENV = {}` (no `__index` fallback) means *nothing* outside
that table is visible any more — not even `print`, unless you explicitly
carry it over: `local _ENV = {print = print}`.

### 2.3 Types and Values

Kuu's runtime kinds: `nil`, `bool`, `number`, `integer`, `string`, `table`,
`nim function`, `lua function`, `user data`, `thread`.

> ⚠️ **Divergence from real Lua:** `type()` reports several of these
> differently than stock Lua does. See
> [§6](#6-quick-reference-divergences-from-standard-lua) for the full list —
> in particular, `type()` distinguishes native and Lua-defined functions
> (`"nim function"` vs `"lua function"`, where real Lua always says just
> `"function"`), and integers from floats (`"integer"` vs `"number"`,
> where real Lua always says `"number"`).

**`rawtype(v)`** — like `type()`, but never affected by a `__type`
metatable override, and reports the raw underlying kind name directly.

### 2.4 Operators

Standard arithmetic (`+ - * / // % ^`), comparison (`== ~= < <= > >=`),
logical (`and or not`), concatenation (`..`), and bitwise (`& | ~ << >>`,
unary `~` for bitwise-not) operators all work as in standard Lua.

`..` coerces both a string and a number together (`"x" .. 5` → `"x5"`),
matching real Lua — but **not** booleans or `nil`; those still raise
without a `__concat` metamethod.

**Set operators** — `|`, `&`, `-`, `~` are overloaded for
[`set` values](#set-kuu-extension) specifically, meaning union,
intersection, difference, and symmetric difference respectively.

### 2.5 Control Flow

```lua
if cond then ... elseif cond2 then ... else ... end
while cond do ... end
repeat ... until cond
for i = 1, 10, 2 do ... end            -- numeric for, with optional step
for k, v in pairs(t) do ... end        -- generic for
break
goto continue
::continue::
```

### 2.6 Functions

```lua
function f(a, b) return a + b end
local function g(a, b) return a * b end
local h = function(a, b) return a - b end

function obj.method(self, x) ... end     -- dotted definition
function obj:method(x) ... end            -- colon sugar: implicit self

obj:method(5)          -- method call sugar
string_value:upper()   -- strings support colon-call syntax too (kuu extension --
                        -- see §4.1's note on the shared string metatable)

local function variadic(...)
  local n = select("#", ...)
  return ...            -- forwards all extra arguments
end
```

> Coroutine (`thread`) values do **not** support colon-call syntax —
> `co:resume()` raises `"attempt to index a thread value"`, matching real
> Lua exactly (confirmed directly against a real Lua interpreter during
> development). Always use `coroutine.resume(co, ...)`.

### 2.7 Tables

```lua
local t = {1, 2, 3, foo = "bar", [10] = "sparse"}
print(t[1], t.foo, t[10])
```

Auto-numbered array-literal keys (`{1, 2, 3}`) are real integers
internally, matching real Lua and making `#t`/`ipairs`/JSON array
detection all behave correctly and consistently.

### 2.8 `enum(...)` (kuu extension)

Not part of standard Lua at all. Declares a fixed, immutable set of named
integer constants with automatic reverse lookup:

```lua
local Color = enum(RED, GREEN, BLUE)
print(Color.RED)          --> 1
print(Color[1])           --> "RED"
```

Every enum (both user-defined ones and the library's own, like `FileMode`)
is genuinely **read-only**: attempting to write a new or existing key
raises, `rawget`/`rawset` are blocked on it, and `getmetatable`/
`setmetatable` are protected via `__metatable`. `type(someEnum)` reports
`"enumeration"`.

### 2.9 String Literals and Escapes

```lua
"double-quoted"
'single-quoted'
[[a long-bracket
   string, spanning multiple lines,
   with no escape processing at all]]
```

Supported escapes inside quoted strings: `\n \t \r \a \b \f \v \\ \" \'`,
`\xNN` (hex byte), `\ddd` (decimal byte, ≤255), `\z` (skips following
whitespace including real newlines — useful for breaking a long literal
across source lines), and a backslash immediately followed by a real
newline (embeds one newline).

Numeric literals support hex integers (`0xFF`), ordinary decimals, and
exponent notation with an optional sign (`1e10`, `1e+5`, `1e-5`).

---

## 3. Core Language Semantics

### 3.1 Metatables and Metamethods

Standard metamethods are all supported: `__index`, `__newindex`, `__call`,
`__add __sub __mul __div __mod __pow __unm __idiv`, `__band __bor __bxor
__bnot __shl __shr`, `__concat`, `__len`, `__eq __lt __le`, `__close`,
`__pairs` *(kuu-only — see below)*, `__tostring`, `__name`, `__metatable`.

- **`__pairs`** is honored if present (checked before falling back to raw
  iteration) — note this is *not* part of Lua 5.3+ (it existed in 5.2,
  then was removed); kuu keeps it as a deliberate, useful extension.
- **`__type`** (kuu-only) overrides what `type()` reports for a value
  entirely. This is distinct from real Lua's `__name`, which only relabels
  the *prefix* of the default `"table: 0x..."`-style representation — kuu
  supports both, doing exactly what each one does in real Lua/this
  project respectively.
- **`__metatable`**, when set, makes `getmetatable` return that value
  instead of the real metatable, and makes `setmetatable` raise
  `"cannot change a protected metatable"`. This matches real Lua's actual,
  documented behavior precisely.

**Strings share one metatable per VM** (`vm.stringMT`), not one per
string value — exactly how real Lua does it. This is what makes
`("hello"):upper()` work at all.

### 3.2 Userdata and Resource Cleanup

File handles and temp-directory handles are backed by real OS resources.
Two layers of cleanup exist:

- **`<close>`** — deterministic. Runs the moment the variable's scope
  ends, or immediately when `coroutine.close()` is called on a suspended
  coroutine holding one (walked in reverse declaration order, innermost
  scope first).
- **A GC-time safety net** (`=destroy`) — a backstop for resources that
  were *not* explicitly closed. This is inherently non-deterministic in
  timing (the same caveat real Lua's own `__gc` carries) — treat it as
  "eventually cleaned up," never as a substitute for `<close>` when you
  need a resource released *right now*.

### 3.3 Coroutines

```lua
local co = coroutine.create(function(a, b)
  local x = coroutine.yield(a + b)
  return x * 2
end)

print(coroutine.resume(co, 1, 2))   --> true  3
print(coroutine.resume(co, 10))     --> true  20
print(coroutine.status(co))         --> dead

local gen = coroutine.wrap(function()
  coroutine.yield(1)
  coroutine.yield(2)
end)
print(gen(), gen())                  --> 1  2   (no leading success boolean;
                                      --          errors are RAISED, not returned)

print(coroutine.isyieldable())       --> false at the top level
print(coroutine.running())           --> nil  true   at the top level

coroutine.close(co)   -- forces a suspended/dead coroutine to dead,
                       -- running any pending <close> handlers it holds
```

`yield()` only succeeds when called directly within the coroutine's own
top-level execution — attempting to yield from inside a nested `pcall` or
metamethod call raises `"attempt to yield across a C-call boundary"`,
matching real Lua's own restriction.

### 3.4 Error Handling

```lua
local ok, err = pcall(function() error("boom") end)
-- err is "line N: boom" -- runtime errors get a source line prefix,
-- tagged once at the innermost point of failure
```

`error()`/`assert()` preserve the *original* error value (string, table,
whatever was passed) via an internal mechanism separate from the line-tag
string — so `error({code = 42})` correctly hands back the real table to
`pcall`, not a stringified, line-prefixed version of it. Only errors that
originate as plain Nim-level runtime failures (not via an explicit
`error()` call) get the `"line N: "` prefix baked into the message itself.

---

## 4. Standard Library

### 4.1 Base Functions

| Function | Notes |
|---|---|
| `print(...)` | tab-separated, newline-terminated |
| `type(v)` / `rawtype(v)` | see §2.3 and §6 for divergences |
| `tostring(v)` / `tonumber(v [, base])` | `tostring` honors `__tostring`/`__name` |
| `pairs(t)` / `ipairs(t)` / `next(t [, k])` | `pairs` honors `__pairs` |
| `select(n, ...)` / `select("#", ...)` | |
| `setmetatable(t, mt)` / `getmetatable(t)` | honor `__metatable` |
| `rawget/rawset/rawequal/rawlen` | raise on tables marked internal (enums, `_G`, `TypeKind`) |
| `assert(v [, msg])` / `error(msg)` | |
| `pcall(f, ...)` / `xpcall(f, handler, ...)` | |
| `require(modname)` | see §1 for search path |
| `collectgarbage([opt])` | `opt` is a `GCOption` value; see §4.14 |

### 4.2 `string`

Fully implements standard Lua's `string` library, **including real
pattern matching** — `find`/`match`/`gmatch`/`gsub`, with character
classes, sets, all four quantifiers (`* + - ?`), anchors, plain and
position (`()`) captures, `%bxy` balanced matches, `%f[set]` frontier
patterns, and `%1`–`%9` back-references. `gsub`'s replacement argument may
be a string (with `%N` back-reference expansion), a table (keyed by the
first capture), or a function (called with every capture, or the whole
match if there were none).

One addition beyond stock Lua:

| Function | Signature | Notes |
|---|---|---|
| `string.split(s [, sep])` | → array of strings | splits on `sep` (default: `","`) |

### 4.3 `table`, `math`

Standard Lua libraries, unchanged.

### 4.4 `coroutine`

See §3.3. Fully implements `create`, `resume`, `yield`, `status`, `wrap`,
`isyieldable`, `running`, `close` — matching real Lua's own coroutine
library (method-call syntax on a `thread` value is the one thing
intentionally *not* supported, matching real Lua).

### 4.5 `file`

Reorganized out of Lua's `io`/`os` libraries into one place.

| Function | Notes |
|---|---|
| `file.open(path, mode)` | `mode` is a `FileMode` value; returns `nil, errmsg` on failure |
| `f:write(...)` / `f:read([format])` / `f:close()` / `f:lines()` / `f:flush()` | |
| `file.stdout` / `file.stderr` / `file.stdin` | `:close()` is a no-op on these |
| `file.remove(path)` / `file.rename(old, new)` | `nil, errmsg` on failure |
| `file.tmpname()` | name only, racy — matches real Lua's own documented caveat |
| `file.tmpfile()` | atomically creates + opens; auto-deletes on close |

**`FileMode`** — `.read .write .append .readWriteExisting .readWrite`

### 4.6 `dir` (kuu extension)

Not part of standard Lua at all — modeled after Nim's own `std/dirs`.

| Function | Notes |
|---|---|
| `dir.create(path)` / `dir.remove(path)` | `remove` is recursive |
| `dir.move(src, dest)` / `dir.copy(src, dest)` | |
| `dir.exists(path)` | |
| `dir.walk(path)` | iterator: `for kind, path in dir.walk(...) do` |
| `dir.temp(prefix, suffix [, base])` | name only |
| `dir.tempScoped(prefix, suffix [, base])` | returns a closeable handle (`<close>`-compatible) |

**`PathKind`** — `.file .dir .linkToFile .linkToDir`

### 4.7 `set` (kuu extension)

```lua
local a = set.new(1, 2, 3)
local b = set.new(2, 3, 4)
print(#a, a[2], a | b, a & b, a - b, a ~ b)
for v in pairs(a) do print(v) end
```

`s:add(v)` / `s:remove(v)` / `s:contains(v)`. `type(s) == "set"`.

### 4.8 `unicode` (kuu extension, reorganized/extended from `utf8`)

| Function | Notes |
|---|---|
| `unicode.char(...)` | encode codepoints → string |
| `unicode.codepoint(s [, i [, j]])` | `j` defaults to (resolved) `i` |
| `unicode.len(s [, i [, j]])` | **byte** positions, matching real `utf8.len` |
| `unicode.sub(s [, i [, j]])` | **character** positions, matching `string.sub`'s clamp-not-raise contract |
| `unicode.offset(s, n [, i])` | find the byte position of the *n*-th character |
| `unicode.codes(s)` | iterator |
| `unicode.valid(s)` | `nil` if valid, else the 1-based bad byte position |
| `unicode.upper/lower/reverse(s)` | genuinely Unicode-aware, unlike `string`'s ASCII-only versions |
| `unicode.isalpha/isspace/isupper/islower(codepoint)` | |

Every function that can encounter malformed UTF-8 (except `char`, whose
argument is a literal codepoint you typed, not decoded data) returns
`nil, position` rather than raising.

### 4.9 `json` (kuu extension)

| Function | Notes |
|---|---|
| `json.tojson(t)` | table → JSON string. A table is treated as a JSON array only if every key is a positive integer *and* the array wouldn't be more than a small, fixed multiple wider than its real entry count (a sparsity cap, guarding against a huge accidental index producing a giant output) |
| `json.loadjson(s)` | JSON string → Lua value |

Unrepresentable values (functions, userdata with no override) become
`null`/`nil`.

### 4.10 `net` (kuu extension)

```lua
local res, err = net.request(url [, method [, headers [, body [, queryParams]]]])
-- res.status, res.body (auto-decoded from JSON if possible, else the raw string)
```

`method` is an `HttpMethod` value. A table `body` is JSON-encoded with
`Content-Type: application/json` set automatically (unless you've already
set your own); a string `body` is sent verbatim with `Content-Type:
text/plain` set automatically under the same rule.

**`HttpMethod`** — `.get .post .put .patch .delete .head`

### 4.11 `time` (kuu extension, reorganized from `os`)

| Function | Notes |
|---|---|
| `time.clock()` | |
| `time.time([table])` / `time.time(y, m, d [, h, min, s])` | the positional form is a kuu-only extension beyond real Lua's table-only `os.time` |
| `time.date([format [, time]])` | `"*t"` returns a table; a leading `!` means UTC |
| `time.difftime(t2, t1)` | |

**`Month`**, **`Weekday`** — enums for readable date construction.

### 4.12 `process` (kuu extension, reorganized from `os`)

| Function | Notes |
|---|---|
| `process.exit([code])` | code may be an integer or boolean |
| `process.getenv(name)` | |
| `process.execute([command])` | shells out — see §5 for sandboxing |

### 4.13 `TypeKind` (kuu extension)

A registry table of every `type()` name that exists — built-in kinds
(`"string"`, `"table"`, ...) plus every custom one registered by a library
module (`"file"`, `"tempdir"`, `"set"`, `"enumeration"`, `"thread"`).
Comparing against `TypeKind.whatever` instead of a bare string literal
means a typo fails loudly (indexing a missing key) instead of silently
comparing false forever. Writing an already-registered name raises.

### 4.14 `GCOption`

`.collect .count .stop .restart` — passed to `collectgarbage`. Note: no
`step`/`incremental`/`generational` modes, since those are specific to
Lua's own collector internals and have no equivalent under Nim's ORC.

---

## 5. Sandboxing and Capabilities

Which standard-library modules get loaded at all is controlled by a
`set[ModuleFlags]` passed to `newVM()` — modeled directly on real Lua's
own `luaL_openlibs`/`luaL_openselectedlibs` embedding API, which works the
same way: whole libraries as the unit of inclusion, not individual
functions within one.

Separately, `process.execute` and `net.request` are gated by their own
capability flags (`allowExecute`, `allowNet` on `ProcessCapabilities`).
**In this project specifically, both default to `true`** — a deliberate
choice, since kuu is used for your own scripts rather than running
untrusted code from others. If that ever changes, both default to
`false` at the type level and can be locked down per-`VM` instance.

---

## 6. Quick-Reference: Divergences from Standard Lua

| Area | Real Lua | Kuu |
|---|---|---|
| `type()` on a native vs. Lua-defined function | always `"function"` | `"nim function"` vs `"lua function"` |
| `type()` on an integer vs. a float | always `"number"` | `"integer"` vs `"number"` |
| `type()` on userdata | `"userdata"` | `"user data"` (note the space) |
| `os.*` | one monolithic library | split into `file`, `dir`, `time`, `process` |
| `utf8.*` | minimal (encode/decode/count/iterate only) | `unicode.*` — same plus real Unicode-aware `upper`/`lower`/`reverse`/`sub`/classification |
| `__pairs` | removed in 5.3+ | supported, as a deliberate extension |
| `dir`, `set`, `json`, `net`, `TypeKind` | don't exist | new standard-library modules |
| `enum(...)` | doesn't exist | new language construct |
| `global` keyword | doesn't exist (bare assignment only) | explicit keyword, always routes through `_ENV` |
| `string:method()` on a string value | works | works (via a shared per-VM string metatable) |
| `thread:method()` on a coroutine | doesn't work | doesn't work (matches real Lua) |
| `os.time`'s argument form | table only | table **or** positional `(y, m, d, ...)` |
| `collectgarbage` modes | includes `step`/`incremental`/`generational` | only `collect`/`count`/`stop`/`restart` |
