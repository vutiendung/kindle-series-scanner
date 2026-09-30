--[[
  main.lua
  Kindle Series Scanner CLI & Extension Entry Point (Lua 5.1.4)
--]]

local Config = require("src.config")
local Logger = require("src.utils.logger")
local SqliteHelper = require("src.db.sqlite_helper")
local SeriesScanner = require("src.services.series_scanner")

local function parse_args(arg_list)
    local opts = {
        command = "scan",
        db_path = nil,
        backup_dir = Config.BACKUP_DIR,
        dry_run = false,
        verbose = true,
        use_eips = false,
    }

    local i = 1
    while i <= #arg_list do
        local a = arg_list[i]
        if a == "scan" or a == "dry-run" or a == "backup" or a == "restore" or a == "diagnose" or a == "cleanup" or a == "clean-all" or a == "reset" then
            opts.command = a
        elseif a == "--db" and i < #arg_list then
            i = i + 1
            opts.db_path = arg_list[i]
        elseif a == "--backup-dir" and i < #arg_list then
            i = i + 1
            opts.backup_dir = arg_list[i]
        elseif a == "--dry-run" then
            opts.dry_run = true
        elseif a == "--eips" then
            opts.use_eips = true
        elseif a == "--quiet" or a == "-q" then
            opts.verbose = false
        end
        i = i + 1
    end

    if opts.command == "dry-run" then
        opts.dry_run = true
    end

    return opts
end

local function print_help()
    print([[
Kindle Series Scanner - Auto-detect Series from AZW3/Calibre & Manage Collections
Usage:
  lua src/main.lua [command] [options]

Commands:
  scan        Scan cc.db & AZW3 books, extract series, and update cc.db (Default)
  dry-run     Preview series detection without modifying cc.db
  clean-all   Reset & delete ALL series from cc.db (sets all books to standalone)
  cleanup     Delete only empty series with 0 books
  backup      Backup cc.db to /mnt/us/kindle_db_backup
  restore     Restore cc.db from /mnt/us/kindle_db_backup/cc_latest.db
  diagnose    Show current series in cc.db

Options:
  --db <path>           Path to cc.db (Default: /var/local/cc.db or ./cc.db)
  --backup-dir <path>   Backup folder (Default: /mnt/us/kindle_db_backup)
  --eips                Render progress to Kindle e-ink screen using eips
  --quiet, -q           Suppress verbose logs
]])
end

local function main()
    local opts = parse_args(arg or {})

    local logger = Logger.new({
        verbose = opts.verbose,
        log_file = Config.LOG_FILE,
        use_eips = opts.use_eips,
    })

    local db_path = Config.get_db_path(opts.db_path)
    local db_helper = SqliteHelper.new(db_path, logger)

    if opts.command == "help" or opts.command == "--help" or opts.command == "-h" then
        print_help()
        return
    end

    if opts.command == "clean-all" or opts.command == "reset" then
        logger:info("=== Resetting and Cleaning ALL series in cc.db ===")
        logger:screen(3, 10, "Resetting all series...")
        local ok, err = db_helper:clean_all_series()
        if ok then
            logger:info("Successfully reset all series! All books are now standalone.")
            logger:screen(3, 12, "All series deleted!")
        else
            logger:error("Failed to reset series: " .. tostring(err))
            logger:screen(3, 12, "Reset Failed!")
        end
        return
    end

    if opts.command == "export" or opts.command == "copy-db" then
        logger:info("Copying database " .. db_path .. " to /mnt/us/cc.db")
        logger:screen(3, 10, "Exporting cc.db...")
        local target = "/mnt/us/cc.db"
        local cp_cmd = string.format("cp -f %q %q && sync", db_path, target)
        local ok = os.execute(cp_cmd)
        if ok == true or ok == 0 then
            logger:info("Database successfully copied to: " .. target)
            logger:screen(3, 12, "Export Complete!")
            logger:screen(3, 14, "/mnt/us/cc.db")
        else
            logger:error("Failed to copy database to: " .. target)
            logger:screen(3, 12, "Export Failed!")
        end
        return
    end

    if opts.command == "backup" then
        logger:info("Backing up database: " .. db_path)
        logger:screen(3, 10, "Backing up cc.db...")
        local ok, path = db_helper:backup_db(opts.backup_dir)
        if ok then
            logger:info("Database backed up to: " .. path)
            logger:screen(3, 12, "Backup Complete!")
        else
            logger:error("Backup failed: " .. tostring(path))
            logger:screen(3, 12, "Backup Failed!")
        end
        return
    end

    if opts.command == "restore" then
        logger:info("Restoring database from: " .. opts.backup_dir)
        logger:screen(3, 10, "Restoring cc.db...")
        local ok, path = db_helper:restore_db(opts.backup_dir)
        if ok then
            logger:info("Database restored from: " .. path)
            logger:screen(3, 12, "Restore Complete!")
        else
            logger:error("Restore failed: " .. tostring(path))
            logger:screen(3, 12, "Restore Failed!")
        end
        return
    end

    if opts.command == "cleanup" then
        logger:info("=== Cleaning up empty and orphaned series ===")
        logger:screen(3, 10, "Cleaning up series...")
        local cleaned, err = db_helper:cleanup_empty_series()
        if cleaned then
            logger:info(string.format("Successfully cleaned up %d empty series.", cleaned))
            logger:screen(3, 12, string.format("Cleaned %d series!", cleaned))
        else
            logger:error("Cleanup failed: " .. tostring(err))
            logger:screen(3, 12, "Cleanup Failed!")
        end
        return
    end

    if opts.command == "diagnose" then
        logger:info("=== Diagnosing Series in cc.db ===")
        local series_rows = db_helper:with_stripped_icu(function()
            return db_helper:query_json([[
SELECT s.d_seriesId, s.d_itemPosition, s.d_itemPositionLabel, e.p_titles_0_nominal, e.p_cdeKey
FROM Series s
JOIN Entries e ON s.d_itemCdeKey = e.p_cdeKey
ORDER BY s.d_seriesId, s.d_itemPosition;
]])
        end)
        logger:info(string.format("Found %d series member records in Series table.", #series_rows))
        local cur_s = nil
        for _, r in ipairs(series_rows) do
            if r.d_seriesId ~= cur_s then
                cur_s = r.d_seriesId
                logger:info("\nSeries: " .. cur_s)
            end
            logger:info(string.format("  [%s] %s (cdeKey: %s)", r.d_itemPositionLabel or "?", r.p_titles_0_nominal or "Untitled", r.p_cdeKey or ""))
        end
        return
    end

    -- Default: scan or dry-run
    logger:screen(3, 8, "Kindle Series Scanner")
    logger:screen(3, 10, opts.dry_run and "Running Dry Run..." or "Scanning Series...")

    local scanner = SeriesScanner.new(db_helper, logger, {
        backup_dir = opts.backup_dir,
        dry_run = opts.dry_run,
    })

    local results = scanner:scan_and_sync()

    if opts.use_eips then
        logger:screen(3, 12, string.format("Scanned %d books", results.scanned_count))
        logger:screen(3, 14, string.format("Created %d series", results.series_count))
        logger:screen(3, 16, "Done! Restarting UI...")
    end
end

main()
