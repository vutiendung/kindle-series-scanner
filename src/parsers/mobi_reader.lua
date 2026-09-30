--[[
  mobi_reader.lua
  Parser for MOBI, AZW, and AZW3 (KF8) files in pure Lua 5.1.
  Extracts PalmDB headers, Record 0 MOBI/EXTH metadata, and embedded text/OPF records.
--]]

local BinaryReader = require("src.utils.binary_reader")
local PalmDoc = require("src.utils.palmdoc")

local MobiReader = {}
MobiReader.__index = MobiReader

function MobiReader.new(filepath)
    local self = setmetatable({}, MobiReader)
    self.filepath = filepath
    self.file = nil
    self.header = {}
    self.records = {}
    self.exth = {}
    self.metadata = {}
    return self
end

function MobiReader:open()
    local f, err = io.open(self.filepath, "rb")
    if not f then
        return false, err
    end
    self.file = f
    return true
end

function MobiReader:close()
    if self.file then
        self.file:close()
        self.file = nil
    end
end

function MobiReader:read_bytes(offset, count)
    if not self.file then return "" end
    self.file:seek("set", offset)
    return self.file:read(count) or ""
end

function MobiReader:parse_header()
    local ok, err = self:open()
    if not ok then return false, err end

    -- Read PalmDB header (first 78 bytes)
    local raw_header = self:read_bytes(0, 78)
    if #raw_header < 78 then
        self:close()
        return false, "File too short for PalmDB header"
    end

    local palm_name = string.gsub(string.sub(raw_header, 1, 32), "%z.*$", "")
    local num_records = BinaryReader.get_uint16_be(raw_header, 77)

    self.header = {
        name = palm_name,
        num_records = num_records,
    }

    -- Read record offset table (num_records * 8 bytes starting at offset 78)
    local raw_table = self:read_bytes(78, num_records * 8)
    self.records = {}

    for i = 0, num_records - 1 do
        local pos = i * 8 + 1
        local offset = BinaryReader.get_uint32_be(raw_table, pos)
        local attr = BinaryReader.get_uint32_be(raw_table, pos + 4)
        table.insert(self.records, {
            index = i,
            offset = offset,
            attributes = attr,
        })
    end

    -- Parse Record 0
    if #self.records > 0 then
        local rec0_offset = self.records[1].offset
        local rec0_len = 4096
        if #self.records > 1 then
            rec0_len = self.records[2].offset - rec0_offset
        end
        local rec0_data = self:read_bytes(rec0_offset, rec0_len)
        self:parse_record0(rec0_data)
    end

    return true
end

function MobiReader:parse_record0(data)
    if #data < 32 then return end

    local compression = BinaryReader.get_uint16_be(data, 1)
    local text_records = BinaryReader.get_uint16_be(data, 9)
    local mobi_header_len = BinaryReader.get_uint32_be(data, 21) or 0

    self.metadata.compression = compression
    self.metadata.text_records = text_records
    self.metadata.mobi_header_len = mobi_header_len

    -- Check EXTH flag (offset 0x80 = 129 in 1-based index)
    local exth_flag = 0
    if #data >= 132 then
        exth_flag = BinaryReader.get_uint32_be(data, 129) or 0
    end

    -- EXTH header offset is 16 + mobi_header_len + 1 (1-based)
    local exth_pos = 16 + mobi_header_len + 1
    if exth_pos + 11 <= #data then
        local magic = string.sub(data, exth_pos, exth_pos + 3)
        if magic == "EXTH" then
            self:parse_exth(data, exth_pos)
        end
    end
end

function MobiReader:parse_exth(data, start_pos)
    local exth_len = BinaryReader.get_uint32_be(data, start_pos + 4)
    local exth_count = BinaryReader.get_uint32_be(data, start_pos + 8)

    self.exth = {}
    local pos = start_pos + 12

    for _ = 1, exth_count do
        if pos + 7 > #data then break end
        local rec_type = BinaryReader.get_uint32_be(data, pos)
        local rec_len = BinaryReader.get_uint32_be(data, pos + 4)
        if rec_len < 8 or (pos + rec_len - 1) > #data then break end

        local rec_data = string.sub(data, pos + 8, pos + rec_len - 1)
        self.exth[rec_type] = rec_data

        -- Map common EXTH tags
        if rec_type == 100 then
            self.metadata.author = rec_data
        elseif rec_type == 101 then
            self.metadata.publisher = rec_data
        elseif rec_type == 103 then
            self.metadata.description = rec_data
        elseif rec_type == 104 then
            self.metadata.isbn = rec_data
        elseif rec_type == 105 then
            self.metadata.subject = rec_data
        elseif rec_type == 108 then
            self.metadata.producer = rec_data
        elseif rec_type == 112 then
            self.metadata.source = rec_data
            local cid = string.match(rec_data, "^calibre:(.+)$")
            if cid then self.metadata.calibre_id = cid end
        elseif rec_type == 113 then
            self.metadata.asin = rec_data
        elseif rec_type == 121 then
            self.metadata.kf8_header_index = BinaryReader.get_uint32_be(rec_data, 1)
        elseif rec_type == 503 then
            self.metadata.title = rec_data
        elseif rec_type == 524 then
            self.metadata.language = rec_data
        end

        pos = pos + rec_len
    end
end

-- Read and decompress text records to search for embedded OPF/metadata (MOBI + KF8)
function MobiReader:extract_embedded_metadata(max_records)
    if not self.records or #self.records < 2 then return "" end

    local chunks = {}
    local is_palmdoc = (self.metadata.compression == 2)
    local num_records = #self.records

    -- 1. Search first text records
    local text_count = math.min(self.metadata.text_records or 1, max_records or 10)
    for i = 1, text_count do
        local rec_info = self.records[i + 1]
        local next_rec = self.records[i + 2]
        if rec_info then
            local rec_len = next_rec and (next_rec.offset - rec_info.offset) or 4096
            local raw = self:read_bytes(rec_info.offset, rec_len)
            if is_palmdoc then
                local decomp = PalmDoc.decompress(raw)
                table.insert(chunks, decomp)
            else
                table.insert(chunks, raw)
            end
        end
    end

    -- 2. If KF8 header exists, also inspect KF8 text and metadata records
    local kf8_idx = self.metadata.kf8_header_index
    if kf8_idx and kf8_idx > 0 and kf8_idx < num_records then
        for i = kf8_idx, math.min(kf8_idx + 10, num_records) do
            local rec_info = self.records[i + 1]
            local next_rec = self.records[i + 2]
            if rec_info then
                local rec_len = next_rec and (next_rec.offset - rec_info.offset) or 4096
                local raw = self:read_bytes(rec_info.offset, rec_len)
                if is_palmdoc then
                    local decomp = PalmDoc.decompress(raw)
                    table.insert(chunks, decomp)
                else
                    table.insert(chunks, raw)
                end
            end
        end
    end

    -- 3. Also check the last 15 records (where Calibre stores uncompressed content.opf and manifest)
    for i = math.max(1, num_records - 15), num_records do
        local rec_info = self.records[i]
        local next_rec = self.records[i + 1]
        if rec_info then
            local rec_len = next_rec and (next_rec.offset - rec_info.offset) or 32768
            local raw = self:read_bytes(rec_info.offset, rec_len)
            table.insert(chunks, raw)
        end
    end

    local full_text = table.concat(chunks, "\n")

    -- 4. Deep search: if series metadata still not found, scan all PalmDB records for OPF/XML tags
    if not string.find(full_text, "calibre:series", 1, true) and not string.find(full_text, "belongs-to-collection", 1, true) then
        for i = 1, num_records do
            local rec_info = self.records[i]
            local next_rec = self.records[i + 1]
            local rec_len = next_rec and (next_rec.offset - rec_info.offset) or 16384
            if rec_len > 20 and rec_len < 500000 then
                local raw = self:read_bytes(rec_info.offset, math.min(rec_len, 65536))
                if string.find(raw, "calibre:series", 1, true) or string.find(raw, "belongs-to-collection", 1, true) or string.find(raw, "<package", 1, true) then
                    table.insert(chunks, raw)
                    break
                end
            end
        end
        full_text = table.concat(chunks, "\n")
    end

    -- Extract Calibre UUID / identifier if present in OPF XML
    if not self.metadata.calibre_id then
        local cid = string.match(full_text, '<dc:identifier[^>]+id=["\']calibre_id["\'][^>]*>([^<]+)</dc:identifier>')
        if not cid then
            cid = string.match(full_text, '<dc:identifier[^>]+opf:scheme=["\']calibre["\'][^>]*>([^<]+)</dc:identifier>')
        end
        if not cid then
            cid = string.match(full_text, 'calibre:([0-9a-fA-F%-]{36})')
        end
        if cid and cid ~= "" then
            self.metadata.calibre_id = cid
        end
    end

    return full_text
end

function MobiReader:get_uuid()
    if self.metadata.calibre_id and self.metadata.calibre_id ~= "" then
        return self.metadata.calibre_id
    end
    self:extract_embedded_metadata(10)
    return self.metadata.calibre_id
end

return MobiReader
