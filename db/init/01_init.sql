-- Claude Shop 数据库初始化

-- 创建测试数据库
CREATE DATABASE IF NOT EXISTS claude_shop_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 授权
GRANT ALL PRIVILEGES ON claude_shop_development.* TO 'claude_shop'@'%';
GRANT ALL PRIVILEGES ON claude_shop_test.* TO 'claude_shop'@'%';

FLUSH PRIVILEGES;