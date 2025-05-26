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
local userid = 0
local userStatus = 0
local reportsessionid = 0

local function send_package(pack)
	skynet.call(gate, "lua", "send", client_fd, pack)
end

local function report(name, data)
	reportsessionid = reportsessionid + 1
	send_request = host:attach(sprotoloader.load(2))
	send_package(send_request(name,data, reportsessionid))
end

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

-- 设置用户状态
local function setUserStatus(status, gameid)
	if not status then return end
	userStatus = status
	local db = getDB()
	skynet.call(db, "lua", "func", "setUserStatus", userid, status, gameid)
end

-- 检查用户状态
local function checkStatus()
	local db = getDB()
	local status = skynet.call(db, "lua", "func", "getUserStatus", userid)
	if not status or status.gameid == 0 then
		setUserStatus(CONFIG.USER_STATUS.ONLINE, 0)
		return
	elseif status.gameid > 0 then
		setUserStatus(CONFIG.USER_STATUS.GAMEING, status.gameid)
		return
	end
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

-- 心跳
function REQUEST:heartbeat()
	leftTime = os.time()
	return { timestamp = leftTime }
end

function REQUEST:quit()
	skynet.call(WATCHDOG, "lua", "close", client_fd)
end

-- 用户数据
function REQUEST:userData(args)
	local db =getDB()
	local userData = skynet.call(db, "lua", "func", "getUserData", userid)
	assert(userData)
	return userData
end

-- 用户财富
function REQUEST:userRiches(args)
	local db =getDB()
	local userRiches = skynet.call(db, "lua", "func", "getUserRiches", userid)
	assert(userRiches)
	local richType = {}
	local richNums = {}
	for k,v in pairs(userRiches) do
		table.insert(richType, v.richType)
		table.insert(richNums, v.richNums)
	end

	LOG.info("richType %s", UTILS.tableToString(richType))
	LOG.info("richNums %s", UTILS.tableToString(richNums))

	return {richType = richType, richNums = richNums}
end

-- 用户状态
function REQUEST:userStatus(args)
	local db = getDB()
	local status = skynet.call(db, "lua", "func", "getUserStatus", userid)
	if not status then
		return {gameid = 0 , status = -1}
	else
		return {gameid = status.gameid , status=status.status}
	end
end

-- 匹配
function REQUEST:match(args)
	local matchServer = skynet.localname(".match")
	if not matchServer then
		return {code = 1, msg ="匹配服务异常"}
	else
		local b = skynet.call(matchServer, "lua", "enterQueue", skynet.self(), userid, 0)
		if b then
			setUserStatus(CONFIG.USER_STATUS.MATCHING)
			report("reportUserStatus", {status = CONFIG.USER_STATUS.MATCHING, gameid = 0})
			return {code = 0, msg ="进入匹配列队成功"}
		else
			return {code = 2, msg ="进入匹配列队失败"}
		end
	end
end

-- 认证
function REQUEST:auth(args)
	LOG.info("auth username %s, password %s", args.userid, args.password)
	local db =getDB()
	local authInfo = skynet.call(db, "lua", "func", "getAuth", args.userid)
	if not authInfo then
		return {code = 1, msg = "acc failed"}
	end

	if authInfo.secret ~= args.password then
		return {code = 2, msg = "pass failed"}
	end

	if authInfo.subid ~= args.subid then
		return {code = 3, msg = "subid failed"}
	end
	skynet.call(db, "lua", "func", "addSubid", args.userid, authInfo.subid + 1)

	bAuth = true
	userid = args.userid
	leftTime = os.time()
	checkStatus()
	return {code = 0, msg = "success"}
end

-- 请求分发
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
	report("reportContent",{code = 1})
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
	setUserStatus(CONFIG.USER_STATUS.OFFLINE)
	LOG.info("agent disconnect")
	skynet.exit()
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		--skynet.trace()
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
	end)
end)
