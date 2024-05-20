local function hello()
    return 1 + 1
end

function TestFunc1()
    return
end

function withManyArgs(a,b,c,def,zxy)

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