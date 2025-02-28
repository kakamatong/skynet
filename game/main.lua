local skynet = require "skynet"
local sprotoloader = require "sprotoloader"

local max_client = 64

skynet.start(function()
	LOG.info("Server start")
	skynet.uniqueservice("protoloader")
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	skynet.newservice("debug_console",8000)

	local db = skynet.newservice("db")
	skynet.call(db, "lua", "cmd", "start")
	--skynet.newservice("simpledb")
	-- 替换为WebSocket登录服务
	skynet.newservice("wslogind")

	-- 网关服务器
	local watchdog = skynet.newservice("watchdog")
	local addr,port = skynet.call(watchdog, "lua", "start", {
		port = 9001,
		maxclient = max_client,
		nodelay = true,
	})
	LOG.info("Watchdog listen on " .. addr .. ":" .. port)

	-- websocket网关服务器
	local wswatchdog = skynet.newservice("wswatchdog")
	local addr,port = skynet.call(wswatchdog, "lua", "start", {
		address = "0.0.0.0",
		port = 9002,
		maxclient = max_client,
	})
	LOG.info("Wswatchdog listen on " .. addr .. ":" .. port)
	skynet.exit()
end)
