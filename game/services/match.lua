-- match.lua
-- 匹配服务，负责玩家匹配逻辑和队列管理
local skynet = require "skynet"
require "skynet.manager"
local CMD = {}
local name = "match"
local users = {}         -- 记录所有正在匹配的用户信息
local queueNum = 4       -- 匹配队列数量
local queueUserids = {}  -- 每个队列的用户id列表
local dTime = 1          -- 匹配检查间隔（秒）

-- 匹配成功后通知agent
local function reportToAgent(userid,gamedata)
    local user = users[userid]
    local agent = user.agent
    -- 通知agent进入游戏
    skynet.send(agent, "lua", "enterGame", gamedata)
end

-- 离开队列
local function leaveQueue(userid)
    LOG.info("leaveQueue %d", userid)
    if not users[userid] then
        return false
    end
    local queueid = users[userid].queueid
    if not queueUserids[queueid] then
        return false
    end 
    for i, v in ipairs(queueUserids[queueid]) do
        if v == userid then
            table.remove(queueUserids[queueid], i)
            break
        end
    end
    users[userid] = nil
    LOG.info("queueUserids %s", UTILS.tableToString(queueUserids))
    return true
end

-- 匹配成功
local function matchSuccess(userid1, userid2)
    -- 1.创建游戏
    -- 2.通知agent
    -- 3.删除queue里的用户
    reportToAgent(userid1, {})
    reportToAgent(userid2, {})
    
    leaveQueue(userid1)
    leaveQueue(userid2)
end

-- 检查队列，尝试匹配
local function checkQueue(queueid)
    LOG.info("checkQueue %d", queueid)
    local que = queueUserids[queueid]
    -- 循环前一个跟后一个比较rate，差值小于0.05，匹配成功
    for i = 1, #que do
        if i < #que then
            local userid1 = que[i]
            local userid2 = que[i+1]
            local user1 = users[userid1]
            local user2 = users[userid2]
            if math.abs(user1.rate - user2.rate) < 0.05 then
                LOG.info("match success %d %d", userid1, userid2)
                matchSuccess(userid1, userid2)
            end
        end
    end
end

-- 启动匹配服务，定时检查所有队列
function CMD.start()
    LOG.info("match start")
    skynet.fork(function()
		while true do
			for i = 1, queueNum do
				if queueUserids[i] and #queueUserids[i] >= 2 then
					checkQueue(i)
				end
			end
			skynet.sleep(dTime * 100)
		end
	end)
end

-- 停止匹配服务
function CMD.stop()
    LOG.info("match stop")
end

-- 玩家进入匹配队列
function CMD.enterQueue(agent, userid, queueid, rate)
    LOG.info("enterQueue %d %d", userid, queueid)
    if not users[userid] then
        users[userid] = {
            userid = userid,
            queueid = queueid or 0,
            rate = rate or 0,
            agent = agent,
            time = os.time(),
        }
    else
        return false
    end
    if not queueUserids[queueid] then
        queueUserids[queueid] = {}
    end
    --根据rate的大小插入队列
    local index = 1
    for i, v in ipairs(queueUserids[queueid]) do
        if rate > users[v].rate then
            index = i
            break
        end
    end
    table.insert(queueUserids[queueid], index, userid)
    return true
end

-- 玩家离开匹配队列
function CMD.leaveQueue(userid)
    return leaveQueue(userid)
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		--skynet.trace()
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
        skynet.register("." .. name)
	end)
end)