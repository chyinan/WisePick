/// 一键测试所有平台API接口可用性
/// 用法：
///   dart run scripts/test_all_apis.dart
///
/// 需要在 .env 或环境变量中设置以下配置：
///   - BACKEND_BASE: 后端服务器地址 (默认: http://localhost:9527)
///   - PDD_CLIENT_ID, PDD_CLIENT_SECRET, PDD_PID: 拼多多配置
///   - JD_APP_KEY, JD_APP_SECRET, JD_UNION_ID: 京东配置
///   - TAOBAO_APP_KEY, TAOBAO_APP_SECRET, TAOBAO_ADZONE_ID: 淘宝配置

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../lib/core/api_client.dart';
import '../lib/core/pdd_client.dart';
import '../lib/core/config.dart';

/// 测试结果枚举
enum TestStatus { pass, fail, skip }

/// 单个测试结果
class TestResult {
  final String name;
  final String platform;
  final TestStatus status;
  final String? message;
  final String? errorDetail;
  final Duration? duration;

  TestResult({
    required this.name,
    required this.platform,
    required this.status,
    this.message,
    this.errorDetail,
    this.duration,
  });

  String get statusIcon {
    switch (status) {
      case TestStatus.pass:
        return '✅';
      case TestStatus.fail:
        return '❌';
      case TestStatus.skip:
        return '⏭️';
    }
  }

  String get statusText {
    switch (status) {
      case TestStatus.pass:
        return 'PASS';
      case TestStatus.fail:
        return 'FAIL';
      case TestStatus.skip:
        return 'SKIP';
    }
  }
}

/// API测试器
class ApiTester {
  final ApiClient _client;
  final String _backendBase;
  final List<TestResult> _results = [];

  ApiTester({String? backendBase})
      : _client = ApiClient(),
        _backendBase = backendBase ??
            Platform.environment['BACKEND_BASE'] ??
            'http://localhost:9527';

  List<TestResult> get results => List.unmodifiable(_results);

  /// 运行所有测试
  Future<void> runAllTests() async {
    print('╔════════════════════════════════════════════════════════════════╗');
    print('║           WisePick 电商平台 API 接口可用性测试                 ║');
    print('╠════════════════════════════════════════════════════════════════╣');
    print('║ 后端地址: ${_backendBase.padRight(50)}║');
    print('╚════════════════════════════════════════════════════════════════╝');
    print('');

    // 打印配置信息（隐藏敏感信息）
    _printConfig();

    print('\n${'═' * 70}');
    print('开始测试...');
    print('${'═' * 70}\n');

    // 1. 测试后端服务器连通性
    await _testBackendHealth();

    // 2. 测试京东 API
    await _testJdApis();

    // 3. 测试拼多多 API
    await _testPddApis();

    // 4. 测试淘宝 API
    await _testTaobaoApis();

    // 打印测试汇总
    _printSummary();
  }

  void _printConfig() {
    print('📋 配置信息：');
    print('  ├─ PDD_CLIENT_ID: ${_maskString(Config.pddClientId)}');
    print('  ├─ PDD_PID: ${_maskString(Config.pddPid)}');
    print('  ├─ JD_APP_KEY: ${_maskString(Config.jdAppKey)}');
    print('  ├─ JD_UNION_ID: ${_maskString(Config.jdUnionId)}');
    print('  ├─ TAOBAO_APP_KEY: ${_maskString(Config.taobaoAppKey)}');
    print('  └─ TAOBAO_ADZONE_ID: ${_maskString(Config.taobaoAdzoneId)}');
  }

  String _maskString(String s) {
    if (s.isEmpty || s.startsWith('YOUR_')) return '(未配置)';
    if (s.length <= 6) return '****';
    return '${s.substring(0, 3)}****${s.substring(s.length - 3)}';
  }

  /// 测试后端服务器连通性
  Future<void> _testBackendHealth() async {
    print('🔌 测试后端服务器连通性...');
    
    await _runTest(
      name: '后端服务器连通性',
      platform: 'Backend',
      test: () async {
        final resp = await _client.get('$_backendBase/__settings');
        if (resp.statusCode == 200) {
          return TestResult(
            name: '后端服务器连通性',
            platform: 'Backend',
            status: TestStatus.pass,
            message: '服务器运行正常',
          );
        } else {
          return TestResult(
            name: '后端服务器连通性',
            platform: 'Backend',
            status: TestStatus.fail,
            message: 'HTTP ${resp.statusCode}',
            errorDetail: resp.data?.toString(),
          );
        }
      },
    );
  }

  /// 测试京东 API
  Future<void> _testJdApis() async {
    print('\n🛒 测试京东 API...');

    // 检查配置
    if (Config.jdAppKey.startsWith('YOUR_')) {
      _results.add(TestResult(
        name: '京东 API (全部)',
        platform: 'JD',
        status: TestStatus.skip,
        message: '未配置 JD_APP_KEY',
      ));
      print('  ⏭️  [SKIP] 京东 API - 未配置');
      return;
    }

    // 测试商品搜索
    await _runTest(
      name: '商品搜索 (goods/query)',
      platform: 'JD',
      test: () async {
        final url = '$_backendBase/jd/union/goods/query';
        final resp = await _makeRequestWithErrorHandling(
          () => _client.get(url, params: {
            'keyword': '耳机',
            'pageIndex': '1',
            'pageSize': '10',
          }),
        );

        return _parseJdSearchResponse(resp, '商品搜索 (goods/query)');
      },
    );

    // 测试签名/推广链接
    await _runTest(
      name: '签名/推广链接 (sign/jd)',
      platform: 'JD',
      test: () async {
        final url = '$_backendBase/sign/jd';
        final resp = await _makeRequestWithErrorHandling(
          () => _client.post(url, data: {'skuId': '100026691838'}),
        );

        return _parseJdSignResponse(resp, '签名/推广链接 (sign/jd)');
      },
    );
  }

  /// 解析京东搜索响应
  TestResult _parseJdSearchResponse(dynamic resp, String testName) {
    if (resp is TestResult) return resp;
    
    final response = resp as Response;
    if (response.statusCode == 200) {
      final data = response.data;
      // 检查是否有商品数据
      List? items;
      if (data is Map) {
        // 检查错误响应
        if (data['error'] != null) {
          return TestResult(
            name: testName,
            platform: 'JD',
            status: TestStatus.fail,
            message: data['error']?.toString() ?? '接口返回错误',
            errorDetail: jsonEncode(data),
          );
        }
        
        if (data['data'] is List) {
          items = data['data'];
        } else if (data['queryResult'] is Map) {
          final qr = data['queryResult'] as Map;
          items = qr['data'] is List ? qr['data'] : null;
        } else {
          // 尝试从顶层wrapper中找
          for (final v in data.values) {
            if (v is Map && v['queryResult'] is Map) {
              final qr = v['queryResult'] as Map;
              if (qr['data'] is List) items = qr['data'];
              break;
            }
          }
        }
        
        // 检查京东API业务错误
        if (data['error_response'] != null) {
          final err = data['error_response'];
          return TestResult(
            name: testName,
            platform: 'JD',
            status: TestStatus.fail,
            message: '接口业务错误: ${err['zh_desc'] ?? err['sub_msg'] ?? err['msg'] ?? '未知错误'}',
            errorDetail: jsonEncode(err),
          );
        }
      }
      
      if (items != null && items.isNotEmpty) {
        return TestResult(
          name: testName,
          platform: 'JD',
          status: TestStatus.pass,
          message: '返回 ${items.length} 件商品',
        );
      } else {
        return TestResult(
          name: testName,
          platform: 'JD',
          status: TestStatus.pass,
          message: '接口响应正常（无商品数据，可能关键词无匹配）',
        );
      }
    } else {
      return TestResult(
        name: testName,
        platform: 'JD',
        status: TestStatus.fail,
        message: 'HTTP ${response.statusCode}',
        errorDetail: response.data?.toString(),
      );
    }
  }

  /// 解析京东签名响应
  TestResult _parseJdSignResponse(dynamic resp, String testName) {
    if (resp is TestResult) return resp;
    
    final response = resp as Response;
    if (response.statusCode == 200) {
      final data = response.data;
      if (data is Map) {
        if (data['error'] != null) {
          return TestResult(
            name: testName,
            platform: 'JD',
            status: TestStatus.fail,
            message: data['error']?.toString() ?? '接口返回错误',
            errorDetail: jsonEncode(data),
          );
        }
        if (data['clickURL'] != null || data['shortURL'] != null) {
          return TestResult(
            name: testName,
            platform: 'JD',
            status: TestStatus.pass,
            message: '成功生成推广链接',
          );
        } else if (data['error_response'] != null) {
          final err = data['error_response'];
          return TestResult(
            name: testName,
            platform: 'JD',
            status: TestStatus.fail,
            message: '接口业务错误: ${err['zh_desc'] ?? err['sub_msg'] ?? err['msg'] ?? '未知错误'}',
            errorDetail: jsonEncode(err),
          );
        }
      }
      return TestResult(
        name: testName,
        platform: 'JD',
        status: TestStatus.pass,
        message: '接口响应正常',
      );
    } else {
      return TestResult(
        name: testName,
        platform: 'JD',
        status: TestStatus.fail,
        message: 'HTTP ${response.statusCode}',
        errorDetail: response.data?.toString(),
      );
    }
  }

  /// 测试拼多多 API
  Future<void> _testPddApis() async {
    print('\n🍊 测试拼多多 API...');

    // 检查配置
    if (Config.pddClientId.startsWith('YOUR_')) {
      _results.add(TestResult(
        name: '拼多多 API (全部)',
        platform: 'PDD',
        status: TestStatus.skip,
        message: '未配置 PDD_CLIENT_ID',
      ));
      print('  ⏭️  [SKIP] 拼多多 API - 未配置');
      return;
    }

    final pdd = PddClient(
      clientId: Config.pddClientId,
      clientSecret: Config.pddClientSecret,
      pid: Config.pddPid,
    );

    // 首先测试授权备案状态
    await _runTest(
      name: '授权备案状态查询 (authority.query)',
      platform: 'PDD',
      test: () async {
        final biz = <String, dynamic>{
          'pid': Config.pddPid,
          // custom_parameters 必须与备案时使用的一致！
          'custom_parameters': jsonEncode({'uid': 'wisepick', 'sid': 'app'}),
        };

        final resp = await pdd.queryAuthorityBind(biz);

        if (resp is Map && resp['error'] == true) {
          return TestResult(
            name: '授权备案状态查询 (authority.query)',
            platform: 'PDD',
            status: TestStatus.fail,
            message: resp['message']?.toString() ?? '请求错误',
            errorDetail: resp['details']?.toString(),
          );
        }

        if (resp is Map && resp['authority_query_response'] != null) {
          final authResp = resp['authority_query_response'] as Map;
          final bind = authResp['bind'];
          if (bind == 1) {
            return TestResult(
              name: '授权备案状态查询 (authority.query)',
              platform: 'PDD',
              status: TestStatus.pass,
              message: '✅ PID 已完成授权备案 (bind=1)',
            );
          } else {
            return TestResult(
              name: '授权备案状态查询 (authority.query)',
              platform: 'PDD',
              status: TestStatus.fail,
              message: '❌ PID 未完成授权备案 (bind=$bind)',
              errorDetail: '请访问 https://jinbao.pinduoduo.com/qa-system?questionId=204 完成备案',
            );
          }
        }

        if (resp is Map && resp['error_response'] != null) {
          final err = resp['error_response'];
          return TestResult(
            name: '授权备案状态查询 (authority.query)',
            platform: 'PDD',
            status: TestStatus.fail,
            message: '接口业务错误: ${err['sub_msg'] ?? err['error_msg'] ?? '未知错误'}',
            errorDetail: jsonEncode(err),
          );
        }

        return TestResult(
          name: '授权备案状态查询 (authority.query)',
          platform: 'PDD',
          status: TestStatus.fail,
          message: '未知响应格式',
          errorDetail: jsonEncode(resp),
        );
      },
    );

    // 测试商品搜索（直接调用 PddClient）
    await _runTest(
      name: '商品搜索 (ddk.goods.search)',
      platform: 'PDD',
      test: () async {
        // 注意: page_size 最小值为 10，最大值为 100
        // 注意: 2024年起拼多多要求 pid 完成授权备案
        // ⚠️ custom_parameters 必须与备案时使用的完全一致！
        final biz = <String, dynamic>{
          'keyword': '手机',
          'page': 1,
          'page_size': 10,  // 修正：最小值为10
          'pid': Config.pddPid,
          // custom_parameters 必须与备案时一致：{"uid":"wisepick","sid":"app"}
          'custom_parameters': jsonEncode({'uid': 'wisepick', 'sid': 'app'}),
        };

        final resp = await pdd.searchGoods(biz);

        if (resp is Map && resp['error'] == true) {
          return TestResult(
            name: '商品搜索 (ddk.goods.search)',
            platform: 'PDD',
            status: TestStatus.fail,
            message: resp['message']?.toString() ?? '请求错误',
            errorDetail: resp['details']?.toString(),
          );
        }

        if (resp is Map && resp['goods_search_response'] != null) {
          final searchResp = resp['goods_search_response'] as Map;
          final items = searchResp['goods_list'];
          if (items is List) {
            return TestResult(
              name: '商品搜索 (ddk.goods.search)',
              platform: 'PDD',
              status: TestStatus.pass,
              message: '返回 ${items.length} 件商品',
            );
          }
        }

        if (resp is Map && resp['error_response'] != null) {
          final err = resp['error_response'];
          return TestResult(
            name: '商品搜索 (ddk.goods.search)',
            platform: 'PDD',
            status: TestStatus.fail,
            message: '接口业务错误: ${err['sub_msg'] ?? err['error_msg'] ?? '未知错误'}',
            errorDetail: jsonEncode(err),
          );
        }

        return TestResult(
          name: '商品搜索 (ddk.goods.search)',
          platform: 'PDD',
          status: TestStatus.pass,
          message: '接口响应正常',
        );
      },
    );

    // 测试签名/推广链接（通过后端proxy）
    await _runTest(
      name: '签名/推广链接 (sign/pdd)',
      platform: 'PDD',
      test: () async {
        final url = '$_backendBase/sign/pdd';
        final resp = await _makeRequestWithErrorHandling(
          () => _client.post(url, data: {'goods_sign': 'test_goods_sign_123'}),
        );

        if (resp is TestResult) return resp;
        
        final response = resp as Response;
        if (response.statusCode == 200) {
          final data = response.data;
          if (data is Map) {
            if (data['clickURL'] != null || data['url'] != null) {
              return TestResult(
                name: '签名/推广链接 (sign/pdd)',
                platform: 'PDD',
                status: TestStatus.pass,
                message: '成功生成推广链接',
              );
            } else if (data['error'] != null || data['error_response'] != null) {
              final err = data['error_response'] ?? data;
              return TestResult(
                name: '签名/推广链接 (sign/pdd)',
                platform: 'PDD',
                status: TestStatus.fail,
                message: '接口业务错误: ${err['sub_msg'] ?? err['error'] ?? '未知错误'}',
                errorDetail: jsonEncode(data),
              );
            }
          }
          return TestResult(
            name: '签名/推广链接 (sign/pdd)',
            platform: 'PDD',
            status: TestStatus.pass,
            message: '接口响应正常',
          );
        } else {
          return TestResult(
            name: '签名/推广链接 (sign/pdd)',
            platform: 'PDD',
            status: TestStatus.fail,
            message: 'HTTP ${response.statusCode}',
            errorDetail: response.data?.toString(),
          );
        }
      },
    );
  }

  /// 测试淘宝 API
  Future<void> _testTaobaoApis() async {
    print('\n🛍️ 测试淘宝 API...');

    // 检查配置
    if (Config.taobaoAppKey.startsWith('YOUR_')) {
      _results.add(TestResult(
        name: '淘宝 API (全部)',
        platform: 'Taobao',
        status: TestStatus.skip,
        message: '未配置 TAOBAO_APP_KEY',
      ));
      print('  ⏭️  [SKIP] 淘宝 API - 未配置');
      return;
    }

    // 测试商品搜索
    // 注意：淘宝接口使用 'para' 参数而不是 'q'
    await _runTest(
      name: '商品搜索 (tbk_search)',
      platform: 'Taobao',
      test: () async {
        final url = '$_backendBase/taobao/tbk_search';
        final resp = await _makeRequestWithErrorHandling(
          () => _client.get(url, params: {
            'para': '手机',  // 注意：参数名是 'para' 不是 'q'
            'page_no': '1',
            'page_size': '10',
          }),
        );

        return _parseTaobaoSearchResponse(resp, '商品搜索 (tbk_search)');
      },
    );

    // 测试万能转链
    await _runTest(
      name: '万能转链 (taobao/convert)',
      platform: 'Taobao',
      test: () async {
        final url = '$_backendBase/taobao/convert';
        final resp = await _makeRequestWithErrorHandling(
          () => _client.post(url, data: {
            'url': 'https://item.taobao.com/item.htm?id=123456789',
          }),
        );

        return _parseTaobaoConvertResponse(resp, '万能转链 (taobao/convert)');
      },
    );

    // 测试签名接口
    await _runTest(
      name: '签名接口 (sign/taobao)',
      platform: 'Taobao',
      test: () async {
        final url = '$_backendBase/sign/taobao';
        final resp = await _makeRequestWithErrorHandling(
          () => _client.post(url, data: {
            'url': 'https://item.taobao.com/item.htm?id=123456789',
          }),
        );

        if (resp is TestResult) return resp;
        
        final response = resp as Response;
        if (response.statusCode == 200) {
          final data = response.data;
          if (data is Map) {
            if (data['tpwd'] != null || data['sign'] != null) {
              return TestResult(
                name: '签名接口 (sign/taobao)',
                platform: 'Taobao',
                status: TestStatus.pass,
                message: '成功生成签名/淘口令',
              );
            } else if (data['error'] != null) {
              return TestResult(
                name: '签名接口 (sign/taobao)',
                platform: 'Taobao',
                status: TestStatus.fail,
                message: '接口业务错误',
                errorDetail: jsonEncode(data),
              );
            }
          }
          return TestResult(
            name: '签名接口 (sign/taobao)',
            platform: 'Taobao',
            status: TestStatus.pass,
            message: '接口响应正常',
          );
        } else {
          return TestResult(
            name: '签名接口 (sign/taobao)',
            platform: 'Taobao',
            status: TestStatus.fail,
            message: 'HTTP ${response.statusCode}',
            errorDetail: response.data?.toString(),
          );
        }
      },
    );
  }

  /// 解析淘宝搜索响应
  TestResult _parseTaobaoSearchResponse(dynamic resp, String testName) {
    if (resp is TestResult) return resp;
    
    final response = resp as Response;
    if (response.statusCode == 200) {
      final data = response.data;
      if (data is Map) {
        // 检查错误
        if (data['error'] != null) {
          return TestResult(
            name: testName,
            platform: 'Taobao',
            status: TestStatus.fail,
            message: data['error']?.toString() ?? '接口返回错误',
            errorDetail: jsonEncode(data),
          );
        }
        
        if (data['error_response'] != null) {
          final err = data['error_response'];
          return TestResult(
            name: testName,
            platform: 'Taobao',
            status: TestStatus.fail,
            message: '接口业务错误: ${err['sub_msg'] ?? err['msg'] ?? '未知错误'}',
            errorDetail: jsonEncode(err),
          );
        }
        
        // 检查各种可能的响应结构
        List? results;
        
        // 尝试从不同的响应结构中提取商品列表
        if (data['tbk_dg_material_optional_upgrade_response'] != null) {
          final r = data['tbk_dg_material_optional_upgrade_response'];
          if (r['result_list'] != null) {
            final rl = r['result_list'];
            results = rl['map_data'] ?? rl;
          }
        } else if (data['results'] is List) {
          results = data['results'];
        } else if (data['result_list'] is Map) {
          results = (data['result_list'] as Map)['map_data'];
        }
        
        if (results is List && results.isNotEmpty) {
          return TestResult(
            name: testName,
            platform: 'Taobao',
            status: TestStatus.pass,
            message: '返回 ${results.length} 件商品',
          );
        }
        
        return TestResult(
          name: testName,
          platform: 'Taobao',
          status: TestStatus.pass,
          message: '接口响应正常（无商品数据，可能关键词无匹配）',
        );
      }
      return TestResult(
        name: testName,
        platform: 'Taobao',
        status: TestStatus.pass,
        message: '接口响应正常',
      );
    } else {
      return TestResult(
        name: testName,
        platform: 'Taobao',
        status: TestStatus.fail,
        message: 'HTTP ${response.statusCode}',
        errorDetail: response.data?.toString(),
      );
    }
  }

  /// 解析淘宝转链响应
  TestResult _parseTaobaoConvertResponse(dynamic resp, String testName) {
    if (resp is TestResult) return resp;
    
    final response = resp as Response;
    if (response.statusCode == 200) {
      final data = response.data;
      if (data is Map) {
        if (data['error'] != null) {
          return TestResult(
            name: testName,
            platform: 'Taobao',
            status: TestStatus.fail,
            message: data['error']?.toString() ?? '接口返回错误',
            errorDetail: jsonEncode(data),
          );
        }
        
        if (data['tpwd'] != null || data['click_url'] != null || data['coupon_click_url'] != null) {
          return TestResult(
            name: testName,
            platform: 'Taobao',
            status: TestStatus.pass,
            message: '成功生成转链',
          );
        } else if (data['error_response'] != null) {
          final err = data['error_response'];
          return TestResult(
            name: testName,
            platform: 'Taobao',
            status: TestStatus.fail,
            message: '接口业务错误: ${err['sub_msg'] ?? err['msg'] ?? '未知错误'}',
            errorDetail: jsonEncode(err),
          );
        }
      }
      return TestResult(
        name: testName,
        platform: 'Taobao',
        status: TestStatus.pass,
        message: '接口响应正常',
      );
    } else {
      return TestResult(
        name: testName,
        platform: 'Taobao',
        status: TestStatus.fail,
        message: 'HTTP ${response.statusCode}',
        errorDetail: response.data?.toString(),
      );
    }
  }

  /// 包装请求，捕获 DioException 并提取详细错误信息
  Future<dynamic> _makeRequestWithErrorHandling(Future<Response> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      String errorDetail = '';
      String message = '';
      
      // 尝试提取响应体中的详细错误信息
      if (e.response != null) {
        final statusCode = e.response!.statusCode;
        message = 'HTTP $statusCode';
        
        final responseData = e.response!.data;
        if (responseData != null) {
          if (responseData is Map) {
            // 尝试解析常见的错误字段
            if (responseData['error'] != null) {
              errorDetail = responseData['error'].toString();
            } else if (responseData['error_response'] != null) {
              final err = responseData['error_response'];
              errorDetail = jsonEncode(err);
              message = '$message - ${err['sub_msg'] ?? err['msg'] ?? err['error_msg'] ?? ''}';
            } else if (responseData['message'] != null) {
              errorDetail = responseData['message'].toString();
            } else {
              errorDetail = jsonEncode(responseData);
            }
          } else if (responseData is String) {
            errorDetail = responseData;
          } else {
            errorDetail = responseData.toString();
          }
        }
      } else {
        message = e.type.toString();
        errorDetail = e.message ?? e.toString();
      }
      
      // 截断过长的错误信息
      if (errorDetail.length > 800) {
        errorDetail = errorDetail.substring(0, 800) + '...(已截断)';
      }
      
      return TestResult(
        name: '',  // 将在调用处填充
        platform: '',
        status: TestStatus.fail,
        message: message,
        errorDetail: errorDetail,
      );
    }
  }

  /// 运行单个测试
  Future<void> _runTest({
    required String name,
    required String platform,
    required Future<TestResult> Function() test,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      var result = await test();
      stopwatch.stop();
      
      // 如果是从 _makeRequestWithErrorHandling 返回的部分结果，补充名称和平台
      if (result.name.isEmpty) {
        result = TestResult(
          name: name,
          platform: platform,
          status: result.status,
          message: result.message,
          errorDetail: result.errorDetail,
          duration: stopwatch.elapsed,
        );
      } else {
        result = TestResult(
          name: result.name,
          platform: result.platform,
          status: result.status,
          message: result.message,
          errorDetail: result.errorDetail,
          duration: stopwatch.elapsed,
        );
      }
      
      _results.add(result);
      _printTestResult(result);
    } catch (e, st) {
      stopwatch.stop();
      final result = TestResult(
        name: name,
        platform: platform,
        status: TestStatus.fail,
        message: '异常: ${e.runtimeType}',
        errorDetail: '$e\n$st',
        duration: stopwatch.elapsed,
      );
      _results.add(result);
      _printTestResult(result);
    }
  }

  void _printTestResult(TestResult result) {
    final duration = result.duration != null ? '(${result.duration!.inMilliseconds}ms)' : '';
    print('  ${result.statusIcon} [${result.statusText}] ${result.name} $duration');
    if (result.message != null) {
      print('       └─ ${result.message}');
    }
    if (result.status == TestStatus.fail && result.errorDetail != null) {
      print('       └─ 错误详情:');
      // 截断过长的错误信息
      final detail = result.errorDetail!;
      if (detail.length > 500) {
        print('          ${detail.substring(0, 500)}...(已截断)');
      } else {
        print('          $detail');
      }
    }
  }

  void _printSummary() {
    final passed = _results.where((r) => r.status == TestStatus.pass).length;
    final failed = _results.where((r) => r.status == TestStatus.fail).length;
    final skipped = _results.where((r) => r.status == TestStatus.skip).length;
    final total = _results.length;

    print('\n${'═' * 70}');
    print('测试汇总');
    print('${'═' * 70}');
    print('');
    print('  ✅ 通过: $passed');
    print('  ❌ 失败: $failed');
    print('  ⏭️ 跳过: $skipped');
    print('  📊 总计: $total');
    print('');

    if (failed > 0) {
      print('${'─' * 70}');
      print('失败的测试:');
      for (final r in _results.where((r) => r.status == TestStatus.fail)) {
        print('  ❌ [${r.platform}] ${r.name}');
        if (r.message != null) print('     └─ ${r.message}');
      }
    }

    print('${'═' * 70}');
    
    // 退出码：有失败则返回1
    if (failed > 0) {
      print('\n⚠️ 存在失败的测试，请检查配置和服务状态。');
    } else if (skipped == total) {
      print('\n⚠️ 所有测试均被跳过，请检查环境变量配置。');
    } else {
      print('\n🎉 所有测试通过！');
    }
  }
}

Future<void> main(List<String> args) async {
  // 解析命令行参数
  String? backendBase;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--backend' && i + 1 < args.length) {
      backendBase = args[i + 1];
    }
  }

  final tester = ApiTester(backendBase: backendBase);
  
  try {
    await tester.runAllTests();
  } catch (e, st) {
    stderr.writeln('测试运行出错: $e');
    stderr.writeln(st);
    exit(2);
  }

  // 根据测试结果设置退出码
  final failed = tester.results.where((r) => r.status == TestStatus.fail).length;
  exit(failed > 0 ? 1 : 0);
}
