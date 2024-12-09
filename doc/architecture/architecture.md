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

6. **集群专用字段**
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
   - 适用于游戏主逻辑阶段
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
   - 世界频道
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

// ... 后面内容保持不变 ...