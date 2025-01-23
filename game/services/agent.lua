local skynet = require "skynet"
local websocket = require "http.websocket"
local sproto = require "sproto"
local sprotoloader = require "sprotoloader"

local WATCHDOG
local gate
local host
local send_request

local CMD = {}
local REQUEST = {}
local client_fd

function REQUEST:get()
	print("get", self.what)
	local r = skynet.call("SIMPLEDB", "lua", "get", self.what)
	return { result = r }
end

function REQUEST:set()
	print("set", self.what, self.value)
	local r = skynet.call("SIMPLEDB", "lua", "set", self.what, self.value)
end

function REQUEST:handshake()
	return { msg = "Welcome to skynet, I will send heartbeat every 5 sec." }
end

function REQUEST:quit()
	skynet.call(WATCHDOG, "lua", "close", client_fd)
end

function REQUEST:auth()
	LOG.info("auth %s", self.username)
	LOG.info("auth %s", self.password)
	LOG.info("auth %s", self.device)
	LOG.info("auth %s", self.version)
	return {code = 0, uid = 1, token = "123456", msg = "success"}
end

local function request(name, args, response)
	LOG.info("request %s", name)
	local f = assert(REQUEST[name])
	local r = f(args)
	if response then
		return response(r)
	end
end

local function send_package(pack)
	--local package = string.pack(">s2", pack)
	-- LOG.info("send_package %d", client_fd)
	-- websocket.write(client_fd, pack, "binary")
	skynet.call(gate, "lua", "send", client_fd, pack)

end

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
		LOG.info("agent unpack msg %s, sz %d", type(msg), sz)
		local str = skynet.tostring(msg, sz)
		return host:dispatch(str, sz)
	end,
	dispatch = function (fd, _, type, ...)
		LOG.info("agent dispatch fd %d, type %s", fd, type)
		assert(fd == client_fd)	-- You can use fd to reply message
		skynet.ignoreret()	-- session is fd, don't call skynet.ret
		skynet.trace()
		if type == "REQUEST" then
			local ok, result  = pcall(request, ...)
			if ok then
				if result then
					send_package(result)
				end
			else
				LOG.error(result)
			end
		else
			assert(type == "RESPONSE")
			error "This example doesn't support request client"
		end
	end
}

function CMD.start(conf)
	local fd = conf.client
	gate = conf.gate
	WATCHDOG = conf.watchdog
	client_fd = fd
	-- slot 1,2 set at main.lua
	host = sprotoloader.load(1):host "package"

	-- 测试 服务的主动推送协议
	send_request = host:attach(sprotoloader.load(2))
	send_package(send_request("reportMsg",{msg = "test", time = os.time()}, 1))

	
	skynet.call(gate, "lua", "forward", fd)
end

function CMD.disconnect()
	-- todo: do something before exit
	skynet.exit()
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		skynet.trace()
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
	end)
end)
