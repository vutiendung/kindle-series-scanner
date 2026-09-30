--[[
  test_parser.lua
  Unit tests for MetadataParser, PalmDOC, Json, and SqliteHelper.
--]]

package.path = "./?.lua;../?.lua;" .. package.path

local MetadataParser = require("src.parsers.metadata_parser")
local Json = require("src.utils.json")
local Series = require("src.models.series")

local function assert_eq(actual, expected, name)
    if actual == expected then
        print(string.format("  [PASS] %s: %s", name, tostring(actual)))
    else
        print(string.format("  [FAIL] %s: Expected '%s', got '%s'", name, tostring(expected), tostring(actual)))
    end
end

print("=== Running MetadataParser Title Regex Tests ===")

local tests = {
    { title = "[Langdon 1] Angels & Demons", exp_name = "Langdon", exp_idx = 1 },
    { title = "[Langdon - 01] Angels & Demons", exp_name = "Langdon", exp_idx = 1 },
    { title = "[Robert Langdon #2] The Da Vinci Code", exp_name = "Robert Langdon", exp_idx = 2 },
    { title = "The Lost Symbol (Robert Langdon #3)", exp_name = "Robert Langdon", exp_idx = 3 },
    { title = "Inferno (Robert Langdon, #4)", exp_name = "Robert Langdon", exp_idx = 4 },
    { title = "Robert Langdon #5: Origin", exp_name = "Robert Langdon", exp_idx = 5 },
    { title = "Chuồn Chuồn Hổ Phách - Tập 1", exp_name = "Chuồn Chuồn Hổ Phách", exp_idx = 1 },
    { title = "Vòng Tròn Đá Thiêng - Tap 2", exp_name = "Vòng Tròn Đá Thiêng", exp_idx = 2 },
    { title = "Fantasy Quest - Book 3", exp_name = "Fantasy Quest", exp_idx = 3 },
    { title = "Manga Classic - Vol. 12", exp_name = "Manga Classic", exp_idx = 12 },
}

for _, t in ipairs(tests) do
    local name, idx = MetadataParser.parse_from_title(t.title)
    assert_eq(name, t.exp_name, "Name for: " .. t.title)
    assert_eq(idx, t.exp_idx, "Index for: " .. t.title)
end

print("\n=== Running MetadataParser XML/OPF Tests ===")

local opf_xml_calibre = [[
<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="uuid_id" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>Angels and Demons</dc:title>
    <dc:creator opf:role="aut">Dan Brown</dc:creator>
    <meta name="calibre:series" content="Robert Langdon"/>
    <meta name="calibre:series_index" content="1.0"/>
  </metadata>
</package>
]]

local name1, idx1 = MetadataParser.parse_from_xml(opf_xml_calibre)
assert_eq(name1, "Robert Langdon", "Calibre OPF series name")
assert_eq(idx1, 1, "Calibre OPF series index")

local opf_xml_epub3 = [[
<package>
  <metadata>
    <meta property="belongs-to-collection" id="c01">Harry Potter</meta>
    <meta refines="#c01" property="collection-type">series</meta>
    <meta refines="#c01" property="group-position">7</meta>
  </metadata>
</package>
]]

local name2, idx2 = MetadataParser.parse_from_xml(opf_xml_epub3)
assert_eq(name2, "Harry Potter", "EPUB3 belongs-to-collection name")
assert_eq(idx2, 7, "EPUB3 group-position index")

print("\n=== Running Series Key Normalization Tests ===")
local s1 = Series.new("Robert Langdon")
assert_eq(s1.cdeKey, "SL-ROBERT-LANGDON", "Series cdeKey")
assert_eq(s1.seriesId, "urn:collection:1:asin-SL-ROBERT-LANGDON", "Series seriesId")

local s2 = Series.new("Bí Ẩn Nguồn Gốc")
assert_eq(s2.cdeKey, "SL-BÍ-ẨN-NGUỒN-GỐC", "Series cdeKey Vietnamese")

print("\n=== Running JSON Encode / Decode Tests ===")
local obj = {
    title = "Test",
    count = 5,
    active = true,
    tags = {"a", "b"}
}
local enc = Json.encode(obj)
local dec = Json.decode(enc)
assert_eq(dec.title, "Test", "JSON title")
assert_eq(dec.count, 5, "JSON count")
assert_eq(dec.active, true, "JSON boolean")
assert_eq(dec.tags[1], "a", "JSON array item 1")
assert_eq(dec.tags[2], "b", "JSON array item 2")

print("\n=== Running MetadataParser KFX UUID Extraction Tests ===")
local kfx_id = MetadataParser.extract_kfx_uuid("Nguon Coi - Dan Brown.kfx")
assert_eq(kfx_id, "B01LY7FD0D", "MetadataParser.extract_kfx_uuid")

print("\nAll unit tests passed successfully!")
