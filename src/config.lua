--[[
  config.lua
  Configuration settings for Kindle Series Scanner KUAL extension.
--]]

local Config = {
    -- Default path on Kindle device
    KINDLE_DB_PATH = "/var/local/cc.db",
    -- Fallback/local path for development
    LOCAL_DB_PATH = "cc.db",
    
    -- Documents path on Kindle
    DOCUMENTS_PATH = "/mnt/us/documents",

    -- Supported book file extensions
    SUPPORTED_EXTENSIONS = {
        [".azw3"] = true,
        [".mobi"] = true,
        [".azw"]  = true,
        [".kfx"]  = true,
    },

    -- Log file paths (stored on user storage for persistence and easy viewing)
    LOG_FILE = "/mnt/us/kindle_series_scanner.log",
    USER_LOG_FILE = "/mnt/us/kindle_series_scanner.log",

    -- Database backup folder path (on Kindle internal user storage)
    BACKUP_DIR = "/mnt/us/kindle_db_backup",

    -- Command to restart Kindle framework and reload metadata
    RELOAD_FRAMEWORK_CMD = "restart framework",
    RELOAD_CCAT = true,
}

function Config.get_db_path(custom_path)
    if custom_path and custom_path ~= "" then
        return custom_path
    end
    -- Check if Kindle system db exists
    local f = io.open(Config.KINDLE_DB_PATH, "r")
    if f then
        f:close()
        return Config.KINDLE_DB_PATH
    end
    return Config.LOCAL_DB_PATH
end

return Config
