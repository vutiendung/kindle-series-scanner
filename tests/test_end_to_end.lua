--[[
  test_end_to_end.lua
  End-to-end test verifying backup, series scanning, and cc.db updating.
--]]

package.path = "./?.lua;../?.lua;" .. package.path

local SqliteHelper = require("src.db.sqlite_helper")
local Logger = require("src.utils.logger")
local Series = require("src.models.series")
local Book = require("src.models.book")

local logger = Logger.new({ verbose = true })
local db_path = "test_cc.db"
local backup_dir = "./test_backup"

-- Copy cc.db to test_cc.db for testing
os.execute(string.format("cp %q %q", "cc.db", db_path))

print("=== 1. Testing Database Backup ===")
local db_helper = SqliteHelper.new(db_path, logger)
local ok, b_path = db_helper:backup_db(backup_dir)
assert(ok, "Backup failed!")
print("Backup created at: " .. b_path)

print("\n=== 2. Testing Series Model and Upsert ===")
local s = Series.new("Robert Langdon")
local b1 = Book.new({
    uuid = "test-uuid-1",
    cdeKey = "2ca9baae-ce13-4611-b3cd-0e1b86be3e8c",
    title = "Thiên Thần Và Ác Quỷ",
    author = "Dan Brown",
    thumbnail = "/mnt/us/system/thumbnails/test.jpg",
    seriesName = "Robert Langdon",
    seriesIndex = 1
})
s:add_book(b1, 1)

local b2 = Book.new({
    uuid = "test-uuid-2",
    cdeKey = "0e931157-f7f2-4aee-8a03-f7e19490af59",
    title = "Mật Mã Da Vinci",
    author = "Dan Brown",
    thumbnail = "/mnt/us/system/thumbnails/test.jpg",
    seriesName = "Robert Langdon",
    seriesIndex = 2
})
s:add_book(b2, 2)

local upsert_ok, err = db_helper:upsert_series(s)
assert(upsert_ok, "Upsert series failed: " .. tostring(err))
print("Series upserted successfully!")

print("\n=== 3. Verifying Series Entries in Database ===")
local rows = db_helper:query_json("SELECT * FROM Series WHERE d_seriesId = 'urn:collection:1:asin-SL-ROBERT-LANGDON' ORDER BY d_itemPosition;")
print(string.format("Found %d rows in Series table for SL-ROBERT-LANGDON:", #rows))
for _, r in ipairs(rows) do
    print(string.format("  Position %s (label=%s): cdeKey=%s", r.d_itemPosition, r.d_itemPositionLabel, r.d_itemCdeKey))
end

local series_entry = db_helper:query_json("SELECT p_cdeKey, p_titles_0_nominal, p_memberCount, p_type FROM Entries WHERE p_cdeKey = 'SL-ROBERT-LANGDON';")
assert(#series_entry > 0, "Series Entry not found in Entries table!")
print("Series entry in Entries table:")
print(string.format("  cdeKey: %s, Title: %s, Members: %s, Type: %s",
    series_entry[1].p_cdeKey,
    series_entry[1].p_titles_0_nominal,
    series_entry[1].p_memberCount,
    series_entry[1].p_type
))

print("\n=== 4. Testing Database Restore ===")
local rest_ok, r_path = db_helper:restore_db(backup_dir)
assert(rest_ok, "Restore failed!")
print("Restored from: " .. r_path)

-- Clean up test backup
os.execute("rm -rf " .. backup_dir .. " test_cc.db")
print("\nAll end-to-end tests passed successfully!")
