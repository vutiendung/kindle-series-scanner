--[[
  series.lua
  Series domain model representing a series grouping and its member books.
--]]

local Series = {}
Series.__index = Series

-- Basic UTF-8 uppercase map for common European and Vietnamese accented characters
local UTF8_LOWER_TO_UPPER = {
    ["a"]="A", ["b"]="B", ["c"]="C", ["d"]="D", ["e"]="E", ["f"]="F", ["g"]="G", ["h"]="H", ["i"]="I",
    ["j"]="J", ["k"]="K", ["l"]="L", ["m"]="M", ["n"]="N", ["o"]="O", ["p"]="P", ["q"]="Q", ["r"]="R",
    ["s"]="S", ["t"]="T", ["u"]="U", ["v"]="V", ["w"]="W", ["x"]="X", ["y"]="Y", ["z"]="Z",
    ["á"]="Á", ["à"]="À", ["ả"]="Ả", ["ã"]="Ã", ["ạ"]="Ạ",
    ["ă"]="Ă", ["ắ"]="Ắ", ["ằ"]="Ằ", ["ẳ"]="Ẳ", ["ẵ"]="Ẵ", ["ặ"]="Ặ",
    ["â"]="Â", ["ấ"]="Ấ", ["ầ"]="Ầ", ["ẩ"]="Ẩ", ["ẫ"]="Ẫ", ["ậ"]="Ậ",
    ["é"]="É", ["è"]="È", ["ẻ"]="Ẻ", ["ẽ"]="Ẽ", ["ẹ"]="Ẹ",
    ["ê"]="Ê", ["ế"]="Ế", ["ề"]="Ề", ["ể"]="Ể", ["ễ"]="Ễ", ["ệ"]="Ệ",
    ["í"]="Í", ["ì"]="Ì", ["ỉ"]="Ỉ", ["ĩ"]="Ĩ", ["ị"]="Ị",
    ["ó"]="Ó", ["ò"]="Ò", ["ỏ"]="Ỏ", ["õ"]="Õ", ["ọ"]="Ọ",
    ["ô"]="Ô", ["ố"]="Ố", ["ồ"]="Ồ", ["ổ"]="Ổ", ["ỗ"]="Ỗ", ["ộ"]="Ộ",
    ["ơ"]="Ơ", ["ớ"]="Ớ", ["ờ"]="Ờ", ["ở"]="Ở", ["ỡ"]="Ỡ", ["ợ"]="Ợ",
    ["ú"]="Ú", ["ù"]="Ù", ["ủ"]="Ủ", ["ũ"]="Ũ", ["ụ"]="Ụ",
    ["ư"]="Ư", ["ứ"]="Ứ", ["ừ"]="Ừ", ["ử"]="Ử", ["ữ"]="Ữ", ["ự"]="Ự",
    ["ý"]="Ý", ["ỳ"]="Ỳ", ["ỷ"]="Ỷ", ["ỹ"]="Ỹ", ["ỵ"]="Ỵ",
    ["đ"]="Đ",
}

local function utf8_upper(str)
    if not str then return "" end
    -- Replace multibyte and singlebyte chars using map
    local res = {}
    local i = 1
    local len = #str
    while i <= len do
        local b = string.byte(str, i)
        local char_len = 1
        if b >= 240 then char_len = 4
        elseif b >= 224 then char_len = 3
        elseif b >= 192 then char_len = 2
        end
        local char = string.sub(str, i, i + char_len - 1)
        table.insert(res, UTF8_LOWER_TO_UPPER[char] or string.upper(char))
        i = i + char_len
    end
    return table.concat(res)
end

function Series.normalize_key(name)
    if not name or name == "" then return "UNKNOWN" end
    local key = utf8_upper(name)
    key = string.gsub(key, "['\"%[%]%(%)]", "")
    key = string.gsub(key, "[%s%p]+", "-")
    key = string.gsub(key, "^%-+", "")
    key = string.gsub(key, "%-+$", "")
    return "SL-" .. key
end

function Series.new(name, custom_asin)
    local self = setmetatable({}, Series)
    self.name = name or "Unknown Series"
    self.cdeKey = custom_asin or Series.normalize_key(self.name)
    self.seriesId = "urn:collection:1:asin-" .. self.cdeKey
    self.books = {}
    return self
end

function Series:add_book(book, index)
    if index then
        book.seriesIndex = index
    end
    -- Check if book already exists in series
    for _, existing in ipairs(self.books) do
        if (existing.cdeKey and book.cdeKey and existing.cdeKey == book.cdeKey) or
           (existing.uuid and book.uuid and existing.uuid == book.uuid) then
            if index then existing.seriesIndex = index end
            if book.title then existing.title = book.title end
            if book.thumbnail then existing.thumbnail = book.thumbnail end
            return false -- merged into existing
        end
    end
    table.insert(self.books, book)
    return true -- newly added
end

function Series:sort_books()
    table.sort(self.books, function(a, b)
        local idx_a = tonumber(a.seriesIndex) or 0
        local idx_b = tonumber(b.seriesIndex) or 0
        if idx_a == idx_b then
            return (a.title or "") < (b.title or "")
        end
        return idx_a < idx_b
    end)
end

function Series:count()
    return #self.books
end

function Series:get_first_book()
    return self.books[1]
end

return Series
