import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用于复制功能
import 'package:supabase_flutter/supabase_flutter.dart';

// ================== 1. 登录页面 ==================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true; // 控制密码可见性

  // 登录逻辑
  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showToast("请输入邮箱和密码", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        _showToast("登录失败，请检查账号密码", isError: true);
      }
      // 登录成功后会自动跳转
    } on AuthException catch (e) {
      if (e.message.contains("Email not confirmed")) {
        _showToast("您的邮箱尚未验证，请查收邮件", isError: true);
      } else if (e.message.contains("Invalid login credentials")) {
        _showToast("账号或密码错误", isError: true);
      } else {
        _showToast("登录失败: ${e.message}", isError: true);
      }
    } catch (e) {
      _showToast("系统错误: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 新增：显示帮助/反馈弹窗 ---
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("帮助与反馈"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("如果您遇到注册或登录问题，请联系我们：", style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 20),
            
            // QQ群
            InkWell(
              onTap: () {
                Clipboard.setData(const ClipboardData(text: "1072752343"));
                _showToast("QQ群号已复制");
                Navigator.pop(ctx);
              },
              child: Row(
                children: const [
                  Icon(Icons.group, color: Colors.blueAccent),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("官方QQ群 (点击复制)", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text("1072752343", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Icon(Icons.copy, size: 16, color: Colors.grey),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // 邮箱
            InkWell(
              onTap: () {
                Clipboard.setData(const ClipboardData(text: "3403938458@qq.com"));
                _showToast("邮箱已复制");
                Navigator.pop(ctx);
              },
              child: Row(
                children: const [
                  Icon(Icons.email, color: Colors.blueAccent),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("反馈邮箱 (点击复制)", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text("3403938458@qq.com", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Icon(Icons.copy, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("关闭")),
        ],
      ),
    );
  }

  void _showResetDialog() {
    final emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("找回密码"),
        content: TextField(
          controller: emailCtrl,
          decoration: const InputDecoration(labelText: "请输入您的注册邮箱"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          ElevatedButton(
            onPressed: () async {
              if (emailCtrl.text.isEmpty) return;
              try {
                await Supabase.instance.client.auth.resetPasswordForEmail(emailCtrl.text.trim());
                if (mounted) {
                   Navigator.pop(ctx);
                   _showToast("重置邮件已发送，请查收");
                }
              } catch (e) {
                _showToast("发送失败: $e", isError: true);
              }
            },
            child: const Text("发送重置邮件"),
          ),
        ],
      ),
    );
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("安全登录")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shield_moon, size: 80, color: Colors.blueAccent),
                const SizedBox(height: 40),
                
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: '邮箱账号', 
                    border: OutlineInputBorder(), 
                    prefixIcon: Icon(Icons.email)
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),
                
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: '密码', 
                    border: const OutlineInputBorder(), 
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                ),
                
                // --- 修改布局：左右对称 ---
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween, // 两端对齐
                    children: [
                      // 左边：遇到问题
                      TextButton(
                        onPressed: _showHelpDialog,
                        child: const Text("遇到问题？", style: TextStyle(color: Colors.grey)),
                      ),
                      // 右边：忘记密码
                      TextButton(
                        onPressed: _showResetDialog,
                        child: const Text("忘记密码？", style: TextStyle(color: Colors.grey)),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 10),
                
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _signIn,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                      child: const Text("立即登录", style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  
                const SizedBox(height: 20),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("还没有账号？"),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RegisterPage()),
                        );
                      },
                      child: const Text("去注册新用户", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================== 2. 注册页面 (保持安全升级版逻辑) ==================
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  
  bool _isLoading = false;
  bool _codeSent = false;
  bool _obscurePassword = true;
  int _countdown = 0;
  Timer? _timer;

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _showToast("请输入有效的邮箱地址", isError: true);
      return;
    }
    if (password.length < 6) {
      _showToast("为了账号安全，密码至少需要6位", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );

      _showToast("验证码已发送，请查收邮件");
      setState(() {
        _codeSent = true;
        _isLoading = false;
        _startCountdown();
      });
      
    } on AuthException catch (e) {
      if (e.message.contains("User already registered") || e.message.contains("already exists")) {
        _showToast("该邮箱已被注册！请直接去登录", isError: true);
      } else {
        _showToast("发送失败: ${e.message}", isError: true);
      }
      setState(() => _isLoading = false);
    } catch (e) {
      _showToast("网络错误，请检查网络", isError: true);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmRegister() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    if (otp.isEmpty) {
      _showToast("请输入验证码", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        token: otp,
        type: OtpType.signup,
        email: email,
      );

      if (response.session != null) {
        _showToast("注册成功！正在进入...");
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.of(context).pop(); 
      }
    } on AuthException catch (e) {
      _showToast("验证码错误或已过期", isError: true);
    } catch (e) {
      _showToast("验证失败: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startCountdown() {
    _countdown = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          _timer?.cancel();
        }
      });
    });
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("注册会员账号")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("创建您的专属账号", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Text("注册后可多端同步数据", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              
              TextField(
                controller: _emailController,
                enabled: !_codeSent, 
                decoration: const InputDecoration(
                  labelText: '邮箱地址',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                  helperText: "请输入真实邮箱接收验证码"
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),
              
              TextField(
                controller: _passwordController,
                enabled: !_codeSent,
                decoration: InputDecoration(
                  labelText: '设置密码',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  helperText: "密码长度至少 6 位",
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
              ),
              const SizedBox(height: 20),

              if (_codeSent)
                TextField(
                  controller: _otpController,
                  decoration: const InputDecoration(
                    labelText: '邮箱验证码',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.security),
                    hintText: "请输入邮件中的数字",
                  ),
                  keyboardType: TextInputType.number,
                ),
              
              const SizedBox(height: 30),

              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                Column(
                  children: [
                    if (!_codeSent)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _sendCode,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                          child: const Text("发送验证码", style: TextStyle(fontSize: 18)),
                        ),
                      )
                    else
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _confirmRegister,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              child: const Text("立即注册", style: TextStyle(fontSize: 18)),
                            ),
                          ),
                          TextButton(
                            onPressed: _countdown > 0 ? null : _sendCode,
                            child: Text(_countdown > 0 ? "${_countdown}秒后可重发" : "没收到？检查垃圾箱或重新发送"),
                          )
                        ],
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}