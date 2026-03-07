# WisePick 测试覆盖率报告

> 生成日期：2026-03-07
> 最后更新：2026-03-07（新增 14 个测试文件，372 个用例）

## 概览

| 指标 | 数值 |
|------|------|
| lib/ 源文件总数 | 133 |
| test/ 测试文件总数 | 85（+14） |
| 估算整体覆盖率 | ~72%（+19%） |

```
按层级统计：
├── core/       83%  (33/40)  █████████████████████░░░░  (+3)
├── features/   44%  (35/80)  ███████████░░░░░░░░░░░░░░
├── services/   60%  ( 6/10)  ███████████████░░░░░░░░░░
└── widgets/     0%  ( 0/10)  ░░░░░░░░░░░░░░░░░░░░░░░░░
```

---

## 已覆盖模块

### core/resilience（完整）
| 文件 | 测试文件 | 覆盖功能点 |
|------|---------|-----------|
| circuit_breaker.dart | circuit_breaker_test.dart | 状态转换、失败阈值、半开探测、回退策略 |
| retry_policy.dart | retry_policy_test.dart | 指数退避、最大重试次数、条件重试 |
| retry_budget.dart | retry_budget_test.dart | 预算消耗、预算恢复、超限拒绝 |
| global_rate_limiter.dart | global_rate_limiter_test.dart | 令牌桶、并发限制、超限处理 |
| adaptive_config.dart | adaptive_config_test.dart | 动态参数调整、负载感知 |
| auto_recovery.dart | auto_recovery_test.dart | 自动恢复触发、恢复策略 |
| self_healing_service.dart | self_healing_service_test.dart | 自愈检测、修复流程 |
| slo_manager.dart | slo_manager_test.dart | SLO 指标计算、违规告警 |
| network_error_detector.dart | network_error_detector_test.dart | 网络错误分类、可重试判断 |
| resilient_service_base.dart | resilient_service_base_test.dart | 基类执行流程、降级处理 |
| result.dart | result_test.dart | Success/Failure 构造、链式操作 |

### core/reliability（完整）
| 文件 | 测试文件 | 覆盖功能点 |
|------|---------|-----------|
| reliability_dashboard.dart | reliability_dashboard_test.dart | 指标聚合、健康评分 |
| predictive_load_manager.dart | predictive_load_manager_test.dart | 负载预测、扩缩容建议 |
| root_cause_analyzer.dart | root_cause_analyzer_test.dart | 故障根因分析、关联规则 |
| reliability_platform.dart | reliability_platform_coverage_test.dart | 平台初始化、组件集成 |

### core/observability（完整）
| 文件 | 测试文件 | 覆盖功能点 |
|------|---------|-----------|
| distributed_tracing.dart | distributed_tracing_test.dart | Span 创建、上下文传播、采样 |
| health_check.dart | health_check_test.dart | 健康检查注册、状态聚合 |
| metrics_collector.dart | metrics_collector_test.dart | 计数器、直方图、指标导出 |

### core/error & logging
| 文件 | 测试文件 | 覆盖功能点 |
|------|---------|-----------|
| app_error_mapper.dart | app_error_mapper_test.dart | HTTP 状态码映射、Dio 异常、中文错误消息 |
| app_logger.dart | app_logger_test.dart | 日志级别、格式化输出 |

### core/validation
| 文件 | 测试文件 | 覆盖功能点 |
|------|---------|-----------|
| ai_response_validator.dart | ai_response_validator_test.dart | JSON 格式验证、字段校验、异常响应处理 |

### features/（已覆盖部分）
| 文件 | 测试文件 | 覆盖功能点 |
|------|---------|-----------|
| auth/auth_service.dart | auth_service_test.dart | 登录、令牌刷新、登出、错误映射 |
| decision/decision_service.dart | decision_service_test.dart | 购买决策评分、折扣率、等级判定 |
| price_history/price_history_service.dart | price_history_service_test.dart | 价格记录、去重、趋势分析、购买建议 |
| cart/cart_service.dart | cart_service_test.dart | 增删改查购物车项 |
| chat/keyword_extractor.dart | keyword_extractor_test.dart | JSON 关键词提取、去重、长度过滤 |
| chat/streaming_text_filter.dart | streaming_text_filter_test.dart | 流式文本过滤、特殊字符处理 |
| chat/chat_error_mapper.dart | chat_error_mapper_test.dart | 所有错误类型映射、DioException 全状态码、iconForType |
| chat/chat_service.dart | chat_service_test.dart | 正常响应解析、错误处理、URL 构建、max_tokens、标题生成 |
| products/pdd_adapter.dart | pdd_adapter_test.dart | 拼多多数据转换、字段映射 |
| products/jd_adapter.dart | jd_adapter_test.dart | 5 种响应格式解析、价格/图片/销量/佣金字段映射、评分启发式修复、推广链接 |
| products/taobao_adapter.dart | taobao_adapter_test.dart | 响应格式解析、价格/优惠券/佣金/ID/图片字段映射、淘口令生成 |

### 压力测试（stress/）
覆盖弹性策略在高并发下的行为，CI 中通过 `@Tags(['stress'])` 标记跳过：
- chaos_engineering_test.dart — 混沌注入（延迟、崩溃、数据损坏）
- concurrency_stress_test.dart — 高并发突发流量
- degradation_analysis_test.dart — 性能降级曲线
- integration_stress_test.dart — 多组件联合压测
- production_traffic_test.dart — 生产流量模拟
- chaos_resilience_validation_test.dart — 全栈混沌验证
- resilience_strategy_test.dart — 策略管道压测

### services/sync/（新增）
| 文件 | 测试文件 | 覆盖功能点 |
|------|---------|-----------|
| conflict_resolver.dart | conflict_resolver_test.dart | 冲突类型推荐策略、keepLocal/keepServer/lastWriteWins/merge/askUser、购物车数量合并、会话消息去重排序、CartConflictResolver/ConversationConflictResolver 全场景 |
| offline_sync_queue.dart | offline_sync_queue_test.dart | 队列增删查、hasPendingChanges、queued_at 时间戳注入、防御性拷贝、clearAll、重复初始化保护 |
| sync_manager.dart（SyncState） | sync_state_test.dart | SyncState 默认值、isSyncing、hasPendingChanges、copyWith 全字段（含 null sentinel）、SyncStatus 枚举 |
| cart_sync_client.dart | cart_sync_client_test.dart | CartItemChange 字段映射/序列化、CartSyncResponse 解析、本地存储读写、sync/getCloudItems/getCloudVersion 全路径 |
| conversation_sync_client.dart | conversation_sync_client_test.dart | ConversationChange/MessageChange 序列化解析、本地存储读写、sync/getCloudConversations/getCloudMessages/getCloudVersion 全路径 |

### services/（新增）
| 文件 | 测试文件 | 覆盖功能点 |
|------|---------|-----------|
| ai_prompt_service.dart | ai_prompt_service_test.dart | buildMessages/buildCasualPromptMessages/buildRecommendationPromptMessages/buildProductDetailMessages/buildPrompt/buildPromptMessages/buildCasualPrompt/buildRecommendationPrompt 全接口 |

### features/analytics/（新增）
| 文件 | 测试文件 | 覆盖功能点 |
|------|---------|-----------|
| analytics_models.dart | analytics_models_test.dart | AnalyticsDateRange 描述/预设范围、PlatformPreference.displayName、HourlyDistribution.displayHour、WeekdayDistribution.displayName、ConsumptionStructure/UserPreferences/ShoppingTimeAnalysis.empty、AnalyticsState 全状态 |

### core/oauth/（新增）
| 文件 | 测试文件 | 覆盖功能点 |
|------|---------|-----------|
| oauth_state_store.dart | oauth_state_store_test.dart | save/consume 正常流程、一次性消费、过期逻辑、并发场景 |
| jd_oauth_service.dart | jd_oauth_service_test.dart | JdToken 序列化/反序列化/isExpired、InMemoryTokenStore CRUD、buildAuthorizeUrl 全参数、getAccessTokenForUser、refreshIfNeededForRequest |
| oauth_controller.dart | oauth_controller_test.dart | authorize 返回结构、UUID state、state 保存到 store、URL 参数、scope 默认值、多次调用独立性 |

---

## 未覆盖模块

### ❌ 高优先级（核心业务逻辑）

目前已无高优先级未覆盖模块。

### ⚠️ 中优先级（服务层）

| 模块 | 文件 |
|------|------|
| features/analytics/ | analytics_service.dart（依赖 PDF/path_provider，需集成测试） |
| features/admin/ | admin_service.dart |
| features/chat/ | conversation_repository.dart |
| services/ | notification_service.dart, price_refresh_service.dart, share_service.dart |

### ℹ️ 低优先级（UI 层）

页面组件和通用 Widget 通常通过集成测试或手动测试覆盖：

| 类别 | 文件数 |
|------|-------|
| features/*/pages（各功能页面） | 11 |
| widgets/（通用 UI 组件） | 10 |
| features/home/ | 2 |
| features/settings/ | 2 |
| core/theme/ | 2 |

---

## 补充测试建议（优先级排序）

1. **features/chat/conversation_repository.dart** — 会话 CRUD、Hive 持久化
2. **features/admin/admin_service.dart** — 管理员服务逻辑
3. **features/analytics/analytics_service.dart** — 需集成测试（依赖 PDF/path_provider）
