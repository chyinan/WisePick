# 京东联盟高级网页爬虫

基于 Dart + Puppeteer 的京东联盟商品信息爬取服务，具备人类行为模拟、反检测、高级缓存等功能。

## 功能特性

- ✅ **双源爬取** - 同时从京东联盟和京东首页获取信息，数据更完整
- ✅ **人类行为模拟** - 贝塞尔曲线鼠标移动、随机输入延迟、自然滚动
- ✅ **反检测机制** - Stealth 模式、指纹随机化、User-Agent 轮换
- ✅ **Cookie 管理** - 自动加载、过期检测、远程更新
- ✅ **浏览器池** - 实例复用、并发控制、自动清理
- ✅ **高级缓存** - LRU 淘汰、TTL 过期、命中率统计
- ✅ **请求去重** - 并发请求合并、避免重复爬取
- ✅ **错误处理** - 自动分类、日志记录、回调通知
- ✅ **性能监控** - 请求耗时、成功率、P95/P99 统计

## 数据来源

| 数据来源 | 获取内容 | 使用场景 |
|---------|---------|---------|
| **京东联盟** | 推广链接、佣金、短链接 | 生成带货推广链接 |
| **京东首页** | 店铺名、商品图片、最新价格 | 获取完整商品信息 |

两个来源共用同一份 Cookie（京东联盟登录后的 Cookie）。

## API 端点

### 商品信息

#### 获取推广链接（京东联盟）
```
GET /api/jd/scraper/product/:skuId
```

**参数:**
- `skuId` (路径参数) - 商品 SKU ID
- `forceRefresh` (查询参数, 可选) - 设为 `true` 强制刷新缓存

**响应:**
```json
{
  "success": true,
  "data": {
    "skuId": "10183999034312",
    "title": "商品标题",
    "price": 899.0,
    "originalPrice": 999.0,
    "commission": 45.0,
    "commissionRate": 0.05,
    "promotionLink": "https://...",
    "shortLink": "https://u.jd.com/xxx",
    "cached": false,
    "fetchTime": "2026-01-14T10:30:00Z"
  }
}
```

#### 获取商品详情（京东首页）
```
GET /api/jd/scraper/product/:skuId/detail
```

通过京东首页搜索获取商品详细信息，包括店铺名、图片等。

**参数:**
- `skuId` (路径参数) - 商品 SKU ID

**响应:**
```json
{
  "success": true,
  "data": {
    "skuId": "10183999034312",
    "title": "商品标题",
    "price": 899.0,
    "originalPrice": 999.0,
    "shopName": "京东自营店",
    "imageUrl": "https://img.jd.com/xxx.jpg",
    "fetchTime": "2026-01-14T10:30:00Z"
  },
  "source": "jd_main_page"
}
```

#### 获取完整信息（双源爬取）⭐ 推荐
```
GET /api/jd/scraper/product/:skuId/enhanced
```

同时从京东联盟和京东首页获取信息，合并返回最完整的数据。

**参数:**
- `skuId` (路径参数) - 商品 SKU ID
- `forceRefresh` (查询参数, 可选) - 设为 `true` 强制刷新缓存
- `includePromotion` (查询参数, 可选) - 是否包含推广链接，默认 `true`
- `includeDetail` (查询参数, 可选) - 是否包含详细信息，默认 `true`

**响应:**
```json
{
  "success": true,
  "data": {
    "skuId": "10183999034312",
    "title": "商品标题",
    "price": 899.0,
    "originalPrice": 999.0,
    "commission": 45.0,
    "commissionRate": 0.05,
    "promotionLink": "https://...",
    "shortLink": "https://u.jd.com/xxx",
    "shopName": "京东自营店",
    "imageUrl": "https://img.jd.com/xxx.jpg",
    "cached": false,
    "fetchTime": "2026-01-14T10:30:00Z"
  },
  "sources": {
    "promotion": true,
    "detail": true
  }
}
```

#### 批量获取推广链接
```
POST /api/jd/scraper/products/batch
Content-Type: application/json

{
  "skuIds": ["sku1", "sku2", "sku3"],
  "maxConcurrency": 2
}
```

**响应:**
```json
{
  "success": true,
  "data": [...],
  "total": 3,
  "success_count": 3
}
```

#### 批量获取完整信息（双源爬取）⭐ 推荐
```
POST /api/jd/scraper/products/batch/enhanced
Content-Type: application/json

{
  "skuIds": ["sku1", "sku2", "sku3"],
  "maxConcurrency": 2,
  "includePromotion": true,
  "includeDetail": true
}
```

**响应:**
```json
{
  "success": true,
  "data": [...],
  "total": 3,
  "success_count": 3,
  "sources": {
    "promotion": true,
    "detail": true
  }
}
```

### Cookie 管理

#### 获取 Cookie 状态
```
GET /api/jd/cookie/status
```

**响应:**
```json
{
  "success": true,
  "data": {
    "exists": true,
    "savedAt": "2026-01-14T08:00:00Z",
    "ageInDays": 1,
    "isPossiblyExpired": false,
    "lastValidatedAt": "2026-01-14T10:00:00Z",
    "isValid": true
  }
}
```

#### 更新 Cookie
```
POST /api/jd/cookie/update
Content-Type: application/json

{
  "cookie": "pin=xxx; unick=xxx; _tp=xxx; ..."
}
```

### 服务状态

#### 获取服务状态
```
GET /api/jd/scraper/status
```

**响应:**
```json
{
  "success": true,
  "data": {
    "initialized": true,
    "closed": false,
    "cookie": {...},
    "browserPool": {
      "maxBrowsers": 3,
      "total": 1,
      "available": 1,
      "inUse": 0
    },
    "cache": {
      "enabled": true,
      "size": 10,
      "maxSize": 500,
      "hitRate": "85.50",
      "hits": 100,
      "misses": 17,
      "evictions": 0
    },
    "deduplicator": {
      "pendingCount": 0
    },
    "concurrency": {
      "maxConcurrency": 3,
      "currentCount": 0,
      "queueLength": 0
    },
    "errors": {
      "total": 2,
      "last24h": 1,
      "lastHour": 0,
      "byType": {
        "timeout": 1,
        "networkError": 1
      }
    },
    "performance": {
      "totalRequests": 117,
      "totalErrors": 2
    }
  }
}
```

### 错误日志

#### 获取错误日志
```
GET /api/jd/errors?limit=50&type=cookieExpired
```

**参数:**
- `limit` (可选) - 返回条目数，默认 50
- `type` (可选) - 错误类型过滤

### 缓存管理

#### 清除缓存
```
POST /api/jd/cache/clear
```

## 兼容旧接口

为了向后兼容，保留了旧的 API 端点：

```
GET /api/get-jd-promotion?sku=xxx
```

此接口使用新的 Dart 爬虫服务，响应格式与旧版本兼容。

## 使用示例

### 命令行测试

```bash
# 查看服务状态
curl http://localhost:9527/api/jd/scraper/status

# 查看 Cookie 状态
curl http://localhost:9527/api/jd/cookie/status

# 更新 Cookie
curl -X POST -H "Content-Type: application/json" \
  -d '{"cookie":"your_cookie_string"}' \
  http://localhost:9527/api/jd/cookie/update

# 获取推广链接（京东联盟）
curl http://localhost:9527/api/jd/scraper/product/10183999034312

# 获取商品详情（京东首页）
curl http://localhost:9527/api/jd/scraper/product/10183999034312/detail

# 获取完整信息（双源爬取，推荐）⭐
curl http://localhost:9527/api/jd/scraper/product/10183999034312/enhanced

# 仅获取详情，不获取推广链接
curl "http://localhost:9527/api/jd/scraper/product/10183999034312/enhanced?includePromotion=false"

# 批量获取推广链接
curl -X POST -H "Content-Type: application/json" \
  -d '{"skuIds":["sku1","sku2"]}' \
  http://localhost:9527/api/jd/scraper/products/batch

# 批量双源爬取（推荐）⭐
curl -X POST -H "Content-Type: application/json" \
  -d '{"skuIds":["sku1","sku2"],"includePromotion":true,"includeDetail":true}' \
  http://localhost:9527/api/jd/scraper/products/batch/enhanced
```

### Dart 代码调用

```dart
import 'package:wisepick_proxy_server/jd_scraper/jd_scraper.dart';

void main() async {
  // 获取服务实例
  final service = JdScraperService.instance;
  await service.initialize();

  try {
    // 方式1: 仅获取推广链接（京东联盟）
    final promoInfo = await service.getProductInfo('10183999034312');
    print('推广链接: ${promoInfo.promotionLink}');

    // 方式2: 仅获取商品详情（京东首页）
    final detailInfo = await service.getProductDetailFromJdMain('10183999034312');
    print('店铺名: ${detailInfo.shopName}');
    print('图片: ${detailInfo.imageUrl}');

    // 方式3: 双源爬取，获取完整信息（推荐）⭐
    final fullInfo = await service.getProductInfoEnhanced('10183999034312');
    print('价格: ${fullInfo.price}');
    print('店铺名: ${fullInfo.shopName}');
    print('推广链接: ${fullInfo.promotionLink}');

    // 批量双源爬取
    final results = await service.getBatchProductInfoEnhanced(['sku1', 'sku2']);
    for (final item in results) {
      print('${item.skuId}: ${item.title} - ${item.shopName}');
    }
  } finally {
    await service.close();
  }
}
```

## Cookie 获取方法

1. 登录 https://union.jd.com/
2. 打开浏览器开发者工具 (F12)
3. 切换到 Network 标签
4. 刷新页面
5. 点击任意请求，在 Headers 中找到 Cookie
6. 复制完整的 Cookie 字符串
7. 通过 API 或配置文件更新 Cookie

## 错误类型

| 类型 | HTTP 状态码 | 说明 |
|------|------------|------|
| `cookieExpired` | 401 | Cookie 已过期，需要重新登录 |
| `loginRequired` | 401 | 需要登录 |
| `antiBotDetected` | 403 | 触发了反爬虫机制 |
| `productNotFound` | 404 | 商品不存在 |
| `timeout` | 504 | 请求超时 |
| `networkError` | 503 | 网络错误 |
| `unknown` | 500 | 未知错误 |

## 配置说明

服务配置可通过代码设置：

```dart
final service = JdScraperService(
  config: JdScraperConfig(
    browserConfig: BrowserPoolConfig(
      maxBrowsers: 3,
      headless: true,
    ),
    cacheDuration: Duration(minutes: 10),
    maxRetries: 3,
    retryDelay: Duration(seconds: 2),
  ),
);
```

## 文件结构

```
server/lib/jd_scraper/
├── jd_scraper.dart              # 主入口
├── jd_scraper_service.dart      # 核心服务
├── jd_scraper_routes.dart       # HTTP API 路由
├── cookie_manager.dart          # Cookie 管理
├── browser_pool.dart            # 浏览器池
├── human_behavior_simulator.dart # 行为模拟
├── error_handler.dart           # 错误处理
├── cache_manager.dart           # 缓存管理
└── models/
    ├── models.dart
    ├── product_info.dart
    ├── cookie_data.dart
    └── scraper_error.dart
```

## 注意事项

1. **Cookie 有效期**: 京东联盟 Cookie 通常有效期 7-30 天，建议定期检查
2. **请求频率**: 建议单次请求间隔 1-3 秒，并发数不超过 3
3. **反爬虫**: 如频繁触发验证码，请降低请求频率或更换 Cookie
4. **内存占用**: 长时间运行建议监控内存，必要时重启服务

