-- 击键计数处理器包装：复用 zqj_stats 模块的共享状态与计数逻辑。
-- 必须在方案补丁的 engine/processors 中排到**链首**（所有方案处理器之前），
-- 且本处理器恒返回 kNoop（放行），只旁路计数，不影响任何输入行为。
return { func = require("zqj_stats").processor }
