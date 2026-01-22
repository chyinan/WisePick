import 'package:uuid/uuid.dart';

import 'jd_oauth_service.dart';
import 'oauth_state_store.dart';

// 已移除未使用的 dart:convert 和 dart:math 导入

class OAuthController {
  final JdOAuthService jdOAuthService;
  final OAuthStateStore stateStore;

  OAuthController({required this.jdOAuthService, required this.stateStore});

  /// 生成随机 state 并返回授权 URL（在实际部署中应把 state 保存到会话或临时存储）
  Map<String, dynamic> authorize({required String redirectUri, String? scope}) {
    final state = const Uuid().v4();
    // persist state in store, tie to admin session in production
    stateStore.save(state);
    final url = jdOAuthService.buildAuthorizeUrl(redirectUri: redirectUri, state: state, scope: scope);
    return {
      'authorize_url': url,
      'state': state,
    };
  }
}