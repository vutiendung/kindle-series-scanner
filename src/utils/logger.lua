--[[
  logger.lua
  Logging module supporting stdout, file logs, and optional Kindle eips display.
--]]

local Logger = {}
Logger.__index = Logger

local LOG_FILE = "/mnt/us/kindle_series_scanner.log"

function Logger.new(opts)
    local self = setmetatable({}, Logger)
    opts = opts or {}
    self.verbose = opts.verbose ~= false
    self.log_file = opts.log_file or LOG_FILE
    self.use_eips = opts.use_eips or false
    return self
end

function Logger:log(level, msg)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local line = string.format("[%s] [%s] %s", timestamp, level, tostring(msg))
    
    if self.verbose then
        print(line)
    end

    local paths = { self.log_file }
    if self.log_file ~= "/mnt/us/kindle_series_scanner.log" then
        table.insert(paths, "/mnt/us/kindle_series_scanner.log")
    end

    for _, path in ipairs(paths) do
        if path then
            local f = io.open(path, "a")
            if f then
                f:write(line .. "\n")
                f:close()
            end
        end
    end
end

function Logger:info(msg)
    self:log("INFO", msg)
end

function Logger:debug(msg)
    if self.verbose then
        self:log("DEBUG", msg)
    end
end

function Logger:warn(msg)
    self:log("WARN", msg)
end

function Logger:error(msg)
    self:log("ERROR", msg)
end

function Logger:screen(x, y, text)
    if self.use_eips then
        os.execute(string.format("eips %d %d %q 2>/dev/null", x or 3, y or 10, tostring(text)))
    end
end

function Logger:screen_clear()
    if self.use_eips then
        os.execute("eips -c 2>/dev/null")
    end
end

return Logger
