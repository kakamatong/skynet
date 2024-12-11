local skynet = require "skynet"
require "skynet.manager"
local socket = require "skynet.socket"
local websocket = require "http.websocket"
local crypt = require "skynet.crypt"

local MODE = ...  -- 启动参数，可以是 "socket" 或 "websocket"

local CMD = {}
local users = {}  -- 在线用户表 {[uid] = {fd = fd, login_time = time, ...}}

-- 用户认证
function CMD.auth(username, password)
    -- 这里调用数据库验证用户名密码
    local db = skynet.queryservice(".db")
    local sql = string.format(
        "SELECT uid, password, salt FROM users WHERE username='%s' LIMIT 1",
        username
    )
    local res = skynet.call(db, "lua", "mysql_query", sql)
    
    if not res or #res == 0 then
        return false, "User not found"
    end
    
    local user = res[1]
    local encrypted = crypt.hashkey(password .. user.salt)
    
    if encrypted ~= user.password then
        return false, "Invalid password"
    end
    
    return true, user
end

-- 用户登录
function CMD.login(fd, uid, mode)
    if users[uid] then
        -- 如果用户已登录，踢出旧连接
        local old_fd = users[uid].fd
        if mode == "socket" then
            socket.close(old_fd)
        else
            websocket.close(old_fd)
        end
    end
    
    users[uid] = {
        fd = fd,
        mode = mode,
        login_time = skynet.now(),
        last_heartbeat = skynet.now()
    }
    
    -- 通知游戏服务有新用户登录
    local game = skynet.queryservice(".game")
    skynet.call(game, "lua", "on_user_login", uid)
    
    return true
end

-- 用户登出
function CMD.logout(uid)
    if users[uid] then
        local fd = users[uid].fd
        users[uid] = nil
        
        -- 通知游戏服务用户登出
        local game = skynet.queryservice(".game")
        skynet.call(game, "lua", "on_user_logout", uid)
        
        return true, fd
    end
    return false
end

-- 处理Socket连接
local function handle_socket(fd, addr)
    socket.start(fd)
    
    -- 读取登录请求
    local data = socket.read(fd)
    if not data then
        socket.close(fd)
        return
    end
    
    local msg = skynet.unpack(data)
    local ok, user = CMD.auth(msg.username, msg.password)
    
    if not ok then
        socket.write(fd, skynet.pack({code = 1, msg = user}))
        socket.close(fd)
        return
    end
    
    -- 登录成功
    CMD.login(fd, user.uid, "socket")
    socket.write(fd, skynet.pack({code = 0, uid = user.uid}))
end

-- 处理WebSocket连接
local function handle_websocket(fd, addr)
    local ok, msg = websocket.read(fd)
    if not ok then
        websocket.close(fd)
        return
    end
    
    msg = skynet.unpack(msg)
    local ok, user = CMD.auth(msg.username, msg.password)
    
    if not ok then
        websocket.write(fd, skynet.pack({code = 1, msg = user}))
        websocket.close(fd)
        return
    end
    
    -- 登录成功
    CMD.login(fd, user.uid, "websocket")
    websocket.write(fd, skynet.pack({code = 0, uid = user.uid}))
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        end
    end)
    
    -- 根据模式启动不同的监听服务
    if MODE == "socket" then
        local port = skynet.getenv "login_port" or 8001
        local listenfd = socket.listen("0.0.0.0", port)
        skynet.error("Login service(socket) listening on port " .. port)
        socket.start(listenfd, handle_socket)
    else
        local port = skynet.getenv "login_ws_port" or 8002
        local protocol = websocket.protocol
        local id = socket.listen("0.0.0.0", port)
        skynet.error("Login service(websocket) listening on port " .. port)
        socket.start(id, function(fd, addr)
            local handle = protocol.accept(fd, addr, handle_websocket, {})
            if handle then
                handle()
            end
        end)
    end
    
    -- 启动心跳检查
    skynet.fork(function()
        while true do
            for uid, info in pairs(users) do
                if skynet.now() - info.last_heartbeat > 600 * 100 then  -- 60秒超时
                    CMD.logout(uid)
                end
            end
            skynet.sleep(100)  -- 每10秒检查一次
        end
    end)
    
    skynet.register ".login"
end) 