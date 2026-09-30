--[[
  binary_reader.lua
  Pure Lua 5.1 binary unpacking utility for Big-Endian and Little-Endian types.
--]]

local BinaryReader = {}
BinaryReader.__index = BinaryReader

function BinaryReader.new(data)
    local self = setmetatable({}, BinaryReader)
    self.data = data or ""
    self.pos = 1
    self.len = #self.data
    return self
end

function BinaryReader:seek(pos)
    self.pos = pos
end

function BinaryReader:tell()
    return self.pos
end

function BinaryReader:length()
    return self.len
end

function BinaryReader:read_bytes(count)
    if self.pos > self.len then return "" end
    local sub = string.sub(self.data, self.pos, self.pos + count - 1)
    self.pos = self.pos + count
    return sub
end

function BinaryReader:read_uint8()
    if self.pos > self.len then return nil end
    local b = string.byte(self.data, self.pos)
    self.pos = self.pos + 1
    return b
end

function BinaryReader:read_uint16_be(offset)
    local pos = offset or self.pos
    if pos + 1 > self.len then return nil end
    local b1, b2 = string.byte(self.data, pos, pos + 1)
    if not offset then self.pos = pos + 2 end
    return b1 * 256 + b2
end

function BinaryReader:read_uint16_le(offset)
    local pos = offset or self.pos
    if pos + 1 > self.len then return nil end
    local b1, b2 = string.byte(self.data, pos, pos + 1)
    if not offset then self.pos = pos + 2 end
    return b2 * 256 + b1
end

function BinaryReader:read_uint32_be(offset)
    local pos = offset or self.pos
    if pos + 3 > self.len then return nil end
    local b1, b2, b3, b4 = string.byte(self.data, pos, pos + 3)
    if not offset then self.pos = pos + 4 end
    return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
end

function BinaryReader:read_uint32_le(offset)
    local pos = offset or self.pos
    if pos + 3 > self.len then return nil end
    local b1, b2, b3, b4 = string.byte(self.data, pos, pos + 3)
    if not offset then self.pos = pos + 4 end
    return b4 * 16777216 + b3 * 65536 + b2 * 256 + b1
end

function BinaryReader:read_cstring(max_len)
    local start_pos = self.pos
    local end_pos = start_pos
    local limit = max_len and (start_pos + max_len - 1) or self.len
    if limit > self.len then limit = self.len end

    while end_pos <= limit do
        if string.byte(self.data, end_pos) == 0 then
            break
        end
        end_pos = end_pos + 1
    end

    local result = string.sub(self.data, start_pos, end_pos - 1)
    self.pos = (max_len and (start_pos + max_len)) or (end_pos + 1)
    return result
end

-- Static helper functions
BinaryReader.get_uint16_be = function(str, pos)
    local b1, b2 = string.byte(str, pos, pos + 1)
    if not b1 or not b2 then return nil end
    return b1 * 256 + b2
end

BinaryReader.get_uint32_be = function(str, pos)
    local b1, b2, b3, b4 = string.byte(str, pos, pos + 3)
    if not b1 or not b2 or not b3 or not b4 then return nil end
    return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
end

return BinaryReader
