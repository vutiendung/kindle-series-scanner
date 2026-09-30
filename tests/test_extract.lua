--[[
  test_extract.lua
  Test script to read AZW3/MOBI files, extract metadata, and print series info.
  Usage:
    lua tests/test_extract.lua ["path/to/book.azw3"]
--]]

package.path = "./?.lua;../?.lua;" .. package.path

local MobiReader = require("src.parsers.mobi_reader")
local MetadataParser = require("src.parsers.metadata_parser")
local SqliteHelper = require("src.db.sqlite_helper")
local Config = require("src.config")

local function test_file(filepath, db_path)
    print(string.rep("=", 70))
    print("Reading Book File: " .. filepath)
    print(string.rep("=", 70))

    local reader = MobiReader.new(filepath)
    local ok, err = reader:parse_header()
    if not ok then
        print(string.format("[ERROR] Failed to parse %s: %s", filepath, tostring(err)))
        return
    end

    local title = reader.metadata.title or reader.header.name or "Unknown Title"
    local author = reader.metadata.author or "Unknown Author"
    local asin = reader.metadata.asin or reader.metadata.calibre_id or "N/A"

    print("\n--- Book Information ---")
    print(string.format("  Title:     %s", title))
    print(string.format("  Author:    %s", author))
    print(string.format("  cdeKey:    %s", asin))
    print(string.format("  Publisher: %s", reader.metadata.publisher or "N/A"))
    print(string.format("  Language:  %s", reader.metadata.language or "N/A"))

    -- 1. Extract series from AZW3 file content
    print("\n--- AZW3 File Series Extraction ---")
    local s_name, s_idx = MetadataParser.extract_series(reader, title, filepath)

    if s_name then
        print(string.format("  [FOUND IN FILE] Series Name  : %s", s_name))
        print(string.format("                  Series Number: %s", tostring(s_idx or 1)))
    else
        print("  [FILE SCAN] No embedded series tag found inside raw AZW3 metadata.")
    end

    -- 2. Lookup in cc.db (if database is available)
    db_path = db_path or Config.get_db_path()
    local f = io.open(db_path, "r")
    if f then
        f:close()
        print("\n--- cc.db Database Linkage ---")
        local db = SqliteHelper.new(db_path)
        local cde_key = reader.metadata.asin or reader.metadata.calibre_id
        if cde_key then
            local rows = db:with_stripped_icu(function()
                local sql = string.format([[
SELECT s.d_seriesId, s.d_itemPosition, s.d_itemPositionLabel,
       COALESCE(e.p_titles_0_nominal, REPLACE(s.d_seriesId, 'urn:collection:1:asin-SL-', '')) as series_name
FROM Series s
LEFT JOIN Entries e ON e.p_cdeKey = REPLACE(s.d_seriesId, 'urn:collection:1:asin-', '')
WHERE s.d_itemCdeKey = %s;
]], db:escape(cde_key))
                return db:query_json(sql)
            end)
            if #rows > 0 then
                local r = rows[1]
                print(string.format("  [FOUND IN CC.DB] Series Name  : %s", r.series_name or "N/A"))
                print(string.format("                   Series Number: %s (Position: %s)", r.d_itemPositionLabel or "1", r.d_itemPosition or "0"))
                print(string.format("                   Series ID    : %s", r.d_seriesId or "N/A"))
                if not s_name then
                    s_name = r.series_name
                    s_idx = tonumber(r.d_itemPositionLabel) or 1
                end
            else
                print("  [CC.DB] Book is currently not assigned to any series in cc.db.")
            end
        end
    end

    -- Summary
    print("\n--- Final Series Detection Result ---")
    if s_name then
        print(string.format("  >>> Series Name   : %s", s_name))
        print(string.format("  >>> Series Number : %s", tostring(s_idx or 1)))
    else
        print("  >>> Standalone Book (No Series)")
    end
    print(string.rep("=", 70) .. "\n")

    reader:close()
end

local target_file = arg and arg[1]
if target_file then
    test_file(target_file)
else
    test_file("Thien Than Va Ac Quy - Dan Brown.azw3")
end
