-- 反查段守卫：反查时只许按拼音解释编码，禁止整句解码器插嘴。
--
-- 为什么需要它：方案的整句翻译器 lua_translator@tiger_sentence_translator 是个
-- 纯 Lua 函数 translator(input, seg, env)，它**不检查段标签**，只要被 Engine 调用
-- 就会把段内编码拿去解码。librime 的 Engine::TranslateSegments 会把列表里每个
-- 翻译器都问一遍再合并结果，于是反查段里方案也照样解一次：
-- 打 `xingbuxing 时，拼音串被当成虎码解出「久在建久在」「久在建久鬲」等候选，
-- 和反查该有的「行不行」混在一起。
--
-- librime-lua 的 LuaTranslator 不支持 tags_match（见 lua_gears.cc：
-- LuaTranslator 的 raw_init 没传 tags_match 参数，只有 LuaFilter 传了），
-- 所以没法用配置让原翻译器按标签失效，只能在补丁里包一层。
--
-- 本包装器对反查段直接返回（不产出任何候选），其余段原样交给方案翻译器。
local tiger = require("tiger_sentence")

local YIN_TAGS = { "yin_add_user", "yin_add_user_quote" }

-- 段上带反查标签，或整个编码以反查引导键开头。
-- 后者是必需的：反查途中按数字会把数字写进编码，recognizer 的
-- ^`[A-Za-z']*$ 不再匹配，段上的 yin 标签会掉，光看标签又会让整句解码器溜进来。
-- 虎码编码本身就是 a-z（见 tiger_sentence.codes.txt 表头），不会以 ` 或 ' 开头，
-- 所以按首字符判断不会误伤正常整句编码；' 在方案里只作选重分隔符，出现在码之后。
local function is_reverse_lookup(segment, env)
    for index = 1, #YIN_TAGS do
        if segment:has_tag(YIN_TAGS[index]) then return true end
    end
    local context = env and env.engine and env.engine.context
    local raw = context and context.input or ""
    local first = raw:sub(1, 1)
    return first == "`" or first == "'"
end

local function translator(input, seg, env)
    if env.engine.context:get_property("zqj_stats_view") ~= "" then return end
    if is_reverse_lookup(seg, env) then return end
    -- 整句翻译器是协程函数（内部 yield），在同一协程里调用即可，
    -- yield 会正常向上传播给 librime-lua 的 LuaTranslation。
    return tiger.translator(input, seg, env)
end

return { func = translator }
