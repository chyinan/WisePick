-- ============================================================
-- WisePick Database Fix Migration
-- Version: 002
-- Date: 2026-01-21
-- Description: Fix missing columns and constraints
-- ============================================================

-- ============================================================
-- 1. Fix login_attempts table - add missing columns
-- ============================================================
ALTER TABLE login_attempts 
ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE login_attempts 
ADD COLUMN IF NOT EXISTS user_agent TEXT;

ALTER TABLE login_attempts 
ADD COLUMN IF NOT EXISTS failure_reason VARCHAR(255);

-- ============================================================
-- 2. Fix cart_items table - add unique constraint for ON CONFLICT
-- ============================================================
-- First, remove any duplicate entries (keep the most recent one)
DELETE FROM cart_items a
USING cart_items b
WHERE a.id < b.id 
  AND a.user_id = b.user_id 
  AND a.product_id = b.product_id;

-- Add unique constraint for (user_id, product_id)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'cart_items_user_product_unique'
    ) THEN
        ALTER TABLE cart_items 
        ADD CONSTRAINT cart_items_user_product_unique 
        UNIQUE (user_id, product_id);
    END IF;
END $$;

-- ============================================================
-- Done
-- ============================================================
