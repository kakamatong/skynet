local skynet = require "skynet"
local websocket = require "http.websocket"
local socket = require "skynet.socket"
local crypt = require "skynet.crypt"
local login = require "snax.loginserver"

local server = {
    host = "0.0.0.0",
    port = 8002,  -- WebSocket登录端口
    name = "ws_login_master",
    multilogin = false,
}

local server_list = {}
local user_online = {}

-- 认证处理器（保持与TCP版一致）
function server.auth_handler(token)
    local user, srv, pwd = token:match("([^@]+)@([^:]+):(.+)")
    user = crypt.base64decode(user)
    srv = crypt.base64decode(srv)
    pwd = crypt.base64decode(pwd)
    assert(pwd == "password", "Invalid password")
    return srv, user
end

-- 登录处理器（保持与TCP版一致）
function server.login_handler(srv, uid, secret)
    local gameserver = assert(server_list[srv], "Unknown server")
    local last = user_online[uid]
    if last then
        skynet.call(last.address, "lua", "kick", uid, last.subid)
    end
    local subid = tostring(skynet.call(gameserver, "lua", "login", uid, secret))
    user_online[uid] = { address = gameserver, subid = subid }
    return subid
end

-- WebSocket认证流程
local function ws_auth(fd)
    -- 生成挑战
    local challenge = crypt.randomkey()
    websocket.write(fd, crypt.base64encode(challenge), "binary")

    -- 读取客户端密钥
    local client_key = websocket.read(fd)
    client_key = crypt.base64decode(client_key)
    if #client_key ~= 8 then
        error("Invalid client key length")
    end

    -- 生成服务端密钥
    local server_key = crypt.randomkey()
    websocket.write(fd, crypt.base64encode(crypt.dhexchange(server_key)), "binary")

    -- 计算共享密钥
    local secret = crypt.dhsecret(client_key, server_key)

    -- 验证HMAC
    local response = websocket.read(fd)
    local hmac = crypt.hmac64(challenge, secret)
    if hmac ~= crypt.base64decode(response) then
        error("HMAC validation failed")
    end

    -- 解密Token
    local etoken = websocket.read(fd)
    local token = crypt.desdecode(secret, crypt.base64decode(etoken))
    return token, secret
end

-- WebSocket连接处理器
local function handle_ws_connection(fd, addr)
    local ok, token, secret = pcall(ws_auth, fd)
    if not ok then
        websocket.write(fd, "401 Unauthorized", "text")
        websocket.close(fd)
        return
    end

    -- 调用认证逻辑
    local ok, srv, uid = pcall(server.auth_handler, token)
    if not ok then
        websocket.write(fd, "403 Forbidden", "text")
        websocket.close(fd)
        return
    end

    -- 调用登录逻辑
    local ok, subid = pcall(server.login_handler, srv, uid, secret)
    if not ok then
        websocket.write(fd, "406 Not Acceptable", "text")
        websocket.close(fd)
        return
    end

    -- 返回成功
    websocket.write(fd, "200 "..crypt.base64encode(subid), "text")
end

-- 服务命令处理器
local CMD = {}

function CMD.register_gate(srv, addr)
    server_list[srv] = addr
end

function server.command_handler(cmd, ...)
    local f = assert(CMD[cmd])
    return f(...)
end

-- 启动服务
login(server)

-- 添加WebSocket监听
skynet.start(function()
    local id = socket.listen(server.host, server.port)
    skynet.error(string.format("WebSocket login server listening on %s:%d", server.host, server.port))
    
    socket.start(id, function(fd, addr)
        local ok, err = websocket.accept(fd, {
            handshake = function(_, header, url)
                return true  -- 接受所有连接
            end,
            connected = function(fd)
                pcall(handle_ws_connection, fd, addr)
            end,
            closed = function(fd)
                websocket.close(fd)
            end
        })
        
        if not ok then
            skynet.error("WebSocket connection failed: "..tostring(err))
        end
    end)
end) 