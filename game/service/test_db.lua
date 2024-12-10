local skynet = require "skynet"

skynet.start(function()
    local db = skynet.queryservice(".db")
    
    -- 测试MySQL
    local res = skynet.call(db, "lua", "mysql_query", "SELECT NOW() as time")
    skynet.error("MySQL time:", res[1].time)
    
    -- 测试Redis
    local res = skynet.call(db, "lua", "redis_cmd", "SET", "test_key", "hello")
    skynet.error("Redis SET:", res)
    
    local res = skynet.call(db, "lua", "redis_cmd", "GET", "test_key")
    skynet.error("Redis GET:", res)
end) 