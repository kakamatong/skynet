local skynet = require "skynet"
require "skynet.manager"
local socket = require "skynet.socket"
local sproto = require "sproto"
local netpack = require "skynet.netpack"
local crypt = require "skynet.crypt"
local aes = require "aes"
local websocket = require "http.websocket"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"

--local WATCHDOG -- watchdog 服务
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

local function callWatchdog(subcmd,  ...)
    local watchdog = skynet.localname(".watchdog")
    if watchdog then
        skynet.call(watchdog, 'lua', subcmd, ...)
    else
        LOG.error("Watchdog not found")
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
    callWatchdog("socket", "client_connected", fd, addr)
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
    callWatchdog("socket", "client_disconnected", fd)
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

-- WebSocket消息打包
local function pack_ws_message(msg)
    return string.pack(">s2", msg)
end

-- WebSocket消息解包
local function unpack_ws_message(msg)
    return string.unpack(">s2", msg)
end

-- 处理WebSocket消息
local function handle_ws_message(ws, message)
    -- 转换WebSocket消息为统一格式
    local msg = pack_ws_message(message)
    local sz = #msg
    
    -- 使用相同的消息处理逻辑
    handler.message(ws.id, msg, sz)
end

-- 发送WebSocket消息
local function send_ws_message(fd, message)
    local ws = connections[fd].ws
    if ws then
        ws:send_binary(message)
    end
end

-- 修改socket.write函数，支持WebSocket
local _socket_write = socket.write
socket.write = function(fd, msg)
    local conn = connections[fd]
    if conn.ws then
        send_ws_message(fd, msg)
    else
        _socket_write(fd, msg)
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
    init_proto()
    
    -- 启动监听
    local socket_port = CONFIG.game_server.socket_port
    local websocket_port = CONFIG.game_server.websocket_port

    -- 启动Socket监听
    local listenfd = socket.listen("0.0.0.0", socket_port)
    LOG.info("Gate service(Socket) listening on port %d", socket_port)
    
    socket.start(listenfd, function(fd, addr)
        handler.connect(fd, addr)
        socket.start(fd)
        socket.onclose(fd, function()
            handler.disconnect(fd)
        end)
    end)

    -- WebSocket处理函数
    local handle = {}
    
    function handle.connect(id)
        local addr = websocket.addrinfo(id)
        handler.connect(id, addr)
        -- 注意: connections[id] 在 handler.connect 中创建
        connections[id].ws = true  -- 标记为 websocket 连接
    end
    
    function handle.message(id, message, op)
        -- 将 WebSocket 消息转换为统一格式
        local msg = string.pack(">s2", message)
        local sz = #msg
        handler.message(id, msg, sz)
    end
    
    function handle.close(id, code, reason)
        LOG.info("WebSocket closed: fd=%d, code=%s, reason=%s", id, code, reason)
        handler.disconnect(id)
    end
    
    function handle.error(id, err)
        LOG.error("WebSocket error: fd=%d, error=%s", id, err)
        handler.disconnect(id)
    end

    function handle.warning(id, size)
        LOG.warn("WebSocket buffer warning: fd=%d, size=%d", id, size)
    end

    function handle.handshake(id, header, url)
        LOG.info("WebSocket handshake: fd=%d, url=%s", id, url)
        -- 可以在这里处理 header 中的额外信息
    end

    -- 重写 socket.write 支持 WebSocket
    local _socket_write = socket.write
    socket.write = function(fd, msg)
        local conn = connections[fd]
        if conn and conn.ws then
            -- 使用 websocket.write 发送二进制消息
            websocket.write(fd, msg, "binary")
        else
            -- 使用普通 Socket 发送
            _socket_write(fd, msg)
        end
    end

    -- 启动WebSocket监听
    local ws_listen_fd = socket.listen("0.0.0.0", websocket_port)
    LOG.info("Gate service(WebSocket) listening on port %d", websocket_port)
    
    socket.start(ws_listen_fd, function(fd, addr)
        local ok, err = websocket.accept(
            fd,                -- socket id
            handle,           -- 处理函数表
            "ws",            -- 协议类型 ("ws" 或 "wss")
            addr             -- 客户端地址
        )
        
        if not ok then
            LOG.error("WebSocket accept failed: fd=%d, err=%s", fd, err)
            socket.close(fd)
        end
    end)

    -- 启动心跳检查
    skynet.fork(function()
        while true do
            local now = skynet.now()
            for fd, conn in pairs(connections) do
                if now - conn.last_heartbeat > 100 * 100 then -- 10秒超时
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