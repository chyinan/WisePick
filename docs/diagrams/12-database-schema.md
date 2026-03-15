# 图12：数据库表结构总览

| 表名 | 说明 | 主要字段 |
|------|------|----------|
| **users** | 用户表 | id、username、email、password_hash、created_at、last_login |
| **refresh_tokens** | 刷新令牌表 | id、user_id、token_hash、expires_at、revoked |
| **cart_items** | 购物车表 | id、user_id、product_id、platform、title、price、quantity、synced_at |
| **conversations** | 会话表 | id、user_id、title、messages（JSONB）、created_at、updated_at |
| **price_history** | 价格历史表 | id、product_id、platform、price、recorded_at |
