## WebSocket认证流程

1. 客户端建立WebSocket连接
2. 服务端发送随机挑战码（base64编码）
3. 客户端生成临时密钥并发送（base64编码）
4. 服务端返回DH交换后的密钥（base64编码）
5. 双方计算共享密钥（secret）
6. 客户端发送HMAC验证（base64编码）
7. 客户端发送DES加密的Token（base64编码）
8. 服务端验证并返回登录结果 