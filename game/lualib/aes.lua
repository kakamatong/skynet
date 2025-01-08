local crypt = require "skynet.crypt"
local aes = {}

-- 使用 xor_str 和 hashkey 实现简单的加密
function aes.encrypt(data, key)
    -- 生成密钥哈希
    local hashed_key = crypt.hashkey(key)
    -- 使用 xor 加密
    return crypt.xor_str(data, hashed_key)
end

-- 解密（使用相同的 xor 操作）
function aes.decrypt(data, key)
    -- 生成相同的密钥哈希
    local hashed_key = crypt.hashkey(key)
    -- 使用 xor 解密
    return crypt.xor_str(data, hashed_key)
end

return aes 