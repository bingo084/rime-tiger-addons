-- Emoji are always available. Keep ordinary decoder candidate indexes intact;
-- reverse lookup can place emoji directly after the matching text.
local M = {}

local function is_reverse_lookup(env)
    local composition = env.engine.context.composition
    if not composition or composition:empty() then return false end
    local segment = composition:back()
    return segment:has_tag("yin_add_user") or segment:has_tag("yin_add_user_quote")
end

function M.func(input, env)
    local reverse = is_reverse_lookup(env)
    if not env.converter then
        env.converter = Opencc(rime_api.get_user_data_dir() .. "/opencc/emoji.json")
    end
    local count, seen, alternatives = 0, {}, {}
    for candidate in input:iter() do
        yield(candidate)
        if count < 12 then
            for _, text in ipairs(env.converter:convert_word(candidate.text) or {}) do
                if text ~= candidate.text and not seen[text] then
                    seen[text] = true
                    local emoji = ShadowCandidate(
                        candidate, "tiger_emoji", text, "〔" .. candidate.text .. "〕")
                    if reverse then
                        yield(emoji)
                    else
                        alternatives[#alternatives + 1] = emoji
                    end
                    count = count + 1
                    if count >= 12 then break end
                end
            end
        end
    end
    for _, candidate in ipairs(alternatives) do yield(candidate) end
end

-- A selected emoji is an explicit choice outside the decoder's text paths.
-- Confirm it before appending a new printable key, rather than giving its
-- menu index to the ordinary decoder and silently losing that choice.
function M.processor(key, env)
    if key:release() or key:ctrl() or key:alt() or key:super() then return 2 end
    local context = env.engine.context
    local selected = context:get_selected_candidate()
    if not selected or selected.type ~= "tiger_emoji" then return 2 end
    local repr = key:repr()
    if repr == "space" or repr == "Return" then
        context:commit()
        return 1
    end
    if key.keycode >= 0x21 and key.keycode <= 0x7e then context:commit() end
    return 2
end

return M
