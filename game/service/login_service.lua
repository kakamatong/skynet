local skynet = require "skynet"
require "skynet.manager"
local crypt = require "skynet.crypt"

local users = {}  -- 在线用户表 {[uid] = {fd = fd, login_time = time, mode = "socket"/"websocket" ...}}
local CMD = {}

-- 用户认证
function CMD.auth(fd, msg, mode)
    local username = msg.username
    local password = msg.password
    
    -- 这里调用数据库验证用户名密码
    local db = skynet.queryservice(".db")
    local sql = string.format(
        "SELECT uid, password, salt FROM users WHERE username='%s' LIMIT 1",
        username
    )
    local res = skynet.call(db, "lua", "mysql_query", sql)
    
    if not res or #res == 0 then
        return { code = 1, msg = "User not found" }
    end
    
    local user = res[1]
    local encrypted = crypt.hashkey(password .. user.salt)
    
    if encrypted ~= user.password then
        return { code = 1, msg = "Invalid password" }
    end
    
    -- 如果用户已登录，踢出旧连接
    if users[user.uid] then
        local old_fd = users[user.uid].fd
        skynet.call(".gate", "lua", "kick", old_fd, "login from other device")
    end
    
    -- 记录用户登录状态
    users[user.uid] = {
        fd = fd,
        mode = mode,  -- 记录连接类型
        login_time = skynet.now(),
        username = username,
        last_heartbeat = skynet.now()
    }
    
    -- 分配agent
    local watchdog = skynet.queryservice(".watchdog")
    local agent = skynet.call(watchdog, "lua", "assign_agent", fd, {
        uid = user.uid,
        username = username,
        mode = mode
    })
    
    -- 返回登录成功
    return {
        code = 0,
        uid = user.uid,
        token = crypt.base64encode(string.format("%s:%d:%s", username, user.uid, mode))
    }
end

-- 心跳处理
function CMD.heartbeat(uid, mode)
    local user = users[uid]
    if user and user.mode == mode then
        user.last_heartbeat = skynet.now()
        return { code = 0 }
    end
    return { code = 1, msg = "User not found or mode mismatch" }
end

-- 用户登出
function CMD.logout(uid, mode)
    local user = users[uid]
    if user and user.mode == mode then
        local fd = user.fd
        users[uid] = nil
        return { code = 0 }
    end
    return { code = 1, msg = "User not found or mode mismatch" }
end

-- 获取在线用户数
function CMD.online_count(mode)
    local count = 0
    for _, user in pairs(users) do
        if not mode or user.mode == mode then
            count = count + 1
        end
    end
    return { count = count }
end

skynet.start(function()
    -- 注册消息处理
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        else
            skynet.error("Unknown command " .. cmd)
        end
    end)
    
    skynet.register ".login"
end) 