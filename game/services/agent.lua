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
local leftTime = 0
local dTime = 15
local bAuth = false

local function close()
	LOG.info("agent close")
	skynet.call(gate, "lua", "kick", client_fd)
	--skynet.exit()
end

local function getDB()
	local dbserver = skynet.localname(".dbserver")
	if not dbserver then
		LOG.error("wsgate login error: dbserver not started")
		return
	end

	return dbserver
end

function REQUEST:get()
	print("get", self.what)
	local r = skynet.call("SIMPLEDB", "lua", "get", self.what)
	return { result = r }
end

function REQUEST:set()
	print("set", self.what, self.value)
	local r = skynet.call("SIMPLEDB", "lua", "set", self.what, self.value)
end

function REQUEST:heartbeat()
	leftTime = os.time()
	return { timestamp = leftTime }
end

function REQUEST:quit()
	skynet.call(WATCHDOG, "lua", "close", client_fd)
end

function REQUEST:auth(args)
	LOG.info("auth username %s, password %s", args.userid, args.password)
	local db =getDB()
	local authInfo = skynet.call(db, "lua", "func", "checkAuth", args.userid, args.password)
	if not authInfo then
		return {code = 0, msg = "auth failed"}
	end
	bAuth = true
	leftTime = os.time()
	return {code = 1, msg = "success"}
end

local function request(name, args, response)
	LOG.info("request %s", name)
	if not bAuth and name ~= "auth" then
		return 
	end
	local f = assert(REQUEST[name])
	local r = f(REQUEST, args)
	if response then
		return response(r)
	end
end

local function send_package(pack)
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
		--skynet.trace()
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

function CMD.content()
	LOG.info("agent content")
	send_request = host:attach(sprotoloader.load(2))
	send_package(send_request("reportContent",{code = 1}, 1))
end

function CMD.start(conf)
	local fd = conf.client
	gate = conf.gate
	WATCHDOG = conf.watchdog
	client_fd = fd
	-- slot 1,2 set at main.lua
	host = sprotoloader.load(1):host "package"
	leftTime = os.time()
	
	skynet.fork(function()
		while true do
			-- 测试 服务的主动推送协议
			-- send_package(send_request("reportMsg",{msg = "test", time = os.time()}, 1))
			local now = os.time()
			if now - leftTime >= dTime then
				LOG.info("agent heartbeat fd %d now %d leftTime %d", client_fd, now, leftTime)
				close()
				break
			end
			skynet.sleep(dTime * 100)
		end
	end)

	
	skynet.call(gate, "lua", "forward", fd, fd, skynet.self())
end

function CMD.disconnect()
	-- todo: do something before exit
	skynet.exit()
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		--skynet.trace()
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
	end)
end)
