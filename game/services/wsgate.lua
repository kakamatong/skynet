local skynet = require "skynet"
local wsgateserver = require "wsgateserver"
local websocket = require "http.websocket"
local sprotoloader = require "sprotoloader"
local watchdog
local connection = {}	-- fd -> connection : { fd , client, agent , ip, mode }

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
}

local handler = {}

function handler.open(source, conf)
	LOG.info("wsgate open")
	watchdog = conf.watchdog or source
	return conf.address, conf.port
end

function handler.message(fd, msg, msgType)
	LOG.info("wsgate message")
	-- recv a package, forward it
	local c = connection[fd]
	local agent = c.agent
	if agent then
		-- It's safe to redirect msg directly , gateserver framework will not free msg.
		skynet.redirect(agent, c.client, "client", fd, msg, string.len(msg))
	else
		skynet.send(watchdog, "lua", "socket", "data", fd, msg)
		-- skynet.tostring will copy msg to a string, so we must free msg here.
		skynet.trash(msg,string.len(msg))
	end
end

function handler.connect(fd)
	LOG.info("wsgate connect")
end

function handler.handshake(fd, header, url)
	local addr = websocket.addrinfo(fd)
	LOG.info("wsgate handshake from: %s, url %s, addr %s" ,tostring(fd), url, addr)
	LOG.info("----header-----")
	for k,v in pairs(header) do
		LOG.info(k,v)
	end
	LOG.info("--------------")

	local c = {
		fd = fd,
		ip = addr,
		url = url,
		header = header,
	}
	connection[fd] = c
	skynet.send(watchdog, "lua", "socket", "open", fd, addr)
end

local function unforward(c)
	if c.agent then
		c.agent = nil
		c.client = nil
	end
end

local function close_fd(fd)
	local c = connection[fd]
	if c then
		unforward(c)
		connection[fd] = nil
	end
end

function handler.close(fd)
	LOG.info("wsgate close")
	close_fd(fd)
	skynet.send(watchdog, "lua", "socket", "close", fd)
end

function handler.error(fd, msg)
	LOG.info("wsgate error")
	close_fd(fd)
	skynet.send(watchdog, "lua", "socket", "error", fd, msg)
end

local CMD = {}

function CMD.forward(source, fd, client, address)
	local c = assert(connection[fd])
	unforward(c)
	c.client = client or 0
	c.agent = address or source
	wsgateserver.openclient(fd)
end

function CMD.send(source, fd, msg)
	websocket.write(fd, msg, "binary")
end

function CMD.accept(source, fd)
	local c = assert(connection[fd])
	unforward(c)
	wsgateserver.openclient(fd)
end

function CMD.kick(source, fd)
	wsgateserver.closeclient(fd)
end

function handler.command(cmd, source, ...)
	local f = assert(CMD[cmd])
	return f(source, ...)
end

wsgateserver.start(handler)
