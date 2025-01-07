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
    local watchdog = skynet.queryservice(".watchdog")
    skynet.send(watchdog, "lua", "client_connected", fd, addr)
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
    local watchdog = skynet.queryservice(".watchdog")
    skynet.send(watchdog, "lua", "client_disconnected", fd)
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
    --WATCHDOG = skynet.queryservice(".watchdog")
    init_proto()
    
    -- 启动监听
    local socket_port = CONFIG.game_server.socket_port
    local websocket_port = CONFIG.game_server.websocket_port

    -- 启动Socket监听
    local listenfd = socket.listen("0.0.0.0", socket_port)
    LOG.info("Gate service(Socket) listening on port %d", socket_port)

    -- WebSocket处理函数
    local handle = {}
    
    -- 处理WebSocket连接打开
    function handle.connect(ws)
        local fd = ws.id
        LOG.info("New websocket connected: %s, fd: %d", ws.addr, fd)
        
        connections[fd] = {
            fd = fd,
            addr = ws.addr,
            status = "connected",
            connect_time = skynet.now(),
            last_heartbeat = skynet.now(),
            ws = ws
        }
        
        local watchdog = skynet.queryservice(".watchdog")
        skynet.send(watchdog, "lua", "client_connected", fd, ws.addr)
    end
    
    -- 处理WebSocket消息
    function handle.message(ws, message)
        local fd = ws.id
        local conn = connections[fd]
        if not conn then
            LOG.error("Connection not found: fd: %d", fd)
            return
        end
        
        -- 更新心跳时间
        conn.last_heartbeat = skynet.now()
        
        -- 将消息转换为统一格式
        local msg = string.pack(">s2", message)
        local sz = #msg
        
        -- 使用统一的消息处理逻辑
        handler.message(fd, msg, sz)
    end
    
    -- 处理WebSocket连接关闭
    function handle.close(ws, code, reason)
        local fd = ws.id
        LOG.info("Websocket closed: fd: %d, code: %s, reason: %s", fd, code, reason)
        handler.disconnect(fd)
    end
    
    -- 处理WebSocket错误
    function handle.error(ws, error_msg)
        local fd = ws.id
        LOG.error("Websocket error: fd: %d, error: %s", fd, error_msg)
        handler.disconnect(fd)
    end
    
    -- 处理WebSocket连接
    local function handle_ws_socket(fd, addr)
        socket.start(fd)
        local read = sockethelper.readfunc(fd)
        local write = sockethelper.writefunc(fd)
        
        local code, url, method, header = httpd.read_request(read)
        if not code then
            socket.close(fd)
            return
        end
        
        if header and header.upgrade ~= "websocket" then
            write("HTTP/1.1 400 Bad Request\r\n\r\n")
            socket.close(fd)
            return
        end
        
        local ws = websocket.new(fd, header, read, write, addr)
        if not ws then
            socket.close(fd)
            return
        end
        
        -- 处理连接建立
        local fd = ws.id
        LOG.info("New websocket connected: %s, fd: %d", addr, fd)
        
        connections[fd] = {
            fd = fd,
            addr = addr,
            status = "connected",
            connect_time = skynet.now(),
            last_heartbeat = skynet.now(),
            ws = ws
        }
        
        local watchdog = skynet.queryservice(".watchdog")
        skynet.send(watchdog, "lua", "client_connected", fd, addr)
        
        -- 开始接收消息
        while true do
            local success, message = pcall(ws.read, ws)
            if not success or not message then
                break
            end
            
            -- 处理消息
            local fd = ws.id
            local conn = connections[fd]
            if not conn then
                break
            end
            
            -- 更新心跳时间
            conn.last_heartbeat = skynet.now()
            
            -- 将消息转换为统一格式
            local msg = string.pack(">s2", message)
            local sz = #msg
            
            -- 使用统一的消息处理逻辑
            handler.message(fd, msg, sz)
        end
        
        -- 连接断开
        handler.disconnect(fd)
        socket.close(fd)
    end
    
    -- 启动WebSocket监听
    local ws_listen_fd = socket.listen("0.0.0.0", websocket_port)
    LOG.info("Gate service(WebSocket) listening on port %d", websocket_port)
    
    socket.start(ws_listen_fd, function(fd, addr)
        skynet.fork(handle_ws_socket, fd, addr)
    end)
    
    -- 修改socket.write函数，支持WebSocket
    local _socket_write = socket.write
    socket.write = function(fd, msg)
        local conn = connections[fd]
        if conn and conn.ws then
            conn.ws:write_binary(msg)
        else
            _socket_write(fd, msg)
        end
    end
    
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