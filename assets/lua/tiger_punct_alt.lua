-- 同键轮换符号候选（复刻 librime 原生 Punctuator::AlternatePunct）
--
-- 背景：虎整句方案自带的 lua_processor@tiger_sentence_processor 排在 punctuator
-- 之前。整句组句时，它把握下的标点键当作“确认当前候选并落字”处理
-- （见 tiger_sentence.lua 中 has_menu + 标点键 -> confirm_current_selection 分支）。
-- 于是当输入本身就是标点、且候选是多选列表时（如 symbols.yaml 的
--   '/' : [ 、, ､, '/', ／, ÷ ]
-- ），反复按同一个键不会轮换候选，而是把当前候选上屏、再重建同一个菜单，
-- 表现为“连续上屏第一个候选 + 候选窗闪烁”。
--
-- 对照：未挂整句处理器的方案（如 RimeUser2 里的 tiger）由 librime 原生
-- Punctuator::AlternatePunct 处理，同键即可在候选间轮换。
--
-- 本处理器插在 tiger_sentence_processor 之前，只在“整个输入就是这个标点键”
-- 时接管，其它情况一律放行，因此不影响整句组句时用标点确认选中项的行为。
local M = {}

local K_ACCEPT, K_NOOP = 1, 2

function M.processor(key_event, env)
    if key_event:release() or key_event:ctrl() or key_event:alt() or key_event:super() then
        return K_NOOP
    end
    local kc = key_event.keycode
    if type(kc) ~= "number" or kc < 0x21 or kc >= 0x7F then
        return K_NOOP
    end

    local ctx = env.engine.context
    -- 仅处理“输入就是这一个标点字符”的情形（原生 AlternatePunct 的判据：
    -- key == ctx->input().substr(segment.start, segment.end - segment.start)）
    local input = ctx.input
    if #input ~= 1 or input ~= string.char(kc) then
        return K_NOOP
    end

    local composition = ctx.composition
    if not composition or composition:empty() then
        return K_NOOP
    end
    local seg = composition:back()
    if not seg or not seg:has_tag("punct") then
        return K_NOOP
    end
    -- status > kVoid 才允许轮换
    if seg.status == "kVoid" then
        return K_NOOP
    end
    if seg.start ~= 0 or seg._end ~= 1 then
        return K_NOOP
    end

    local menu = seg.menu
    if not menu then
        return K_NOOP
    end
    local count = menu:candidate_count()
    if type(count) ~= "number" or count < 2 then
        return K_NOOP
    end
    if menu:prepare(seg.selected_index + 2) == 0 then
        return K_NOOP
    end

    -- 与 C++ 一致：前进一项，并把状态退回 kGuess（保持“未确认”，
    -- 这样下一次按键仍会重新组句，而不会立刻把候选上屏）
    seg.selected_index = (seg.selected_index + 1) % count
    seg.status = "kGuess"
    return K_ACCEPT
end

return { func = M.processor }
