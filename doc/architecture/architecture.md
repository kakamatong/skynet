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