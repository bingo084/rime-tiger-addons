-- Compare the real decoder indexes before/after adding words.
local original_dir, words_dir = arg[1], arg[2]
package.path = words_dir .. "/lua/?.lua;" .. package.path
local active = original_dir
rime_api = { get_user_data_dir = function() return active end,
    get_shared_data_dir = function() return "/usr/share/rime-data" end }
local baseline = require("tiger_sentence").ensure_lexicon()
active = words_dir
package.loaded.tiger_sentence = nil
local added = require("tiger_sentence").ensure_lexicon()
local singles, count = {}, 0
for code, list in pairs(added.codes) do
    for _, item in ipairs(list) do
        if utf8.len(item.t) == 1 then singles[code .. "\0" .. item.t] = item end
    end
end
for code, list in pairs(baseline.codes) do
    for _, item in ipairs(list) do
        if utf8.len(item.t) == 1 then
            local candidate = singles[code .. "\0" .. item.t]
            assert(candidate, "Original character disappeared: " .. item.t .. "/" .. code)
            assert(candidate.primary_single == item.primary_single, "Character primary code changed")
            assert(candidate.optimal_single == item.optimal_single, "Character shortest code changed")
            count = count + 1
        end
    end
end
local merge = require("tiger_user_codes").merge
local official = { { word = "尾", code = "cv" }, { word = "肢", code = "vc" } }
local mixed = merge(official, "\239\187\191# comment\r\n不要\tcv\tafter\r\n要不\tvc\tbefore\n要不\tvc\n尾\tcv\tafter\n")
assert(#mixed == 4 and mixed[1].word == "要不" and mixed[2].word == "尾" and mixed[4].word == "不要")
assert(#merge(official, "") == 2)
local ok = pcall(merge, official, "不要\tcv\t100\n")
assert(not ok, "Numeric weight was silently treated as placement")
assert(baseline.learning_rules ~= added.learning_rules, "Personal words missing from learning rules")
print("PASS original character indexes: " .. count .. " entries; placement, deduplication, BOM/CRLF, learning rules")
