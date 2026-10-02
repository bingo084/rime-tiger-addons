-- 兼容 lua_processor@*tiger_kf_processor 的模块化写法。
-- librime-lua 对 `*` 形式会执行 require()，并在返回的 table 上取 func 字段，
-- 因此这里必须返回 { func = ... }，不能直接返回 tiger_kf 模块本身。
local M = require("tiger_kf")
return { init = M.init, func = M.processor, fini = M.fini }
