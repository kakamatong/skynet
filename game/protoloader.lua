local skynet = require "skynet"
local sprotoloader = require "sprotoloader"

skynet.start(function()
	sprotoloader.register("proto/c2s.sproto", 1)
	sprotoloader.register("proto/s2c.sproto", 2)
	LOG.info("protoloader start")
	-- don't call skynet.exit() , because sproto.core may unload and the global slot become invalid
end)

