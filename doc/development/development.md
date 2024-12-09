# Skynet 开发指南

## 1. 服务开发

### 1.1 基础服务模板
~~~lua
local skynet = require "skynet"

local CMD = {}
function CMD.echo(...)
    return ...
end

skynet.start(function()
    -- 注册消息处理器
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.retpack(f(...))
        end
    end)
end)
~~~

### 1.2 服务注册
~~~lua
-- 注册全局服务
skynet.register(".myservice")

-- 注册本地服务
local handle = skynet.newservice("myservice")
~~~

## 2. 消息处理

### 2.1 消息发送
~~~lua
-- 同步调用
local resp = skynet.call(service, "lua", "cmd", ...)

-- 异步发送
skynet.send(service, "lua", "cmd", ...)
~~~

### 2.2 消息注册
~~~lua
skynet.register_protocol {
    name = "custom",
    id = 100,
    pack = function(...) return ... end,
    unpack = function(...) return ... end,
    dispatch = function(...) end
}
~~~

## 3. 集群通信

### 3.1 集群配置
~~~lua
cluster.reload {
    node1 = "127.0.0.1:2526",
    node2 = "127.0.0.1:2527",
}
~~~

### 3.2 集群���用
~~~lua
-- 远程调用
cluster.call("node1", "@service", "cmd", ...)

-- 远程发送
cluster.send("node1", "@service", "cmd", ...)
~~~

## 4. 网络编程

### 4.1 TCP服务
~~~lua
local socket = require "skynet.socket"

-- 创建服务器
local listen_id = socket.listen("0.0.0.0", 8888)
socket.start(listen_id, function(id, addr)
    -- 新连接回调
end)
~~~

### 4.2 WebSocket
~~~lua
local websocket = require "http.websocket"

-- WebSocket服务器
local handle = websocket.listen("0.0.0.0", 8001, {
    open = function() end,
    message = function() end,
    close = function() end,
})
~~~ 