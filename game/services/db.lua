-- 业务逻辑
local skynet = require "skynet"

local db = {}

function db.test(mysql,redis,...)
    
end

function db.setAuth(mysql,redis,...)
    local userid, secret, subid, strType = ...
    local sql = string.format("INSERT INTO auth (userid, secret, subid, type) VALUES (%d, '%s', %d, '%s') ON DUPLICATE KEY UPDATE secret = '%s',type= VALUES(type),subid=subid+1, updated_at = CURRENT_TIMESTAMP;",userid,secret,subid,strType,secret)
    LOG.info(sql)
    local res = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if res.err then
        LOG.error("insert auth error: %s", res.err)
        return false
    end

    return db.getAuthSubid(mysql,redis,userid)
end

function db.getAuthSubid(mysql,redis,userid)
    local sql = string.format("SELECT subid FROM auth WHERE userid = %d;",userid)
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
    
    local userid = ...
    LOG.info("getAuth:"..userid)
    local sql = string.format("SELECT * FROM auth WHERE userid = %d;",userid)
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

function db.doAuth(mysql,redis,...)
    local userid, secret =...
    local sql = string.format("UPDATE auth SET secret = '%s' WHERE userid = %d;",secret,userid)
    local res, err = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("update auth error: %s", err)
        return false
    end
    return true
end

function db.checkAuth(mysql,redis,...)
    local userid, secret =...
    local sql = string.format("SELECT * FROM auth WHERE userid = %d AND secret = '%s';",userid,secret)
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
    local username,password,loginType = ...
    local sql = string.format("SELECT * FROM %s WHERE username = '%s' AND password = UPPER(MD5('%s'));",loginType,username,password)
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