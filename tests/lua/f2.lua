-- global function

function GFunc()
    local x = 0
    return x
end

local function newStep()
    return setmetatable({},mt)
end

function LuaBuild:addStep()
    table.insert(steps,self)
end

function LuaBuild:addLibraryDir(libdir)
    table.insert(self.library_args, libdir)
end

function withMultArgs(a,b,c,def)
    do
        print(a)
        print(b) 
        print(c)
        print(def)
    end
end