-- kuu.stub.lua
--
-- Type annotations only -- this file is never executed by kuu itself.
-- Point your editor's Lua language server at the folder containing this
-- file (see the .luarc.json snippet at the bottom) so it can offer
-- completion/hover/type-checking for kuu's library surface.
--
-- NOT covered here, on purpose:
--   - math/table/string: faithful to real Lua's own signatures; a generic
--     LSP already understands them correctly, EXCEPT for string.split
--     (kuu's one addition beyond stock Lua's string library), stubbed
--     below as a single additive declaration -- NOT a full @class string
--     redefinition, which would risk overriding the LSP's own built-in
--     knowledge of string.format/byte/etc.
--   - coroutine: every function (create/resume/yield/status/wrap/
--     isyieldable/running/close) exists in real Lua 5.4 with matching
--     behavior -- nothing kuu-specific to describe.
--   - The `enum(...)` construct and the `global` keyword: these are real
--     SYNTAX, not library surface. No stub file can teach a parser new
--     grammar -- that part needs the actual custom-LSP work later.

---------------------------------------------------------------------------
-- string (one addition beyond stock Lua)
---------------------------------------------------------------------------

---Splits `s` into substrings wherever `sep` occurs (default separator: ",").
---@param s string
---@param sep? string
---@return string[]
function string.split(s, sep) end

---------------------------------------------------------------------------
-- file
---------------------------------------------------------------------------

---@enum FileMode
FileMode = { read = 1, write = 2, append = 3, readWriteExisting = 4, readWrite = 5 }

---@class FileHandle
---@field write fun(self: FileHandle, ...: string|number): FileHandle
---@field read fun(self: FileHandle, format?: string): string|nil
---@field close fun(self: FileHandle): boolean
---@field lines fun(self: FileHandle): fun(): string|nil
---@field flush fun(self: FileHandle): FileHandle

---@class FileLib
---@field open fun(path: string, mode: integer): FileHandle|nil, string|nil
---@field stdout FileHandle
---@field stderr FileHandle
---@field stdin FileHandle
---@field remove fun(path: string): boolean|nil, string|nil
---@field rename fun(old: string, new: string): boolean|nil, string|nil
---@field tmpname fun(): string
---@field tmpfile fun(): FileHandle|nil, string|nil
file = {}

---------------------------------------------------------------------------
-- dir
---------------------------------------------------------------------------

---@enum PathKind
PathKind = { file = 1, dir = 2, linkToFile = 3, linkToDir = 4 }

---@class TempDirHandle
---@field remove fun(self: TempDirHandle): boolean
---@field path fun(self: TempDirHandle): string

---@class DirLib
---@field create fun(path: string): boolean|nil, string|nil
---@field remove fun(path: string): boolean|nil, string|nil
---@field move fun(src: string, dest: string): boolean|nil, string|nil
---@field exists fun(path: string): boolean
---@field copy fun(src: string, dest: string): boolean|nil, string|nil
---@field walk fun(path: string): fun(): (integer|nil, string|nil)
---@field temp fun(prefix: string, suffix: string, baseDir?: string): string|nil, string|nil
---@field tempScoped fun(prefix: string, suffix: string, baseDir?: string): TempDirHandle|nil, string|nil
dir = {}

---------------------------------------------------------------------------
-- set
---------------------------------------------------------------------------

---@class SetType
---@operator bor(SetType): SetType
---@operator band(SetType): SetType
---@operator sub(SetType): SetType
---@operator bxor(SetType): SetType
---@field add fun(self: SetType, value: any): SetType
---@field remove fun(self: SetType, value: any): SetType
---@field contains fun(self: SetType, value: any): boolean

---@class SetLib
---@field new fun(...: any): SetType
set = {}

---------------------------------------------------------------------------
-- unicode
---------------------------------------------------------------------------

---@class UnicodeLib
---@field char fun(...: integer): string
---@field len fun(s: string, i?: integer, j?: integer): integer|nil, integer|nil
---@field valid fun(s: string): integer|nil
---@field upper fun(s: string): string|nil, integer|nil
---@field lower fun(s: string): string|nil, integer|nil
---@field reverse fun(s: string): string|nil, integer|nil
---@field codepoint fun(s: string, i?: integer, j?: integer): integer|nil, integer|nil
---@field sub fun(s: string, i?: integer, j?: integer): string|nil, integer|nil
---@field offset fun(s: string, n: integer, i?: integer): integer|nil
---@field codes fun(s: string): fun(): (integer|nil, integer|nil)
---@field isalpha fun(codepoint: integer): boolean
---@field isspace fun(codepoint: integer): boolean
---@field isupper fun(codepoint: integer): boolean
---@field islower fun(codepoint: integer): boolean
unicode = {}

---------------------------------------------------------------------------
-- json
---------------------------------------------------------------------------

---@class JsonLib
---@field tojson fun(value: table): string
---@field loadjson fun(s: string): table|number|string|boolean|nil, string|nil
json = {}

---------------------------------------------------------------------------
-- net
---------------------------------------------------------------------------

---@enum HttpMethod
HttpMethod = { get = 1, post = 2, put = 3, patch = 4, delete = 5, head = 6 }

---@class NetResponse
---@field status integer
---@field body table|string

---@class NetLib
---@field request fun(url: string, method?: integer, headers?: table, body?: table|string, queryParams?: table): NetResponse|nil, string|nil
net = {}

---------------------------------------------------------------------------
-- time
---------------------------------------------------------------------------

---@enum Month
Month = {
  January = 1, February = 2, March = 3, April = 4, May = 5, June = 6,
  July = 7, August = 8, September = 9, October = 10, November = 11, December = 12,
}

---@enum Weekday
Weekday = {
  Sunday = 1, Monday = 2, Tuesday = 3, Wednesday = 4,
  Thursday = 5, Friday = 6, Saturday = 7,
}

---@class TimeLib
---@field clock fun(): number
---@field time fun(dateTable?: table): integer|nil, integer|nil
---@field date fun(format?: string, time?: integer): string|table|nil, integer|nil
---@field difftime fun(t2: integer, t1: integer): number
time = {}

---------------------------------------------------------------------------
-- process
---------------------------------------------------------------------------

---@class ProcessLib
---@field exit fun(code?: integer|boolean)
---@field getenv fun(name: string): string|nil
---@field execute fun(command?: string): boolean, string, integer
process = {}

---------------------------------------------------------------------------
-- Global registries
---------------------------------------------------------------------------

---@enum GCOption
GCOption = { collect = 1, count = 2, stop = 3, restart = 4 }

---@type fun(opt?: integer): number|integer
collectgarbage = nil

---@type table<string, string>
-- A registry of every custom "kind" name reported by type(): built-in
-- kinds (string/bool/nil/number/integer/table/nim function/lua function/
-- user data) plus every kuu-specific one (file/tempdir/set/enumeration/
-- thread). Writing an already-registered key raises at runtime.
TypeKind = {}

---@type fun(v: any): string
-- Like type(), but never affected by a __type metatable override.
rawtype = nil