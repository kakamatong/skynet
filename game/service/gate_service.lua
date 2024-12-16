local skynet = require "skynet"
require "skynet.manager"
local socket = require "skynet.socket"
local sproto = require "sproto"
local netpack = require "skynet.netpack"
local crypt = require "skynet.crypt"
local aes = require "aes" -- 需要实现AES加密模块

local WATCHDOG -- watchdog 服务
local PROTO -- 协议对象
local connections = {} -- 连接管理 {fd = {fd=,addr=,agent=,client=,status=}}

local CMD = {}
local handler = {}

-- 加密密钥
local SECRET_KEY = "your_secret_key"

-- 解密消息
local function decrypt_message(msg)
    return aes.decrypt(msg, SECRET_KEY)
end

-- 加密消息
local function encrypt_message(msg)
    return aes.encrypt(msg, SECRET_KEY)
end

-- 初始化协议
local function init_proto()
    local f = io.open("proto/game.sproto", "r")
    local content = f:read("*a")
    f:close()
    
    PROTO = sproto.parse(content)
end

-- 消息转发
local function forward_message(fd, msg, sz)
    local message = netpack.tostring(msg, sz)
    
    -- 解密消息
    message = decrypt_message(message)
    
    local proto_id, proto_msg = string.unpack(">I2", message)
    
    -- 根据协议ID判断服务类型
    local service_name
    if proto_id < 10000 then
        service_name = ".login"
    elseif proto_id < 20000 then
        service_name = ".game"
    else
        service_name = ".chat"
    end
    
    -- 解析协议
    local proto_name = PROTO:decode_message_name(proto_id)
    local proto_content = PROTO:decode_message(proto_id, proto_msg)
    
    -- 添加连接类型
    local conn = connections[fd]
    proto_content.mode = conn.mode
    
    -- 转发消息
    if conn.agent then
        skynet.redirect(conn.agent, conn.client, "client", fd, msg, sz)
    else
        local service = skynet.queryservice(service_name)
        local ok, result = pcall(skynet.call, service, "lua", "handle_message", 
            fd, proto_name, proto_content)
        
        if ok and result then
            -- 加密响应
            local response = PROTO:encode_message(proto_name .. "_response", result)
            response = encrypt_message(response)
            socket.write(fd, response)
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
    WATCHDOG = skynet.queryservice(".watchdog")
    init_proto()
    
    -- 启动监听
    local socket_port = CONFIG.game_server.socket_port
    local websocket_port = CONFIG.game_server.websocket_port

    -- 启动Socket监听
    local listenfd = socket.listen("0.0.0.0", socket_port)
    LOG.info("Gate service(Socket) listening on port %d", socket_port)

    -- 启动WebSocket监听
    local websocket = require "http.websocket"
    local handle = websocket.listen("0.0.0.0", websocket_port, {
        open = function(ws)
            handler.connect(ws.id, ws.addr)
        end,
        message = function(ws, msg)
            handler.message(ws.id, msg, #msg)
        end,
        close = function(ws)
            handler.disconnect(ws.id)
        end,
    })
    LOG.info("Gate service(WebSocket) listening on port %d", websocket_port)
    
    -- 启动心跳检查
    skynet.fork(function()
        while true do
            for fd, conn in pairs(connections) do
                if skynet.now() - conn.last_heartbeat > 100 * 100 then -- 10秒超时
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