-- ============================================================
-- WisePick Security Questions Feature
-- Version: 003
-- Created: 2026-01-24
-- Description: Add user security questions table for password recovery
-- ============================================================

-- ============================================================
-- 1. User Security Questions Table (user_security_questions)
-- ============================================================
CREATE TABLE IF NOT EXISTS user_security_questions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    question        VARCHAR(500) NOT NULL,
    answer_hash     VARCHAR(255) NOT NULL,
    question_order  INTEGER NOT NULL DEFAULT 1,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, question_order)
);

-- Index
CREATE INDEX IF NOT EXISTS idx_security_questions_user ON user_security_questions(user_id);

-- Update trigger
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_security_questions_updated_at') THEN
        CREATE TRIGGER update_security_questions_updated_at 
            BEFORE UPDATE ON user_security_questions 
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END
$$;

-- ============================================================
-- 2. Password Reset Tokens Table (password_reset_tokens)
-- ============================================================
CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token           VARCHAR(255) NOT NULL UNIQUE,
    verified        BOOLEAN DEFAULT FALSE,
    expires_at      TIMESTAMP WITH TIME ZONE NOT NULL,
    used_at         TIMESTAMP WITH TIME ZONE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index
CREATE INDEX IF NOT EXISTS idx_password_reset_token ON password_reset_tokens(token);
CREATE INDEX IF NOT EXISTS idx_password_reset_user ON password_reset_tokens(user_id);

-- ============================================================
-- Table Comments
-- ============================================================
COMMENT ON TABLE user_security_questions IS 'User security questions for password recovery';
COMMENT ON TABLE password_reset_tokens IS 'Tokens for password reset flow';

-- ============================================================
-- Done
-- ============================================================
