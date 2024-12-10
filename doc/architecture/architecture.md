# Skynet 架构设计

## 1. 整体架构

### 1.1 架构图

~~~mermaid
graph TD
    A[Skynet Node] --> B[Master Service]
    A --> C[Harbor Service] 
    A --> D[Logger Service]
    A --> E[Worker Services]

    B --> F[Service Management]
    B --> G[Message Dispatch]
    
    C --> H[Inter-node Communication]
    C --> I[Name Service]
    
    E --> J[Game Logic]
    E --> K[DB Access]
    E --> L[Network Protocol]
~~~

### 1.2 核心组件

~~~mermaid
graph TD
    A[Service Manager] --> B[Create Service]
    A --> C[Kill Service]
    A --> D[Query Service]
    A --> E[Name Service]
    
    B --> F[Load Code]
    B --> G[Init Context]
    
    E --> H[Global Name]
    E --> I[Local Name]
~~~

## 2. 消息系统

### 2.1 消息流程

~~~mermaid
sequenceDiagram
    participant Client
    participant Service A
    participant Service B
    participant Message Queue
    
    Client->>Service A: send/call
    Service A->>Message Queue: push message
    Message Queue->>Service B: dispatch
    Service B->>Service A: response
~~~

### 2.2 消息类型
~~~lua
-- 系统内置消息类型
PTYPE_TEXT = 0,      -- 文本消息
PTYPE_RESPONSE = 1,  -- 响应消息
PTYPE_MULTICAST = 2, -- 多播消息
PTYPE_CLIENT = 3,    -- 客户端消息
PTYPE_SYSTEM = 4,    -- 系统消息
PTYPE_HARBOR = 5,    -- 节点间通信
PTYPE_SOCKET = 6,    -- 网络消息
PTYPE_ERROR = 7,     -- 错误消息
PTYPE_QUEUE = 8,     -- 队列消息
PTYPE_DEBUG = 9,     -- 调试消息
PTYPE_LUA = 10,      -- Lua服务消息
PTYPE_SNAX = 11,     -- SNAX服务消息
PTYPE_TRACE = 12     -- 追踪消息
~~~

### 2.3 消息数据结构

~~~lua
-- 消息基础结构
message = {
    source = 0,      -- 消息来源服务句柄
    session = 0,     -- 会话ID，用于请求-响应匹配
    type = 0,        -- 消息类型(PTYPE_*)
    size = 0,        -- 消息数据大小
    data = nil       -- 消息内容
}

-- 扩展消息结构(用于集群间通信)
cluster_message = {
    source = 0,      -- 消息来源服务句柄
    session = 0,     -- 会话ID
    type = 0,        -- 消息类型
    addr = "",       -- 目标节点地址
    name = "",       -- 目标服务名称
    pad = 0,         -- 对齐填充
    msg = nil        -- 实际消息内容
}
~~~

#### 字段说明

1. **source** (服务句柄)
   - 消息发送方的唯一标识符
   - 用于标识消息的来源服务
   - 通常是一个整数值

2. **session** (会话ID)
   - 0: 表示是一个单向消息
   - >0: 表示需要响应的请求消息
   - <0: 表示是对请求的响应消息
   
   session生成规则:
   ~~~lua
   local session = 0
   -- 会话ID生成器
   function gen_session()
       -- session从1开始递增
       session = session + 1
       -- 超过最大值后重置
       if session > 0x7fffffff then  
           session = 1
       end
       return session
   end
   
   -- 响应消息的session处理
   function handle_response(session)
       -- 响应消息的session为请求消息session的负值
       return -session
   end
   ~~~
   
   注意事项:
   - session在每个服务内部独立维护
   - 取值范围: 1 ~ 0x7fffffff (21亿)
   - 超出范围后循环使用
   - 响应消息的session = -(请求消息的session)
   - 同一服务内session保证唯一性
   - 用于匹配异步请求和响应的配对关系

3. **type** (消息类型)
   - 对应2.2中定义的PTYPE_*类型
   - 决定了消息的处理方式和路由规则

4. **size** (消息大小)
   - 消息数据部分的字节大小
   - 用于内存分配和消息边界判断

5. **data** (消息数据)
   - 可以是任意Lua类型
   - 通常使用以下格式:
     - 字符串
     - Table
     - 序列化的对象
     - 二进制数据

6. **集群专用字��**
   - addr: 目标节点的地址/标识
   - name: 目标服务的名称
   - pad: 内存对齐用的填充值

~~~mermaid
classDiagram
    class Message {
        +int source
        +int session
        +int type
        +int size
        +any data
    }
    
    class ClusterMessage {
        +int source
        +int session
        +int type
        +string addr
        +string name
        +int pad
        +any msg
    }
~~~

## 3. 服务模型

### 3.1 服务生命周期

~~~mermaid
stateDiagram-v2
    [*] --> Init: skynet.start
    Init --> Running: dispatch
    Running --> Exit: skynet.exit
    Exit --> [*]
~~~

### 3.2 服务通信
- 同步调用 (call)
- 异步发送 (send)
- 广播多播 (multicast)
- 远程调用 (cluster)

## 4. 目录结构

~~~
skynet/
├── 3rd/                    # 第三方库
├── examples/               # 示例代码
├── lualib/                 # Lua 库文件
│   ├── skynet/            # Skynet 核心库
│   ├── http/              # HTTP 相关库
│   └── ...
├── lualib-src/            # C 语言实现的 Lua 库
├── service/               # 基础服务
├── service-src/           # C 语言实现的服务
├── skynet-src/            # Skynet 核心代码
└── test/                  # 测试用例
~~~ 

## 5. 网关模块

### 5.1 网关架构

~~~mermaid
graph TD
    A[Client] --> B[Gate Service]
    B --> C[Watchdog Service]
    B --> D[Agent Service]
    B --> I[Broker Service]
    
    C --> E[Login Logic]
    C --> F[Session Management]
    
    D --> G[Game Logic]
    D --> H[Message Processing]
    
    I --> J[Message Broadcasting]
    I --> K[Channel Management]
    I --> L[Message Filter]
    
    subgraph Direct Mode
        C
    end
    
    subgraph Agent Mode
        D
    end
    
    subgraph Broker Mode
        I
    end
~~~

### 5.2 网关模式

网关服务支持三种工作模式:

1. **直接模式 (Direct Mode)**
   ~~~lua
   -- 网关直接转发消息到watchdog
   connection = {
       fd = socket_id,
       agent = nil,
       client = nil,
   }
   ~~~
   
   特点:
   - 所有消息直接转发给watchdog处理
   - 适用于登录验证阶段
   - 由watchdog统一管理连接状态
   - 处理未认证客户端的消息

2. **代理模式 (Agent Mode)**
   ~~~lua
   -- 网关将消息转发到指定agent
   connection = {
       fd = socket_id,
       agent = agent_handle,
       client = client_handle,
   }
   ~~~
   
   特点:
   - 每个连接绑定一个专属agent服务
   - 适用于游戏主逻辑段
   - 支持消息双向流动
   - 提供会话隔离
   - 便于实现玩家专属逻辑

3. **广播模式 (Broker Mode)**
   ~~~lua
   -- 网关将消息转发到broker服务
   gate_service = {
       broker = broker_handle,
       client_tag = skynet.PTYPE_CLIENT,
   }
   ~~~
   
   特点:
   - 所有消息转发到统一的broker服务
   - 适用于聊天、广播等群发场景
   - 支持消息过滤和分发
   - 实现订阅发布模式

### 5.3 工作流程

~~~mermaid
sequenceDiagram
    participant C as Client
    participant G as Gate
    participant W as Watchdog
    participant A as Agent

    C->>G: Connect
    G->>W: Report Connect
    W->>G: Set Direct Mode
    
    C->>G: Login Request
    G->>W: Forward Message
    W->>A: Create Agent
    W->>G: Bind Agent
    
    C->>G: Game Message
    G->>A: Forward to Agent
    A->>G: Response
    G->>C: Send to Client
~~~

### 5.4 使用场景

1. **直接模式使用场景**
   - 登录验证阶段
   - 简单的服务接入
   - 需要集中处理的消息
   - 连接初始化阶段

2. **代理模式使用场景**
   - 游戏主逻辑
   - 需要保持玩家状态
   - 复杂的业务处理
   - 需要会话隔离
   - 玩家专属逻辑

3. **广播模式使用场景**
   - 聊天系统
   - 公告广播
   - ��界频道
   - 房间消息
   - 群组通信

### 5.5 配置示例

~~~lua
-- 网关配置
local gate_conf = {
    -- 基础配置
    address = "0.0.0.0",
    port = 8888,
    maxclient = 1024,
    
    -- 工作模式
    watchdog = watchdog_service,  -- 直接模式
    agent = agent_pool,           -- 代理模式
    broker = broker_service,      -- 广播模式
    
    -- 协议配置
    proto = "lua",
    name = "gate",
    
    -- 安全配置
    timeout = 60,
    max_connection = 1024,
}
~~~

### 5.6 注意事项

1. **模式切换**
   - 同一连接可以在不同模式间切换
   - 切换时需要正确清理旧模式的状态
   - 避免消息处理冲突

2. **资源管理**
   - 及时清理断开的连接
   - 控制最大连接数
   - 管理Agent服务的生命周期
   - 处理超时连接

3. **安全考虑**
   - 实现消息频率限制
   - 添加消息验证机制
   - 防止消息伪造
   - 控制单IP连接数

4. **性能优化**
   - 使用消息队列缓冲
   - 批量处理消息
   - 合理设置缓冲区大小
   - 监控网关性能指标

## 6. 数据库模块

### 6.1 数据库架构

~~~mermaid
graph TD
    A[DB Manager] --> B[Connection Pool]
    A --> C[Query Interface]
    A --> D[Cache Layer]
    
    B --> E[MySQL Conn]
    B --> F[Redis Conn]
    B --> G[MongoDB Conn]
    
    C --> H[SQL Builder]
    C --> I[ORM Mapper]
    
    D --> J[Local Cache]
    D --> K[Redis Cache]
~~~

### 6.2 连接池管理

~~~lua
-- 数据库连接池配置
local db_conf = {
    mysql = {
        host = "127.0.0.1",
        port = 3306,
        user = "root",
        password = "password",
        database = "game",
        pool_size = 8,
        max_packet = 1024 * 1024
    },
    
    redis = {
        host = "127.0.0.1",
        port = 6379,
        auth = "password",
        db = 0,
        pool_size = 16
    },
    
    mongodb = {
        url = "mongodb://localhost:27017",
        database = "game",
        pool_size = 4
    }
}

-- 连接池状态
pool_status = {
    total = 0,       -- 总连接数
    active = 0,      -- 活跃连接数
    idle = 0,        -- 空闲连接数
    waiting = 0      -- 等待连接数
}
~~~

### 6.3 查询接口

1. **MySQL接口**
~~~lua
-- 同步查询
local function query(sql)
    local db = mysql_pool.acquire()
    local res = db:query(sql)
    mysql_pool.release(db)
    return res
end

-- 异步查询
local function async_query(sql)
    return skynet.call(db_service, "lua", "query", sql)
end

-- 事务处理
local function transaction(func)
    local db = mysql_pool.acquire()
    db:query("START TRANSACTION")
    local ok, err = pcall(func, db)
    if ok then
        db:query("COMMIT")
    else
        db:query("ROLLBACK")
    end
    mysql_pool.release(db)
    return ok, err
end
~~~

2. **Redis接口**
~~~lua
-- 基础操作
local function redis_cmd(cmd, ...)
    local db = redis_pool.acquire()
    local res = db[cmd](db, ...)
    redis_pool.release(db)
    return res
end

-- 管道操作
local function pipeline(cmds)
    local db = redis_pool.acquire()
    db:init_pipeline()
    for _, cmd in ipairs(cmds) do
        db[cmd[1]](db, table.unpack(cmd, 2))
    end
    local res = db:commit_pipeline()
    redis_pool.release(db)
    return res
end
~~~

3. **MongoDB接口**
~~~lua
-- 文档操作
local function mongo_op(collection, op, ...)
    local db = mongo_pool.acquire()
    local coll = db[collection]
    local res = coll[op](coll, ...)
    mongo_pool.release(db)
    return res
end
~~~

### 6.4 缓存策略

~~~lua
-- 缓存配置
local cache_conf = {
    -- 本地缓存
    local_cache = {
        capacity = 10000,    -- 最大容量
        expire = 300,        -- 过期时间(秒)
        update_factor = 0.2  -- 更新因子
    },
    
    -- Redis缓存
    redis_cache = {
        prefix = "game:",    -- 键前缀
        expire = 3600,       -- 过期���间(秒)
        compress = true      -- 是否压缩
    }
}

-- 缓存接口
local cache = {
    -- 获取数据(先查本地,再查Redis,最后查DB)
    get = function(key)
        local data = local_cache.get(key)
        if not data then
            data = redis_cache.get(key)
            if not data then
                data = db_query(key)
                redis_cache.set(key, data)
            end
            local_cache.set(key, data)
        end
        return data
    end,
    
    -- 更新数据(同时更新本地和Redis)
    set = function(key, value)
        local_cache.set(key, value)
        redis_cache.set(key, value)
    end,
    
    -- 删除数据
    del = function(key)
        local_cache.del(key)
        redis_cache.del(key)
    end
}
~~~

### 6.5 性能监控

~~~lua
-- 性能指标收集
local metrics = {
    -- 查询统计
    query_stats = {
        total = 0,       -- 总查询数
        success = 0,     -- 成功数
        failed = 0,      -- 失败数
        timeout = 0      -- 超时数
    },
    
    -- 响应时间
    response_time = {
        avg = 0,         -- 平均响应时间
        max = 0,         -- 最大响应时间
        min = 0          -- 最小响应时间
    },
    
    -- 连接池状态
    pool_stats = {
        mysql = pool_status,
        redis = pool_status,
        mongodb = pool_status
    }
}

-- 监控报告生成
local function gen_report()
    return {
        timestamp = os.time(),
        metrics = metrics,
        warnings = {},
        errors = {}
    }
end
~~~

### 6.6 注意事项

1. **连接管理**
   - 合理设置连接池大小
   - 及时释放空闲连接
   - 处理连接超时
   - 实现连接重试机制

2. **查询优化**
   - 使用预处理语句
   - 合理使用索引
   - 控制查询复杂度
   - 避免大事务

3. **缓存使用**
   - 设置合理的过期时间
   - 实现缓存预热
   - 防止缓存雪崩
   - 控制缓存数据大小

4. **异常处理**
   - 处理连接断开
   - 处理查询超时
   - 实现故障转移
   - 记录错误日志

## 7. Sproto协议

### 7.1 协议定义

协议文件通常存放在 `proto/` 目录下，使用 `.sproto` 扩展名。

~~~lua
-- proto/game.sproto
-- 基础数据类型
.package {
    type 0 : integer
    type 1 : boolean
    type 2 : string
    type 3 : binary
    type 4 : double
}

-- 复合类型定义
.Position {
    x 0 : integer
    y 1 : integer
    z 2 : integer
}

.Player {
    id 0 : integer
    name 1 : string
    level 2 : integer
    pos 3 : Position
    items 4 : *integer     # 数组类型使用*标记
    attrs 5 : *string      # 字符串数组
}

-- 协议定义
login 1 {      # 请求协议号为1
    request {  # 请求结构
        username 0 : string
        password 1 : string
        device 2 : string
    }
    response { # 响应结构
        code 0 : integer
        uid 1 : integer
        token 2 : string
        error 3 : string
    }
}

move 2 {       # 协议号为2
    request {
        pos 0 : Position
        speed 1 : integer
    }
    response {
        code 0 : integer
        current_pos 1 : Position
    }
}

chat 3 {
    request {
        type 0 : integer     # 1:私聊 2:公频 3:队伍
        target 1 : integer   # 目标玩家ID
        content 2 : string   # 聊天内容
    }
    response {
        code 0 : integer
        timestamp 1 : integer
    }
}
~~~

### 7.2 协议加载

~~~lua
local sproto = require "sproto"
local sprotoparser = require "sprotoparser"

-- 加载协议文件
local function load_protocol()
    local f = io.open("proto/game.sproto", "r")
    local content = f:read("*a")
    f:close()
    
    -- 解析协议
    local sp = sprotoparser.parse(content)
    -- 创建协议对象
    local proto = sproto.new(sp)
    
    return proto
end

-- 创建协议主机(用于RPC)
local function create_proto_host()
    local proto = load_protocol()
    -- 创建host(用于请求和响应)
    local host = sproto.new(proto):host "package"
    -- 创建request对象(用于编码请求)
    local request = host:attach(proto)
    
    return host, request
end
~~~

### 7.3 协议使用

1. **服务端处理**
~~~lua
local host, proto_request = create_proto_host()

-- 消息分发
function handle_message(msg, sz)
    -- 解包消息
    local type, name, request, response = host:dispatch(msg, sz)
    
    if type == "REQUEST" then
        -- 处理请求
        local ok, result = pcall(handle_request, name, request)
        -- 返回响应
        if ok then
            return response(result)
        else
            return response({ code = 1, error = result })
        end
    else
        -- 处理响应
        handle_response(name, response)
    end
end

-- 请求处理
function handle_request(name, args)
    if name == "login" then
        return {
            code = 0,
            uid = 10000,
            token = "xxx",
        }
    elseif name == "move" then
        return {
            code = 0,
            current_pos = args.pos
        }
    end
end
~~~

2. **客户端调用**
~~~lua
local host, request = create_proto_host()

-- 发送请求
local function send_request(name, args)
    -- 编码请求
    local msg = request(name, args)
    -- 发送消息
    socket.send(connection, msg)
end

-- 登录请求示例
send_request("login", {
    username = "player1",
    password = "123456",
    device = "android"
})

-- 移动请求示例
send_request("move", {
    pos = {
        x = 100,
        y = 200,
        z = 0
    },
    speed = 10
})
~~~

### 7.4 协议规范

1. **类型定义规则**
   - 基础类型: integer, boolean, string, binary, double
   - 数组类型: 使用*前缀标记
   - 复合类型: 使用.开头定义
   - 字段编号: 从0开始的整数

2. **协议定义规则**
   - 协议号: 唯一的正整数
   - 请求结构: request块
   - 响应结构: response块
   - 可选字段: 字段名后加?标记

3. **命名规范**
   - 类型名: 大写开头的驼峰命名
   - 协议名: 小写字母加下划线
   - 字段名: 小写字母加下划线
   - 注释: 使用#号

### 7.5 注意事项

1. **性能考虑**
   - 协议预编译
   - 复用协议对象
   - 合理设计数据结构
   - 避免过大的消息包

2. **版本管理**
   - 协议版本号管理
   - 向下兼容
   - 废弃字段处理
   - 协议升级策略

3. **调试方法**
   - 协议分析工具
   - 消息跟踪
   - 数据包打印
   - 错误处理

## 8. Demo游戏架构

### 8.1 基础服务架构

~~~mermaid
graph TD
    A[Skynet Node] --> B[Login Service]
    A --> C[Gate Service]
    A --> D[Game Service]
    A --> E[DB Service]
    A --> F[Chat Service]
    
    B --> B1[登录验证]
    B --> B2[账号管理]
    
    C --> C1[连接管理]
    C --> C2[消息路由]
    
    D --> D1[玩家管理]
    D --> D2[游戏逻辑]
    
    E --> E1[数据存储]
    E --> E2[缓存管理]
    
    F --> F1[聊天系统]
    F --> F2[广播系统]
~~~

### 8.2 服务说明

1. **Login Service (登录服务)**
   - 处理玩家登录请求
   - 账号验证
   - 会话管理
   - 登录队列

2. **Gate Service (网关服务)**
   - 管理客户端连接
   - 消息转发
   - 负载均衡
   - 心跳检测

3. **Game Service (游戏服务)**
   - 玩家数据管理
   - 核心游戏逻辑
   - 状态同步
   - 场景管理

4. **DB Service (数据库服务)**
   - 数据持久化
   - 缓存管理
   - 异步存储
   - 数据备份

5. **Chat Service (聊天服务)**
   - 世界聊天
   - 私聊系统
   - 频道管理
   - 消息广播