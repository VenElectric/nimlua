local y = setmetatable({},{ __call = function() return "hello callable" end})

local t = setmetatable({}, {
  __tostring = y
})

print(tostring(t))