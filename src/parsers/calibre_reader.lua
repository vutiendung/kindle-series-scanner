--[[
  calibre_reader.lua
  Parses /mnt/us/metadata.calibre (Calibre on-device library cache JSON)
  to retrieve accurate series names and indices without modifying book files.
--]]

local Json = require("src.utils.json")

local CalibreReader = {}
CalibreReader.__index = CalibreReader

function CalibreReader.new(custom_path, logger)
    local self = setmetatable({}, CalibreReader)
    self.custom_path = custom_path
    self.logger = logger
    self.by_path = {}
    self.by_filename = {}
    self.by_title = {}
    self.by_uuid = {}
    self.loaded = false
    self.total_series_count = 0
    return self
end

function CalibreReader:find_file()
    local search_paths = {
        self.custom_path,
        "/mnt/us/metadata.calibre",
        "./metadata.calibre",
    }

    for _, p in ipairs(search_paths) do
        if p and p ~= "" then
            local f = io.open(p, "r")
            if f then
                f:close()
                if self.logger then
                    self.logger:info(string.format("Found metadata.calibre at: %s", p))
                end
                return p
            end
        end
    end

    -- Specifically search for metadata.calibre (ignore driveinfo.calibre)
    local handle = io.popen("find /mnt/us -maxdepth 2 -name 'metadata.calibre' 2>/dev/null")
    if handle then
        local found = handle:read("*l")
        handle:close()
        if found and found ~= "" then
            local f = io.open(found, "r")
            if f then
                f:close()
                if self.logger then
                    self.logger:info("Found metadata.calibre at: " .. found)
                end
                return found
            end
        end
    end

    return nil
end

function CalibreReader:load()
    local filepath = self:find_file()
    if not filepath then
        if self.logger then
            self.logger:warn("metadata.calibre not found at /mnt/us/metadata.calibre")
        end
        return false
    end

    local f = io.open(filepath, "r")
    if not f then
        if self.logger then
            self.logger:warn("Could not open " .. tostring(filepath))
        end
        return false
    end

    local content = f:read("*a")
    f:close()

    local ok, data = pcall(Json.decode, content)
    if not ok or type(data) ~= "table" then
        if self.logger then
            self.logger:warn("Could not parse metadata.calibre JSON: " .. tostring(data))
        end
        return false
    end

    self.total_series_count = 0
    for _, item in ipairs(data) do
        if item.series and item.series ~= "" then
            self.total_series_count = self.total_series_count + 1
            local series_info = {
                series = item.series,
                series_index = tonumber(item.series_index) or 1,
                title = item.title,
                uuid = item.uuid,
            }

            -- Index by full kindle path (/mnt/us/documents/...)
            if item.lpath then
                local full_path = "/mnt/us/" .. string.gsub(item.lpath, "^/+", "")
                self.by_path[full_path] = series_info
                self.by_path[item.lpath] = series_info

                local base = string.match(item.lpath, "([^/\\]+)$")
                if base then
                    self.by_filename[base] = series_info
                end
            end

            -- Index by title
            if item.title and item.title ~= "" then
                self.by_title[item.title] = series_info
                self.by_title[string.lower(item.title)] = series_info
            end

            -- Index by uuid and identifiers (asin, mobi-asin, etc.)
            if item.uuid and item.uuid ~= "" then
                self.by_uuid[item.uuid] = series_info
            end
            if item.identifiers and type(item.identifiers) == "table" then
                for _, id in pairs(item.identifiers) do
                    if id and id ~= "" then
                        self.by_uuid[tostring(id)] = series_info
                    end
                end
            end
        end
    end

    self.loaded = true
    if self.logger then
        self.logger:info(string.format("Loaded metadata.calibre from %s: found %d series books.", filepath, self.total_series_count))
    end
    return true
end

function CalibreReader:lookup_series(book)
    if not self.loaded then return nil, nil end
    if not book then return nil, nil end

    local match = nil

    -- 1. Lookup by UUID (extracted from file or cc.db)
    if book.uuid and book.uuid ~= "" then
        match = self.by_uuid[book.uuid]
    end
    if not match and book.cdeKey and book.cdeKey ~= "" then
        match = self.by_uuid[book.cdeKey]
    end

    -- 2. Lookup by location (/mnt/us/documents/...)
    if not match and book.location and book.location ~= "" then
        match = self.by_path[book.location]
        if not match then
            local base = string.match(book.location, "([^/\\]+)$")
            if base then
                match = self.by_filename[base]
            end
        end
    end

    -- 3. Lookup by title
    if not match and book.title and book.title ~= "" then
        match = self.by_title[book.title] or self.by_title[string.lower(book.title)]
    end

    if match and match.series and match.series ~= "" then
        return match.series, match.series_index
    end

    return nil, nil
end

return CalibreReader
