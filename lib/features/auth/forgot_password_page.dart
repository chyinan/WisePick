import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_providers.dart';
import 'login_page.dart';

/// 忘记密码页面 - 通过安全问题重置密码
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _answerController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // 步骤: 0=输入邮箱, 1=回答安全问题, 2=设置新密码, 3=完成
  int _currentStep = 0;

  // 安全问题信息
  String? _securityQuestion;
  String? _resetToken;

  @override
  void dispose() {
    _emailController.dispose();
    _answerController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// 验证邮箱格式
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return '请输入邮箱';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return '请输入有效的邮箱地址';
    }
    return null;
  }

  /// 验证答案
  String? _validateAnswer(String? value) {
    if (value == null || value.isEmpty) {
      return '请输入安全问题答案';
    }
    if (value.length < 2) {
      return '答案至少2个字符';
    }
    return null;
  }

  /// 验证密码
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return '请输入新密码';
    }
    if (value.length < 8) {
      return '密码至少8位';
    }
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(value);
    final hasDigit = RegExp(r'\d').hasMatch(value);
    if (!hasLetter || !hasDigit) {
      return '密码必须包含字母和数字';
    }
    return null;
  }

  /// 验证确认密码
  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return '请确认新密码';
    }
    if (value != _newPasswordController.text) {
      return '两次输入的密码不一致';
    }
    return null;
  }

  /// 第一步：获取安全问题
  Future<void> _handleGetSecurityQuestion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = ref.read(authServiceProvider);
    final result = await authService.getSecurityQuestionByEmail(
      _emailController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (result.success && result.questions.isNotEmpty) {
      setState(() {
        _securityQuestion = result.questions.first['question'] as String;
        _currentStep = 1;
      });
    } else {
      setState(() {
        _errorMessage = result.message ?? '该邮箱未注册或未设置安全问题';
      });
    }
  }

  /// 第二步：验证安全问题答案
  Future<void> _handleVerifyAnswer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = ref.read(authServiceProvider);
    final result = await authService.verifySecurityQuestion(
      email: _emailController.text.trim(),
      answer: _answerController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (result.success && result.resetToken != null) {
      setState(() {
        _resetToken = result.resetToken;
        _currentStep = 2;
      });
    } else {
      setState(() {
        _errorMessage = result.message ?? '安全问题答案错误';
      });
    }
  }

  /// 第三步：重置密码
  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    if (_resetToken == null) {
      setState(() {
        _errorMessage = '重置令牌无效，请重新开始';
        _currentStep = 0;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = ref.read(authServiceProvider);
    final result = await authService.resetPassword(
      resetToken: _resetToken!,
      newPassword: _newPasswordController.text,
    );

    setState(() => _isLoading = false);

    if (result.success) {
      setState(() => _currentStep = 3);
    } else {
      setState(() {
        _errorMessage = result.message ?? '密码重置失败';
      });
    }
  }

  /// 返回登录页面
  void _goToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    final isTablet = screenWidth >= 600 && screenWidth < 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('找回密码'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 64 : (isTablet ? 48 : 24),
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 520 : (isTablet ? 480 : 400),
              ),
              child: isDesktop
                  ? _buildDesktopLayout(theme)
                  : _buildMobileLayout(theme),
            ),
          ),
        ),
      ),
    );
  }

  /// 桌面端布局 - 卡片式设计
  Widget _buildDesktopLayout(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Form(
          key: _formKey,
          child: _buildContent(theme),
        ),
      ),
    );
  }

  /// 移动端布局
  Widget _buildMobileLayout(ThemeData theme) {
    return Form(
      key: _formKey,
      child: _buildContent(theme),
    );
  }

  /// 通用内容布局
  Widget _buildContent(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 图标
        Icon(
          _currentStep == 3
              ? Icons.check_circle_outline
              : Icons.lock_reset_outlined,
          size: 64,
          color: _currentStep == 3
              ? Colors.green
              : theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),

        // 标题
        Text(
          _getStepTitle(),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        // 副标题
        Text(
          _getStepSubtitle(),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // 步骤指示器
        if (_currentStep < 3) ...[
          _buildStepIndicator(theme),
          const SizedBox(height: 24),
        ],

        // 错误提示
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () =>
                      setState(() => _errorMessage = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 根据步骤显示不同内容
        _buildStepContent(theme),

        const SizedBox(height: 24),

        // 返回登录
        if (_currentStep < 3)
          TextButton(
            onPressed: _goToLogin,
            child: const Text('返回登录'),
          ),
      ],
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0:
        return '输入邮箱';
      case 1:
        return '验证身份';
      case 2:
        return '设置新密码';
      case 3:
        return '密码已重置';
      default:
        return '找回密码';
    }
  }

  String _getStepSubtitle() {
    switch (_currentStep) {
      case 0:
        return '请输入您注册时使用的邮箱';
      case 1:
        return '请回答您设置的安全问题';
      case 2:
        return '请设置您的新密码';
      case 3:
        return '您的密码已成功重置，请使用新密码登录';
      default:
        return '';
    }
  }

  Widget _buildStepIndicator(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < 3; i++) ...[
          if (i > 0)
            Container(
              width: 40,
              height: 2,
              color: i <= _currentStep
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= _currentStep
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              border: Border.all(
                color: i <= _currentStep
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: 2,
              ),
            ),
            child: Center(
              child: i < _currentStep
                  ? Icon(
                      Icons.check,
                      size: 16,
                      color: theme.colorScheme.onPrimary,
                    )
                  : Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: i <= _currentStep
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStepContent(ThemeData theme) {
    switch (_currentStep) {
      case 0:
        return _buildEmailStep(theme);
      case 1:
        return _buildSecurityQuestionStep(theme);
      case 2:
        return _buildNewPasswordStep(theme);
      case 3:
        return _buildSuccessStep(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  /// 第一步：输入邮箱
  Widget _buildEmailStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          validator: _validateEmail,
          enabled: !_isLoading,
          onFieldSubmitted: (_) => _handleGetSecurityQuestion(),
          decoration: InputDecoration(
            labelText: '邮箱',
            hintText: 'example@email.com',
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isLoading ? null : _handleGetSecurityQuestion,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('下一步', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  /// 第二步：回答安全问题
  Widget _buildSecurityQuestionStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 显示安全问题
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.security_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '安全问题',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _securityQuestion ?? '',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 答案输入
        TextFormField(
          controller: _answerController,
          textInputAction: TextInputAction.done,
          validator: _validateAnswer,
          enabled: !_isLoading,
          onFieldSubmitted: (_) => _handleVerifyAnswer(),
          decoration: InputDecoration(
            labelText: '您的答案',
            hintText: '请输入安全问题的答案',
            prefixIcon: const Icon(Icons.question_answer_outlined),
            helperText: '答案不区分大小写',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        setState(() {
                          _currentStep = 0;
                          _answerController.clear();
                          _errorMessage = null;
                        });
                      },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('上一步'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton(
                onPressed: _isLoading ? null : _handleVerifyAnswer,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('验证'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 第三步：设置新密码
  Widget _buildNewPasswordStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _newPasswordController,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.next,
          validator: _validatePassword,
          enabled: !_isLoading,
          decoration: InputDecoration(
            labelText: '新密码',
            hintText: '至少8位，包含字母和数字',
            prefixIcon: const Icon(Icons.lock_outlined),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 16),

        TextFormField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          textInputAction: TextInputAction.done,
          validator: _validateConfirmPassword,
          enabled: !_isLoading,
          onFieldSubmitted: (_) => _handleResetPassword(),
          decoration: InputDecoration(
            labelText: '确认新密码',
            hintText: '再次输入新密码',
            prefixIcon: const Icon(Icons.lock_outlined),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () {
                setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword);
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 24),

        FilledButton(
          onPressed: _isLoading ? null : _handleResetPassword,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('重置密码', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  /// 完成步骤
  Widget _buildSuccessStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle,
                size: 48,
                color: Colors.green,
              ),
              const SizedBox(height: 16),
              Text(
                '密码重置成功！',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请使用您的新密码登录',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _goToLogin,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('去登录', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}
