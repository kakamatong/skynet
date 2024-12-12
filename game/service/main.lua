local skynet = require "skynet"
require "skynet.manager"

skynet.start(function()
    -- 初始化随机种子
    math.randomseed(os.time())
    -- 启动DEBUG控制台
    skynet.newservice("debug_console", skynet.getenv "debug_console_port")
    
    -- 启动数据库服务
    local db = skynet.newservice("db_service")
    skynet.name(".db", db)
    
    -- 启动登录服务(Socket)
    local login = skynet.newservice("login_service", "socket")
    skynet.name(".login", login)
    
    -- 启动登录服务(WebSocket)
    local login_ws = skynet.newservice("login_service", "websocket")
    skynet.name(".login_ws", login_ws)
    
    -- 启动网关相关服务
    local watchdog = skynet.newservice("watchdog")
    skynet.name(".watchdog", watchdog)
    
    local gate = skynet.newservice("gate_service")
    skynet.name(".gate", gate)
    
    -- 启动游戏服务
    -- local game = skynet.newservice("game_service")
    -- skynet.name(".game", game)
    
    -- 启动聊天服务
    -- local chat = skynet.newservice("chat_service")
    -- skynet.name(".chat", chat)
    
    -- 启动完成
    LOG.info("Server started")
end) 