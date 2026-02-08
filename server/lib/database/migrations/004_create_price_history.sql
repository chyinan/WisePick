-- ============================================================
-- WisePick Price History Table
-- Version: 004
-- Created: 2026-02-07
-- Description: Create price_history table for tracking product price changes
-- ============================================================

-- ============================================================
-- 1. Price History Table (price_history)
-- ============================================================
CREATE TABLE IF NOT EXISTS price_history (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id      VARCHAR(100) NOT NULL,
    platform        VARCHAR(20) NOT NULL,  -- taobao, jd, pdd
    price           DECIMAL(12, 2) NOT NULL,
    original_price  DECIMAL(12, 2),
    coupon          DECIMAL(12, 2) DEFAULT 0,
    final_price     DECIMAL(12, 2),
    title           VARCHAR(500),
    source          VARCHAR(50) DEFAULT 'auto',  -- auto, manual, scraper
    recorded_at     TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_price_history_product ON price_history(product_id);
CREATE INDEX IF NOT EXISTS idx_price_history_product_platform ON price_history(product_id, platform);
CREATE INDEX IF NOT EXISTS idx_price_history_recorded ON price_history(product_id, recorded_at);
CREATE INDEX IF NOT EXISTS idx_price_history_platform ON price_history(platform);

-- ============================================================
-- Table Comments
-- ============================================================
COMMENT ON TABLE price_history IS 'Product price history for tracking price changes over time';

-- ============================================================
-- Done
-- ============================================================
