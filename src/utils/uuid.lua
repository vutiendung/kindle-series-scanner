--[[
  uuid.lua
  UUID v4 generator for Lua 5.1 / Kindle environment.
--]]

local Uuid = {}

-- Try reading from /proc/sys/kernel/random/uuid (standard on Kindle Linux)
function Uuid.generate()
    local f = io.open("/proc/sys/kernel/random/uuid", "r")
    if f then
        local id = f:read("*l")
        f:close()
        if id and #id >= 32 then
            return string.lower(string.gsub(id, "%s+", ""))
        end
    end

    -- Fallback to pure Lua generation
    math.randomseed(os.time() + (os.clock() * 1000000))
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format("%x", v)
    end)
end

return Uuid
