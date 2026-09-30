--[[
  series_scanner.lua
  Service coordinating the scanning of cc.db and AZW3 files,
  extracting Calibre series metadata, and inserting collections into cc.db.
--]]

local Config = require("src.config")
local MobiReader = require("src.parsers.mobi_reader")
local MetadataParser = require("src.parsers.metadata_parser")
local CalibreReader = require("src.parsers.calibre_reader")
local Series = require("src.models.series")

local SeriesScanner = {}
SeriesScanner.__index = SeriesScanner

function SeriesScanner.new(db_helper, logger, opts)
    local self = setmetatable({}, SeriesScanner)
    self.db_helper = db_helper
    self.logger = logger
    self.opts = opts or {}
    self.backup_dir = self.opts.backup_dir or Config.BACKUP_DIR
    self.dry_run = self.opts.dry_run or false
    return self
end

-- Resolve book file location locally or on device
function SeriesScanner:resolve_filepath(location)
    if not location or location == "" then return nil end

    -- 1. Direct path check
    local f = io.open(location, "rb")
    if f then
        f:close()
        return location
    end

    -- 2. Local workspace / relative check
    local basename = string.match(location, "([^/\\]+)$")
    if basename then
        local local_path = basename
        f = io.open(local_path, "rb")
        if f then
            f:close()
            return local_path
        end
    end

    return nil
end

function SeriesScanner:scan_and_sync()
    self.logger:info("=== Starting Kindle Series Scanner ===")

    -- 1. Automatic Backup before any writes
    if not self.dry_run then
        self.logger:info("Creating database backup in " .. self.backup_dir)
        local ok, b_path = self.db_helper:backup_db(self.backup_dir)
        if ok then
            self.logger:info("Backup saved to: " .. b_path)
        else
            self.logger:warn("Could not create backup: " .. tostring(b_path))
        end
    else
        self.logger:info("[DRY RUN] Skipping database backup.")
    end

    -- 2. Load existing series from cc.db to preserve existing collections
    self.logger:info("Loading existing series from cc.db...")
    local series_map = self.db_helper:get_existing_series_map()
    local existing_count = 0
    for _ in pairs(series_map) do existing_count = existing_count + 1 end
    self.logger:info(string.format("Found %d existing series in database.", existing_count))

    -- 3. Load /mnt/us/metadata.calibre
    local calibre_reader = CalibreReader.new(nil, self.logger)
    if not calibre_reader:load() then
        self.logger:error("metadata.calibre not found! Aborting scan without modifying database or restarting framework.")
        return {
            success = false,
            scanned_count = 0,
            matched_count = 0,
            series_count = 0,
        }
    end

    -- 4. Read all book entries from cc.db
    self.logger:info("Reading books from cc.db...")
    local books = self.db_helper:get_all_books()
    self.logger:info(string.format("Found %d book entries in database.", #books))

    local scanned_count = 0
    local new_matched_count = 0

    -- 5. Scan books: match via metadata.calibre cache + AZW3/MOBI files
    local missing_books = {}
    local is_device = (io.open("/mnt/us", "r") ~= nil) or (io.open("/mnt/us/documents", "r") ~= nil)

    for _, book in ipairs(books) do
        local s_name, s_idx = nil, nil
        local filepath = self:resolve_filepath(book.location)

        if filepath then
            scanned_count = scanned_count + 1
            local ext = string.lower(string.match(filepath, "(%.%w+)$") or "")

            -- 1. Read file to extract Calibre UUID
            local book_uuid = nil
            if Config.SUPPORTED_EXTENSIONS[ext] then
                if ext == ".kfx" then
                    book_uuid = MetadataParser.extract_kfx_uuid(filepath)
                else
                    local reader = MobiReader.new(filepath)
                    if reader:parse_header() then
                        book_uuid = reader:get_uuid()
                    end
                    reader:close()
                end
            end

            -- 2. Match with metadata.calibre at /mnt/us using UUID (or path/title)
            if calibre_reader.loaded then
                s_name, s_idx = calibre_reader:lookup_series({
                    uuid = book_uuid or book.uuid or book.cdeKey,
                    location = book.location,
                    title = book.title
                })
                if s_name then
                    self.logger:info(string.format("  [CALIBRE MATCH] '%s' -> Series '%s' (#%s) [UUID: %s]", book.title or "", s_name, tostring(s_idx), tostring(book_uuid)))
                end
            end

            -- 3. Fallback: Parse from title pattern if not in metadata.calibre
            if not s_name then
                s_name, s_idx = MetadataParser.parse_from_title(book.title)
                if s_name then
                    self.logger:info(string.format("  [TITLE MATCH] '%s' -> Series '%s' (#%s)", book.title or "", s_name, tostring(s_idx)))
                end
            end
        else
            if is_device and book.location and string.find(book.location, "^/mnt/us/") then
                table.insert(missing_books, book)
            else
                self.logger:debug("  File not found for location: " .. tostring(book.location))
            end
        end

        -- Add book to series map if series info found
        if s_name and s_name ~= "" then
            book.seriesName = s_name
            book.seriesIndex = s_idx or 1
            new_matched_count = new_matched_count + 1

            -- Find existing series by exact name or normalized key
            local target_series = series_map[s_name]
            if not target_series then
                local s_key = Series.normalize_key(s_name)
                for _, s_obj in pairs(series_map) do
                    if s_obj.cdeKey == s_key then
                        target_series = s_obj
                        break
                    end
                end
            end

            if not target_series then
                target_series = Series.new(s_name)
                series_map[s_name] = target_series
                self.logger:info(string.format("  [NEW SERIES] Created '%s' for book: %s (#%s)", s_name, book.title, tostring(book.seriesIndex)))
            else
                self.logger:info(string.format("  [APPEND TO SERIES] '%s' -> %s (#%s)", target_series.name, book.title, tostring(book.seriesIndex)))
            end

            target_series:add_book(book, book.seriesIndex)
        end
    end

    -- Delete orphaned/missing book records from cc.db
    if #missing_books > 0 then
        if not self.dry_run then
            self.logger:info(string.format("Found %d deleted/missing books on Kindle. Purging from database...", #missing_books))
            self.db_helper:delete_books(missing_books)
        else
            self.logger:info(string.format("  -> [DRY RUN] Would purge %d missing books from database.", #missing_books))
        end
    end

    local total_series_count = 0
    for _ in pairs(series_map) do total_series_count = total_series_count + 1 end
    self.logger:info(string.format("Scanned %d files. %d newly matched. Total %d series in library.", scanned_count, new_matched_count, total_series_count))

    -- 5. Insert or Update series in cc.db
    local series_count = 0
    for s_name, series_obj in pairs(series_map) do
        series_obj:sort_books()
        series_count = series_count + 1

        self.logger:info(string.format("Processing Series '%s' (%d books):", series_obj.name, series_obj:count()))
        for i, b in ipairs(series_obj.books) do
            self.logger:info(string.format("    %d. [#%s] %s (cdeKey=%s)", i, tostring(b.seriesIndex), b.title, b.cdeKey or "unknown"))
        end
    end

    if not self.dry_run then
        self.logger:info(string.format("Saving %d series into cc.db in a single transaction...", series_count))
        local ok, err = self.db_helper:upsert_all_series(series_map)
        if ok then
            self.logger:info("  -> All series saved into cc.db successfully!")
        else
            self.logger:error("  -> Failed to save series into cc.db: " .. tostring(err))
        end
    else
        self.logger:info("  -> [DRY RUN] Skipped writing to cc.db.")
    end

    -- 6. Cleanup empty or orphaned series
    if not self.dry_run then
        self.logger:info("Checking and cleaning up empty series...")
        local cleaned, err = self.db_helper:cleanup_empty_series()
        if cleaned and cleaned > 0 then
            self.logger:info(string.format("Cleaned up %d empty/orphaned series.", cleaned))
        end
    end

    self.logger:info("=== Finished. All series synchronized! ===")
    return {
        success = true,
        scanned_count = scanned_count,
        matched_count = matched_count,
        series_count = series_count,
        series_map = series_map,
    }
end

return SeriesScanner
