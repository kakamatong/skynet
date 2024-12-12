local skynet = require "skynet"
require "skynet.manager"
local socket = require "skynet.socket"
local sproto = require "sproto"
local netpack = require "skynet.netpack"

local WATCHDOG -- watchdog 服务
local PROTO -- 协议对象
local connections = {} -- 连接管理 {fd = {fd=,addr=,agent=,client=,status=}}
local forwarding = {} -- 消息转发表 {msgname = service_name}

local CMD = {}
local handler = {}

-- 初始化协议
local function init_proto()
    local f = io.open("proto/game.sproto", "r")
    local content = f:read("*a")
    f:close()
    
    PROTO = sproto.parse(content)
    
    -- 初始化消息转发表
    forwarding = {
        ["login.auth"] = ".login",
        ["game.enter"] = ".game",
        ["chat.send"] = ".chat",
        -- 添加更多消息路由
    }
end

-- 消息转发
local function forward_message(fd, msg, sz)
    local message = netpack.tostring(msg, sz)
    local proto_id, proto_msg = string.unpack(">I2", message)
    
    -- 解析协议
    local proto_name = PROTO:decode_message_name(proto_id)
    local proto_content = PROTO:decode_message(proto_id, proto_msg)
    
    -- 查找目标服务
    local service_name = forwarding[proto_name]
    if not service_name then
        LOG.error("Unknown message type: %s", proto_name)
        return
    end
    
    -- 转发消息
    local conn = connections[fd]
    if conn.agent then
        -- 已经有agent，直接转发
        skynet.redirect(conn.agent, conn.client, "client", fd, msg, sz)
    else
        -- 没有agent，通过目标服务处理
        local service = skynet.queryservice(service_name)
        local ok, result = pcall(skynet.call, service, "lua", "handle_message", 
            fd, proto_name, proto_content)
        
        if ok then
            -- 发送响应
            if result then
                local response = PROTO:encode_message(proto_name .. "_response", result)
                socket.write(fd, response)
            end
        else
            LOG.error("Forward message failed: %s", result)
        end
    end
end

-- 处理客户端连接
function handler.connect(fd, addr)
    LOG.info("New client connected: %s, fd: %d", addr, fd)
    
    connections[fd] = {
        fd = fd,
        addr = addr,
        status = "connected",
        connect_time = skynet.now(),
        last_heartbeat = skynet.now(),
    }
    
    skynet.send(WATCHDOG, "lua", "client_connected", fd, addr)
end

-- 处理客户端断开
function handler.disconnect(fd)
    LOG.info("Client disconnected: fd: %d", fd)
    
    local conn = connections[fd]
    if conn then
        if conn.agent then
            skynet.call(conn.agent, "lua", "disconnect")
        end
        connections[fd] = nil
    end
    
    skynet.send(WATCHDOG, "lua", "client_disconnected", fd)
end

-- 处理客户端消息
function handler.message(fd, msg, sz)
    local conn = connections[fd]
    if not conn then
        LOG.error("Connection not found: fd: %d", fd)
        return
    end
    
    -- 更新心跳时间
    conn.last_heartbeat = skynet.now()
    
    -- 转发消息
    forward_message(fd, msg, sz)
end

-- 关闭连接
function CMD.kick(fd, reason)
    local conn = connections[fd]
    if conn then
        LOG.info("Kick client: fd: %d, reason: %s", fd, reason)
        socket.close(fd)
        connections[fd] = nil
    end
end

-- 绑定Agent
function CMD.bind_agent(fd, agent, client)
    local conn = connections[fd]
    if conn then
        conn.agent = agent
        conn.client = client
        conn.status = "binded"
    end
end

-- 解绑Agent
function CMD.unbind_agent(fd)
    local conn = connections[fd]
    if conn then
        conn.agent = nil
        conn.client = nil
        conn.status = "connected"
    end
end

-- 广播消息
function CMD.broadcast(msg, exclude_fd)
    for fd, conn in pairs(connections) do
        if fd ~= exclude_fd and conn.status == "connected" then
            socket.write(fd, msg)
        end
    end
end

skynet.start(function()
    -- 注册协议
    skynet.register_protocol {
        name = "client",
        id = skynet.PTYPE_CLIENT,
        unpack = netpack.unpack,
        dispatch = function(_, _, fd, msg, sz)
            handler.message(fd, msg, sz)
        end
    }
    
    -- 初始化
    WATCHDOG = skynet.queryservice("watchdog")
    init_proto()
    
    -- 启动监听
    local port = tonumber(skynet.getenv "gate_port") or 8888
    local listenfd = socket.listen("0.0.0.0", port)
    LOG.info("Gate service listening on port %d", port)
    
    socket.start(listenfd, function(fd, addr)
        socket.start(fd)
        handler.connect(fd, addr)
    end)
    
    -- 启动心跳检查
    skynet.fork(function()
        while true do
            for fd, conn in pairs(connections) do
                if skynet.now() - conn.last_heartbeat > 600 * 100 then -- 60秒超时
                    CMD.kick(fd, "heartbeat timeout")
                end
            end
            skynet.sleep(100) -- 每10秒检查一次
        end
    end)
    
    -- 注册命令处理
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        else
            LOG.error("Unknown command: %s", cmd)
        end
    end)
    
    skynet.register ".gate"
end) 