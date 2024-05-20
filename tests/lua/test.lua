

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