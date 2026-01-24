import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_providers.dart';
import 'login_page.dart';

/// 注册页面
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _securityQuestionController = TextEditingController();
  final _securityAnswerController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;
  
  // 步骤控制: 0=账号信息, 1=安全问题
  int _currentStep = 0;
  
  // 预设的安全问题选项
  final List<String> _presetQuestions = [
    '您母亲的姓名是什么？',
    '您第一只宠物的名字是什么？',
    '您毕业的小学名称是什么？',
    '您最喜欢的电影是什么？',
    '您童年好友的名字是什么？',
    '您父亲的出生城市是什么？',
    '自定义问题...',
  ];
  String? _selectedQuestion;
  bool _useCustomQuestion = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nicknameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _securityQuestionController.dispose();
    _securityAnswerController.dispose();
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

  /// 验证昵称
  String? _validateNickname(String? value) {
    if (value != null && value.isNotEmpty && value.length < 2) {
      return '昵称至少2个字符';
    }
    if (value != null && value.length > 30) {
      return '昵称不能超过30个字符';
    }
    return null;
  }

  /// 验证密码
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return '请输入密码';
    }
    if (value.length < 8) {
      return '密码至少8位';
    }
    // 检查密码复杂度
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
      return '请确认密码';
    }
    if (value != _passwordController.text) {
      return '两次输入的密码不一致';
    }
    return null;
  }

  /// 验证安全问题
  String? _validateSecurityQuestion(String? value) {
    if (_useCustomQuestion) {
      if (value == null || value.isEmpty) {
        return '请输入自定义安全问题';
      }
      if (value.length < 5) {
        return '安全问题至少5个字符';
      }
    }
    return null;
  }

  /// 验证安全问题答案
  String? _validateSecurityAnswer(String? value) {
    if (value == null || value.isEmpty) {
      return '请输入安全问题答案';
    }
    if (value.length < 2) {
      return '答案至少2个字符';
    }
    return null;
  }

  /// 获取最终的安全问题
  String? get _finalSecurityQuestion {
    if (_useCustomQuestion) {
      return _securityQuestionController.text.trim();
    }
    return _selectedQuestion;
  }

  /// 验证第一步（账号信息）
  bool _validateStep1() {
    // 验证邮箱
    if (_validateEmail(_emailController.text) != null) {
      return false;
    }
    // 验证昵称（可选，但如果填了要验证）
    if (_validateNickname(_nicknameController.text) != null) {
      return false;
    }
    // 验证密码
    if (_validatePassword(_passwordController.text) != null) {
      return false;
    }
    // 验证确认密码
    if (_validateConfirmPassword(_confirmPasswordController.text) != null) {
      return false;
    }
    return true;
  }

  /// 进入下一步
  void _goToNextStep() {
    if (!_formKey.currentState!.validate()) return;
    
    if (_currentStep == 0 && _validateStep1()) {
      setState(() => _currentStep = 1);
    }
  }

  /// 返回上一步
  void _goToPreviousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep = _currentStep - 1);
    }
  }

  /// 执行注册
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请阅读并同意用户协议')),
      );
      return;
    }

    // 验证安全问题
    final question = _finalSecurityQuestion;
    if (question == null || question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择或输入安全问题')),
      );
      return;
    }

    ref.read(authStateProvider.notifier).clearError();

    final success = await ref.read(authStateProvider.notifier).register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          nickname: _nicknameController.text.trim().isEmpty
              ? null
              : _nicknameController.text.trim(),
        );

    if (success && mounted) {
      // 注册成功后设置安全问题
      final authService = ref.read(authServiceProvider);
      final securityResult = await authService.setSecurityQuestion(
        question: question,
        answer: _securityAnswerController.text.trim(),
      );

      if (!securityResult.success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('安全问题设置失败: ${securityResult.message}')),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('注册成功')),
        );
        Navigator.of(context).pop(true); // 返回 true 表示注册成功
      }
    }
  }

  /// 跳转到登录页面
  void _goToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authStateProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    final isTablet = screenWidth >= 600 && screenWidth < 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('注册'),
        centerTitle: true,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _goToPreviousStep,
              )
            : null,
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
                maxWidth: isDesktop ? 560 : (isTablet ? 500 : 400),
              ),
              child: Form(
                key: _formKey,
                child: isDesktop
                    ? _buildDesktopLayout(theme, authState)
                    : _buildMobileLayout(theme, authState),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 桌面端布局 - 卡片式分步骤设计
  Widget _buildDesktopLayout(ThemeData theme, AuthState authState) {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题区域
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _currentStep == 0
                        ? Icons.person_add_outlined
                        : Icons.security_outlined,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              _currentStep == 0 ? '创建账号' : '设置安全问题',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _currentStep == 0
                  ? '注册快淘帮账号，同步您的数据'
                  : '设置安全问题用于找回密码',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // 步骤指示器
            _buildStepIndicator(theme),
            const SizedBox(height: 32),

            // 错误提示
            if (authState.errorMessage != null) ...[
              _buildErrorMessage(theme, authState.errorMessage!),
              const SizedBox(height: 16),
            ],

            // 根据步骤显示不同内容
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _currentStep == 0
                  ? _buildStep1Content(theme, authState)
                  : _buildStep2Content(theme, authState),
            ),
          ],
        ),
      ),
    );
  }

  /// 移动端布局 - 单列分步骤设计
  Widget _buildMobileLayout(ThemeData theme, AuthState authState) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Logo / 标题
        Icon(
          _currentStep == 0
              ? Icons.person_add_outlined
              : Icons.security_outlined,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          _currentStep == 0 ? '创建账号' : '设置安全问题',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _currentStep == 0
              ? '注册快淘帮账号，同步您的数据'
              : '设置安全问题用于找回密码',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // 步骤指示器
        _buildStepIndicator(theme),
        const SizedBox(height: 32),

        // 错误提示
        if (authState.errorMessage != null) ...[
          _buildErrorMessage(theme, authState.errorMessage!),
          const SizedBox(height: 16),
        ],

        // 根据步骤显示不同内容
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _currentStep == 0
              ? _buildStep1Content(theme, authState)
              : _buildStep2Content(theme, authState),
        ),
      ],
    );
  }

  /// 步骤指示器
  Widget _buildStepIndicator(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 步骤1
        _buildStepCircle(theme, 0, '账号信息'),
        // 连接线
        Container(
          width: 60,
          height: 2,
          color: _currentStep >= 1
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
        // 步骤2
        _buildStepCircle(theme, 1, '安全设置'),
      ],
    );
  }

  Widget _buildStepCircle(ThemeData theme, int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: 2,
            ),
          ),
          child: Center(
            child: _currentStep > step
                ? Icon(
                    Icons.check,
                    size: 18,
                    color: theme.colorScheme.onPrimary,
                  )
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      color: isActive
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isCurrent
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  /// 步骤1：账号信息
  Widget _buildStep1Content(ThemeData theme, AuthState authState) {
    return Column(
      key: const ValueKey('step1'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 邮箱输入框
        _buildEmailField(theme, authState),
        const SizedBox(height: 16),

        // 昵称输入框
        _buildNicknameField(theme, authState),
        const SizedBox(height: 16),

        // 密码输入框
        _buildPasswordField(theme, authState),
        const SizedBox(height: 16),

        // 确认密码输入框
        _buildConfirmPasswordField(theme, authState),
        const SizedBox(height: 32),

        // 下一步按钮
        FilledButton(
          onPressed: authState.isLoading ? null : _goToNextStep,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('下一步', style: TextStyle(fontSize: 16)),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 20),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 登录链接
        _buildLoginLink(theme),
      ],
    );
  }

  /// 步骤2：安全问题
  Widget _buildStep2Content(ThemeData theme, AuthState authState) {
    return Column(
      key: const ValueKey('step2'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 安全问题下拉选择
        _buildSecurityQuestionDropdown(theme, authState),
        const SizedBox(height: 16),

        // 自定义安全问题输入
        if (_useCustomQuestion) ...[
          _buildCustomQuestionField(theme, authState),
          const SizedBox(height: 16),
        ],

        // 安全问题答案输入
        _buildSecurityAnswerField(theme, authState),
        const SizedBox(height: 24),

        // 用户协议
        _buildTermsCheckbox(theme),
        const SizedBox(height: 32),

        // 按钮行
        Row(
          children: [
            // 上一步按钮
            Expanded(
              child: OutlinedButton(
                onPressed: authState.isLoading ? null : _goToPreviousStep,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_back, size: 20),
                    SizedBox(width: 8),
                    Text('上一步'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            // 注册按钮
            Expanded(
              flex: 2,
              child: _buildRegisterButton(theme, authState),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // 通用组件
  // ============================================================

  Widget _buildErrorMessage(ThemeData theme, String message) {
    return Container(
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
              message,
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () =>
                ref.read(authStateProvider.notifier).clearError(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField(ThemeData theme, AuthState authState) {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      validator: _validateEmail,
      enabled: !authState.isLoading,
      decoration: InputDecoration(
        labelText: '邮箱 *',
        hintText: 'example@email.com',
        prefixIcon: const Icon(Icons.email_outlined),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildNicknameField(ThemeData theme, AuthState authState) {
    return TextFormField(
      controller: _nicknameController,
      textInputAction: TextInputAction.next,
      validator: _validateNickname,
      enabled: !authState.isLoading,
      decoration: InputDecoration(
        labelText: '昵称（可选）',
        hintText: '给自己起个名字吧',
        prefixIcon: const Icon(Icons.person_outline),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildPasswordField(ThemeData theme, AuthState authState) {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.next,
      validator: _validatePassword,
      enabled: !authState.isLoading,
      decoration: InputDecoration(
        labelText: '密码 *',
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
    );
  }

  Widget _buildConfirmPasswordField(ThemeData theme, AuthState authState) {
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirmPassword,
      textInputAction: TextInputAction.next,
      validator: _validateConfirmPassword,
      enabled: !authState.isLoading,
      decoration: InputDecoration(
        labelText: '确认密码 *',
        hintText: '再次输入密码',
        prefixIcon: const Icon(Icons.lock_outlined),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirmPassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () {
            setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
          },
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildSecurityQuestionDropdown(ThemeData theme, AuthState authState) {
    return DropdownButtonFormField<String>(
      value: _selectedQuestion,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: '安全问题 *',
        prefixIcon: const Icon(Icons.security_outlined),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      items: _presetQuestions.map((question) {
        return DropdownMenuItem<String>(
          value: question,
          child: Text(
            question,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: authState.isLoading
          ? null
          : (value) {
              setState(() {
                _selectedQuestion = value;
                _useCustomQuestion = value == '自定义问题...';
                if (!_useCustomQuestion) {
                  _securityQuestionController.clear();
                }
              });
            },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '请选择安全问题';
        }
        return null;
      },
    );
  }

  Widget _buildCustomQuestionField(ThemeData theme, AuthState authState) {
    return TextFormField(
      controller: _securityQuestionController,
      textInputAction: TextInputAction.next,
      validator: _validateSecurityQuestion,
      enabled: !authState.isLoading,
      decoration: InputDecoration(
        labelText: '自定义问题 *',
        hintText: '请输入您的自定义安全问题',
        prefixIcon: const Icon(Icons.edit_outlined),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildSecurityAnswerField(ThemeData theme, AuthState authState) {
    return TextFormField(
      controller: _securityAnswerController,
      textInputAction: TextInputAction.done,
      validator: _validateSecurityAnswer,
      enabled: !authState.isLoading,
      onFieldSubmitted: (_) => _handleRegister(),
      decoration: InputDecoration(
        labelText: '安全问题答案 *',
        hintText: '请输入答案（找回密码时需要）',
        prefixIcon: const Icon(Icons.question_answer_outlined),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        helperText: '请牢记您的答案，答案不区分大小写',
      ),
    );
  }

  Widget _buildTermsCheckbox(ThemeData theme) {
    return Row(
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: _agreedToTerms,
            onChanged: (v) {
              setState(() => _agreedToTerms = v ?? false);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            children: [
              Text(
                '我已阅读并同意',
                style: theme.textTheme.bodyMedium,
              ),
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('用户协议页面开发中')),
                  );
                },
                child: Text(
                  '《用户协议》',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '和',
                style: theme.textTheme.bodyMedium,
              ),
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('隐私政策页面开发中')),
                  );
                },
                child: Text(
                  '《隐私政策》',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterButton(ThemeData theme, AuthState authState) {
    return FilledButton(
      onPressed: authState.isLoading ? null : _handleRegister,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: authState.isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text(
              '注册',
              style: TextStyle(fontSize: 16),
            ),
    );
  }

  Widget _buildLoginLink(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '已有账号?',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        TextButton(
          onPressed: _goToLogin,
          child: const Text('立即登录'),
        ),
      ],
    );
  }
}
