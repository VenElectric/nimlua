local LuaBuild = {
    CC = "gcc",
    include_args = {},
    library_args = {},
    link_args = {},
    order = {
        include_args = 1,
        library_args = 2,
        link_args = 3
    },
    output = "",
    main = "",
    command = ""
}

local mt = {__index = LuaBuild}

local flags = {
    include = "-I",
    library = "-L",
    link = "-l",
    output = "-o"
}

local steps = {}

local function newStep()
    return setmetatable({},mt)
end

function LuaBuild:addStep()
    table.insert(steps,self)
end

function LuaBuild:addMain(main)
    self.main = main
end

function LuaBuild:setOutputFile(out)
    self.output = out
end

local function formatArgs(t,flag) 
    local str = ""
    for k,v in ipairs(t) do
        str = string.format("%s %s%s",str,flag,v)
    end
    return str
end

local StrTableAccess = {
    link_args = function(link_args) return formatArgs(link_args,flags.link) end,
    library_args = function(library_args) return formatArgs(library_args,flags.library) end,
    include_args = function(include_args) return formatArgs(include_args,flags.include) end,
}

function LuaBuild:linkLibrary(lib)
    table.insert(self.link_args, lib)
end

function LuaBuild:addIncludeDir(dir)
    table.insert(self.include_args, dir)
end

function LuaBuild:addLibraryDir(libdir)
    table.insert(self.library_args, libdir)
end

function LuaBuild:changeCompiler(newCC)
    self.CC = newCC
end

function LuaBuild:getArgOrder()
    return setmetatable({}, { __index = self.order })
end

function LuaBuild:setArgOrder(newOrder)
    for k, v in pairs(newOrder) do
        self.order[k] = v
    end
end

function LuaBuild:getArgTableByOrder()
    local sortedOrder = {}
    for k, v in pairs(self.order) do
        sortedOrder[v] = k
    end
    return setmetatable({}, { __index = sortedOrder })
end

function LuaBuild:appendToCommand(value)
    if self.command:len() < 1 then
        self.command = string.format("%s",value)
    else
        self.command = string.format("%s %s",self.command,value)
    end
end

function LuaBuild:createCommand()
    local sorted = self:getArgTableByOrder()
    self:appendToCommand(self.CC)
    self:appendToCommand(self.main)
    if self.output:len() > 0 then
        self:appendToCommand(string.format("%s %s",flags.output,self.output))
    end
    for k, v in ipairs(sorted) do
        self:appendToCommand(StrTableAccess[v](self[v]))
    end
end

function LuaBuild:executeCommand()
    self:createCommand()
    print(self.command)
    os.execute(self.command)
end

return newStep
