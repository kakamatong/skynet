local skynet = require "skynet"
local websocket = require "http.websocket"
local socket = require "skynet.socket"
local crypt = require "skynet.crypt"
require "skynet.manager"
-- WebSocket认证流程
local function ws_auth(fd)
    -- 生成挑战
    local challenge = crypt.randomkey()
    local challenge_b64 = crypt.base64encode(challenge)
    LOG.info("login challenge_b64 %s", challenge_b64)
    websocket.write(fd, challenge_b64, "binary")

    -- 读取客户端密钥
    local client_key = websocket.read(fd)
    LOG.info("login client_key_b64 %s", client_key)
    
    client_key = crypt.base64decode(client_key)
    if #client_key ~= 8 then
        LOG.info("Invalid client key length")
        error("Invalid client key length")
    end
    -- 生成服务端密钥
    local server_key = crypt.randomkey()
    local server_key_dh = crypt.dhexchange(server_key)
    local server_key_b64 = crypt.base64encode(server_key_dh)
    LOG.info("login server_key_b64 %s", server_key_b64)
    websocket.write(fd, server_key_b64, "binary")

    -- 计算共享密钥
    local secret = crypt.dhsecret(client_key, server_key)
    -- secret = string.char(0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08)
    -- local tmpToken = "dGVzdFVzZXI=@Z2FtZVNlcnZlcg==:cGFzc3dvcmQ="
    -- local tmpToken2 = crypt.desencode(secret, tmpToken)
    -- LOG.info("auth tmpToken2 %s", crypt.base64encode(tmpToken2))
    
    -- 验证HMAC
    local response = websocket.read(fd)
    local hmac = crypt.hmac64(challenge, secret)
    local client_hmac = crypt.base64decode(response)
    if hmac ~= client_hmac then
        error("HMAC validation failed")
    end
    
    LOG.info("auth handshake success secret %s", crypt.hexencode(secret))
    -- 解密Token
    local etoken = websocket.read(fd)
    LOG.info("auth etoken %s", etoken)
    local token = crypt.desdecode(secret, crypt.base64decode(etoken))
    LOG.info("auth token %s", token)
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
        LOG.info(string.format("WebSocket login server listening on %s:%d", conf.host, conf.port))
        
        socket.start(id, function(fd, addr)
            LOG.info("login websocket add %s", addr)
            local ok, err = websocket.accept(fd, {
                handshake = function(fd, header, url)
                    LOG.info("login handshake %s",url)
                    pcall(handle_ws_connection, fd, addr, conf)
                    return true  -- 接受所有连接
                end,
                connect = function(fd)
                    LOG.info("login connect %d",fd)
                end,
                closed = function(fd)
                    websocket.close(fd)
                end
            })
            
            if not ok then
                LOG.error("WebSocket connection failed: "..tostring(err))
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