/// 拼多多 PID 授权备案检查与生成工具
/// 
/// 用法：
///   dart run scripts/pdd_authority_check.dart
///   dart run scripts/pdd_authority_check.dart --generate  # 生成授权链接
///
/// 功能：
///   1. 查询当前 PID 的授权备案状态
///   2. 生成授权备案链接（如果未备案）

import 'dart:convert';
import 'dart:io';

import '../lib/core/pdd_client.dart';
import '../lib/core/config.dart';

Future<void> main(List<String> args) async {
  print('╔════════════════════════════════════════════════════════════════╗');
  print('║         拼多多 PID 授权备案检查工具                            ║');
  print('╚════════════════════════════════════════════════════════════════╝');
  print('');

  // 检查配置
  if (Config.pddClientId.startsWith('YOUR_')) {
    print('❌ 错误: 未配置 PDD_CLIENT_ID');
    print('请在环境变量中设置 PDD_CLIENT_ID, PDD_CLIENT_SECRET, PDD_PID');
    exit(1);
  }

  print('📋 当前配置:');
  print('   PDD_CLIENT_ID: ${_mask(Config.pddClientId)}');
  print('   PDD_PID: ${Config.pddPid}');
  print('');

  final pdd = PddClient(
    clientId: Config.pddClientId,
    clientSecret: Config.pddClientSecret,
    pid: Config.pddPid,
  );

  // 定义 custom_parameters - 必须与后续搜索接口使用的保持一致
  final customParams = jsonEncode({'uid': 'wisepick', 'sid': 'app'});

  // 1. 查询授权备案状态
  print('${'─' * 60}');
  print('🔍 步骤1: 查询 PID 授权备案状态...');
  print('${'─' * 60}');

  final queryBiz = <String, dynamic>{
    'pid': Config.pddPid,
    'custom_parameters': customParams,
  };

  final queryResp = await pdd.queryAuthorityBind(queryBiz);
  
  bool isBound = false;
  
  if (queryResp is Map && queryResp['error'] == true) {
    print('❌ 查询失败: ${queryResp['message']}');
    if (queryResp['details'] != null) {
      print('   详情: ${queryResp['details']}');
    }
  } else if (queryResp is Map && queryResp['authority_query_response'] != null) {
    final authResp = queryResp['authority_query_response'] as Map;
    final bind = authResp['bind'];
    isBound = bind == 1;
    
    if (isBound) {
      print('✅ PID 已完成授权备案 (bind=1)');
      print('   您的 PID ${Config.pddPid} 已可正常使用');
    } else {
      print('❌ PID 未完成授权备案 (bind=$bind)');
      print('   需要生成授权链接并完成备案');
    }
  } else if (queryResp is Map && queryResp['error_response'] != null) {
    final err = queryResp['error_response'];
    print('❌ 接口返回错误:');
    print('   错误码: ${err['error_code']}');
    print('   错误信息: ${err['error_msg']}');
    print('   子错误: ${err['sub_msg']}');
    print('');
    print('   完整响应: ${jsonEncode(err)}');
  } else {
    print('⚠️ 未知响应格式:');
    print('   ${jsonEncode(queryResp)}');
  }

  print('');

  // 2. 如果未备案或传入 --generate 参数，生成授权链接
  final shouldGenerate = args.contains('--generate') || !isBound;
  
  if (shouldGenerate) {
    print('${'─' * 60}');
    print('🔗 步骤2: 生成授权备案链接...');
    print('   使用接口: pdd.ddk.rp.prom.url.generate (channel_type=10)');
    print('${'─' * 60}');

    // 使用 pdd.ddk.rp.prom.url.generate 接口，channel_type=10 生成授权备案链接
    final genBiz = <String, dynamic>{
      'p_id_list': [Config.pddPid],  // 注意是 p_id_list 数组
      'channel_type': 10,             // channel_type=10 生成授权备案链接
      'custom_parameters': customParams,
      'generate_we_app': true,        // 同时生成小程序链接
    };

    final genResp = await pdd.generateRpPromUrl(genBiz);

    if (genResp is Map && genResp['error'] == true) {
      print('❌ 生成失败: ${genResp['message']}');
      if (genResp['details'] != null) {
        print('   详情: ${genResp['details']}');
      }
    } else if (genResp is Map && genResp['rp_promotion_url_generate_response'] != null) {
      final rpResp = genResp['rp_promotion_url_generate_response'] as Map;
      
      // 获取 url_list 中的链接
      final urlList = rpResp['url_list'];
      if (urlList is List && urlList.isNotEmpty) {
        final firstUrl = urlList[0] as Map;
        
        print('✅ 授权备案链接生成成功！');
        print('');
        
        if (firstUrl['url'] != null) {
          print('📱 H5授权链接 (在浏览器打开):');
          print('   ${firstUrl['url']}');
          print('');
        }
        
        if (firstUrl['mobile_url'] != null) {
          print('📱 移动端授权链接:');
          print('   ${firstUrl['mobile_url']}');
          print('');
        }
        
        if (firstUrl['mobile_short_url'] != null) {
          print('📱 移动端短链接:');
          print('   ${firstUrl['mobile_short_url']}');
          print('');
        }

        if (firstUrl['short_url'] != null) {
          print('🔗 短链接:');
          print('   ${firstUrl['short_url']}');
          print('');
        }
        
        if (firstUrl['we_app_info'] != null) {
          final weApp = firstUrl['we_app_info'] as Map;
          print('🔗 微信小程序授权:');
          print('   AppID: ${weApp['app_id']}');
          print('   Page Path: ${weApp['page_path']}');
          if (weApp['source_display_name'] != null) {
            print('   Source Display Name: ${weApp['source_display_name']}');
          }
          if (weApp['user_name'] != null) {
            print('   User Name: ${weApp['user_name']}');
          }
          print('');
        }
        
        print('${'─' * 60}');
        print('📝 操作说明:');
        print('   1. 复制上面的授权链接（推荐使用H5链接）');
        print('   2. 在浏览器或手机中打开链接');
        print('   3. 按提示登录拼多多账号并完成授权');
        print('   4. 授权完成后，重新运行此脚本验证备案状态');
        print('${'─' * 60}');
      } else {
        print('⚠️ 响应中没有找到 url_list:');
        print('   ${jsonEncode(rpResp)}');
      }
      
    } else if (genResp is Map && genResp['error_response'] != null) {
      final err = genResp['error_response'];
      print('❌ 接口返回错误:');
      print('   错误码: ${err['error_code']}');
      print('   错误信息: ${err['error_msg']}');
      print('   子错误: ${err['sub_msg']}');
      print('');
      print('   完整响应: ${jsonEncode(err)}');
      
      // 提供常见错误的解决方案
      final subCode = err['sub_code']?.toString() ?? '';
      final errorCode = err['error_code']?.toString() ?? '';
      if (subCode == '20031' || errorCode == '20031') {
        print('');
        print('💡 解决方案: 您的应用可能没有此接口的权限');
        print('   请在拼多多开放平台检查应用的API权限包');
      }
    } else {
      print('⚠️ 未知响应格式:');
      print('   ${jsonEncode(genResp)}');
    }
  } else {
    print('ℹ️ PID 已备案，无需生成授权链接');
    print('   如需重新生成，请使用 --generate 参数');
  }

  print('');
  print('${'═' * 60}');
  print('💡 重要提示:');
  print('   搜索接口中的 custom_parameters 必须与备案时使用的一致!');
  print('   当前使用的 custom_parameters: $customParams');
  print('${'═' * 60}');
}

String _mask(String s) {
  if (s.length <= 6) return '****';
  return '${s.substring(0, 3)}****${s.substring(s.length - 3)}';
}

