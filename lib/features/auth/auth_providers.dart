import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'user_model.dart';
import 'auth_service.dart';
import 'token_manager.dart';

/// Token 管理器 Provider
final tokenManagerProvider = Provider<TokenManager>((ref) {
  return TokenManager.instance;
});

/// 认证服务 Provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// 认证状态
enum AuthStatus {
  initial,      // 初始状态
  loading,      // 加载中
  authenticated,  // 已认证
  unauthenticated, // 未认证
  error,        // 错误
}

/// 认证状态
class AuthState {
  final AuthStatus status;
  final User? user;
  final String? errorMessage;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
    this.isLoading = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? errorMessage,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// 是否已登录
  bool get isLoggedIn => status == AuthStatus.authenticated && user != null;

  /// 清除用户
  AuthState clearUser() {
    return AuthState(
      status: AuthStatus.unauthenticated,
      user: null,
      errorMessage: null,
      isLoading: false,
    );
  }
}

/// 登录后同步回调类型
typedef OnLoginCallback = Future<void> Function();

/// 认证状态管理器
class AuthStateNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;
  final TokenManager _tokenManager;
  
  /// 登录后同步回调（由外部注入，例如 SyncManager）
  OnLoginCallback? onLoginSuccess;

  AuthStateNotifier({
    required AuthService authService,
    required TokenManager tokenManager,
  })  : _authService = authService,
        _tokenManager = tokenManager,
        super(const AuthState());

  /// 初始化 - 检查是否已登录
  /// 
  /// 会话保持策略：
  /// 1. 如果本地有有效的 refresh token（未过期），则认为已登录
  /// 2. 尝试从服务器获取用户信息，失败时使用本地缓存
  /// 3. 只有当 refresh token 过期时才清除登录状态
  Future<void> initialize() async {
    state = state.copyWith(status: AuthStatus.loading, isLoading: true);

    try {
      // TokenManager.init() 会自动检查会话是否过期
      await _tokenManager.init();

      if (_tokenManager.isLoggedIn) {
        // 先尝试使用本地缓存的用户数据恢复登录状态
        final cachedUserData = await _tokenManager.getCachedUserData();
        User? user;
        
        if (cachedUserData != null) {
          user = User.fromJson(cachedUserData);
          // 立即设置已登录状态（使用缓存数据）
          state = AuthState(
            status: AuthStatus.authenticated,
            user: user,
            isLoading: false,
          );
          // 触发登录后同步
          _triggerOnLoginCallback();
        }
        
        // 后台尝试刷新用户信息（不阻塞 UI）
        _refreshUserInBackground();
        
        // 如果有缓存用户，直接返回
        if (user != null) {
          return;
        }
        
        // 没有缓存时，尝试从服务器获取
        user = await _authService.getCurrentUser();
        if (user != null) {
          state = AuthState(
            status: AuthStatus.authenticated,
            user: user,
            isLoading: false,
          );
          _triggerOnLoginCallback();
          return;
        }
      }

      state = const AuthState(
        status: AuthStatus.unauthenticated,
        isLoading: false,
      );
    } catch (e) {
      // 即使出错，如果本地有缓存用户数据，仍然保持登录状态
      if (_tokenManager.isLoggedIn) {
        final cachedUserData = await _tokenManager.getCachedUserData();
        if (cachedUserData != null) {
          state = AuthState(
            status: AuthStatus.authenticated,
            user: User.fromJson(cachedUserData),
            isLoading: false,
          );
          _triggerOnLoginCallback();
          return;
        }
      }
      
      state = AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: e.toString(),
        isLoading: false,
      );
    }
  }
  
  /// 后台刷新用户信息（静默执行，不影响 UI）
  void _refreshUserInBackground() {
    Future.microtask(() async {
      try {
        final user = await _authService.getCurrentUser();
        if (user != null && state.status == AuthStatus.authenticated) {
          state = state.copyWith(user: user);
        }
      } catch (_) {
        // 静默处理，不影响当前登录状态
      }
    });
  }

  /// 用户注册
  Future<bool> register({
    required String email,
    required String password,
    String? nickname,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final result = await _authService.register(
      email: email,
      password: password,
      nickname: nickname,
    );

    if (result.success && result.user != null) {
      state = AuthState(
        status: AuthStatus.authenticated,
        user: result.user,
        isLoading: false,
      );
      // 触发登录后同步
      _triggerOnLoginCallback();
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        errorMessage: result.message ?? '注册失败',
      );
      return false;
    }
  }

  /// 用户登录
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final result = await _authService.login(
      email: email,
      password: password,
    );

    if (result.success && result.user != null) {
      state = AuthState(
        status: AuthStatus.authenticated,
        user: result.user,
        isLoading: false,
      );
      // 触发登录后同步
      _triggerOnLoginCallback();
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        errorMessage: result.message ?? '登录失败',
      );
      return false;
    }
  }
  
  /// 触发登录后回调
  void _triggerOnLoginCallback() {
    if (onLoginSuccess != null) {
      // 异步执行，不阻塞登录流程
      Future.microtask(() async {
        try {
          await onLoginSuccess!();
        } catch (_) {
          // 静默处理同步回调错误
        }
      });
    }
  }

  /// 登出
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    await _authService.logout();
    state = const AuthState(
      status: AuthStatus.unauthenticated,
      isLoading: false,
    );
  }

  /// 登出所有设备
  Future<void> logoutAll() async {
    state = state.copyWith(isLoading: true);
    await _authService.logoutAll();
    state = const AuthState(
      status: AuthStatus.unauthenticated,
      isLoading: false,
    );
  }

  /// 刷新用户信息
  Future<void> refreshUser() async {
    if (!state.isLoggedIn) return;

    final user = await _authService.getCurrentUser();
    if (user != null) {
      state = state.copyWith(user: user);
    }
  }

  /// 更新用户资料
  Future<bool> updateProfile({
    String? nickname,
    String? avatarUrl,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final result = await _authService.updateProfile(
      nickname: nickname,
      avatarUrl: avatarUrl,
    );

    if (result.success && result.user != null) {
      state = state.copyWith(
        user: result.user,
        isLoading: false,
      );
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        errorMessage: result.message ?? '更新失败',
      );
      return false;
    }
  }

  /// 修改密码
  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final result = await _authService.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );

    state = state.copyWith(isLoading: false);

    if (result.success) {
      return true;
    } else {
      state = state.copyWith(errorMessage: result.message ?? '修改失败');
      return false;
    }
  }

  /// 清除错误消息
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}

/// 认证状态 Provider
final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  final tokenManager = ref.watch(tokenManagerProvider);
  return AuthStateNotifier(
    authService: authService,
    tokenManager: tokenManager,
  );
});

/// 是否已登录 Provider（方便快速访问）
final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).isLoggedIn;
});

/// 当前用户 Provider（方便快速访问）
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).user;
});

/// 用户会话列表 Provider
final userSessionsProvider = FutureProvider<List<UserSession>>((ref) async {
  final authService = ref.read(authServiceProvider);
  final isLoggedIn = ref.watch(isLoggedInProvider);
  if (!isLoggedIn) return [];
  return authService.getUserSessions();
});
