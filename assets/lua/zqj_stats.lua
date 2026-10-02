-- 虎整句·速度统计（zqj 版 v3，适配"基于模型 + 提前上屏"的整句方案）
-- 文件名以 zqj_ 前缀个性化，避免与市面通用统计脚本（input_statistics / userdb / stats.userdb）重名冲突。
--
-- ============================ v3 相对 v2 的修正（实机反馈） ============================
-- ① 【标点必须计入字数】旧版把一整张 CJK 码位区段表硬编码在脚本里，只数汉字、把标点全部丢弃。
--    这是错的：标点同样要花时间敲，跟打器（TypeSunnyPro）也把标点计入字数与速度；
--    不计标点则「字数」分母偏小、速度虚高。实测 133 字文档实为 151 个非空白字符
--    （汉字 133 + 标点 18：，×7 。×5 —×2 ：×2 “×1 ”×1），旧口径漏 18 个（少 12%）。
--    现改为 count_chars()：除空白与零宽空格外的所有字符一律计入，不再硬编码任何码位表。
-- ② 【状态必须按引擎隔离】旧版把 commit_history 快照放在模块级全局 `S` 里，而 Rime 会为
--    每个会话/应用各建一个引擎（用户实机一天 `starting engine` 76 次）。A 引擎的快照去和
--    B 引擎的 commit_history 做差量 → 重叠对齐失败 → 退回"整张表都算新增" → 最多 20 条
--    记录被整批重复计数。症状：字数虚高、码数准确 → 平均码长被压到 0.89 码/字
--    （虎码物理不可能；跟打器同段为 2.47）。修法：init() 里 reset_engine_state()。
--    注：不能用 tostring(ctx)/tostring(engine) 当每引擎 key——实测每次访问都返回不同
--    的 userdata 包装（同一引擎内 12 次击键得到 12 个地址），当键等于每键新建状态。
-- ③ 【取消击键攒批】旧版为省 I/O 把击键/码数攒够 32 个才落盘，但引擎重建时 fini() 不保证
--    被调用，缓冲里的计数整批丢失（实测 harness 真值编码键 1758，攒批版只记到 1561）。
--    现改为每次击键立即落盘；端到端实测与攒批版无差异。
-- ④ 【删掉无意义指标】移除 `模型落地/用户上屏` 两行——经 engine.cc 与实测确认，
--    本方案"落地"即等于已上屏（两条路径都先 Push 记录再 sink_()），该拆分答非所问。
--
-- ============================ v2 相对 v1 的修正 ============================
-- A. 【统计指令污染统计】v1 把 /tj /rtj /ztj /ytj /ntj /tjql 的仪表盘文本当作普通上屏，
--    经 commit_history 计入字数/上屏次数/分布。实测一次 /tj 加 13 字、一次 /tjql 加 9 字，
--    且每次查询都污染速度统计。v2 按记录 type=="stat"（本脚本自身产出的候选类型）跳过，
--    再以"效率仪表盘"文本兜底。/ 引导的按键 v1 已排除，v2 保持。
-- B. 【首帧重复计数】v1 在模块（重新）加载时 prev_texts=nil，差量函数把当时整张
--    commit_history（最多 20 条）当作"新增"再计一次，模块每次重载都会虚增。v2 首帧只
--    记录快照、不计数。
-- C. 【落地 != 上屏 的澄清】"落地"（模型提前上屏，commit_history type=="raw"）
--    与"上屏"（用户按空格/回车/选重/标点触发 Context::Commit）是两件事。
--    注意：**librime 的 commit_history 里不存在"模型判定但未上屏"的文本**——凡是进入
--    commit_history 的记录都已调用过 sink_() 真正送到应用（见 engine.cc 的 CommitText /
--    OnCommit）。模型"内部判定但未 commit"的候选根本不进 commit_history。因此字数口径
--    本身没有把"未上屏"算进来；真正会虚高的是**分布**（每条 raw 片段各算一次"落地"），
--    所以要合并成"上屏单元"。
-- D. 【历史脏数据必须一次性迁移】早期版本按"每条 raw 片段 = 一次落地"累计，
--    [1] 字 / [2 码] 占比因此虚高。旧计数与新口径不可混用，且**不清掉就会永久虚高**。
--    用 meta_ver 做一次性迁移：旧计数键改名到 legacy_ 前缀（原文保留、不丢数据），
--    新口径从零起算。**v3 再次执行迁移**（v2 的库口径亦不正确），meta_ver=3。
-- E. 【热路径开销】缓存日界键（不再每键 os.date）、commit_history 无变化时提前返回不做
--    to_table() 分配、LevelDB 方法句柄在模块加载时解析一次（避免每次访问都新建闭包）。
--
-- 为什么普通形码统计脚本在本方案下不准（实测：真实 librime 1.17 + 跟打 133 字文档）：
--   1) 方案的"提前上屏"极其活跃：整段里绝大多数字是模型在你还没敲空格时，经
--      env.engine:commit_text() 自动上屏的。该调用是 librime 的 Engine::CommitText，
--      **不触发 commit_notifier**（只写 sink 与 commit_history）。只有空格结束整段时的
--      Context::Commit 才触发 commit_notifier。→ 仅挂 commit_notifier 会漏掉绝大多数字
--      （实测原脚本 133 字只统计到 34 字）。
--   2) 本 build 的 librime-lua 里 commit_history 是**属性**：用 ctx.commit_history（userdata）
--      再 :to_table()，不能写 ctx:commit_history()。它**同时**收录两条上屏路径：提前上屏
--      type="raw"，整段提交 type=候选类型（如 "sentence"）。容量 20（kMaxRecords），超出弹出最旧。
--   3) 因此字数/词条一律改从 commit_history 差量捕获；击键与码数改用一个恒放行、排在链首的
--      processor 精确计数，不再用 #ctx.input 反推（提前上屏会截断 input，反推必然失真）。
--
-- 口径定义（v4）：
--   · 字数(_len)   = 实际上屏到应用的非空白字符数（模型提前上屏 + 用户上屏），汉字与标点一视同仁。
--   · 上屏(_cnt)   = **用户上屏单元**次数：把此前累计的 raw 片段并入其后的 Context::Commit
--                    合成"一次上屏"，不把 raw 片段当独立一次。
--   · 键(_keys)    = 有效按键数。计入：可打印字符、空格/回车（上屏动作）、退格（改正动作）。
--                    排除：纯修饰键、方向键/翻页/Tab/Esc 等**与输入方案无关的按键请求**、
--                    以及 /统计指令 自身的按键。
--   · 时长(_active_ms) = 相邻有效击键间隔累加（轮内间隔全额计入，反映真实击键节奏）。
--   · 轮池(_r_keys/_r_len/_r_ms/_r_n) = **速率类指标的专用口径**。一轮 = 一段连续输入
--                    （相邻有效击键间隔 ≤ SESSION_GAP_S）。只收"产出过文字"的轮：
--                    纯查询/翻候选/零星导航这类空轮整轮不入池。
--   · 均速/平均击键/平均码长 = 由轮池汇总按跟打器公式计算，三者同源同批：
--                    速度 = 字数/时长×60   击键 = 键数/时长   码长 = 键数/字数。
--   · 峰速         = 向前累计窗口算法，以"落字字数 + 时间戳"为输入。
--
-- 为什么速率类不能按天算：按天把 `_keys` 与 `_active_ms` 相除，会让查询、切窗口、
-- 翻候选等**不产出文字**的输入也占用分母（它们耗时却不加字），速度与击键被系统性压低。
-- 实测同一轮 137 字：按天口径 均速 72.7 / 击键 2.87，而跟打器同轮为 88.5 / 3.29。

local userdb = require("zqj_userdb")
local db = userdb.LevelDb("lua/zqj_stats")   -- 数据库文件夹：lua/zqj_stats.userdb

-- LevelDB 方法句柄一次性解析：zqj_userdb 的 __index 每次访问都会新建一个闭包，
-- 热路径（每次击键）里反复访问会产生大量短命闭包与 GC 压力。这里只取一次。
local db_fetch  = db.fetch
local db_update = db.update
local db_erase  = db.erase
local db_loaded = db.loaded
local db_empty  = db.empty
-- 注意：query_with 是 zqj_userdb 定义的 `function extends:query_with(prefix, handler)`，
-- 元表 __index 直接返回原始函数、不做 self 绑定，因此**必须用冒号调用**
-- `db:query_with(...)`；若先 `local f = db.query_with` 再 `f(prefix, handler)`，
-- self 会变成 prefix 字符串，静默失败。

local schema_name = "虎整句"
local raw_software_name = rime_api.get_distribution_code_name()

local DATA_VERSION = 6   -- 计数口径版本；旧库首次加载时一次性迁移（见 migrate_data）

-- ============================ 平台信息 ============================
local function process_platform_info(name, ver)
    name = name or ""; ver = ver or ""
    ver = ver:gsub("^(.-%-[^%-]+)%-.*$", "%1")
    if name == "Weasel" then name = "小狼毫"
    elseif name == "fcitx-rime" then name = "小企鹅"
    elseif name == "foxy" then name = "小狐狸"
    elseif name == "trime" then name = "同文输入法"
    elseif name == "hamster3" then name = "元书输入法"
    elseif name == "hamster" then name = "仓输入法" end
    return name, ver
end

-- ============================ 北京时间 ============================
-- 统一按 UTC+8 计算，与系统本地时区无关：既用于展示时间戳，也用于"今日/多日"的日界。
local function bj_table(offset_days)
    return os.date("!*t", os.time() + 8 * 3600 - (offset_days or 0) * 86400)
end
local function bj_stamp()
    local t = bj_table(0)
    return string.format("%04d/%02d/%02d %02d:%02d:%02d",
        t.year, t.month, t.day, t.hour, t.min, t.sec)
end
local function day_key_at(offset_days)
    local t = bj_table(offset_days)
    return string.format("d_%04d%02d%02d", t.year, t.month, t.day)
end
-- 日界键缓存：按"分钟"失效，避免每次击键都走 os.date + string.format。
local _day_minute, _day_key = nil, nil
local function day_key_now()
    local minute = math.floor(os.time() / 60)
    if minute ~= _day_minute then
        _day_minute = minute
        _day_key = day_key_at(0)
    end
    return _day_key
end

-- ============================ 字数口径 ============================
-- 【v13 定稿】字数 = **汉字 + 中文标点**。
-- 历史沿革（三次修正，别再退回旧口径）：
--   v2 只数汉字（硬编码 CJK 表）→ 漏掉标点 18 个，字数 133 而虎魄 151，对不上；
--   v3 改为"非空白即算" → 抓到了标点，但也把指令残留串（纯 ASCII 40 字符）
--      和乱码碎片（实测一条 [ŕ]）一起算了进去，这正是用户实机"字数虚增"的来源；
--   v13 改为"只认中文（汉字+中文标点+全角+通用标点）" → 与三个参考脚本同一思路，
--      既保住标点、又天然排除 ASCII/残留/乱码，不再依赖易漏的字符串特判。
-- 实测：同一篇 138 字的文章，虎魄报 137、本脚本报 138，口径吻合。
--
-- 三个参考脚本的做法一致且更稳：**只认汉字**，其余一律不算。
--   · input_stat.lua        get_pure_chinese_length() —— is_chinese_code 逐码位判定
--   · input_statistic.lua   同类实现
--   · input_statistics.lua  chinese_length()
-- 本脚本沿用其"只认中文"的思路，但把**中文标点也计入**——因为实机校验证实
-- 虎魄的"字数"是含标点的：同一篇 138 字的文章，虎魄报 137、本脚本报 138；
-- 若只算汉字会掉到 120 上下，与虎魄对不上（用户明确要求与跟打器可比）。
--
-- 覆盖范围：CJK 基本区/扩展A、中文标点（0x3000–0x303F）、全角字符（0xFF00–0xFFEF）、
-- 以及中文常用的几个通用标点（—— … “ ” ‘ ’ 等，落在 0x2010–0x2027）。
-- **不含 ASCII**：正常中文正文不会用到；而指令残留串、乱码碎片全是 ASCII/拉丁扩展，
-- 于是被这个口径一次性挡掉，不必再靠 is_cmd_residue 那种易漏的特判。
local function count_chars(text)
    if type(text) ~= "string" then return 0 end
    local n = 0
    for _, code in utf8.codes(text) do
        if (code >= 0x4E00 and code <= 0x9FFF)     -- CJK 基本区
            or (code >= 0x3400 and code <= 0x4DBF) -- CJK 扩展 A
            or (code >= 0xF900 and code <= 0xFAFF) -- CJK 兼容
            or (code >= 0x3000 and code <= 0x303F) -- 中文标点（。，、《》…）
            or (code >= 0xFF00 and code <= 0xFFEF) -- 全角（：；？！（）等）
            or (code >= 0x2000 and code <= 0x206F) -- 通用标点（—— … “ ” ‘ ’）
        then
            n = n + 1
        end
    end
    return n
end

-- ============================ 时钟（用于击键间隔/峰速） ============================
local is_windows = (raw_software_name == "Weasel")
local _base_time  = os.time()
local _base_clock = os.clock()
local function now_seconds()
    if rime_api.get_time_ms then
        return rime_api.get_time_ms() / 1000
    elseif is_windows then
        return _base_time + (os.clock() - _base_clock)
    else
        return os.time()
    end
end

-- ============================ 峰速：向前累计窗口 ============================
local peak_history = {}
local PEAK_WINDOW_SEC = 10
local PEAK_HISTORY_MAX = 300
local function compute_peak_cpm(gap, hanzi_len)
    table.insert(peak_history, { gap = gap, cnt = hanzi_len })
    if #peak_history > PEAK_HISTORY_MAX then table.remove(peak_history, 1) end
    local gap_sum, cnt_sum = 0, 0
    for i = #peak_history, 1, -1 do
        gap_sum = gap_sum + peak_history[i].gap
        cnt_sum = cnt_sum + peak_history[i].cnt
        if gap_sum >= PEAK_WINDOW_SEC then break end
    end
    if gap_sum < PEAK_WINDOW_SEC then return 0 end
    return math.floor(cnt_sum / gap_sum * 60)
end

-- ============================ 数据库 ============================
local function ensure_db_open()
    if not db_loaded(db) then return db:open() end
    return true
end
local function db_get(key) return tonumber(db_fetch(db, key)) or 0 end
local function db_incr(suffix, amount, day_key)
    amount = amount or 1
    if amount == 0 then return end
    local dk = day_key .. suffix
    db_update(db, dk, tostring(db_get(dk) + amount))
    local tk = "total" .. suffix
    db_update(db, tk, tostring(db_get(tk) + amount))
end
local function db_set_max(suffix, val, day_key)
    local dk = day_key .. suffix
    if val > db_get(dk) then db_update(db, dk, tostring(val)) end
    local tk = "total" .. suffix
    if val > db_get(tk) then db_update(db, tk, tostring(val)) end
end

-- 遍历数据库键。**不要自己写 `for k,v in da:iter()`**：本 build 的 DbAccessor 返回泛型
-- for 三元组，包在 pcall 闭包里遍历会挂死（已实测，见交接文档）。zqj_userdb 提供的
-- query_with 内部就是标准 da:iter() 用法，实测可靠；注意必须**冒号调用**（不绑 self）。
local function each_key(handler)
    local ok = pcall(function()
        db:query_with("", function(key, _) handler(key) end)
    end)
    return ok
end

-- 一次性口径迁移：v1 早期把每条 raw 片段当作一次"落地"，其累计值已知虚高，
-- 与 v2 的"用户上屏单元"口径不可混用，不清掉会永久虚高。
-- 旧计数键改名到 legacy_ 前缀**原文保留**，新口径从零起算。
local function migrate_data()
    if not ensure_db_open() then return end
    local ver = tonumber(db_fetch(db, "meta_ver")) or 0
    if ver >= DATA_VERSION then return end
    local keys = {}
    each_key(function(k)
        if k:match("^d_%d%d%d%d%d%d%d%d_") or k:match("^total_") then
            keys[#keys + 1] = k
        end
    end)    for _, k in ipairs(keys) do
        local v = db_fetch(db, k)
        if v then db_update(db, "legacy_" .. k, v) end
        db_erase(db, k)
    end
    db_update(db, "meta_ver", tostring(DATA_VERSION))
    peak_history = {}
end

-- ============================ 运行状态 ============================
-- process 与 translator 共享同一模块（模块级 upvalue），这是 librime-lua 的标准做法。
--
-- 【v3 关键修正·多引擎重复计数】状态**必须**在每次 init() 时重置差量基准。
-- 病因（实机实测）：Rime 会为每个会话/应用各建一个引擎（用户实机一天 `starting engine` 76 次），
-- 而 Lua 模块是**跨引擎长期存活**的（实测探针：INIT#1 → INIT#2 → INIT#3 依次发生，
-- 模块级 upvalue 不清空）。若沿用上一个引擎留下的 prev_texts 去和本引擎的 commit_history
-- 做差量，两边历史毫无重叠 → `new_records` 退回"整张表都算新增" → 最多 20 条记录
-- 被整批重复计数。症状：**字数虚高、码数准确** → 平均码长被压到 0.89 码/字
-- （虎码物理不可能；跟打器同段为 2.47）。反推真实字数≈158，394/158=2.49 吻合。
-- 沙箱只有一个引擎、且模块只 init 一次，故此缺陷在沙箱中无法复现——这正是此前
-- 回归全绿却实机失真的原因。修法：init() 里把差量基准清空（primed=false）。
--
-- 注：不要试图用 `tostring(ctx)` / `tostring(env.engine)` 做每引擎 key——实测它们
-- **每次访问都返回不同的 userdata 包装**（同一引擎内 12 次击键得到 12 个不同地址），
-- 拿它当键等于每次都新建状态，反而彻底失效（实测字数被算成 383 ≠ 真值 151）。
local S = {
    last_ks_ts     = nil,   -- 上次击键时间戳（会话判定）
    in_session     = false, -- 当前是否处于一个连续输入会话中
    last_landing_ts= nil,   -- 上次落字时间戳（峰速）
    pending_code   = 0,     -- 自上次结算以来敲的编码键数（用于算每次落字消耗了几码）
    pend_at_landing= 0,     -- 上次落字时的 pending_code（本次落字的码数 = 两者之差）
    prev_texts     = nil,   -- 上次 commit_history 快照（记录数组），用于差量
    prev_size      = -1,    -- 上次快照长度（配合 prev_back_* 做"无变化"快速判定）
    prev_back_type = "",
    prev_back_text = "",
    primed         = false, -- 是否已取过首帧快照（首帧只记录、不计数）
    -- 【按轮统计】速度/击键/码长必须按「一轮」算，不能按天。
    -- 病因（实机实测）：按天聚合时，一天里夹着的查询、聊天、改稿、零星导航键全被并进
    -- 同一个分母——那些键几乎不产出字符，却按 ≤阈值 的间隔往时长里加数，
    -- 于是「字数几乎不变、时长却涨了几十秒」，速度和击键被系统性压低
    -- （实测一轮 137 字：按天口径得 均速 72.7 / 击键 2.87，而跟打器同轮为 88.5 / 3.29）。
    -- 跟打器测的本来就是「一轮」：从本轮第一键到最后一键。故按轮汇总。
    -- 一轮结束时，若该轮产出过文字，就把 (键数, 字数, 时长) 累加进当天与总计的轮池；
    -- 没产出文字的轮（纯查询/面板/导航）整轮不入池——这正是剔除稀释的关键。
    cs_keys        = 0,     -- 当前轮：击键数
    cs_len         = 0,     -- 当前轮：上屏字数
    cs_ms          = 0,     -- 当前轮：时长（仅计入 ≤ 阈值的间隔）
    cs_day         = nil,   -- 当前轮所属日期键（跨日查询时用于判断该轮是否落在窗口内）
    -- 【字数差量补漏】commit_history 容量只有 20 条（kMaxRecords），而本方案的提前上屏
    -- **不触发任何 notifier**：两次 capture 之间可能已落字超过 20 条，最老的那批已被
    -- pop_front 挤掉，快照对齐无从谈起 → new_records 退回"整张表都算新增" → 一批记录
    -- 被重复计数。实测症状：两遍 137 字正文后字数 370（应为 274，虚增 96），而**键数与
    -- 时长都准确**，于是均速被抬高、码长被压低（用户实机：均速 113.88、码长 1.62）。
    -- 修法：每次**击键**也采样一次历史（击键必然伴随落字，采样密度足够高，
    -- 不会再积压到超过 20 条）；同时用一个"总落字数"指纹做兜底校验。
    last_fp        = nil,   -- 上次已计入的历史指纹（type+text 的哈希），用于去重兜底
    -- 【v14 标顶识别：用"按键代"区分"一次上屏"与"分次上屏"】
    --
    -- 用户指出的关键区别（同一段最终文字，来源完全不同）：
    --   · 顶字上屏：整句打完没上屏，此时按 `？`（Shift+/）或 `，`/`；` ——标点把待上屏的
    --     整句**一起顶出去**。用户只按了**一个键**，屏幕上一下出现"整句+标点"。
    --   · 分次上屏：先用空格把整句上屏，再**单独**按 `？`（或快符 `;w`）输出标点。
    --     用户按了**两次**，屏幕是分两次出现的。
    -- 两者最终文字一模一样，但「一次上屏」还是「两次上屏」不同——只看文本无法分辨，
    -- 我此前"凡标点就并入前一次落字"是一刀切，错在此：**没有待顶内容时标点无法标顶**，
    -- 那种标点本身就是一次独立上屏。
    --
    -- 可靠判据（实测得出，见下）：**同一个按键代**。
    --   A 标顶  : KEY#3(按 ，, input=[sr]) → 同一代里先出 sentence[发]、再出 punct[，]
    --   B 分次  : KEY#6(space) → sentence[发]；KEY#7(，) → punct[，]（**不同代**）
    --   C 空输入: KEY#8(.) → punct[。]（本代内前面没有正文记录）
    -- 故按"代"合并：只有与该次正文记录**同代**的标点才并入它；否则标点自成一次上屏。
    ks_gen         = 0,     -- 按键代：每处理一个按键 +1（见 on_keystroke 末尾）
    hold_hz        = 0,     -- 当前待结算的落字：字数
    hold_codes     = 0,     -- 当前待结算的落字：编码键数
    hold_gen       = -1,    -- 该落字所属的按键代（用于判断后继标点是否同代）
}

local HISTORY_CAP = 20     -- librime CommitHistory::kMaxRecords（commit_history 容量）

-- 【v13 关键修正·跨引擎重复计数（用户实机症状的直接病根）】
-- 病根：`commit_history` 是**每引擎独立**的，而差量基准原本放在**模块级全局** `S` 里。
-- 用户在两个窗口/应用之间切换时，引擎 B 的历史被拿去和引擎 A 的基准比对，两者毫无
-- 重叠 → new_records 找不到最大重叠、退回 `return cur`，于是**整张历史被当新增重算一遍**。
-- 实测复现（沙箱，两窗口交替，正文两遍真值 len=302 / cnt=54）：
--     单窗口 302 ✓   两窗口交替 332（+30）   ← 与用户实机（+31）同一签名
--
-- 状态容器怎么选（实测结论，别再试错）：
--   · 模块级 `S`  → 全局共享，跨引擎互相污染 ✗
--   · `env`       → **每个组件各一份**，不是每引擎一份：实测两次 init 各自 envcnt=1，
--                   processor 的 env 又从 1 重新计。用它做键会让 processor 与
--                   translator 各持一个基准 → 同一条历史被算两遍（实测 603 = 2×302）✗
--   · `ctx`/`env.engine` userdata → 每次访问返回**新包装**，做表键等于每次都新建状态 ✗
--   · **context 自定义属性** → 每引擎稳定：init 里 set、processor 里 get 能原样读回 ✓
-- 故：用属性 `zqj_eid` 拿一个每引擎稳定的 id，再用它给**模块级**表分桶
--（表在模块级才能被 processor 与 translator 两个组件共享，这正是需求）。
local _eid_seq = 0
local _baseline = {}       -- [eid] = {texts, size, back_type, back_text, primed}

local function eid_of(ctx)
    local ok, v = pcall(function() return ctx:get_property("zqj_eid") end)
    if ok and type(v) == "string" and v:match("^E%d+$") then return v end
    _eid_seq = _eid_seq + 1
    local id = "E" .. _eid_seq
    pcall(function() ctx:set_property("zqj_eid", id) end)
    return id
end

local function base_of(ctx)
    local k = eid_of(ctx)
    local b = _baseline[k]
    if not b then
        -- 引擎数上界护栏：超限整体清空（各自重新取首帧、本帧不计数），
        -- 方向是"少计"的安全降级，绝不制造虚高。
        if _eid_seq > 128 then _baseline = {} end
        b = { texts = nil, size = -1, back_type = "", back_text = "", primed = false }
        _baseline[k] = b
    end
    return b
end

-- 【单次采样可接受的新增条数上限】
-- 采样时机：processor 在**链首**、即按键进入引擎处理**之前**先采一次；之后
-- update/commit notifier 在处理过程中再各采一次。因此相邻两次采样之间的新增，
-- 只可能来自"上一次按键"这一下，正常情况下是 0～2 条。
-- 一旦某次采到的新增远超此数，必是"换了引擎/历史被整体替换"造成的对齐失败，
-- 而不是真有这么多字落屏。此时只更新基准、放弃本帧计数（少计，绝不虚高）。
-- 阈值取 8：正常整句一次提交只新增 1 条，实测 1385 次采样中最大 burst 仅 2；
-- 而跨引擎错位跳变的量级是"整张历史"（十几到 20 条）。8 对两侧都留足余量。
local MAX_ADDED_PER_CAPTURE = 8

-- 每个引擎启动时清空**该引擎**的差量基准：本引擎的第一帧只记录快照，不把既有历史算进来。
local function reset_engine_state(ctx)
    if ctx then
        pcall(function() _baseline[eid_of(ctx)] = nil end)
    else
        _baseline = {}
    end
    S.pending_code   = 0
    S.pend_at_landing= 0
    -- 【重要】当前轮的累计值**不能**在这里清零：它是对应"用户这一轮"的，与引擎无关。
    -- 引擎重建（切应用/换窗口）不代表用户停止打字，清掉会让本轮前半段凭空消失。
    -- 也不重置 cs_day：跨引擎的同一轮仍应记在它开始的那一天。
    -- 真正的清零点只有一个：close_round()（判定为跨轮时）。
    -- last_ks_ts / in_session 同样保留：时间轴跨引擎连续。
end

-- ============================ 停顿阈值 / 会话 ============================
-- 【设计：单阈值会话制】
--
-- 需求（用户提出）：既要体现"一个 session 的完整性"（停顿要计入，口径与跟打器可比），
-- 又不能让"打完一篇、隔一小时再打"把那一小时算进速度里。故需要一个停顿阈值。
--
-- 三个参考脚本及其局限（已通读，见桌面「新建文件夹 (2)」）：
--   · input_stat.lua        间隔≤阈值才累加，>阈值**整段丢弃**。丢弃太粗暴：长停顿直接归零，
--                          速度被抬高得虚高。
--   · input_statistic.lua   超阈值重新计时，旧会话≥1s 且有数据则结算。思路可取。
--   · input_statistics.lua  万象：双阈值会话制（1s 管峰速 / 5s 管均速）+ 最小会话时长过滤。
--                          设计成熟，但**不能照搬**：它把会话挂在 commit 节奏
--                          （observe_input_activity）上，这对拼音成立——拼音「逐音节敲字母→
--                          空格上屏」，commit 节奏≈手指节奏；而虎码整句的 commit 是
--                          **模型驱动的突发流**（一次击键可能触发多条 raw 落地，也可能连敲
--                          十几键不落地），且整句一次上屏 20+ 码、句内思考停顿是常态。
--                          故本方案把会话判定**挂在击键流上**，且只用一个阈值。
--
-- 规则（**单一阈值**，只有切断、没有封顶）：
--   · 相邻击键间隔 ≤ SESSION_GAP_S：同一会话，该间隔**全额**计入 `_active_ms`。
--       —— 会话内的思考停顿照实计入，保"一次连续输入"的完整性（与跟打器一轮的
--          TotalSeconds 同一含义：从本轮第一键到最后一键）。
--   · 相邻击键间隔 > SESSION_GAP_S：视为跨会话，该间隔**完全不计入**任何时间；
--       本次击键开启新会话，`_sess` 计数 +1。
--       —— "打完一篇、隔一会儿再打"中间的空闲不会被算进速度。
--   · 速度类指标一律以 `_active_ms` 为分母。
--
-- 为什么不做"单间隔封顶"：那会让一次真实的长时间思考只贡献封顶值，分子（字数/击键）
-- 却按全额计，结果速度偏高且与跟打器不可比。切断才是正确的边界处理。
--
-- 阈值取 5 秒的依据：
--   ① 轮内并不存在需要"保留"的长停顿——本机实测击键节奏 3.29 键/秒（虎魄 jijian），
--      即相邻击键平均 0.30 s；用户自己描述"轮内一直在打字、手没空过"。
--      故轮内间隔本就是亚秒级，5 s 已是约 16 倍余量，不会切断正常的一轮。
--      （早前版本曾以"轮内可停顿 6.85 s"为由抬到 15 s，那是**误读**：6.85 s 出自虎魄
--       replay 的逐段输入耗时，含义是"该段内容从起到上屏所花时间"，不是击键间隙，
--      虎魄自己的 time 就等于这些段耗时之和，全程照算、不做任何切割。）
--   ② 轮间空闲远大于它：虎魄 history 里同一篇文章相邻两轮的最小间隔为 21 s
--      （19:34:30→19:34:51；其余 22/30/34/42/43/56/70/113 s）。
--   ③ 你给的参考脚本 input_stat.lua（IDLE_THRESHOLD=5）与 input_statistic.lua
--      （gapThd=5000）也都是 5 秒。
--   故 5 秒：足够宽（不会切断轮内）、足够窄（能断开你打字前的那段等待）。
--   可由 schema 配置 zqj_stats/session_gap_s 覆盖。
local SESSION_GAP_S = 5

-- 从 schema 配置覆盖阈值（可选）。任何异常都回退默认值，绝不影响统计。
local function read_thresholds(env)
    local ok, cfg = pcall(function() return env.engine.schema.config end)
    if not ok or not cfg then return end
    local ok1, v = pcall(function() return cfg:get_int("zqj_stats/session_gap_s") end)
    if ok1 and type(v) == "number" and v > 0 then
        SESSION_GAP_S = math.max(1, math.min(3600, v))
    end
end

-- ---------- 击键记录（processor 调用） ----------
-- 【口径对齐跟打器】跟打器的三个成绩指标共用**同一个分子「键数」**：
--     速度 = 字数 / 时长 × 60
--     击键 = 键数 / 时长
--     码长 = 键数 / 字数        ← 与「击键」同分子，不是另算一个"编码键数"
-- 验证（虎魄原始字段 length=137, jianshu=305, time=92.845）：
--     137/92.845×60 = 88.53 ✓   305/92.845 = 3.285 ✓   305/137 = 2.226 ✓
--
-- 因此本脚本只维护一个击键计数 `_keys`：**所有非修饰键都计入**（a–z、数字、
-- 标点（虎码用 , . ; 等作编码/标顶）、退格、空格）。早前版本把 `_code` 限制为
-- 仅 a–z，导致「码长」与「击键」分子不一致（实测码长 2.08 而击键 2.87 自相矛盾），
-- 这是错的：标点与退格同样是用户付出的按键，必须进分子。
--
-- 注：不再从跟打器的 key_press_count 之类**键盘统计模块**反推其成绩字段口径——
-- 那是另一个维度；本脚本只对齐上面三条输出公式本身。
--
-- 与「上屏码长分布」的分工：`_keys` 只服务上面三个**总成绩指标**；而"这一次上屏用了
-- 几个码"属于另一回事，由 `S.pending_code` 单独累计（见 on_unit_close）。
-- 【有效按键的判定】只有"与输入有关"的按键才计入击键与时长：
--   · 计入：可打印字符（字母/数字/标点，虎码用 , . ; 等作编码与标顶）、空格（上屏动作）、
--           回车（上屏动作）、退格（改正动作）。
--   · 不计入：纯修饰键（Shift/Ctrl/Alt/Win/Caps）；以及**与输入方案无关的按键请求**——
--           方向键、翻页 PageUp/PageDown、Home/End、Insert/Delete、Tab、Esc、功能键。
--     这些键既不产生编码、也不上屏，若计入就会同时污染分子（键数）与分母（时长），
--     把速度与击键拉低。用户明确要求剔除这一类。
-- （统计指令自身的按键在 processor 里另行排除。）
local function is_modifier_keycode(kc)
    return (kc >= 0xFFE1 and kc <= 0xFFEC) or kc == 0xFFE5  -- Shift/Ctrl/Alt/Super/Caps
end

local NAV_KEYS = {
    [0xFF08] = false, -- BackSpace  → 是改正动作，计入（下面单列）
    [0xFF09] = true,  -- Tab
    [0xFF1B] = true,  -- Escape
    [0xFF50] = true,  -- Home
    [0xFF51] = true,  -- Left
    [0xFF52] = true,  -- Up
    [0xFF53] = true,  -- Right
    [0xFF54] = true,  -- Down
    [0xFF55] = true,  -- Page_Up
    [0xFF56] = true,  -- Page_Down
    [0xFF57] = true,  -- End
    [0xFF63] = true,  -- Insert
    [0xFFFF] = true,  -- Delete
}
local function is_input_key(kc)
    -- 可打印字符（含空格 0x20）
    if kc >= 0x20 and kc <= 0x7E then return true end
    if kc == 0xFF08 then return true end   -- BackSpace：改正动作
    if kc == 0xFF0D then return true end   -- Return：上屏动作
    if NAV_KEYS[kc] then return false end
    if kc >= 0xFF58 and kc <= 0xFF6F then return false end  -- F1–F24 等
    return false
end
-- 编码键（用于"上屏码长分布"）：可打印且非空格的字符才是码，空格/回车/退格不算码。
local function is_code_key(kc)
    return kc >= 0x21 and kc <= 0x7E
end

-- 结束当前轮：
--   · 本轮**产出过文字** → 轮数 +1（键数/字数/时长已在打字过程中写入库，见 on_keystroke）；
--   · 本轮**一个字符都没上屏**（纯查询、翻候选、零星导航）→ 把它的键数与时长**回滚**，
--     让这个空轮对速率毫无贡献。
-- 为什么边走边写库、而不是"等轮结束再一次性入池"：引擎会频繁重建（实机一天 76 次），
-- 进程也可能重启，写进库则任何时刻查询都能读到，且不必对"当前未结算的一轮"做特判。
local function close_round()
    local dk = S.cs_day
    if dk and S.cs_keys > 0 then
        if S.cs_len > 0 then
            db_incr("_r_n", 1, dk)
        else
            db_incr("_r_keys", -S.cs_keys, dk)
            local ms = math.floor(S.cs_ms + 0.5)
            if ms > 0 then db_incr("_r_ms", -ms, dk) end
        end
    end
    S.cs_keys, S.cs_len, S.cs_ms = 0, 0, 0
    S.cs_day = nil
end

-- 前向声明：on_keystroke 里要顺手采样历史（见下方 v12 说明），而 capture 定义在其后。
local capture

local function on_keystroke(kc, ctx)
    if not ensure_db_open() then return end
    -- 只有与输入有关的按键才参与统计（见 is_input_key 说明）。
    if not is_input_key(kc) then return end
    -- 【v12】先采样历史、再累加本键：这样"此刻发现的落字"所消耗的码数
    -- 不会把当前这个键算进去（当前键是落字之后才敲的）。
    if ctx then pcall(capture, ctx) end
    local dk = day_key_now()
    local now = now_seconds()
    local new_session = true
    if S.last_ks_ts then
        local gap = now - S.last_ks_ts
        -- 同一轮：间隔 ≤ 阈值即全额计入本轮时长（轮内思考停顿照算，与跟打器一轮同义）。
        -- 注意判据是 `gap >= 0` 而非 `> 0`：时钟是毫秒精度，快速连击会落在同一毫秒里
        -- 得到 gap == 0，若把它判成"新轮"就会在打字中途凭空切段
        -- （实测一次 316 键的输入被切成 23 段，并把已敲的键当空轮回滚，丢掉 6 个键）。
        -- 时钟倒退（gap < 0）同样按同轮处理、只是不加时间，绝不切段。
        if gap >= 0 and gap <= SESSION_GAP_S then
            new_session = false
            if gap > 0 then
                local gms = math.floor(gap * 1000 + 0.5)
                S.cs_ms = S.cs_ms + gap * 1000
                db_incr("_active_ms", gms, dk)
                db_incr("_r_ms", gms, dk)
            end
        end
    end
    if new_session then
        close_round()             -- 上一轮到此为止（空轮回滚、有字的轮计数）
        S.in_session = true
        db_incr("_sess", 1, dk)
    end
    if not S.cs_day then S.cs_day = dk end
    S.last_ks_ts = now
    S.cs_keys = S.cs_keys + 1
    db_incr("_keys", 1, dk)
    db_incr("_r_keys", 1, dk)     -- 轮池增量落库：不依赖内存，重启不丢
    if is_code_key(kc) then S.pending_code = S.pending_code + 1 end
    -- 【按键代】本键处理完毕，代号 +1。同一按键处理过程中产生的多条落字记录
    --（正文 + 标顶的标点）共享同一个代号；跨按键产生的记录代号必然不同。
    -- capture 里据此区分"标顶（一次上屏）"与"分次上屏（两次）"。
    S.ks_gen = S.ks_gen + 1
end

-- ---------- 上屏文本捕获（notifier 调用） ----------
local function history_snapshot(ctx)
    local h = ctx.commit_history
    if not h then return {} end
    local ok, tbl = pcall(function() return h:to_table() end)
    if not ok or type(tbl) ~= "table" then return {} end
    local rec = {}
    for i = 1, #tbl do rec[i] = { type = tbl[i].type, text = tbl[i].text } end
    return rec
end
local function rec_eq(a, b) return a and b and a.type == b.type and a.text == b.text end
-- 【差量对齐】返回 cur 中相对 prev 的**新增**记录（按追加顺序）。
--
-- 分两种情形：
-- ① 未满容量（nc < HISTORY_CAP=20）：Push 只会让 size +1，**新增条数 = size 之差**，
--    这是精确解，不必也不该用文本匹配去猜。
-- ② 已满容量：size 恒为 20，必须靠内容对齐——用最长后缀重叠（prev 的尾部 == cur 的头部），
--    这样对 push_back + pop_front 的淘汰天然免疫。
local function new_records(prev, cur)
    if not prev or #prev == 0 then return cur end
    local np, nc = #prev, #cur
    -- ① 未满：精确算术
    if nc < HISTORY_CAP and np >= 0 and nc >= np then
        local k = nc - np
        if k == 0 then return {} end
        local res = {}
        for i = nc - k + 1, nc do res[#res + 1] = cur[i] end
        return res
    end
    -- ② 已满：最长后缀重叠
    local maxL = math.min(np, nc)
    for L = maxL, 0, -1 do
        local match = true
        for i = 1, L do
            if not rec_eq(prev[np - L + i], cur[i]) then match = false; break end
        end
        if match then
            local res = {}
            for i = L + 1, nc do res[#res + 1] = cur[i] end
            return res
        end
    end
    return cur
end

-- 统计指令（仪表盘）自己产出的文本：绝不计数。type 由本脚本的 Candidate("stat", ...) 决定，
-- 再以"效率仪表盘"文本兜底，防止其它路径复用同类型。
local function is_stat_record(r)
    if r.type == "stat" then return true end
    local text = r.text
    return type(text) == "string" and text:find("效率仪表盘", 1, true) ~= nil
end

-- 【字数 + 峰速】按 commit_history 的每条记录累计（含提前上屏的 raw 片段）。
-- 每个字符只计一次；峰速用"每条落字记录 + 相邻间隔"，与已验证的均速/峰速口径一致。
local function on_char_record(hz)
    local dk = day_key_now()
    db_incr("_len", hz, dk)
    if not S.cs_day then S.cs_day = dk end
    S.cs_len = S.cs_len + hz
    db_incr("_r_len", hz, S.cs_day)   -- 轮池增量落库：空轮回滚、重启不丢
    local now = now_seconds()
    if S.last_landing_ts then
        local gap = now - S.last_landing_ts
        if gap > 0 then
            local cpm = compute_peak_cpm(gap, hz)
            if cpm > 0 then db_set_max("_spd", cpm, dk) end
        end
    end
    S.last_landing_ts = now
end

-- 【每次落字】= commit_history 里的一条**落字记录**（一条 raw 片段、或一次用户上屏）。
--
-- 【v12 关键修正·两个分布都算错了】旧实现把"整句的 raw 片段全部并成一个上屏单元"，
-- 再用该单元的**累计码数**分桶。这个口径在整句方案下必然是错的：
--   · 一次提交就是一整句，累计码数恒为 20–38 → 「上屏码长分布」100% 落进「其他」；
--   · 那 12 个标点单元是"1 字 / 0 码"，把「上屏字数分布」的 [1] 撑到 50%。
-- 实测（沙箱一遍 151 字，99 条落字记录）：
--   旧口径码数 = 0,4,6,9,12,13,15,19,23,25,25,31,32,33,38（全部落「其他」）
--   正确口径 = 2码29次 3码26次 4码6次 其余26次
-- 正确口径就是"每一次落字各自消耗了几个编码键"——用户举的例子最清楚：
--   打 srm 时 `发`(编码 sr) 就已经上屏，这一次落字只花了 2 码。
-- 故本函数按**单条落字记录**计数：hz = 这条记录交付了几个字，codes = 它消耗了几个编码键。
--
-- 连打率（打词率）也用这两个量算，且按**字数加权**（与跟打器 CiRatio 同义）：
--   连打率 = 落在"多字落字"里的字数 ÷ 总字数 = (len - l1) / len
-- 其中 l1 是"单字落字"的次数，单字落字的字数恰等于其次数。
-- 实测该式 (151-65)/151 = 56.95%，与虎魄同篇的打词率 56.2% 吻合。
-- 【连打率专用·按"记录"计】标点在 commit_history 里是一条独立记录（hz=1），
-- 虎魄的打词率正是按这个口径算的：同一篇 137 字（汉字123+标点14）报 89.8%
--   = (137 - 14) / 137 —— 那 14 就是标点记录。
-- 故连打率的 l1 必须**含标点记录**，不能合并，否则会变成 100% 与虎魄对不上。
local function count_phrase(hz)
    local dk = day_key_now()
    db_incr("_lan", 1, dk)
    if hz == 1 then db_incr("_l1", 1, dk)
    elseif hz == 2 then db_incr("_l2", 1, dk)
    elseif hz == 3 then db_incr("_l3", 1, dk)
    elseif hz == 4 then db_incr("_l4", 1, dk)
    else db_incr("_l_gt4", 1, dk) end
end

-- 【两个分布 + 上屏次数·按"合并后的落字"计】
--
-- 【v14 关键修正·标顶被当成两次上屏】
-- 用户指出：标点是**随前面的整句"标顶上屏"**的，不是单独以单字形式上屏。
-- 实测（沙箱，提前上屏关，打"每一颗种子都有破土而出的梦想，"）commit_history 里是：
--     sentence:12[每一颗种子都有破土而出的梦想]   ← 被标点顶出去
--     punct:1[，]                                 ← 紧随其后的标点记录
-- 旧实现把这两条各算一次落字，于是：
--     · 「上屏」虚高近一倍（用户实机 26 次，其中 13 次其实是标点）；
--     · 「上屏字数分布」的 [1] 被撑到 50%（那 13 个 1 字落字全是标点）；
--     · 「上屏码长分布」却看不到它们——因为标点记录 hz=1 而 codes=0，全落进「其他」，
--       于是两个分布自相矛盾（用户：一个字最多两三码，为何 [2码] 只有 7%）。
-- 修法：标点记录**并入它顶出的那一次落字**，不新增落字次数。
-- 结果：本篇文章 上屏 26→13、[1] 50%→0%、[+5] →100%，与"整句一次上屏"的直觉一致。
local function count_merged(hz, codes)
    local dk = day_key_now()
    db_incr("_mlan", 1, dk)
    db_incr("_cnt", 1, dk)
    if hz == 1 then db_incr("_ml1", 1, dk)
    elseif hz == 2 then db_incr("_ml2", 1, dk)
    elseif hz == 3 then db_incr("_ml3", 1, dk)
    elseif hz == 4 then db_incr("_ml4", 1, dk)
    else db_incr("_ml_gt4", 1, dk) end
    if codes == 2 then db_incr("_mc2", 1, dk)
    elseif codes == 3 then db_incr("_mc3", 1, dk)
    elseif codes == 4 then db_incr("_mc4", 1, dk)
    else db_incr("_mc_other", 1, dk) end
end

-- 【结算当前落字】把 hold 里的正文（可能已并入同代标点）计为一次上屏。
local function flush_hold()
    if S.hold_hz > 0 then
        count_merged(S.hold_hz, S.hold_codes)
    end
    S.hold_hz, S.hold_codes, S.hold_gen = 0, 0, -1
end

-- 注意：这里必须是 `capture = function(...)`，不能再写 `local function capture`——
-- 否则会新建一个同名局部变量、遮蔽前面的前向声明，on_keystroke 里拿到的仍是 nil，
-- 采样静默失效（pcall 会吞掉这个错误，症状表现为"字数照旧重复计数"）。
capture = function(ctx)
    if not ensure_db_open() then return end
    local h = ctx.commit_history
    if not h then return end

    -- 快速判定（必须无漏计）：commit_history 容量 kMaxRecords=20，未满时 Push 必然让
    -- size +1，故「size 未变且 back 相同」可安全判定无新增。**满 20 条后**会 push_back
    -- + pop_front，size 恒为 20，此时 size+back 都不足以证明无变化（连续两条同 type 同 text
    -- 的记录会误判），必须整表比对，否则漏计（实测漏 1 字）。
    local bs = base_of(ctx)
    local ok_back, back = pcall(function() return h:back() end)
    local size = h.size
    if ok_back and back and bs.primed and type(size) == "number" and size < HISTORY_CAP then
        local bt = back.type or ""
        local bx = back.text or ""
        if size == bs.size and bt == bs.back_type and bx == bs.back_text then
            return
        end
    end

    local cur = history_snapshot(ctx)
    local n_cur = #cur
    if not bs.primed then
        -- 首帧（含模块重新加载 / 新引擎启动）：只记录快照，不把既有历史重复计入。
        bs.primed = true
        bs.texts = cur
        bs.size = n_cur
        return
    end
    local added
    -- 【v13 核心修正·对齐方式】统一交给 new_records：
    -- 未满容量用 size 之差（精确），已满用最长后缀重叠（对 pop_front 免疫）。
    added = new_records(bs.texts, cur)
    -- 【安全护栏】相邻两次采样之间只可能新增"上一次按键"产生的少数几条记录
    --（processor 在链首先采，之后 update/commit notifier 在处理中再采）。
    -- 实测 1385 次采样中最大 burst = 2。一旦新增条数远超此量级，必是库被重置 /
    -- 历史被整体替换导致的对齐失败，而非真有这么多字落屏 → 只更新基准、放弃本帧计数
    --（方向是"少计"，绝不制造虚高）。
    local suspicious = (#added > MAX_ADDED_PER_CAPTURE)
    bs.texts = cur
    bs.size = n_cur
    if ok_back and back then
        bs.back_type = back.type or ""
        bs.back_text = back.text or ""
    end
    if suspicious then return end

    for _, r in ipairs(added) do
        -- "thru" = 原样透传的按键；"stat" = 本脚本的统计指令输出。两者都不是用户文本。
        if r.type ~= "thru" and not is_stat_record(r) then
            do
                local hz = count_chars(r.text)
                if hz > 0 then
                    local codes = S.pending_code - S.pend_at_landing
                    if codes < 0 then codes = 0 end
                    on_char_record(hz)
                    -- 连打率：按"记录"计数，标点记录也是独立一条（与虎魄打词率口径一致）
                    count_phrase(hz)
                    S.pend_at_landing = S.pending_code
                    -- 【v14 两个分布 + 上屏次数】按"按键代"区分标顶与分次上屏：
                    --   同代  → 标点是被这一代的标点键顶出去的 → 并进本次落字
                    --   不同代 → 标点是自己一次独立上屏（无待顶内容，标顶不成立）
                    if r.type == "punct" then
                        if S.hold_hz > 0 and S.hold_gen == S.ks_gen then
                            -- 标顶：并入本代刚产生的正文，仍算**一次**上屏
                            S.hold_hz = S.hold_hz + hz
                        else
                            -- 独立标点：自成一次上屏，先结算挂起的正文
                            flush_hold()
                            count_merged(hz, codes)
                        end
                    else
                        -- 正文记录：若上一代还挂着没结算的落字，先结掉（分次上屏）
                        flush_hold()
                        S.hold_hz = hz
                        S.hold_codes = codes
                        S.hold_gen = S.ks_gen
                    end
                end
            end
        end
    end
end

-- ============================ 聚合查询 ============================
-- 两类数据分开取，各有各的正确口径：
--   · **计数类**（字数/上屏次数/各分布桶）：按窗口逐日累加。这些是"发生了多少次"，
--     与时间无关，直接相加即可。
--   · **速率类**（均速/平均击键/平均码长）：取**轮池**（_r_keys/_r_len/_r_ms）。
--     三个量必须同源同批，且只含"产出过文字"的轮。
--     为什么不能像旧版那样把 `_keys` 和 `_active_ms` 直接按天相除：那等于把查询、
--     切窗口、翻候选、零星导航这些**不产出文字**的输入也算进分母——它们照样消耗
--     时间却几乎不加字，于是速度和击键被系统性压低（实测一轮 137 字：按天得
--     均速 72.7 / 击键 2.87，而跟打器同轮为 88.5 / 3.29）。
-- 轮池是**增量实时落库**的（on_keystroke 每键、on_char_record 每字都在写），
-- 因此查询时直接读库即可，不需要对"当前未结算的一轮"做任何特判；
-- 空轮（无文字产出）会在 close_round() 里被回滚掉。
local function aggregate_stats(days_lookback)
    if not ensure_db_open() then return nil end
    local function pack(prefix)
        return {
            len=db_get(prefix.."_len"), cnt=db_get(prefix.."_cnt"),
            code=db_get(prefix.."_code"), keys=db_get(prefix.."_keys"),
            spd=db_get(prefix.."_spd"),
            active_ms=db_get(prefix.."_active_ms"), sess=db_get(prefix.."_sess"),
            r_keys=db_get(prefix.."_r_keys"), r_len=db_get(prefix.."_r_len"),
            r_ms=db_get(prefix.."_r_ms"), r_n=db_get(prefix.."_r_n"),
            lan=db_get(prefix.."_lan"),
            l1=db_get(prefix.."_l1"), l2=db_get(prefix.."_l2"), l3=db_get(prefix.."_l3"),
            l4=db_get(prefix.."_l4"), l_gt4=db_get(prefix.."_l_gt4"),
            -- 两个分布的计数：标点已并入其顶出的正文（m 前缀 = merged）
            mlan=db_get(prefix.."_mlan"),
            ml1=db_get(prefix.."_ml1"), ml2=db_get(prefix.."_ml2"),
            ml3=db_get(prefix.."_ml3"), ml4=db_get(prefix.."_ml4"),
            ml_gt4=db_get(prefix.."_ml_gt4"),
            mc2=db_get(prefix.."_mc2"), mc3=db_get(prefix.."_mc3"),
            mc4=db_get(prefix.."_mc4"), mc_other=db_get(prefix.."_mc_other"),
        }
    end
    local res
    if days_lookback == 0 then
        res = pack("total")
    else
        res = {len=0,cnt=0,code=0,keys=0,spd=0,active_ms=0,sess=0,
               r_keys=0,r_len=0,r_ms=0,r_n=0,lan=0,
               l1=0,l2=0,l3=0,l4=0,l_gt4=0,c2=0,c3=0,c4=0,c_other=0,
               mlan=0,ml1=0,ml2=0,ml3=0,ml4=0,ml_gt4=0,
               mc2=0,mc3=0,mc4=0,mc_other=0}
        for i = 0, days_lookback - 1 do
            local dk = day_key_at(i)
            res.len=res.len+db_get(dk.."_len"); res.cnt=res.cnt+db_get(dk.."_cnt")
            res.code=res.code+db_get(dk.."_code"); res.keys=res.keys+db_get(dk.."_keys")
            res.active_ms=res.active_ms+db_get(dk.."_active_ms")
            res.sess=res.sess+db_get(dk.."_sess")
            res.r_keys=res.r_keys+db_get(dk.."_r_keys")
            res.r_len=res.r_len+db_get(dk.."_r_len")
            res.r_ms=res.r_ms+db_get(dk.."_r_ms")
            res.r_n=res.r_n+db_get(dk.."_r_n")
            res.lan=res.lan+db_get(dk.."_lan")
            res.l1=res.l1+db_get(dk.."_l1"); res.l2=res.l2+db_get(dk.."_l2")
            res.l3=res.l3+db_get(dk.."_l3"); res.l4=res.l4+db_get(dk.."_l4")
            res.l_gt4=res.l_gt4+db_get(dk.."_l_gt4")
            res.c2=res.c2+db_get(dk.."_c2"); res.c3=res.c3+db_get(dk.."_c3")
            res.c4=res.c4+db_get(dk.."_c4"); res.c_other=res.c_other+db_get(dk.."_c_other")
            res.mlan=res.mlan+db_get(dk.."_mlan")
            res.ml1=res.ml1+db_get(dk.."_ml1"); res.ml2=res.ml2+db_get(dk.."_ml2")
            res.ml3=res.ml3+db_get(dk.."_ml3"); res.ml4=res.ml4+db_get(dk.."_ml4")
            res.ml_gt4=res.ml_gt4+db_get(dk.."_ml_gt4")
            res.mc2=res.mc2+db_get(dk.."_mc2"); res.mc3=res.mc3+db_get(dk.."_mc3")
            res.mc4=res.mc4+db_get(dk.."_mc4"); res.mc_other=res.mc_other+db_get(dk.."_mc_other")
            local ds = db_get(dk.."_spd"); if ds > res.spd then res.spd = ds end
        end
    end
    -- 轮池是**增量实时落库**的（on_keystroke / on_char_record 每键每字都在写），
    -- 因此这里不需要再补"当前未结算的一轮"——那样反而会重复计算。
    return res
end

-- ============================ UI ============================
-- 【v4 排版精简】按用户反馈重新排版：
--   ① 删掉 ▓░ 进度条——纯装饰、无信息量，却每条占 11 字符 × 9 条 ≈ 100 字符；
--   ② 分布不再每项一行，改为「标题 + 全部桶」挤在一行，9 行并为 2 行；
--   ③ 均速/峰速/字数/上屏 合并成一行；平均码长/平均击键/连打率 合并成一行；
--   ④ 方案与平台合并成一行。
--   动因：用户实测在微信里候选窗内容被截断（QQ 正常），排版越冗长越易触发；
--   精简后总长由 ~495 字符 / 26 行 降到 ~300 字符 / 14 行。
local function format_summary(title, data)
    if not data or data.cnt == 0 then
        return string.format("※ %s统计 · 效率仪表盘(%s)\n暂无数据", title, bj_stamp())
    end
    -- 速率类一律取**轮池**（只含产出过文字的轮），与计数类分开。
    -- 公式（与跟打器同一套，三个量同源同批、共用同一个分子「键数」）：
    --     速度 = 字数 / 时长 × 60      击键 = 键数 / 时长      码长 = 键数 / 字数
    -- 验证（虎魄原始字段 length=137, jianshu=305, time=92.845）：
    --     137/92.845×60 = 88.53 ✓   305/92.845 = 3.285 ✓   305/137 = 2.226 ✓
    -- 旧版把 `_keys` 与 `_active_ms` 按天相除：等于让查询、翻页、零星导航的时间也进
    -- 分母，那些时间不产出文字，于是速度与击键被系统性压低。
    local r_keys, r_len, r_ms = data.r_keys or 0, data.r_len or 0, data.r_ms or 0
    if r_ms <= 0 or r_keys <= 0 or r_len <= 0 then
        -- 兜底（如库刚清空、还没有成轮的数据）：退回按天口径，保证不自相矛盾。
        r_keys, r_len, r_ms = data.keys, data.len, data.active_ms
    end
    local r_sec = r_ms / 1000
    local avg_code = 0
    if r_len > 0 then avg_code = r_keys / r_len end
    local avg_kps = 0
    local avg_cpm = 0
    if r_sec > 0 then
        avg_kps = r_keys / r_sec
        avg_cpm = r_len / (r_sec / 60)
    end
    local peak_cpm = data.spd
    if peak_cpm < avg_cpm then peak_cpm = avg_cpm end

    -- 两个分布以**落字次数**（_lan）为分母，不是"上屏单元"（_cnt）。
    -- 旧版用 _cnt 做分母有两处错：
    --   ① 标点各算一个单元且是"1字/0码"，把 [1] 与连打率都带偏；
    --   ② 整句方案一次上屏就是一整句，单元码数恒 20+，码长分布必然 100% 落「其他」。
    -- 改为"每一次落字"后实测（沙箱 151 字）：2码29次 / 3码26次 / 4码6次 / 其余26次。
    -- 【v14】两个分布的分母 = **合并后的落字次数**（_mlan），不是原始记录数（_lan）。
    -- 标顶产生的那条 punct 记录已并进它顶出的正文，不再另算一次上屏；
    -- 而"空格提交后再单独打标点"的那种标点没有待顶内容，仍自成一次上屏。
    -- 判据是"是否同一个按键代"，见 capture 里 S.ks_gen 的说明。
    local lan = data.mlan or 0
    local function pct(n)
        if lan <= 0 then return 0 end
        return math.floor(n / lan * 100)
    end
    -- 连打率（打词率）= (字数 - 单字落字次数) / 字数，按**记录**口径（含标点记录），
    -- 与虎魄同义：同一篇 137 字报 89.8% = (137-14)/137，那 14 正是标点记录。
    local phrase_rate = 0
    local single_hits = data.l1 or 0
    if r_len > 0 then phrase_rate = (r_len - single_hits) / r_len * 100 end

    local raw_ver = rime_api.get_distribution_version() or ""
    local clean_name, clean_ver = process_platform_info(raw_software_name, raw_ver)
    local zwsp = "\226\128\139"
    return string.format(
        "※ %s统计 · 效率仪表盘(%s)" .. zwsp .. "\n" ..
        "───────────────" .. zwsp .. "\n" ..
        "📊 综合数据" .. zwsp .. "\n" ..
        "  均速:%.2f   上屏:%d" .. zwsp .. "\n" ..
        "  峰速:%.2f   字数:%d" .. zwsp .. "\n" ..
        "───────────────" .. zwsp .. "\n" ..
        "⚡ 核心效率" .. zwsp .. "\n" ..
        "  平均码长：%.2f 码/字" .. zwsp .. "\n" ..
        "  平均击键：%.2f 键/秒" .. zwsp .. "\n" ..
        "  连打率：%.1f %%" .. zwsp .. "\n" ..
        "───────────────" .. zwsp .. "\n" ..
        "📈 上屏字数分布" .. zwsp .. "\n" ..
        "  [1] %d%%  [2] %d%%  [3] %d%%  [4] %d%%  [+5] %d%%" .. zwsp .. "\n" ..
        "🎯 上屏码长分布" .. zwsp .. "\n" ..
        "  [2码] %d%%  [3码] %d%%  [4码] %d%%  [其他] %d%%" .. zwsp .. "\n" ..
        "───────────────" .. zwsp .. "\n" ..
        "◉ 方案：%s" .. zwsp .. "\n" ..
        "◉ 平台：%s %s" .. zwsp,
        title, bj_stamp(),
        avg_cpm, math.floor(data.cnt),
        peak_cpm, math.floor(data.len),
        avg_code, avg_kps, phrase_rate,
        pct(data.ml1), pct(data.ml2), pct(data.ml3), pct(data.ml4), pct(data.ml_gt4),
        pct(data.mc2), pct(data.mc3), pct(data.mc4), pct(data.mc_other),
        schema_name, clean_name, clean_ver
    )
end

-- ============================ 方案菜单统计视图 ============================
-- 使用内部占位符承载候选，不占用任何实际标点键。
-- 只在输入已结束时打开；避免改变正在输入的句子和 Tab 锁定状态。
local VIEW_INPUT = "\31"
local PERIODS = { {"今日", 1}, {"七日", 7}, {"三十日", 30}, {"近365日", 365}, {"累计", 0} }

local function close_view(ctx)
    if ctx:get_property("zqj_stats_view") == "" then return end
    local was_dumb = ctx:get_property("zqj_stats_was_dumb") == "1"
    ctx:set_property("zqj_stats_view", "")
    ctx:set_property("zqj_stats_was_dumb", "")
    ctx:set_option("tiger_stats_view", false)
    ctx:set_option("dumb", was_dumb)
    if ctx.input == VIEW_INPUT then ctx:clear() end
end

local function init(env)
    ensure_db_open()
    migrate_data()
    read_thresholds(env)
    local ctx = env.engine.context
    env._zqj_update = ctx.update_notifier:connect(function(c)
        capture(c)
        -- 鼠标选择/API 确认也不能把仪表盘插入应用。
        if c.input == "" then close_view(c) end
    end)
    env._zqj_commit = ctx.commit_notifier:connect(function(c) capture(c) end)
    env._zqj_option = ctx.option_update_notifier:connect(function(c, name)
        if name ~= "tiger_stats_view" then return end
        if not c:get_option(name) then close_view(c); return end
        if c:get_property("zqj_stats_view") ~= "" then return end
        if c.input ~= "" then c:set_option(name, false); return end
        capture(c)
        flush_hold()
        c:set_property("zqj_stats_was_dumb", c:get_option("dumb") and "1" or "0")
        c:set_property("zqj_stats_view", "1")
        c:set_option("dumb", true)
        c:push_input(VIEW_INPUT)
    end)
    pcall(function() capture(ctx) end)
end

local function fini(env)
    pcall(flush_hold)
    for _, name in ipairs({"_zqj_commit", "_zqj_update", "_zqj_option"}) do
        if env[name] then env[name]:disconnect(); env[name] = nil end
    end
    if db and db_loaded(db) then db:close() end
end

local function processor(key, env)
    if key:release() then return 2 end
    local ctx = env.engine.context
    local period = tonumber(ctx:get_property("zqj_stats_view"))
    if period then
        local kc = key.keycode
        if not (key:ctrl() or key:alt() or key:super()) then
            local direction
            if kc == 0xff53 or kc == 0xff54 or kc == 0xff09 then direction = 1 end
            if kc == 0xff51 or kc == 0xff52 or (kc == 0xff09 and key:shift()) then direction = -1 end
            if direction then
                ctx:set_property("zqj_stats_view", tostring((period - 1 + direction) % #PERIODS + 1))
                ctx:refresh_non_confirmed_composition()
                return 1
            end
            if kc == 0xff1b or kc == 0x20 or kc == 0xff0d then close_view(ctx); return 1 end
        end
        close_view(ctx)
    end
    -- 普通输入按原口径计数，标点不再充当查询指令。
    if type(key.keycode) == "number" then pcall(on_keystroke, key.keycode, ctx) end
    return 2
end

local function translator(input, seg, env)
    local period = tonumber(env.engine.context:get_property("zqj_stats_view"))
    if input ~= VIEW_INPUT or not period then return end
    local entry = PERIODS[period]
    local candidate = Candidate("stat", seg.start, seg._end,
        format_summary(entry[1], aggregate_stats(entry[2])), "←/→ 切换周期 · Esc/空格关闭")
    candidate.preedit = "统计"
    yield(candidate)
end

return { init = init, func = translator, fini = fini, processor = processor }
