-- ============================================================
-- WisePick 用户账号系统数据库迁移
-- 版本: 001
-- 创建日期: 2026-01-20
-- 描述: 创建用户认证和数据同步所需的表结构
-- ============================================================

-- 启用 UUID 扩展
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. 用户表 (users)
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255) UNIQUE NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    nickname        VARCHAR(100),
    avatar_url      VARCHAR(500),
    email_verified  BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_login_at   TIMESTAMP WITH TIME ZONE,
    status          VARCHAR(20) DEFAULT 'active'  -- active, suspended, deleted
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);

-- 更新时间触发器
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at 
    BEFORE UPDATE ON users 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 2. 设备/会话表 (user_sessions)
-- ============================================================
CREATE TABLE IF NOT EXISTS user_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id       VARCHAR(100) NOT NULL,
    device_name     VARCHAR(200),
    device_type     VARCHAR(50),  -- ios, android, windows, macos, linux, web
    refresh_token   VARCHAR(500) NOT NULL,
    push_token      VARCHAR(500),
    last_active_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ip_address      INET,
    user_agent      TEXT,
    is_active       BOOLEAN DEFAULT TRUE
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_sessions_user ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_device ON user_sessions(device_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_user_device ON user_sessions(user_id, device_id);
CREATE INDEX IF NOT EXISTS idx_sessions_refresh_token ON user_sessions(refresh_token);

-- ============================================================
-- 3. 购物车表 (cart_items)
-- ============================================================
CREATE TABLE IF NOT EXISTS cart_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id      VARCHAR(100) NOT NULL,
    platform        VARCHAR(20) NOT NULL,  -- taobao, jd, pdd
    title           VARCHAR(500) NOT NULL,
    price           DECIMAL(12, 2) NOT NULL,
    original_price  DECIMAL(12, 2),
    coupon          DECIMAL(12, 2) DEFAULT 0,
    final_price     DECIMAL(12, 2),
    image_url       VARCHAR(1000),
    shop_title      VARCHAR(200),
    link            VARCHAR(2000),
    description     TEXT,
    rating          DECIMAL(3, 2),
    sales           INTEGER,
    commission      DECIMAL(12, 2),
    quantity        INTEGER DEFAULT 1,
    initial_price   DECIMAL(12, 2),
    current_price   DECIMAL(12, 2),
    raw_data        JSONB,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at      TIMESTAMP WITH TIME ZONE,
    sync_version    BIGINT DEFAULT 1
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_cart_user ON cart_items(user_id);
CREATE INDEX IF NOT EXISTS idx_cart_user_product ON cart_items(user_id, product_id);
CREATE INDEX IF NOT EXISTS idx_cart_sync ON cart_items(user_id, sync_version);
CREATE INDEX IF NOT EXISTS idx_cart_deleted ON cart_items(user_id, deleted_at) WHERE deleted_at IS NULL;

-- 更新时间触发器
CREATE TRIGGER update_cart_items_updated_at 
    BEFORE UPDATE ON cart_items 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 4. 会话表 (conversations)
-- ============================================================
CREATE TABLE IF NOT EXISTS conversations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_id       VARCHAR(100) NOT NULL,
    title           VARCHAR(500),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at      TIMESTAMP WITH TIME ZONE,
    sync_version    BIGINT DEFAULT 1,
    UNIQUE(user_id, client_id)
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_conv_user ON conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_conv_sync ON conversations(user_id, sync_version);
CREATE INDEX IF NOT EXISTS idx_conv_deleted ON conversations(user_id, deleted_at) WHERE deleted_at IS NULL;

-- 更新时间触发器
CREATE TRIGGER update_conversations_updated_at 
    BEFORE UPDATE ON conversations 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 5. 消息表 (messages)
-- ============================================================
CREATE TABLE IF NOT EXISTS messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    client_id       VARCHAR(100) NOT NULL,
    role            VARCHAR(20) NOT NULL,  -- user, assistant
    content         TEXT NOT NULL,
    products        JSONB,
    keywords        JSONB,
    ai_parsed_raw   TEXT,
    failed          BOOLEAN DEFAULT FALSE,
    retry_for_text  TEXT,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    sync_version    BIGINT DEFAULT 1,
    UNIQUE(conversation_id, client_id)
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_msg_conv ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_msg_sync ON messages(conversation_id, sync_version);
CREATE INDEX IF NOT EXISTS idx_msg_created ON messages(conversation_id, created_at);

-- ============================================================
-- 6. 同步版本跟踪表 (sync_versions)
-- ============================================================
CREATE TABLE IF NOT EXISTS sync_versions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entity_type     VARCHAR(50) NOT NULL,  -- cart, conversations, messages
    current_version BIGINT DEFAULT 0,
    last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, entity_type)
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_sync_versions_user ON sync_versions(user_id);

-- ============================================================
-- 7. 登录尝试记录表 (用于防暴力破解)
-- ============================================================
CREATE TABLE IF NOT EXISTS login_attempts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255) NOT NULL,
    ip_address      INET,
    attempted_at    TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    success         BOOLEAN DEFAULT FALSE
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_login_attempts_email ON login_attempts(email, attempted_at);
CREATE INDEX IF NOT EXISTS idx_login_attempts_ip ON login_attempts(ip_address, attempted_at);

-- 清理旧记录的函数（可定期调用）
CREATE OR REPLACE FUNCTION cleanup_old_login_attempts()
RETURNS void AS $$
BEGIN
    DELETE FROM login_attempts WHERE attempted_at < NOW() - INTERVAL '1 day';
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 8. 邮箱验证码表
-- ============================================================
CREATE TABLE IF NOT EXISTS email_verifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255) NOT NULL,
    code            VARCHAR(10) NOT NULL,
    type            VARCHAR(20) NOT NULL,  -- register, reset_password, verify
    expires_at      TIMESTAMP WITH TIME ZONE NOT NULL,
    used_at         TIMESTAMP WITH TIME ZONE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_email_verif_email ON email_verifications(email, type, expires_at);

-- ============================================================
-- 辅助函数：获取下一个同步版本号
-- ============================================================
CREATE OR REPLACE FUNCTION get_next_sync_version(
    p_user_id UUID,
    p_entity_type VARCHAR(50)
)
RETURNS BIGINT AS $$
DECLARE
    v_version BIGINT;
BEGIN
    INSERT INTO sync_versions (user_id, entity_type, current_version, last_updated_at)
    VALUES (p_user_id, p_entity_type, 1, NOW())
    ON CONFLICT (user_id, entity_type) 
    DO UPDATE SET 
        current_version = sync_versions.current_version + 1,
        last_updated_at = NOW()
    RETURNING current_version INTO v_version;
    
    RETURN v_version;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Table Comments
-- ============================================================
COMMENT ON TABLE users IS 'User accounts table';
COMMENT ON TABLE user_sessions IS 'User login sessions, supports multi-device login';
COMMENT ON TABLE cart_items IS 'User shopping cart with soft delete and version sync';
COMMENT ON TABLE conversations IS 'AI chat conversations';
COMMENT ON TABLE messages IS 'Chat messages';
COMMENT ON TABLE sync_versions IS 'Sync version tracking';
COMMENT ON TABLE login_attempts IS 'Login attempts for security protection';
COMMENT ON TABLE email_verifications IS 'Email verification codes';

-- ============================================================
-- Done
-- ============================================================
