~~~mermaid
%%{init: {'theme': 'neutral'}}%%
graph TD
%% ======= 客户端部分 =======
CWeb[Web/移动客户端] -->|1认证请求<br>proto/c2s.sproto| CLogin[登录服务<br>logind.lua:8001]
CGame[游戏客户端] -->|1认证请求<br>proto/c2s.sproto| CLogin
%% ======= 服务端认证流程 =======
CLogin -->|2数据库验证| CDB[(MySQL数据库<br>game/services/logind.lua)]
CLogin -->|3生成会话Token| CToken[Token缓存]
%% ======= 网关连接流程 =======
CWeb -->|4WebSocket连接<br>wsgateserver.lua:9002| CGate[网关集群]
CGame -->|4TCP连接<br>watchdog.lua:9001| CGate
CGate -->|5Token验证| CToken
CGate -->|6创建代理| CAgent[玩家代理服务<br>agent.lua]
%% ======= 游戏业务逻辑 =======
CAgent -->|7业务请求| CLogic[游戏逻辑服务]
CLogic -->|8数据持久化| CDB
CLogic -->|9跨服通信| CCluster[集群服务<br>cluster.lua]
%% ======= 监控体系 =======
CGate -->|心跳监控| CMonitor[监控服务<br>monitor.lua]
CAgent -->|状态上报| CMonitor
CMonitor -->|告警| CAlert[告警服务]
%% ======= 基础组件 =======
CConfig[配置中心<br>sharedatad.lua]
CLog[日志服务<br>service/logind.lua]
CCache[缓存服务<br>redis.cluster.lua]
style CLogin fill:#F9E79F,stroke:#F1C40F
style CGate fill:#AED6F1,stroke:#3498DB
style CAgent fill:#A2D9CE,stroke:#48C9B0
~~~