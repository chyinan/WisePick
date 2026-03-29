import 'package:flutter/material.dart';
import 'auth_service.dart';
import '../api_client.dart';
import '../server_config_dialog.dart';
import '../server_config_service.dart';
import '../../features/dashboard/dashboard_page.dart';

/// 登录页面
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _focusNode = FocusNode();

  // 使用 getter 确保切换服务器后拿到新实例
  ApiClient get _apiClient => ApiClient();
  AuthService get _authService => AuthService(_apiClient);

  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _isInitialized = false;
  String _currentServerUrl = ServerConfigService.defaultUrl;

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
    _checkExistingSession();
  }

  /// 加载当前服务器地址用于显示
  Future<void> _loadServerUrl() async {
    final url = await ServerConfigService.getSavedUrl();
    if (mounted) setState(() => _currentServerUrl = url);
  }

  /// 检查是否已有有效会话，如有则直接跳转
  Future<void> _checkExistingSession() async {
    try {
      final isLoggedIn = await _authService.isLoggedIn();
      if (isLoggedIn && mounted) {
        // 使用 addPostFrameCallback 确保导航在当前帧渲染完成后执行
        // 这避免了在 build 过程中调用 Navigator 导致的问题
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _navigateToDashboard();
          }
        });
        return;
      }
    } catch (_) {
      // 忽略检查错误，继续显示登录页
    }

    if (mounted) {
      setState(() => _isInitialized = true);
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // 清除之前的错误
    setState(() => _errorMessage = null);

    // 表单验证
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.login(_passwordController.text.trim());

      if (!mounted) return;

      if (result.success) {
        _navigateToDashboard();
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = result.errorMessage ?? '登录失败';
        });
        // 聚焦到密码输入框便于重新输入
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '登录过程中发生错误，请重试';
        });
      }
    }
  }

  void _navigateToDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const DashboardPage(),
      ),
    );
  }

  String? _validatePassword(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入管理员密码';
    }
    if (value.trim().length < 3) {
      return '密码长度不正确';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // 初始化中显示加载状态
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 48),
                    _buildPasswordField(),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      _buildErrorMessage(),
                    ],
                    const SizedBox(height: 24),
                    _buildLoginButton(),
                    const SizedBox(height: 16),
                    _buildServerConfigButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.admin_panel_settings_rounded,
            color: Colors.white,
            size: 48,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'WisePick Admin',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '管理后台登录',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _currentServerUrl,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      focusNode: _focusNode,
      obscureText: _obscurePassword,
      enabled: !_isLoading,
      autofillHints: const [AutofillHints.password],
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _login(),
      validator: _validatePassword,
      decoration: InputDecoration(
        labelText: '管理员密码',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
          tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        errorMaxLines: 2,
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: _isLoading ? null : _login,
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                '登录',
                style: TextStyle(fontSize: 16),
              ),
      ),
    );
  }

  Widget _buildServerConfigButton() {
    return Center(
      child: TextButton.icon(
        onPressed: () async {
          final switched = await ServerConfigDialog.show(context);
          if (switched == true) {
            _loadServerUrl();
          }
        },
        icon: const Icon(Icons.settings, size: 16),
        label: const Text('服务器配置', style: TextStyle(fontSize: 13)),
      ),
    );
  }
}
