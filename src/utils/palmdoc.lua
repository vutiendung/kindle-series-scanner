--[[
  palmdoc.lua
  Pure Lua 5.1 implementation of PalmDOC decompression algorithm.
--]]

local PalmDoc = {}

function PalmDoc.decompress(data)
    if not data or #data == 0 then return "" end

    local out = {}
    local out_len = 0
    local n = #data
    local i = 1

    while i <= n do
        local b = string.byte(data, i)
        i = i + 1

        if b >= 1 and b <= 8 then
            -- Copy next `b` literal bytes
            local next_chunk = string.sub(data, i, i + b - 1)
            out_len = out_len + 1
            out[out_len] = next_chunk
            i = i + b
        elseif b <= 0x7F then
            -- Single literal (0x00 to 0x7F)
            out_len = out_len + 1
            out[out_len] = string.char(b)
        elseif b >= 0xC0 then
            -- Space + char (b ^ 0x80)
            out_len = out_len + 1
            out[out_len] = " " .. string.char(b - 0x80)
        elseif b >= 0x80 then
            -- Sliding dictionary match (2 bytes)
            if i <= n then
                local b2 = string.byte(data, i)
                i = i + 1

                local distance = math.floor(((b % 64) * 256 + b2) / 8)
                local length = (b2 % 8) + 3

                local flat = table.concat(out)
                local cur_total = #flat

                if distance > 0 and cur_total >= distance then
                    local match_start = cur_total - distance + 1
                    local matched = ""
                    for k = 0, length - 1 do
                        local src_idx = match_start + (k % distance)
                        matched = matched .. string.sub(flat, src_idx, src_idx)
                    end
                    out = { flat, matched }
                    out_len = 2
                end
            end
        end
    end

    return table.concat(out)
end

return PalmDoc
