local skynet = require "skynet"
local sproto = require "sproto"

local gate
local client
local fd
local CMD = {}
local REQUEST = {}

local function send_package(pack)
    socket.write(fd, pack)
end

function CMD.start(gate_, client_, fd_)
    gate = gate_
    client = client_
    fd = fd_
    
    -- 可以在这里做一些初始化工作
    return true
end

function CMD.disconnect()
    -- 处理断开连接的逻辑
    -- 保存数据等
    skynet.exit()
end

function CMD.handle_message(msg_type, msg)
    local f = REQUEST[msg_type]
    if f then
        return f(msg)
    else
        LOG.error("Unknown message type: %s", msg_type)
    end
end

-- 注册消息处理函数
REQUEST["game.move"] = function(msg)
    -- 处理移动消息
    return { ok = true }
end

REQUEST["game.attack"] = function(msg)
    -- 处理攻击消息
    return { ok = true }
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        end
    end)
end) 