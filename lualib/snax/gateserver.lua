local skynet = require "skynet"
local netpack = require "skynet.netpack"
local socketdriver = require "skynet.socketdriver"

local gateserver = {}

local socket	-- 监听socket
local queue		-- 消息队列
local maxclient	-- 最大客户端连接数
local client_number = 0 -- 当前客户端连接数
local CMD = setmetatable({}, { __gc = function() netpack.clear(queue) end }) -- 命令表，带有垃圾回收功能
local nodelay = false -- 是否启用无延迟模式

local connection = {} -- 连接状态表
-- true : 已连接
-- nil : 已关闭
-- false : 关闭读取

-- 打开客户端连接
function gateserver.openclient(fd)
	if connection[fd] then
		socketdriver.start(fd)
	end
end

-- 关闭客户端连接
function gateserver.closeclient(fd)
	local c = connection[fd]
	if c ~= nil then
		connection[fd] = nil
		socketdriver.close(fd)
	end
end

-- 启动网关服务器
function gateserver.start(handler)
	assert(handler.message) -- 确保有消息处理函数
	assert(handler.connect) -- 确保有连接处理函数

	local listen_context = {} -- 监听上下文

	-- 打开监听
	function CMD.open(source, conf)
		assert(not socket)
		local address = conf.address or "0.0.0.0"
		local port = assert(conf.port)
		maxclient = conf.maxclient or 1024
		nodelay = conf.nodelay
		skynet.error(string.format("Listen on %s:%d", address, port))
		socket = socketdriver.listen(address, port, conf.backlog)
		listen_context.co = coroutine.running()
		listen_context.fd = socket
		skynet.wait(listen_context.co)
		conf.address = listen_context.addr
		conf.port = listen_context.port
		listen_context = nil
		socketdriver.start(socket)
		if handler.open then
			return handler.open(source, conf)
		end
	end

	-- 关闭监听
	function CMD.close()
		assert(socket)
		socketdriver.close(socket)
	end

	local MSG = {} -- 消息处理表

	-- 分发消息
	local function dispatch_msg(fd, msg, sz)
		if connection[fd] then
			handler.message(fd, msg, sz)
		else
			skynet.error(string.format("Drop message from fd (%d) : %s", fd, netpack.tostring(msg,sz)))
		end
	end

	MSG.data = dispatch_msg

	-- 分发队列中的消息
	local function dispatch_queue()
		local fd, msg, sz = netpack.pop(queue)
		if fd then
			skynet.fork(dispatch_queue)
			dispatch_msg(fd, msg, sz)

			for fd, msg, sz in netpack.pop, queue do
				dispatch_msg(fd, msg, sz)
			end
		end
	end

	MSG.more = dispatch_queue

	-- 处理新连接
	function MSG.open(fd, msg)
		client_number = client_number + 1
		if client_number >= maxclient then
			socketdriver.shutdown(fd)
			return
		end
		if nodelay then
			socketdriver.nodelay(fd)
		end
		connection[fd] = true
		handler.connect(fd, msg)
	end

	-- 处理连接关闭
	function MSG.close(fd)
		if fd ~= socket then
			client_number = client_number - 1
			if connection[fd] then
				connection[fd] = false -- 关闭读取
			end
			if handler.disconnect then
				handler.disconnect(fd)
			end
		else
			socket = nil
		end
	end

	-- 处理错误
	function MSG.error(fd, msg)
		if fd == socket then
			skynet.error("gateserver accept error:", msg)
		else
			socketdriver.shutdown(fd)
			if handler.error then
				handler.error(fd, msg)
			end
		end
	end

	-- 处理警告
	function MSG.warning(fd, size)
		if handler.warning then
			handler.warning(fd, size)
		end
	end

	-- 初始化监听
	function MSG.init(id, addr, port)
		if listen_context then
			local co = listen_context.co
			if co then
				assert(id == listen_context.fd)
				listen_context.addr = addr
				listen_context.port = port
				skynet.wakeup(co)
				listen_context.co = nil
			end
		end
	end

	-- 注册socket协议
	skynet.register_protocol {
		name = "socket",
		id = skynet.PTYPE_SOCKET, -- PTYPE_SOCKET = 6
		unpack = function (msg, sz)
			return netpack.filter(queue, msg, sz)
		end,
		dispatch = function (_, _, q, type, ...)
			queue = q
			if type then
				MSG[type](...)
			end
		end
	}

	-- 初始化函数
	local function init()
		skynet.dispatch("lua", function (_, address, cmd, ...)
			local f = CMD[cmd]
			if f then
				skynet.ret(skynet.pack(f(address, ...)))
			else
				skynet.ret(skynet.pack(handler.command(cmd, address, ...)))
			end
		end)
	end

	-- 判断是否嵌入启动
	if handler.embed then
		init()
	else
		skynet.start(init)
	end
end

return gateserver
