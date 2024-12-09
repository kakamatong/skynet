# 登录验证模块

## 1. 架构设计

### 1.1 登录流程

~~~mermaid
sequenceDiagram
    participant Client
    participant Gate
    participant Login
    participant Auth
    participant DB

    Client->>Gate: 1. 连接请求
    Gate->>Login: 2. 创建登录会话
    Client->>Login: 3. 发送登录凭证
    Login->>Auth: 4. 验证请求
    Auth->>DB: 5. 查询用户数据
    DB-->>Auth: 6. 返回用户信息
    Auth-->>Login: 7. 验证结果
    Login-->>Client: 8. 登录响应
    Login->>Gate: 9. 绑定用户会话
~~~

### 1.2 模块组件
- Gate Service: 网关服务,处理客户端连接
- Login Service: 登录服务,处理登录请求
- Auth Service: 认证服务,验证用户身份
- Session Service: 会话服务,维护用户状态

## 2. 接口定义

### 2.1 登录接口
~~~lua
-- 登录请求
local function login_handler(username, password)
    -- 验证用户名密码
    local ok, user = auth_service.verify(username, password)
    if not ok then
        return false, "Invalid username or password"
    end
    
    -- 创建会话
    local session = session_service.create(user)
    return true, {
        uid = user.uid,
        session = session,
        token = session.token
    }
end

-- 注册登录处理器
skynet.dispatch("lua", function(session, source, cmd, ...)
    if cmd == "login" then
        local ok, result = login_handler(...)
        skynet.retpack(ok, result)
    end
end)
~~~

### 2.2 会话管理
~~~lua
-- 会话服务
local session = {}
local sessions = {}

-- 创建会话
function session.create(user)
    local s = {
        uid = user.uid,
        login_time = skynet.now(),
        token = generate_token(),
        data = {}
    }
    sessions[user.uid] = s
    return s
end

-- 验证会话
function session.verify(uid, token)
    local s = sessions[uid]
    if not s then
        return false
    end
    return s.token == token
end
~~~

## 3. 安全机制

### 3.1 Token 生成
~~~lua
-- 生成安全Token
local function generate_token()
    local random = skynet.random(100000)
    local time = skynet.now()
    local str = string.format("%d:%d", time, random)
    return crypt.hashkey(str)
end
~~~

### 3.2 密码加密
~~~lua
-- 密码加密
local function encrypt_password(password, salt)
    return crypt.hashkey(password .. salt)
end

-- 密码验证
local function verify_password(password, encrypted, salt)
    return encrypt_password(password, salt) == encrypted
end
~~~

## 4. 示例代码

### 4.1 客户端登录
~~~lua
local function do_login(username, password)
    -- 连接登录服务器
    local login_server = connect_login_server()
    
    -- 发送登录请求
    local ok, result = login_server:request("login", {
        username = username,
        password = password,
        platform = "ios",
        version = "1.0.0"
    })
    
    if not ok then
        return false, result
    end
    
    -- 保存登录信息
    save_login_info(result.uid, result.token)
    return true
end
~~~

### 4.2 服务端验证
~~~lua
-- 登录服务
local function verify_login(username, password)
    -- 查询用户信息
    local user = database.get_user(username)
    if not user then
        return false, "User not found"
    end
    
    -- 验证密码
    if not verify_password(password, user.password, user.salt) then
        return false, "Invalid password"
    end
    
    -- 创建登录会话
    local session = session_service.create(user)
    
    -- 通知网关服务
    gate_service.bind_session(user.uid, session.id)
    
    return true, {
        uid = user.uid,
        token = session.token
    }
end
~~~

## 5. 配置说明

### 5.1 登录服务配置
~~~lua
-- config/login.lua
return {
    -- 登录服务器配置
    login_server = {
        host = "0.0.0.0",
        port = 8001,
        max_client = 1000,
    },
    
    -- 会话配置
    session = {
        timeout = 3600,  -- 会话超时时间(秒)
        max_sessions = 10000, -- 最大会话数
    },
    
    -- 数据库配置
    database = {
        host = "127.0.0.1",
        port = 3306,
        user = "game",
        password = "password",
        database = "user_db"
    }
}
~~~

### 5.2 安全配置
~~~lua
-- config/security.lua
return {
    -- 密码策略
    password = {
        min_length = 6,
        max_length = 20,
        require_special = true,
    },
    
    -- Token配置
    token = {
        expire_time = 7200, -- Token过期时间
        secret_key = "your_secret_key"
    },
    
    -- 登录限制
    login_limit = {
        max_tries = 5,      -- 最大尝试次数
        lock_time = 300,    -- 锁定时间(秒)
    }
}
~~~

## 6. 注意事项

### 6.1 安全建议
- 使用HTTPS进行通信加密
- 实现登录频率限制
- 定期更新Token
- 加密存储敏感信息
- 记录登录日志

### 6.2 性能优化
- 使用连接池
- 缓存会话信息
- 异步处理登录请求
- 合理设置超时时间
- 定期清理过期会话 