local skynet = require "skynet"
local mysql = require "skynet.db.mysql"
local redis = require "skynet.db.redis"
require "skynet.manager"
local CMD = {}
local FUNC = {}

local mysql_db = nil
local redis_db = nil

local function startMysql()
    mysql_db = mysql.connect({
        host = CONFIG.mysql.host,
        port = CONFIG.mysql.port,
        user = CONFIG.mysql.user,
        password = CONFIG.mysql.password,
        database = CONFIG.mysql.database,
    })
end

local function startRedis()
    redis_db = redis.connect({
        host = CONFIG.redis.host,
        port = CONFIG.redis.port,
        auth = CONFIG.redis.auth,
    })
end

function CMD.start()
    startMysql()
    startRedis()
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)

        if cmd == "func" then
            local f = assert(FUNC[subcmd])
            return skynet.ret(skynet.pack(f(...)))
        elseif cmd == "cmd" then
            local f = assert(CMD[subcmd])
            return skynet.ret(skynet.pack(f(...)))
        else
            return skynet.ret(skynet.pack(nil))
        end
    end)

    skynet.register(".db")
end)