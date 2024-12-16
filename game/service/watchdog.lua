local skynet = require "skynet"
require "skynet.manager"

local CMD = {}
local SOCKET = {}
local gate
local agents = {}

function SOCKET.client_connected(fd, addr)
    LOG.info("Client connected: %s, fd: %d", addr, fd)
    agents[fd] = nil
end

function SOCKET.client_disconnected(fd)
    LOG.info("Client disconnected: fd: %d", fd)
    local agent = agents[fd]
    if agent then
        skynet.call(gate, "lua", "unbind_agent", fd)
        skynet.kill(agent)
        agents[fd] = nil
    end
end

-- 创建Agent
local function create_agent()
    local agent = skynet.newservice("agent")
    return agent
end

-- 分配Agent
function CMD.assign_agent(fd, msg)
    local agent = create_agent()
    local client = skynet.self()
    
    -- 初始化agent
    skynet.call(agent, "lua", "start", gate, client, fd)
    
    -- 绑定agent到网关
    skynet.call(gate, "lua", "bind_agent", fd, agent, client)
    
    agents[fd] = agent
    return agent
end

function CMD.register_gate(gate_service)
    -- 启动网关
    gate = gate_service
end

skynet.start(function()
    -- 注册socket消息处理
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        if cmd == "socket" then
            local f = SOCKET[subcmd]
            f(...)
            -- socket api don't need return
        else
            local f = assert(CMD[cmd])
            skynet.ret(skynet.pack(f(subcmd, ...)))
        end
    end)
    
    skynet.register ".watchdog"
    LOG.info("watchdog started")
end) 