-- game/preload.lua
local skynet = require "skynet"

-- 全局配置
local config = {}
_G.CONFIG = config

-- 全局常量定义
_G.GAME_CONST = {
    -- 玩家状态
    PLAYER_STATE = {
        OFFLINE = 0,    -- 离线
        ONLINE = 1,     -- 在线
        GAMING = 2,     -- 游戏中
        AFK = 3,        -- 暂离
    },
    
    -- 错误码
    ERROR_CODE = {
        SUCCESS = 0,            -- 成功
        FAILED = 1,            -- 失败
        INVALID_PARAM = 2,     -- 无效参数
        NOT_FOUND = 3,         -- 未找到
        NO_PERMISSION = 4,     -- 无权限
        TIMEOUT = 5,           -- 超时
        SERVER_ERROR = 6,      -- 服务器错误
    },
    
    -- 聊天频道
    CHAT_CHANNEL = {
        WORLD = 1,     -- 世界频道
        PRIVATE = 2,   -- 私聊频道
        TEAM = 3,      -- 队伍频道
        SYSTEM = 4,    -- 系统频道
    },
}

-- 全局工具函数
_G.UTILS = {
    -- 深拷贝
    deepcopy = function(orig)
        local copy
        if type(orig) == 'table' then
            copy = {}
            for orig_key, orig_value in next, orig, nil do
                copy[UTILS.deepcopy(orig_key)] = UTILS.deepcopy(orig_value)
            end
            setmetatable(copy, UTILS.deepcopy(getmetatable(orig)))
        else
            copy = orig
        end
        return copy
    end,
    
    -- 表合并
    table_merge = function(t1, t2)
        for k, v in pairs(t2) do
            t1[k] = v
        end
        return t1
    end,
    
    -- 字符串分割
    string_split = function(str, delimiter)
        local result = {}
        local from = 1
        local delim_from, delim_to = string.find(str, delimiter, from)
        while delim_from do
            table.insert(result, string.sub(str, from, delim_from - 1))
            from = delim_to + 1
            delim_from, delim_to = string.find(str, delimiter, from)
        end
        table.insert(result, string.sub(str, from))
        return result
    end,
}

-- 日志工具
local LOG_LEVEL = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
}

_G.LOG = {
    debug = function(fmt, ...)
        if config.debug then
            skynet.error(string.format("[DEBUG] " .. fmt, ...))
        end
    end,
    
    info = function(fmt, ...)
        skynet.error(string.format("[INFO] " .. fmt, ...))
    end,
    
    warn = function(fmt, ...)
        skynet.error(string.format("[WARN] " .. fmt, ...))
    end,
    
    error = function(fmt, ...)
        skynet.error(string.format("[ERROR] " .. fmt, ...))
    end,
}

-- 性能统计
_G.STAT = {
    -- 计时开始
    timing_start = function(key)
        if not _G.STAT.timers then
            _G.STAT.timers = {}
        end
        _G.STAT.timers[key] = skynet.now()
    end,
    
    -- 计时结束
    timing_end = function(key)
        if not _G.STAT.timers or not _G.STAT.timers[key] then
            return 0
        end
        local cost = skynet.now() - _G.STAT.timers[key]
        _G.STAT.timers[key] = nil
        return cost
    end,
    
    -- 计数增加
    counter_inc = function(key, value)
        if not _G.STAT.counters then
            _G.STAT.counters = {}
        end
        _G.STAT.counters[key] = (_G.STAT.counters[key] or 0) + (value or 1)
    end,
}

-- 错误处理
_G.ERROR = {
    -- 创建错误对象
    new = function(code, msg)
        return {
            code = code,
            msg = msg,
        }
    end,
    
    -- 抛出错误
    throw = function(code, msg)
        error(string.format("ERROR[%d]: %s", code, msg))
    end,
}

-- 在这里可以添加更多的全局初始化内容
LOG.info("Preload completed") 