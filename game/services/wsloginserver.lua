local skynet = require "skynet"
local websocket = require "http.websocket"
local socket = require "skynet.socket"
local crypt = require "skynet.crypt"
require "skynet.manager"
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
local function handle_ws_connection(fd, addr, conf)
    local ok, token, secret = pcall(ws_auth, fd)
    if not ok then
        websocket.write(fd, "401 Unauthorized", "text")
        websocket.close(fd)
        return
    end

    -- 调用认证逻辑
    local ok, srv, uid = pcall(conf.auth_handler, token)
    if not ok then
        websocket.write(fd, "403 Forbidden", "text")
        websocket.close(fd)
        return
    end

    -- 调用登录逻辑
    local ok, subid = pcall(conf.login_handler, srv, uid, secret)
    if not ok then
        websocket.write(fd, "406 Not Acceptable", "text")
        websocket.close(fd)
        return
    end

    -- 返回成功
    websocket.write(fd, "200 "..crypt.base64encode(subid), "text")
end

local function login(conf)
    assert(conf.login_handler)
	assert(conf.command_handler)
    assert(conf.host)
    assert(conf.port)
    assert(conf.name)

    skynet.start(function()
        -- 添加WebSocket监听
        local id = socket.listen(conf.host, conf.port)
        skynet.error(string.format("WebSocket login server listening on %s:%d", conf.host, conf.port))
        
        socket.start(id, function(fd, addr)
            local ok, err = websocket.accept(fd, {
                handshake = function(_, header, url)
                    return true  -- 接受所有连接
                end,
                connected = function(fd)
                    pcall(handle_ws_connection, fd, addr, conf)
                end,
                closed = function(fd)
                    websocket.close(fd)
                end
            })
            
            if not ok then
                skynet.error("WebSocket connection failed: "..tostring(err))
            end
        end)

        skynet.dispatch("lua", function(_,source,command, ...)
            skynet.ret(skynet.pack(conf.command_handler(command, ...)))
        end)

        local name = "." .. (conf.name or 'wslogin')
        skynet.register(name)
    end) 
    
end

return login