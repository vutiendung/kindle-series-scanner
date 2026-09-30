--[[
  sqlite_helper.lua
  SQLite database helper for reading and updating Kindle cc.db.
  Executes queries via the sqlite3 CLI binary with support for ICU collation pragmas.
--]]

local Json = require("src.utils.json")
local Uuid = require("src.utils.uuid")
local Book = require("src.models.book")

local SqliteHelper = {}
SqliteHelper.__index = SqliteHelper

function SqliteHelper.new(db_path, logger)
    local self = setmetatable({}, SqliteHelper)
    self.db_path = db_path
    self.logger = logger
    return self
end

function SqliteHelper:escape(val)
    if val == nil then return "NULL" end
    local s = tostring(val)
    s = string.gsub(s, "'", "''")
    return "'" .. s .. "'"
end

function SqliteHelper:_get_tmp_path()
    self._query_counter = (self._query_counter or 0) + 1
    return string.format("/tmp/kss_q_%d_%d_%d.sql", os.time(), math.random(10000, 99999), self._query_counter)
end

function SqliteHelper:exec(sql)
    -- Write SQL to a unique temporary script file with busy_timeout configured
    local tmp_path = self:_get_tmp_path()
    local f = io.open(tmp_path, "w")
    if not f then
        return false, "Failed to create temp SQL file"
    end
    f:write("PRAGMA busy_timeout = 15000;\n" .. sql .. "\n")
    f:close()

    local cmd = string.format("sqlite3 -cmd \".timeout 15000\" %q < %q 2>&1", self.db_path, tmp_path)
    local handle = io.popen(cmd)
    local output = handle:read("*a")
    local success = handle:close()
    os.remove(tmp_path)

    -- Clean harmless PRAGMA timeout echo from output
    local clean_output = string.gsub(output or "", "^%s*15000%s*", "")
    clean_output = string.gsub(clean_output, "^%s+", "")
    clean_output = string.gsub(clean_output, "%s+$", "")

    if self.logger and clean_output ~= "" then
        self.logger:debug("SQLite Output: " .. clean_output)
    end

    return success, output
end

function SqliteHelper:query_json(sql)
    local tmp_path = self:_get_tmp_path()
    local f = io.open(tmp_path, "w")
    if not f then return {} end
    f:write("PRAGMA busy_timeout = 15000;\n.mode line\n" .. sql .. "\n")
    f:close()

    local cmd = string.format("sqlite3 -cmd \".timeout 15000\" %q < %q", self.db_path, tmp_path)
    local handle = io.popen(cmd)
    local raw = handle:read("*a")
    handle:close()
    os.remove(tmp_path)

    local rows = {}
    local current_row = nil

    for line in string.gmatch(raw .. "\n", "([^\r\n]*)\r?\n") do
        if line == "" then
            if current_row and next(current_row) ~= nil then
                table.insert(rows, current_row)
                current_row = nil
            end
        else
            local key, val = string.match(line, "^%s*([^=]+)%s*=%s*(.*)$")
            if key then
                key = string.gsub(key, "^%s+", "")
                key = string.gsub(key, "%s+$", "")
                if not current_row then current_row = {} end
                current_row[key] = val
            end
        end
    end

    if current_row and next(current_row) ~= nil then
        table.insert(rows, current_row)
    end

    return rows
end

-- Strip ICU collation by directly patching cc.db binary in-place
function SqliteHelper:strip_icu()
    local f = io.open(self.db_path, "rb")
    if not f then return false, "Cannot open db file" end
    local content = f:read("*a")
    f:close()

    local offsets = {}
    local pos = 1
    while true do
        local s, e = string.find(content, "COLLATE icu", pos, true)
        if not s then break end
        table.insert(offsets, s - 1)
        pos = e + 1
    end

    if #offsets == 0 then
        return true
    end

    self._icu_offsets = offsets

    local fmod = io.open(self.db_path, "r+b")
    if not fmod then return false, "Cannot open db file for patching" end
    for _, o in ipairs(offsets) do
        fmod:seek("set", o)
        fmod:write("           ") -- 11 spaces
    end
    fmod:close()
    return true
end

-- Restore ICU collation by writing back COLLATE icu to recorded binary offsets
function SqliteHelper:restore_icu()
    if not self._icu_offsets or #self._icu_offsets == 0 then
        return true
    end

    local fmod = io.open(self.db_path, "r+b")
    if not fmod then return false, "Cannot open db file for restoration" end
    for _, o in ipairs(self._icu_offsets) do
        fmod:seek("set", o)
        fmod:write("COLLATE icu")
    end
    fmod:close()
    self._icu_offsets = nil
    return true
end

-- Safely execute a block with ICU stripped and guaranteed restoration
function SqliteHelper:with_stripped_icu(callback)
    self:strip_icu()
    local ok, res, err = pcall(callback)
    self:restore_icu()
    if not ok then
        error(res)
    end
    return res, err
end

-- Fetch all books from cc.db
function SqliteHelper:get_all_books()
    return self:with_stripped_icu(function()
        local sql = [[
SELECT p_uuid, p_cdeKey, p_cdeType, p_location, p_titles_0_nominal,
       p_credits_0_name_collation, p_thumbnail, j_credits, j_titles, p_seriesState
FROM Entries
WHERE p_type = 'Entry:Item' AND p_location IS NOT NULL
ORDER BY p_titles_0_nominal;
]]
        local rows = self:query_json(sql)
        local books = {}
        for _, r in ipairs(rows) do
            table.insert(books, Book.new({
                uuid = r.p_uuid,
                cdeKey = r.p_cdeKey,
                cdeType = r.p_cdeType or "EBOK",
                location = r.p_location,
                title = r.p_titles_0_nominal,
                author = r.p_credits_0_name_collation,
                thumbnail = r.p_thumbnail,
                j_credits = r.j_credits,
                j_titles = r.j_titles,
                seriesState = tonumber(r.p_seriesState) or 1,
            }))
        end
        return books
    end)
end

-- Fetch all existing series and their member books from cc.db
function SqliteHelper:get_existing_series_map()
    return self:with_stripped_icu(function()
        local sql = [[
SELECT s.d_seriesId, s.d_itemCdeKey, s.d_itemPosition, s.d_itemPositionLabel,
       COALESCE(se.p_titles_0_nominal, REPLACE(s.d_seriesId, 'urn:collection:1:asin-SL-', '')) as series_name,
       e.p_uuid, e.p_titles_0_nominal as book_title, e.p_credits_0_name_collation as book_author,
       e.p_thumbnail, e.p_location, e.j_credits, e.j_titles, e.p_seriesState
FROM Series s
JOIN Entries e ON s.d_itemCdeKey = e.p_cdeKey AND e.p_type = 'Entry:Item'
LEFT JOIN Entries se ON se.p_cdeKey = REPLACE(s.d_seriesId, 'urn:collection:1:asin-', '') AND se.p_type = 'Entry:Item:Series'
ORDER BY s.d_seriesId, s.d_itemPosition;
]]
        local rows = self:query_json(sql)
        local Series = require("src.models.series")
        local series_map = {}

        for _, r in ipairs(rows) do
            local s_name = r.series_name or "Unknown Series"
            local s_id = r.d_seriesId
            local s_key = string.match(s_id, "urn:collection:1:asin%-(.+)$") or Series.normalize_key(s_name)

            if not series_map[s_name] then
                local s_obj = Series.new(s_name, s_key)
                series_map[s_name] = s_obj
            end

            local b = Book.new({
                uuid = r.p_uuid,
                cdeKey = r.d_itemCdeKey,
                cdeType = "EBOK",
                location = r.p_location,
                title = r.book_title,
                author = r.book_author,
                thumbnail = r.p_thumbnail,
                j_credits = r.j_credits,
                j_titles = r.j_titles,
                seriesName = s_name,
                seriesIndex = tonumber(r.d_itemPositionLabel) or (tonumber(r.d_itemPosition) and (tonumber(r.d_itemPosition) + 1)) or 1,
            })

            series_map[s_name]:add_book(b, b.seriesIndex)
        end

        return series_map
    end)
end

-- Generate SQL statements for a single series
function SqliteHelper:_generate_series_sql(series_obj)
    local books = series_obj.books
    if #books == 0 then return {} end

    local series_id = series_obj.seriesId
    local series_cde_key = series_obj.cdeKey
    local series_name = series_obj.name
    local member_count = #books

    local first_book = series_obj:get_first_book()
    local credits_json = first_book.j_credits or "[]"
    local credit_collation = first_book.author or ""
    local credit_pron = credit_collation
    local thumbnail = first_book.thumbnail or ""

    local titles_json = Json.encode({{
        display = series_name,
        collation = series_name,
        language = "en",
        pronunciation = series_name,
    }})

    local meta_words = string.lower(series_name) .. "\239\191\188" .. string.lower(series_name)
    if credit_pron and credit_pron ~= "" then
        meta_words = meta_words .. "\239\191\188" .. string.lower(credit_pron) .. "\239\191\188" .. string.lower(credit_pron)
    end

    local sql_statements = {}

    -- 1. Insert or Replace Series member rows
    for i, book in ipairs(books) do
        local position = (tonumber(book.seriesIndex) or i) - 1
        if position < 0 then position = i - 1 end
        local position_label = tostring(book.seriesIndex or i)

        table.insert(sql_statements, string.format(
            "INSERT OR REPLACE INTO Series (d_seriesId, d_itemCdeKey, d_itemPosition, d_itemPositionLabel, d_itemType, d_seriesOrderType) VALUES (%s, %s, %f, %s, 'Entry:Item', 'ordered');",
            self:escape(series_id),
            self:escape(book.cdeKey),
            position,
            self:escape(position_label)
        ))

        -- Hide standalone book entry if in series (p_seriesState = 0)
        table.insert(sql_statements, string.format(
            "UPDATE Entries SET p_seriesState = 0 WHERE p_cdeKey = %s AND p_type = 'Entry:Item';",
            self:escape(book.cdeKey)
        ))
    end

    -- 2. Upsert Entry:Item:Series
    local current_time = os.time()
    local check_sql = string.format("SELECT p_uuid FROM Entries WHERE p_cdeKey = %s AND p_type = 'Entry:Item:Series';", self:escape(series_cde_key))
    local existing = self:query_json(check_sql)

    if #existing > 0 then
        table.insert(sql_statements, string.format([[
UPDATE Entries SET
    p_lastAccess = %d,
    p_modificationTime = %d,
    p_titles_0_nominal = %s,
    p_titles_0_collation = %s,
    p_titles_0_pronunciation = %s,
    j_titles = %s,
    p_credits_0_name_collation = %s,
    p_credits_0_name_pronunciation = %s,
    j_credits = %s,
    p_creditCount = %d,
    p_memberCount = %d,
    p_homeMemberCount = %d,
    p_virtualCollectionCount = %d,
    p_thumbnail = %s,
    p_metadataUnicodeWords = %s
WHERE p_cdeKey = %s AND p_type = 'Entry:Item:Series';
]],
            current_time,
            current_time,
            self:escape(series_name),
            self:escape(series_name),
            self:escape(series_name),
            self:escape(titles_json),
            self:escape(credit_collation),
            self:escape(credit_pron),
            self:escape(credits_json),
            (credits_json ~= "[]") and 1 or 0,
            member_count,
            member_count,
            member_count + 1,
            self:escape(thumbnail),
            self:escape(meta_words),
            self:escape(series_cde_key)
        ))
    else
        local entry_uuid = Uuid.generate()
        local display_objects = Json.encode({{ ref = "titles" }, { ref = "credits" }})
        table.insert(sql_statements, string.format([[
INSERT INTO Entries (
    p_uuid, p_type, p_cdeKey, p_cdeType, p_cdeGroup,
    p_lastAccess, p_modificationTime,
    p_titles_0_nominal, p_titles_0_collation, p_titles_0_pronunciation,
    j_titles, p_titleCount,
    p_credits_0_name_collation, p_credits_0_name_pronunciation,
    j_credits, p_creditCount,
    j_members, p_memberCount, p_homeMemberCount,
    p_mimeType, p_thumbnail,
    j_displayObjects, p_metadataUnicodeWords,
    p_isArchived, p_isVisibleInHome, p_isLatestItem,
    p_isUpdateAvailable, p_isTestData,
    p_seriesState, p_visibilityState, p_isProcessed,
    p_contentState, p_ownershipType, p_originType,
    p_contentIndexedState, p_noteIndexedState,
    p_collectionSyncCounter, p_collectionDataSetName,
    p_subType, j_languages, p_languageCount,
    p_virtualCollectionCount
) VALUES (
    %s, 'Entry:Item:Series', %s, 'series', %s,
    %d, %d,
    %s, %s, %s,
    %s, 1,
    %s, %s,
    %s, %d,
    '[]', %d, %d,
    'application/x-kindle-series', %s,
    %s, %s,
    1, 1, 1,
    0, 0,
    1, 1, 1,
    0, 0, -1,
    2147483647, 0,
    0, '0',
    0, '[]', 0,
    %d
);
]],
            self:escape(entry_uuid),
            self:escape(series_cde_key),
            self:escape(series_id),
            current_time,
            current_time,
            self:escape(series_name),
            self:escape(series_name),
            self:escape(series_name),
            self:escape(titles_json),
            self:escape(credit_collation),
            self:escape(credit_pron),
            self:escape(credits_json),
            (credits_json ~= "[]") and 1 or 0,
            member_count,
            member_count,
            self:escape(thumbnail),
            self:escape(display_objects),
            self:escape(meta_words),
            member_count + 1
        ))
    end

    return sql_statements
end

-- Upsert a single series into cc.db
function SqliteHelper:upsert_series(series_obj)
    local books = series_obj.books
    if #books == 0 then return false end

    return self:with_stripped_icu(function()
        local sql_statements = self:_generate_series_sql(series_obj)
        local batch_sql = table.concat(sql_statements, "\n")
        return self:exec(batch_sql)
    end)
end

-- Upsert all series in a single atomic transaction with 1 single ICU strip
function SqliteHelper:upsert_all_series(series_map)
    return self:with_stripped_icu(function()
        local all_sql = { "BEGIN TRANSACTION;" }

        for _, series_obj in pairs(series_map) do
            local statements = self:_generate_series_sql(series_obj)
            for _, stmt in ipairs(statements) do
                table.insert(all_sql, stmt)
            end
        end

        table.insert(all_sql, "COMMIT;")
        local batch_sql = table.concat(all_sql, "\n")
        return self:exec(batch_sql)
    end)
end

-- Backup cc.db to destination folder (e.g. /mnt/us/kindle_db_backup)
function SqliteHelper:backup_db(target_dir)
    target_dir = target_dir or "/mnt/us/kindle_db_backup"
    
    -- Create backup directory if not exists
    os.execute(string.format("mkdir -p %q", target_dir))

    local timestamp = os.date("%Y%m%d_%H%M%S")
    local backup_file = string.format("%s/cc_%s.db", target_dir, timestamp)
    local latest_file = string.format("%s/cc_latest.db", target_dir)

    -- Copy database file
    local cp_cmd = string.format("cp %q %q && cp %q %q", self.db_path, backup_file, self.db_path, latest_file)
    local ok = os.execute(cp_cmd)

    if self.logger then
        self.logger:info(string.format("Backup created at %s", backup_file))
    end

    return (ok == true or ok == 0), backup_file
end

-- Restore cc.db from a backup file or latest backup in folder
function SqliteHelper:restore_db(backup_path_or_dir)
    backup_path_or_dir = backup_path_or_dir or "/mnt/us/kindle_db_backup"
    local restore_src = backup_path_or_dir

    -- If directory provided, look for cc_latest.db
    local f = io.open(restore_src, "r")
    if not f or string.sub(restore_src, -3) ~= ".db" then
        restore_src = string.format("%s/cc_latest.db", backup_path_or_dir)
    else
        f:close()
    end

    local test_f = io.open(restore_src, "r")
    if not test_f then
        return false, string.format("Backup file not found at %s", restore_src)
    end
    test_f:close()

    local cp_cmd = string.format("cp %q %q", restore_src, self.db_path)
    local ok = os.execute(cp_cmd)

    if self.logger then
        self.logger:info(string.format("Database restored from %s to %s", restore_src, self.db_path))
    end

    return (ok == true or ok == 0), restore_src
end

-- Delete missing/orphaned book records from Entries and Series tables
function SqliteHelper:delete_books(books)
    if not books or #books == 0 then return true end

    return self:with_stripped_icu(function()
        local sql_statements = { "BEGIN TRANSACTION;" }
        for _, book in ipairs(books) do
            if self.logger then
                self.logger:info(string.format("  [ORPHAN CLEANUP] Removed missing book from database: '%s' (%s)", book.title or "Untitled", book.cdeKey or ""))
            end
            table.insert(sql_statements, string.format("DELETE FROM Entries WHERE p_cdeKey = %s AND p_type = 'Entry:Item';", self:escape(book.cdeKey)))
            table.insert(sql_statements, string.format("DELETE FROM Series WHERE d_itemCdeKey = %s;", self:escape(book.cdeKey)))
        end
        table.insert(sql_statements, "COMMIT;")
        local batch_sql = table.concat(sql_statements, "\n")
        return self:exec(batch_sql)
    end)
end

-- Cleanup empty series or orphaned series entries with no books
function SqliteHelper:cleanup_empty_series()
    return self:with_stripped_icu(function()
        -- 1. Find series entries in Entries table that have 0 books in Series table
        local find_empty_sql = [[
SELECT p_uuid, p_cdeKey, p_titles_0_nominal
FROM Entries
WHERE p_type = 'Entry:Item:Series'
  AND ('urn:collection:1:asin-' || p_cdeKey) NOT IN (
      SELECT DISTINCT s.d_seriesId
      FROM Series s
      JOIN Entries e ON s.d_itemCdeKey = e.p_cdeKey AND e.p_type = 'Entry:Item'
  );
]]
        local empty_series = self:query_json(find_empty_sql)
        local cleaned_count = #empty_series

        -- 2. Delete orphaned records in Series table where book no longer exists
        local sql_statements = {
            "DELETE FROM Series WHERE d_itemCdeKey NOT IN (SELECT p_cdeKey FROM Entries WHERE p_type = 'Entry:Item');",
        }

        for _, es in ipairs(empty_series) do
            if self.logger then
                self.logger:info(string.format("  [CLEANUP] Removing empty series: '%s' (cdeKey: %s)", es.p_titles_0_nominal or "Unknown", es.p_cdeKey or ""))
            end
            table.insert(sql_statements, string.format("DELETE FROM Entries WHERE p_cdeKey = %s AND p_type = 'Entry:Item:Series';", self:escape(es.p_cdeKey)))
            table.insert(sql_statements, string.format("DELETE FROM Series WHERE d_seriesId = %s;", self:escape("urn:collection:1:asin-" .. es.p_cdeKey)))
        end

        local batch_sql = table.concat(sql_statements, "\n")
        local ok, err = self:exec(batch_sql)
        return cleaned_count, err
    end)
end

-- Clean / Reset ALL series from database (restores all books to standalone)
function SqliteHelper:clean_all_series()
    return self:with_stripped_icu(function()
        local sql = [[
BEGIN TRANSACTION;
DELETE FROM Series;
DELETE FROM Entries WHERE p_type = 'Entry:Item:Series';
UPDATE Entries SET p_seriesState = 1 WHERE p_type = 'Entry:Item';
COMMIT;
]]
        return self:exec(sql)
    end)
end

return SqliteHelper
