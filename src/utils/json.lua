--[[
  json.lua
  Lightweight JSON encoder/decoder in pure Lua 5.1
--]]

local Json = {}

local function escape_str(s)
    local in_char  = {'\\', '"', '/', '\b', '\f', '\n', '\r', '\t'}
    local out_char = {'\\\\', '\\"', '\\/', '\\b', '\\f', '\\n', '\\r', '\\t'}
    for i, c in ipairs(in_char) do
        s = string.gsub(s, c, out_char[i])
    end
    return s
end

local function is_array(t)
    if type(t) ~= "table" then return false end
    local max = 0
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
            return false
        end
        if k > max then max = k end
        count = count + 1
    end
    return max == count
end

function Json.encode(val)
    local t = type(val)
    if val == nil then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        return tostring(val)
    elseif t == "string" then
        return '"' .. escape_str(val) .. '"'
    elseif t == "table" then
        if is_array(val) then
            local items = {}
            for i, v in ipairs(val) do
                table.insert(items, Json.encode(v))
            end
            return "[" .. table.concat(items, ",") .. "]"
        else
            local items = {}
            for k, v in pairs(val) do
                if type(k) == "string" or type(k) == "number" then
                    table.insert(items, '"' .. escape_str(tostring(k)) .. '":' .. Json.encode(v))
                end
            end
            return "{" .. table.concat(items, ",") .. "}"
        end
    else
        return "null"
    end
end

-- Minimal JSON decoder
function Json.decode(str)
    if not str or str == "" then return nil end

    local pos = 1
    local len = #str

    local function skip_whitespace()
        while pos <= len do
            local c = string.sub(str, pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            else
                break
            end
        end
    end

    local parse_value -- forward declaration

    local function parse_string()
        pos = pos + 1 -- skip opening quote
        local start_pos = pos
        local result = {}
        while pos <= len do
            local c = string.sub(str, pos, pos)
            if c == '"' then
                table.insert(result, string.sub(str, start_pos, pos - 1))
                pos = pos + 1
                return table.concat(result)
            elseif c == '\\' then
                table.insert(result, string.sub(str, start_pos, pos - 1))
                pos = pos + 1
                local esc = string.sub(str, pos, pos)
                if esc == '"' or esc == '\\' or esc == '/' then
                    table.insert(result, esc)
                elseif esc == 'b' then table.insert(result, '\b')
                elseif esc == 'f' then table.insert(result, '\f')
                elseif esc == 'n' then table.insert(result, '\n')
                elseif esc == 'r' then table.insert(result, '\r')
                elseif esc == 't' then table.insert(result, '\t')
                elseif esc == 'u' then
                    -- unicode escape \uXXXX
                    local hex = string.sub(str, pos + 1, pos + 4)
                    local code = tonumber(hex, 16)
                    if code then
                        if code < 0x80 then
                            table.insert(result, string.char(code))
                        elseif code < 0x800 then
                            table.insert(result, string.char(
                                0xC0 + math.floor(code / 0x40),
                                0x80 + (code % 0x40)
                            ))
                        else
                            table.insert(result, string.char(
                                0xE0 + math.floor(code / 0x1000),
                                0x80 + (math.floor(code / 0x40) % 0x40),
                                0x80 + (code % 0x40)
                            ))
                        end
                    end
                    pos = pos + 4
                end
                pos = pos + 1
                start_pos = pos
            else
                pos = pos + 1
            end
        end
        return table.concat(result)
    end

    local function parse_number()
        local match = string.match(str, "^[%-%+]?[%d%.]+[eE]?[%-%+]?%d*", pos)
        if match then
            pos = pos + #match
            return tonumber(match)
        end
        return nil
    end

    local function parse_array()
        pos = pos + 1 -- skip '['
        local arr = {}
        skip_whitespace()
        if string.sub(str, pos, pos) == ']' then
            pos = pos + 1
            return arr
        end
        while pos <= len do
            local val = parse_value()
            table.insert(arr, val)
            skip_whitespace()
            local c = string.sub(str, pos, pos)
            if c == ']' then
                pos = pos + 1
                return arr
            elseif c == ',' then
                pos = pos + 1
            else
                break
            end
        end
        return arr
    end

    local function parse_object()
        pos = pos + 1 -- skip '{'
        local obj = {}
        skip_whitespace()
        if string.sub(str, pos, pos) == '}' then
            pos = pos + 1
            return obj
        end
        while pos <= len do
            skip_whitespace()
            if string.sub(str, pos, pos) ~= '"' then break end
            local key = parse_string()
            skip_whitespace()
            if string.sub(str, pos, pos) == ':' then
                pos = pos + 1
            end
            local val = parse_value()
            obj[key] = val
            skip_whitespace()
            local c = string.sub(str, pos, pos)
            if c == '}' then
                pos = pos + 1
                return obj
            elseif c == ',' then
                pos = pos + 1
            else
                break
            end
        end
        return obj
    end

    parse_value = function()
        skip_whitespace()
        local c = string.sub(str, pos, pos)
        if c == '"' then
            return parse_string()
        elseif c == '{' then
            return parse_object()
        elseif c == '[' then
            return parse_array()
        elseif c == 't' and string.sub(str, pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif c == 'f' and string.sub(str, pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif c == 'n' and string.sub(str, pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            return parse_number()
        end
    end

    return parse_value()
end

return Json
