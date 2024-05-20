local x = true and false

while true do
    if true then
        break
    end
end

do
    print("Hello World")
end

if true then
    print("true")
elseif false then
    print("false")
end

for x=1,10 do
    print(x)
end

local none = nil

local abc = false
local xyz = false

while abc == false do ::continue::
    while xyz == false do
        goto continue
    end
end

local isNot = not true

local isOr = 1 or 0

local function varArgs(...)
    print(arg)
end

local t = {1,2,3}

for x in pairs(t) do
    print(x)
end

local concatString = "Hello " .. "World"

local le = 5 <= 7
local less = 5 < 10
local ge = 7 >= 5
local greater = 7 > 5
local eqeq = 5 == 5
local ne = 5 ~= 6

repeat
    line = io.read()
    -- should we handle empty strings?
  until line ~= ""
  print(line)