local login = require "wsloginserver"
local crypt = require "skynet.crypt"
local skynet = require "skynet"

local server = {
	host = "0.0.0.0",
	port = 8002,
	multilogin = false,	-- disallow multilogin
	name = "ws_login_master",
}

local server_list = {}
local user_online = {}
local user_login = {}

function server.auth_handler(token)
	-- the token is base64(user)@base64(server):base64(password)
	local user, server, password, loginType = token:match("([^@]+)@([^:]+):([^#]+)#(.+)")
	user = crypt.base64decode(user)
	server = crypt.base64decode(server)
	password = crypt.base64decode(password)
	loginType = crypt.base64decode(loginType)
	LOG.info(string.format("user %s login, server is %s, password is %s, loginType is %s", user, server, password, loginType))
	local dbserver = skynet.localname(".dbserver")
	if not dbserver then
		LOG.error("wsgate login error: dbserver not started")
		return
	end
	local userInfo = skynet.call(dbserver, "lua", "func", "login", user,password,loginType)

	assert(userInfo, "account or password error")
	return server, userInfo.userid, loginType
end

function server.login_handler(server, userid, secret, loginType)
	LOG.info("111")
	LOG.info(string.format("%d@%s is login, secret is %s", userid, server, crypt.hexencode(secret)))
	local gameserver = assert(server_list[server], "Unknown server")
	-- only one can login, because disallow multilogin
	-- local last = user_online[numid]
	-- if last then
	-- 	skynet.call(last.address, "lua", "kickByNumid", numid, last.subid)
	-- end
	-- if user_online[numid] then
	-- 	error(string.format("user %d is already online", numid))
	-- end

	local subid = tostring(skynet.call(gameserver, "lua", "login", userid, crypt.hexencode(secret), loginType))
	-- LOG.info(string.format("%d@%s login success, subid is %s", numid, server, subid))
	-- user_online[numid] = { address = gameserver, subid = subid , secret = crypt.hexencode(secret)}
	return subid
end

local CMD = {}

function CMD.register_gate(server, address)
	LOG.info(string.format("Register gate %s %s", server, address))
	server_list[server] = address
end

-- function CMD.logout(uid, subid)
-- 	local u = user_online[uid]
-- 	if u then
-- 		print(string.format("%s@%s is logout", uid, u.server))
-- 		user_online[uid] = nil
-- 	end
-- end

function server.command_handler(command, ...)
	local f = assert(CMD[command])
	return f(...)
end

login(server)
