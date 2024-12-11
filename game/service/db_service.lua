local skynet = require "skynet"
local mysql = require "skynet.db.mysql"
local redis = require "skynet.db.redis"

local CMD = {}
local pool = {}

function CMD.init()
    local ok, err = xpcall(function()
        -- 初始化MySQL连接池
        skynet.error("Connecting to MySQL...")
        pool.mysql = mysql.connect({
            host = CONFIG.database.mysql.host,
            port = CONFIG.database.mysql.port,
            database = CONFIG.database.mysql.database,
            user = CONFIG.database.mysql.user,
            password = CONFIG.database.mysql.password,
            max_packet_size = CONFIG.database.mysql.max_packet_size,
            timeout = 1000,
            auth_plugin = "mysql_native_password",
            on_connect = function(db)
                db:query("set charset utf8")
            end
        })
        
        skynet.sleep(100)
        
        -- 初始化Redis连接池
        skynet.error("Connecting to Redis...")
        pool.redis = redis.connect({
            host = CONFIG.database.redis.host,
            port = CONFIG.database.redis.port,
            auth = CONFIG.database.redis.auth,
            db = CONFIG.database.redis.db,
            timeout = 1000
        })
    end, debug.traceback)
    
    if not ok then
        skynet.error("Database init failed: " .. tostring(err))
        return false
    end
    
    return true
end

function CMD.mysql_query(sql)
    return pool.mysql:query(sql)
end

function CMD.redis_cmd(cmd, ...)
    return pool.redis[cmd](pool.redis, ...)
end

skynet.start(function()
    local ok, err = xpcall(function()
        skynet.error("Database service starting...")
        
        skynet.dispatch("lua", function(session, source, cmd, ...)
            local f = assert(CMD[cmd])
            skynet.ret(skynet.pack(f(...)))

        end)
        
        if CMD.init() then
            skynet.error("Database service started.")
        else
            skynet.error("Database service start failed")
            skynet.exit()
        end
    end, debug.traceback)
    
    if not ok then
        skynet.error("Database service error: " .. tostring(err))
        skynet.exit()
    end
end) 