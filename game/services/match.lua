local skynet = require "skynet"

local CMD = {}
local name = "match"
local users = {}
local queueNum = 4
local queueUserids = {}
local dTime = 1

local function matchSuccess(userid1, userid2)
    -- 1.创建游戏
    -- 2.删除queue里的用户
    -- 3.通知agent
    local user1 = users[userid1]
    local user2 = users[userid2]
    local agent1 = user1.agent
    local agent2 = user2.agent
    skynet.call(agent1, "lua", "enterGame", userid2)
end

local function checkQueue(queueid)
    local que = queueUserids[queueid]
    -- 循环前一个跟后一个比较rate，差值小于0.05，匹配成功
    for i = 1, #que do
        if i < #que - 1 then
            local userid1 = que[i]
            local userid2 = que[i+1]
            local user1 = users[userid1]
            local user2 = users[userid2]
            if math.abs(user1.rate - user2.rate) < 0.05 then
                LOG.info("match success %d %d", userid1, userid2)
                
            end
        end
    end
        
end

function CMD.start()
    LOG.info("match start")

    skynet.fork(function()
		while true do
			for i = 1, queueNum do
				if #queueUserids[i] >= 2 then
					checkQueue(i)
				end
			end
			
			skynet.sleep(dTime * 100)
		end
	end)
end

function CMD.stop()
    LOG.info("match stop")
end

function CMD.enterQueue(agent, userid, queueid, rate)
    LOG.info("enterQueue %d", userid)
    if not users[userid] then
        users[userid] = {
            userid = userid,
            queueid = queueid or 0,
            rate = rate or 0,
            agent = agent,
        }
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

function CMD.leaveQueue(userid)
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
    LOG.info("queueUserids %s", UTILS.tableToString(queueUserids))
    return true
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		--skynet.trace()
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
        skynet.register("." .. name)
	end)
end)