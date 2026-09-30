--[[
  book.lua
  Book domain model representing a book entry from cc.db and/or parsed from file.
--]]

local Book = {}
Book.__index = Book

function Book.new(data)
    local self = setmetatable({}, Book)
    data = data or {}
    self.uuid = data.uuid or data.p_uuid
    self.cdeKey = data.cdeKey or data.p_cdeKey
    self.cdeType = data.cdeType or data.p_cdeType or "EBOK"
    self.title = data.title or data.p_titles_0_nominal
    self.author = data.author or data.p_credits_0_name_collation
    self.location = data.location or data.p_location
    self.thumbnail = data.thumbnail or data.p_thumbnail
    self.j_credits = data.j_credits
    self.j_titles = data.j_titles
    self.seriesState = data.seriesState or data.p_seriesState
    
    -- Extracted series metadata
    self.seriesName = data.seriesName
    self.seriesIndex = data.seriesIndex
    
    return self
end

function Book:has_series()
    return self.seriesName ~= nil and self.seriesName ~= ""
end

function Book:to_string()
    local s_info = ""
    if self:has_series() then
        s_info = string.format(" [Series: %s #%s]", self.seriesName, tostring(self.seriesIndex or 1))
    end
    return string.format("%s by %s (%s)%s", self.title or "Unknown", self.author or "Unknown", self.cdeKey or "no-key", s_info)
end

return Book
