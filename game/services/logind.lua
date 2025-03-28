local login = require "snax.loginserver"
local crypt = require "skynet.crypt"
local skynet = require "skynet"

local server = {
	host = "127.0.0.1",
	port = 8001,
	multilogin = false,	-- disallow multilogin
	name = "login_master",
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
	return server, userInfo.numid
end

function server.login_handler(server, uid, secret)
	print(string.format("%s@%s is login, secret is %s", uid, server, crypt.hexencode(secret)))
	local gameserver = assert(server_list[server], "Unknown server")
	-- only one can login, because disallow multilogin
	local last = user_online[uid]
	if last then
		skynet.call(last.address, "lua", "kick", uid, last.subid)
	end
	if user_online[uid] then
		error(string.format("user %s is already online", uid))
	end

	local subid = tostring(skynet.call(gameserver, "lua", "login", uid, secret))
	user_online[uid] = { address = gameserver, subid = subid , server = server}
	return subid
end

local CMD = {}

function CMD.register_gate(server, address)
	server_list[server] = address
end

function CMD.logout(uid, subid)
	local u = user_online[uid]
	if u then
		print(string.format("%s@%s is logout", uid, u.server))
		user_online[uid] = nil
	end
end

function server.command_handler(command, ...)
	local f = assert(CMD[command])
	return f(...)
end

login(server)
