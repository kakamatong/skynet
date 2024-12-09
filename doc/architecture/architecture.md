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
└─��� test/                  # 测试用例
~~~ 