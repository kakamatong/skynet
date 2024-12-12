local crypt = require "skynet.crypt"
local aes = {}

-- AES加密
function aes.encrypt(data, key)
    -- 生成IV
    local iv = string.rep("\0", 16)
    -- 使用PKCS7填充
    local padding = 16 - (#data % 16)
    data = data .. string.rep(string.char(padding), padding)
    -- AES-CBC加密
    return crypt.aes_cbc_encrypt(key, data, iv)
end

-- AES解密
function aes.decrypt(data, key)
    -- 使用相同的IV
    local iv = string.rep("\0", 16)
    -- AES-CBC解密
    local result = crypt.aes_cbc_decrypt(key, data, iv)
    -- 移除PKCS7填充
    local padding = string.byte(result, -1)
    return string.sub(result, 1, -padding-1)
end

return aes 