-- 业务逻辑
local skynet = require "skynet"

local db = {}

function db.test(mysql,redis,...)
    
end

function db.setAuth(mysql,redis,...)
    local numid, secret, subid, strType = ...
    local sql = string.format("INSERT INTO auth (numid, secret, subid, type) VALUES (%d, '%s', %d, '%s') ON DUPLICATE KEY UPDATE secret = '%s',type= VALUES(type),subid=subid+1, updated_at = CURRENT_TIMESTAMP;",numid,secret,subid,strType,secret)
    LOG.info(sql)
    local res = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if res.err then
        LOG.error("insert auth error: %s", res.err)
        return false
    end

    return db.getAuthSubid(mysql,redis,numid)
end

function db.getAuthSubid(mysql,redis,numid)
    local sql = string.format("SELECT subid FROM auth WHERE numid = %d;",numid)
    local res, err = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("select auth error: %s", err)
        return false
    end
    if #res == 0 then
        return nil
    end
    return res[1].subid
end

function db.getAuth(mysql,redis,...)
    
    local numid = ...
    LOG.info("getAuth:"..numid)
    local sql = string.format("SELECT * FROM auth WHERE numid = %d;",numid)
    local res, err = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("select auth error: %s", err)
        return false
    end
    if #res == 0 then
        return nil
    end
    return res[1]
end

function db.login(mysql,redis,...)
    local uid,password,loginType = ...
    local sql = string.format("SELECT * FROM %s WHERE userid = '%s' AND password = UPPER(MD5('%s'));",loginType,uid,password)
    local res, err = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("select auth error: %s", err)
        return false
    end
    if #res == 0 then
        return nil
    end
    return res[1]
end

return db