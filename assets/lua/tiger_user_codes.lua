-- Personal words are merged in memory; the official table is never rewritten.
-- Each line: word<TAB>code[<TAB>before|after]. Default placement is before.
local M = {}

function M.merge(official, content)
    local before, after = {}, {}
    content = content:gsub("^\239\187\191", "")
    for raw_line in (content .. "\n"):gmatch("([^\n]*)\n") do
        local line = raw_line:gsub("\r$", "")
        if not line:match("^%s*#") then
            local word, code, position = line:match("^%s*(%S+)%s+(%S+)%s*(%S*)")
            if word and code then
                code = code:lower()
                if code:match("^[a-z]+$") then
                    if position == "" then position = "before" end
                    if position ~= "before" and position ~= "after" then
                        error("custom_phrase.txt: placement must be before or after")
                    end
                    local list = position == "after" and after or before
                    list[#list + 1] = { word = word, code = code }
                end
            end
        end
    end
    local merged, seen = {}, {}
    for _, list in ipairs({ before, official, after }) do
        for _, entry in ipairs(list) do
            local key = entry.word .. "\0" .. entry.code
            if not seen[key] then
                seen[key] = true
                merged[#merged + 1] = entry
            end
        end
    end
    return merged
end

return M
