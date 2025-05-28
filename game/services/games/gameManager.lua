local skynet = require "skynet"
require "skynet.manager"

local CMD = {}
local name = "gameManager"

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            f(source, ...)
        end
        skynet.register("." .. name)
    end)
end)