--[[
  metadata_parser.lua
  Extracts series name and series index using multiple detection strategies:
  1. Calibre OPF metadata embedded in KF8 / AZW3
  2. Calibre Description / HTML tags
  3. Filename and Title patterns (Calibre plugboards, [Series #] Title, etc.)
--]]

local MetadataParser = {}

local function clean_string(str)
    if not str then return nil end
    -- Remove HTML tags
    str = string.gsub(str, "<[^>]+>", "")
    -- Trim leading and trailing whitespace
    str = string.gsub(str, "^%s+", "")
    str = string.gsub(str, "%s+$", "")
    return str
end

function MetadataParser.parse_from_xml(text)
    if not text or text == "" then return nil, nil end

    local series_name = nil
    local series_index = nil

    -- 1. Check <meta name="calibre:series" content="..." />
    local s = string.match(text, '<meta[^>]+name=["\']calibre:series["\'][^>]+content=["\']([^"\']+)["\']')
    if not s then
        s = string.match(text, '<meta[^>]+content=["\']([^"\']+)["\'][^>]+name=["\']calibre:series["\']')
    end
    if s and s ~= "" then
        series_name = s
    end

    -- Check <meta name="calibre:series_index" content="..." />
    local idx = string.match(text, '<meta[^>]+name=["\']calibre:series_index["\'][^>]+content=["\']([^"\']+)["\']')
    if not idx then
        idx = string.match(text, '<meta[^>]+content=["\']([^"\']+)["\'][^>]+name=["\']calibre:series_index["\']')
    end
    if idx and idx ~= "" then
        series_index = tonumber(idx)
    end

    -- 2. Check EPUB 3 belongs-to-collection
    if not series_name then
        local coll = string.match(text, '<meta[^>]+property=["\']belongs%-to%-collection["\'][^>]*>([^<]+)</meta>')
        if coll and coll ~= "" then
            series_name = coll
            local gpos = string.match(text, '<meta[^>]+property=["\']group%-position["\'][^>]*>([%d%.]+)</meta>')
            if gpos then
                series_index = tonumber(gpos)
            end
        end
    end

    -- 3. Check generic <meta name="series" content="..." />
    if not series_name then
        local gs = string.match(text, '<meta[^>]+name=["\']series["\'][^>]+content=["\']([^"\']+)["\']')
        if gs and gs ~= "" then
            series_name = gs
            local gidx = string.match(text, '<meta[^>]+name=["\']series_index["\'][^>]+content=["\']([^"\']+)["\']')
            if gidx then
                series_index = tonumber(gidx)
            end
        end
    end

    return clean_string(series_name), series_index
end

-- Fallback regex parser for titles or filenames
function MetadataParser.parse_from_title(title)
    if not title or title == "" then return nil, nil end

    local name, idx

    -- Pattern 1: "[Series Name - 01] Actual Title" or "[Series Name #01] Actual Title"
    name, idx = string.match(title, "^%[([^%]]+)%s*[-#]%s*([%d%.]+)%]")
    if name and idx then
        return clean_string(name), tonumber(idx)
    end

    -- Pattern 2: "[Series Name 01] Actual Title" or "[Series Name 1] Actual Title"
    name, idx = string.match(title, "^%[([^%]]-)%s+([%d%.]+)%]")
    if name and idx then
        return clean_string(name), tonumber(idx)
    end

    -- Pattern 3: "Actual Title (Series Name #1)" or "Actual Title (Series Name, #1)"
    name, idx = string.match(title, "%(([^%)]-)%s*[,#]%s*#?([%d%.]+)%)$")
    if name and idx then
        return clean_string(name), tonumber(idx)
    end

    -- Pattern 4: "Series Name #1 - Actual Title" or "Series Name #01: Actual Title"
    name, idx = string.match(title, "^(.-)%s*#([%d%.]+)%s*[:-]")
    if name and idx then
        return clean_string(name), tonumber(idx)
    end

    -- Pattern 5: "Series Name - Tap 1" or "Series Name - Tập 1" or "Series Name - TẬP 1"
    name, idx = string.match(title, "^(.-)%s*-%s*[Tt][Aa][Pp]%s*([%d%.]+)")
    if not name then
        name, idx = string.match(title, "^(.-)%s*-%s*[Tt]ập%s*([%d%.]+)")
    end
    if not name then
        name, idx = string.match(title, "^(.-)%s*-%s*[Tt]ẬP%s*([%d%.]+)")
    end
    if name and idx then
        return clean_string(name), tonumber(idx)
    end

    -- Pattern 6: "Series Name - Book 1"
    name, idx = string.match(title, "^(.-)%s*-%s*[Bb][Oo][Oo][Kk]%s*([%d%.]+)")
    if name and idx then
        return clean_string(name), tonumber(idx)
    end

    -- Pattern 7: "Series Name - Vol. 1" or "Series Name - Volume 1"
    name, idx = string.match(title, "^(.-)%s*-%s*[Vv][Oo][Ll]%.?%s*([%d%.]+)")
    if not name then
        name, idx = string.match(title, "^(.-)%s*-%s*[Vv][Oo][Ll][Uu][Mm][Ee]%s*([%d%.]+)")
    end
    if name and idx then
        return clean_string(name), tonumber(idx)
    end

    return nil, nil
end

-- Master parsing function
function MetadataParser.extract_series(mobi_reader, fallback_title, fallback_filename)
    -- 1. Try embedded XML / OPF in text records
    local embedded_text = mobi_reader:extract_embedded_metadata(6)
    local s_name, s_idx = MetadataParser.parse_from_xml(embedded_text)
    if s_name then
        return s_name, s_idx or 1
    end

    -- 2. Try EXTH 103 (Description / Comments) for series tags
    if mobi_reader.metadata.description then
        s_name, s_idx = MetadataParser.parse_from_xml(mobi_reader.metadata.description)
        if s_name then
            return s_name, s_idx or 1
        end
    end

    -- 3. Try EXTH 503 (Title) or Record 0 Title
    local title = mobi_reader.metadata.title or fallback_title
    if title then
        s_name, s_idx = MetadataParser.parse_from_title(title)
        if s_name then
            return s_name, s_idx or 1
        end
    end

    -- 4. Try Filename (without path and extension)
    if fallback_filename then
        local base = string.match(fallback_filename, "([^/\\]+)%.%w+$") or fallback_filename
        s_name, s_idx = MetadataParser.parse_from_title(base)
        if s_name then
            return s_name, s_idx or 1
        end
    end

    return nil, nil
end

return MetadataParser
