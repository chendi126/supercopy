import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:vibration/vibration.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'detail_page.dart';
import 'login_page.dart';
import 'package:confetti/confetti.dart'; // 记得导入这个包
import 'dart:math';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 【重要】请填入你的 Supabase URL 和 Anon Key
  await Supabase.initialize(
    url: 'your', // 替换你的 URL
    anonKey: 'your', // 替换你的 Key
  );

  runApp(const MyApp());
}

// --- 数据模型 ---
class ClipboardItem {
  int? id; // 数据库唯一ID
  String content;
  String extractedInfo;
  String type;
  List<String> tags;
  int timestamp;
  bool isFavorite;

  ClipboardItem({
    this.id,
    required this.content,
    required this.extractedInfo,
    this.type = 'text',
    this.tags = const [],
    required this.timestamp,
    this.isFavorite = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'extractedInfo': extractedInfo,
        'type': type,
        'tags': tags,
        'timestamp': timestamp,
        'isFavorite': isFavorite,
      };

  factory ClipboardItem.fromJson(Map<String, dynamic> json) {
    String safeType = json['type'] ?? 'text';
    List<String> safeTags = json['tags'] != null ? List<String>.from(json['tags']) : [safeType];
    
    return ClipboardItem(
      id: json['id'], // 必须获取 ID，否则无法删除
      content: json['content'] ?? '',
      extractedInfo: json['extractedInfo'] ?? '',
      type: safeType,
      tags: safeTags,
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      // 【关键修改】读取数据库里的 is_favorite 字段
      // 数据库里叫 is_favorite (下划线)，本地叫 isFavorite (驼峰)
      isFavorite: json['is_favorite'] ?? false,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '超级剪贴板',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(), 
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
      
      // 自动监听登录状态
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
          if (session != null) {
            return const HomePageWrapper();
          } else {
            return const LoginPage();
          }
        },
      ),
    );
  }
}

class HomePageWrapper extends StatefulWidget {
  const HomePageWrapper({super.key});
  @override
  State<HomePageWrapper> createState() => _HomePageWrapperState();
}

class _HomePageWrapperState extends State<HomePageWrapper> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('themeMode') ?? 0;
    setState(() {
      if (themeIndex == 1) _themeMode = ThemeMode.light;
      else if (themeIndex == 2) _themeMode = ThemeMode.dark;
      else _themeMode = ThemeMode.system;
    });
  }

  void _updateTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    int val = 0;
    if (mode == ThemeMode.light) val = 1;
    if (mode == ThemeMode.dark) val = 2;
    await prefs.setInt('themeMode', val);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF2F5F8),
        cardColor: Colors.white,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        cardColor: const Color(0xFF2C2C2C),
      ),
      home: HomePage(onThemeChanged: _updateTheme, currentTheme: _themeMode),
    );
  }
}

class HomePage extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final ThemeMode currentTheme;

  const HomePage({super.key, required this.onThemeChanged, required this.currentTheme});

  @override
  State<HomePage> createState() => _HomePageState();
}

// ==================== 新增：彩蛋弹窗动画组件 ====================


class StarRewardDialogContent extends StatefulWidget {
  const StarRewardDialogContent({super.key});

  @override
  State<StarRewardDialogContent> createState() => _StarRewardDialogContentState();
}

class _StarRewardDialogContentState extends State<StarRewardDialogContent> {
  // 1. 定义动画控制器
  late ConfettiController _controllerCenter;

  @override
  void initState() {
    super.initState();
    // 2. 初始化控制器，设置动画持续时间
    _controllerCenter = ConfettiController(duration: const Duration(seconds: 3));
    // 3. 弹窗一打开就自动开始播放动画
    _controllerCenter.play();
  }

  @override
  void dispose() {
    // 4. 一定要记得销毁控制器，防止内存泄漏
    _controllerCenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Stack 使得粒子动画能覆盖在文字和图片上方
    return Stack(
      alignment: Alignment.topCenter, // 粒子发射源在顶部中心
      children: [
        // --- 底层：原来的弹窗内容 ---
        Column(
          mainAxisSize: MainAxisSize.min, // 内容包裹，防止太高
          children: [
            // --- 替换开始 ---
            const Text(
              "“你也想看全是星星的宇宙吗？”",
              style: TextStyle(
                fontSize: 20, // 稍微加大一点，更有冲击力
                // fontStyle: FontStyle.italic, // 【已删除】去掉老气的斜体
                fontWeight: FontWeight.w700, // 使用更结实的粗体
                // color: Colors.blueAccent, // 【已删除】去掉默认蓝
                // 【新颜色】使用深邃的星空靛蓝色，更高级
                color: Color(0xFF283593), 
                letterSpacing: 1.5, // 【关键】增加字间距，瞬间提升气质
                height: 1.3, // 增加一点行高让文字更舒展
              ),
              textAlign: TextAlign.center,
            ),
            // --- 替换结束 ---
            const SizedBox(height: 20),
            // 显示图片，加了点阴影和圆角让它更好看
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/pay.png',
                  width: 220, // 稍微大了一点点
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) {
                    return Container(
                      width: 220, height: 220,
                      color: Colors.grey[200],
                      child: const Center(child: Text("图片加载失败\n请检查 assets/pay.jpg", textAlign: TextAlign.center)),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 15),
            const Text("感谢您的支持与打赏 ❤️", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
          ],
        ),

        // --- 顶层：粒子动画控件 ---
        ConfettiWidget(
          confettiController: _controllerCenter,
          blastDirectionality: BlastDirectionality.explosive, // 发射方向：爆发式（会向四周散开然后下落）
          shouldLoop: false, // 只播放一次，不循环
          colors: const [ // 设置星星的颜色，用金色、蓝色、青色营造宇宙感
            Colors.green,
            Colors.blue,
            Colors.pink,
            Colors.orange,
            Colors.purple
          ], 
          createParticlePath: drawStar, // 【关键】设置粒子形状为星星
          emissionFrequency: 0.05, // 发射频率 (越小越快)
          numberOfParticles: 20, // 一次发射多少个
          gravity: 0.2, // 重力感 (越大下落越快)
          minBlastForce: 10, // 最小爆发力
          maxBlastForce: 20, // 最大爆发力
        ),
      ],
    );
  }

  // --- 辅助函数：绘制星星形状 ---
  // 这是一个标准的绘制五角星的路径算法
  Path drawStar(Size size) {
    // Method to convert degree to radians
    double degToRad(double deg) => deg * (pi / 180.0);

    const numberOfPoints = 5;
    final halfWidth = size.width / 2;
    final externalRadius = halfWidth;
    final internalRadius = halfWidth / 2.5;
    final degreesPerStep = degToRad(360 / numberOfPoints);
    final halfDegreesPerStep = degreesPerStep / 2;
    final path = Path();
    final fullAngle = degToRad(360);
    path.moveTo(size.width, halfWidth);

    for (double step = 0; step < fullAngle; step += degreesPerStep) {
      path.lineTo(halfWidth + externalRadius * cos(step),
          halfWidth + externalRadius * sin(step));
      path.lineTo(halfWidth + internalRadius * cos(step + halfDegreesPerStep),
          halfWidth + internalRadius * sin(step + halfDegreesPerStep));
    }
    path.close();
    return path;
  }
}

// ==================== 新增：终极全屏流星+呼吸星空特效 ====================

// --- 1. 数据模型 ---
class Star {
  double x, y, radius;
  double baseOpacity; // 基础亮度
  double twinkleOffset; // 闪烁起始点（相位）
  double twinkleSpeed;  // 闪烁速度（新增：每颗星闪的快慢不一样）

  Star({
    required this.x, 
    required this.y, 
    required this.radius, 
    required this.baseOpacity, 
    required this.twinkleOffset,
    required this.twinkleSpeed,
  });
}

class Meteor {
  double x, y, length, angle, speed;
  double opacity;
  Meteor({
    required this.x, 
    required this.y, 
    required this.length, 
    required this.angle, 
    required this.speed, 
    this.opacity = 1.0
  });
}

// --- 2. 全屏页面组件 ---
class MeteorFullScreen extends StatefulWidget {
  const MeteorFullScreen({super.key});

  @override
  State<MeteorFullScreen> createState() => _MeteorFullScreenState();
}

class _MeteorFullScreenState extends State<MeteorFullScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _opacityAnimation;
  late AnimationController _skyController; // 驱动星空呼吸

  final List<Star> _stars = [];
  final List<Meteor> _meteors = [];
  final math.Random _random = math.Random();
  Timer? _meteorTimer;

  @override
  void initState() {
    super.initState();

    // 1. 内容渐显动画
    _fadeController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _opacityAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _fadeController.forward();
    });

    // 2. 天空循环动画 (无限循环，驱动星星闪烁)
    _skyController = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();

    // 3. 定时生成流星
    _meteorTimer = Timer.periodic(Duration(milliseconds: 800 + _random.nextInt(2000)), (timer) {
      if (mounted) _addMeteor();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _skyController.dispose();
    _meteorTimer?.cancel();
    super.dispose();
  }

  // 初始化星星
  void _initStars(Size size) {
    if (_stars.isNotEmpty) return;
    // 生成 200 颗星星
    for (int i = 0; i < 200; i++) {
      _stars.add(Star(
        x: _random.nextDouble() * size.width,
        y: _random.nextDouble() * size.height,
        radius: 0.5 + _random.nextDouble() * 2.0, // 大小差异化
        baseOpacity: 0.5 + _random.nextDouble() * 0.5, // 基础亮度
        twinkleOffset: _random.nextDouble() * math.pi * 2, // 随机起点
        twinkleSpeed: 0.5 + _random.nextDouble() * 1.5, // 随机闪烁速度 (0.5倍速 ~ 2倍速)
      ));
    }
  }

  // 添加流星
  void _addMeteor() {
    final size = MediaQuery.of(context).size;
    double angle = math.pi / 4 + (_random.nextDouble() - 0.5) * 0.3; // 45度角
    double speed = 12 + _random.nextDouble() * 8; 
    double length = 100 + _random.nextDouble() * 150;

    // 随机从上方或右侧出现
    double startX, startY;
    if (_random.nextBool()) {
      startX = size.width + length;
      startY = _random.nextDouble() * size.height * 0.6;
    } else {
      startX = _random.nextDouble() * size.width + size.width / 2;
      startY = -length;
    }

    setState(() {
      _meteors.add(Meteor(x: startX, y: startY, length: length, angle: angle, speed: speed));
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _initStars(size);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            // --- 1. 动态绘制层 (背景+星星+流星) ---
            AnimatedBuilder(
              animation: _skyController,
              builder: (context, child) {
                _updateMeteors(size);
                return CustomPaint(
                  size: size,
                  painter: SkyPainter(
                    stars: _stars,
                    meteors: _meteors,
                    // 传入一个随时间变化的因子
                    timeValue: DateTime.now().millisecondsSinceEpoch / 1000.0,
                  ),
                );
              },
            ),

            // --- 2. 前景文字内容 ---
            Center(
              child: FadeTransition(
                opacity: _opacityAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "“你也想看全是星星的宇宙吗？”",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 4.0, // 增加字间距，更有格调
                        height: 1.5,
                        shadows: [
                          Shadow(blurRadius: 25, color: Colors.blueAccent, offset: Offset(0, 0)),
                          Shadow(blurRadius: 10, color: Colors.white, offset: Offset(0, 0)),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 50),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, spreadRadius: 5),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/pay.png',
                          width: 240, height: 240, fit: BoxFit.cover,
                          errorBuilder: (_,__,___) => const SizedBox(
                            width: 240, height: 240, 
                            child: Center(child: Text("加载失败", style: TextStyle(color: Colors.white54))),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      "点击任意位置返回地球",
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, letterSpacing: 3),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateMeteors(Size size) {
    for (var m in _meteors) {
      m.x -= math.cos(m.angle) * m.speed;
      m.y += math.sin(m.angle) * m.speed;
      if (m.x < -m.length || m.y > size.height + m.length) {
        m.opacity -= 0.02;
      }
    }
    _meteors.removeWhere((m) => m.opacity <= 0 || m.x < -m.length * 2 || m.y > size.height + m.length * 2);
  }
}

// --- 3. 核心画笔 (控制星星闪烁) ---
class SkyPainter extends CustomPainter {
  final List<Star> stars;
  final List<Meteor> meteors;
  final double timeValue;

  SkyPainter({required this.stars, required this.meteors, required this.timeValue});

  @override
  void paint(Canvas canvas, Size size) {
    // A. 绘制背景 (深空渐变)
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Color(0xFF000000), // 纯黑
          Color(0xFF0B1026), // 深蓝
          Color(0xFF2B32B2), // 远处的星云蓝 (很淡)
        ],
        stops: [0.2, 0.6, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // B. 绘制星星 (呼吸闪烁逻辑)
    for (var star in stars) {
      // 核心算法：使用 Sine 正弦波模拟呼吸
      // timeValue * star.twinkleSpeed 让每颗星闪烁频率不一样
      // + star.twinkleOffset 让它们不要同时亮同时暗
      double sineWave = math.sin(timeValue * 3 * star.twinkleSpeed + star.twinkleOffset);
      
      // 将 Sine 波 (-1 ~ 1) 映射到 透明度 (0.2 ~ 1.0)
      // 这样星星最暗的时候也不会完全消失，最亮的时候非常亮
      double opacityFactor = (sineWave + 1) / 2; // 0 ~ 1
      double currentOpacity = 0.2 + (star.baseOpacity * 0.8 * opacityFactor);

      final paint = Paint()
        ..color = Colors.white.withOpacity(currentOpacity.clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5); // 微弱发光

      canvas.drawCircle(Offset(star.x, star.y), star.radius, paint);
    }

    // C. 绘制流星
    for (var m in meteors) {
      if (m.opacity <= 0) continue;
      
      double tailX = m.x + math.cos(m.angle) * m.length;
      double tailY = m.y - math.sin(m.angle) * m.length;

      final meteorPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withOpacity(m.opacity), // 头部亮白
            Colors.cyanAccent.withOpacity(m.opacity * 0.5), // 尾部带点青色
            Colors.transparent
          ],
          stops: const [0.0, 0.2, 1.0],
        ).createShader(Rect.fromPoints(Offset(m.x, m.y), Offset(tailX, tailY)))
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(m.x, m.y), Offset(tailX, tailY), meteorPaint);
      
      // 头部光晕
      canvas.drawCircle(Offset(m.x, m.y), 3, Paint()
        ..color = Colors.white.withOpacity(m.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
  }

  @override
  bool shouldRepaint(covariant SkyPainter oldDelegate) {
    return true; // 持续重绘以实现动画
  }
}

class _HomePageState extends State<HomePage> {
  List<ClipboardItem> historyList = [];
  String searchText = "";
  bool enableVibration = true;
  final int maxRecordCount = 50;
  final _supabase = Supabase.instance.client;
  StreamSubscription? _cloudSubscription;

  @override
  void initState() {
    super.initState();
    _initStorage();
    _startCloudSync(); // 启动同步
  }

  @override
  void dispose() {
    _cloudSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initStorage() async {
    final prefs = await SharedPreferences.getInstance();
    enableVibration = prefs.getBool('enableVibration') ?? true;
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enableVibration', enableVibration);
  }

  void _triggerVibration() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;
    if (enableVibration && await Vibration.hasVibrator() == true) {
      Vibration.vibrate(duration: 30);
    }
  }

// --- UI 优化：胶囊状提示框 ---
  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center, // 文字居中
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        // 颜色：错误用红色，正常用半透明深灰 (毛玻璃感用颜色模拟)
        backgroundColor: isError 
            ? Colors.red.withOpacity(0.9) 
            : const Color.fromARGB(171, 97, 97, 97).withOpacity(0.95),
        duration: const Duration(seconds: 1), // 显示时间短一点
        behavior: SnackBarBehavior.floating, // 悬浮模式
        elevation: 0, // 去掉阴影，更扁平
        // 形状：胶囊状 (圆角 50)
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        // 边距：让它悬浮在屏幕中下方，不要太宽
        margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height * 0.12, // 距离底部 12%
            left: 80, // 左右留白，让它变短
            right: 80
        ),
      ),
    );
  }

  // --- 修复 3: Stream 监听逻辑 (确保冷启动也加载 AI 数据) ---
  void _startCloudSync() {
    _cloudSubscription = _supabase
        .from('history')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(maxRecordCount)
        .listen((List<Map<String, dynamic>> data) {
          
          final newList = data.map((e) {
             String content = e['content'] ?? '';
             String? cloudExtracted = e['extracted_info'];
             String? cloudTagsStr = e['tags'];
             
             // 默认先用本地算一下（以防万一）
             ClipboardItem finalItem = _analyzeText(content);
             
             // 如果云端有“干货”，覆盖本地算法
             if (cloudExtracted != null && cloudExtracted.isNotEmpty && cloudExtracted != 'null' && cloudExtracted != content) {
                finalItem.extractedInfo = cloudExtracted;
                finalItem.type = e['type'] ?? 'text';
                
                // 处理 Tags
                if (cloudTagsStr != null && cloudTagsStr.isNotEmpty) {
                  finalItem.tags = cloudTagsStr.split(',');
                } else {
                  // 如果云端有类型但没 tags 字段，手动补一个
                  finalItem.tags = [finalItem.type == 'code' ? '取件码' : 
                                    finalItem.type == 'address' ? '地址' : '文本'];
                }
             }
             
             // 必须补全的基础字段
             finalItem.id = e['id'];
             finalItem.isFavorite = e['is_favorite'] ?? false;
             finalItem.timestamp = DateTime.parse(e['created_at']).millisecondsSinceEpoch;

             return finalItem;
          }).toList();

          if (mounted) {
            setState(() {
              historyList = newList;
            });
          }
        });
  }

  // --- 核心逻辑修复 2: 解决删除不掉 + Dismissible 报错 ---
  // 删除操作分为两步：1.立刻删UI(防止卡顿) 2.后台删数据库
  void _deleteItem(ClipboardItem item) {
    // 1. 同步操作：立刻更新界面，防止 Dismissible 报错
    setState(() {
      historyList.remove(item);
    });

    // 2. 异步操作：后台去删数据库
    _deleteItemFromCloud(item);
  }

  Future<void> _deleteItemFromCloud(ClipboardItem item) async {
    _triggerVibration();
    
    // 如果 item.id 是空的，说明这条数据还没同步完就被删了，或者数据有问题
    if (item.id != null) {
      try {
        await _supabase.from('history').delete().eq('id', item.id!);
      } catch (e) {
        // 静默失败，或者提示
        print("云端删除失败: $e");
      }
    }
  }
// --- 修改：上传函数 (支持返回 ID) ---
  Future<int?> _uploadToCloud(String text, String type, {bool isTemp = false}) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // 先删旧的
      await _supabase.from('history').delete().eq('content', text);

      // 插入新的，并返回 ID
      final res = await _supabase.from('history').insert({
        'content': text,
        'type': type,
        'user_id': userId,
        // 如果是刚读取还没分析，可以先标个 tags 叫 '分析中...'
        'tags': isTemp ? 'AI分析中' : '', 
      }).select().single();

      return res['id'] as int; // 返回新生成的 ID
      
    } catch (e) {
      print("上传失败: $e");
      return null;
    }
  }

  // --- 修复 2: 升级版 AI 分析 (更强的 Prompt + 完整的字段解析) ---
  Future<void> _analyzeWithKimi(ClipboardItem item) async {
    // 防止重复分析 (如果已经分析过且不是默认文本，就跳过，除非你想强制重刷)
    // if (item.extractedInfo != item.content) return; 

    _showToast("AI 正在深度思考...");
    // _triggerVibration(); // 频繁震动可能体验不好，可去掉

    const apiKey = "sk-xxxxxx"; 
    const apiUrl = "https://api.moonshot.cn/v1/chat/completions";

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          "model": "kimi-k2-turbo-preview", // 推荐使用 turbo 模型，速度快且够聪明
          "messages": [
            {
              "role": "system",
              "content": """
你是一个智能剪贴板助手。请分析用户文本，提取关键信息并按照优先级分类。
请严格返回 JSON 格式，不要包含 markdown 标记。

你需要识别以下内容：
1. 验证码 (verification): 明确包含"验证码"字样，或用于登录/注册的4-6位数字。
2. 取件码 (pickup): 快递取件码，通常包含"取件"、"驿站"、"丰巢"字样，或者是"8-1-203"这种格式。
3. 电话 (phone): 手机号或座机。
4. 链接 (link): http/https 链接。
5. 地址 (address): 包含省市区或详细街道。
6. 文本 (text): 无法提取上述内容。

请返回如下 JSON 结构：
{
  "primary_type": "类型字符串(verification/code/phone/link/address/text)",
  "extracted_info": "提取出的最核心的那一个信息(用于大字展示)",
  "tags": ["标签1", "标签2", "标签3"],
  "summary": "简短的一句话摘要(可选)"
}

逻辑规则：
- 如果文本包含 "验证码" 字样，primary_type 必须是 'verification'，tags 必须包含 "验证码"
- 如果是快递信息，primary_type 设为 'pickup'，tags 包含 "取件码"。
- 如果包含地址和电话，但没有取件码，primary_type 设为 'address' (因为地址通常更重要)，tags 包含 "地址", "电话"。
- 如果是单纯的链接，extracted_info 就是链接本身。
- 如果提取出的最核心的那一个信息是链接，那就要显示链接的标签link
- primary_type 必须是这六个单词之一：verification,code, phone, link, address, text。
"""
            },
            {"role": "user", "content": item.content}
          ],
          "temperature": 0.2 // 稍微降低随机性，保证格式稳定
        }),
      );

      if (response.statusCode == 200) {
        // 处理编码，防止中文乱码
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        String content = data['choices'][0]['message']['content'];
        // 清理可能存在的 markdown 符号
        content = content.replaceAll(RegExp(r'```json|```'), '').trim();

        try {
           final result = jsonDecode(content);
           
           // 1. 获取 AI 的分析结果
           String aiType = result['primary_type'] ?? 'text';
           String aiInfo = result['extracted_info'] ?? item.content;
           List<String> aiTags = [];
           if (result['tags'] != null) {
             aiTags = List<String>.from(result['tags']);
           } else {
             aiTags = [aiType]; // 兜底
           }

           // 映射一下中文标签名，让 UI 更好看
           // (其实可以让 AI 直接返回中文，但代码里映射更稳)
           // 这里我们直接信任 AI 返回的 tags，或者你可以保留之前的 _getTypeBadge 逻辑

           // 2. 更新数据库
           if (item.id != null) {
             await _supabase.from('history').update({
               'type': aiType,
               'extracted_info': aiInfo,
               'tags': aiTags.join(','), // 存入数据库
             }).eq('id', item.id!);
             
             // 3. (可选) 如果你想让本地 UI 瞬间变色，不需要等 Stream，可以手动 setState
             // 但因为你用了 StreamBuilder/Stream 监听，通常数据库变了，界面马上就会变
             _showToast("AI 识别完成: ${aiTags.join(',')}");
           }
           
        } catch (e) {
          print("AI JSON 解析失败: $content");
        }
      } else {
        print("AI API 错误: ${response.statusCode}");
      }
    } catch (e) {
      print("网络请求错误: $e");
    }
  }

  // --- 新增：把 AI 结果更新到云端 ---
  Future<void> _updateCloudSmartInfo(ClipboardItem item) async {
    if (item.id == null) return;
    try {
      await _supabase.from('history').update({
        'extracted_info': item.extractedInfo, // 存入刚加的字段
        'tags': item.tags.join(','),          // 存入刚加的字段(逗号拼接)
        'type': item.type,                    // 更新类型
      }).eq('id', item.id!);
    } catch (e) {
      print("云端更新失败: $e");
    }
  }

  // --- 修复 1: 真正智能的下拉刷新 (优先信任云端 AI 结果) ---
  Future<void> _onRefresh() async {
    _triggerVibration();
    
    try {
      // 1. 获取最新数据
      final response = await _supabase
          .from('history')
          .select()
          .order('created_at', ascending: false)
          .limit(maxRecordCount);
      
      final data = response as List<dynamic>;
      
      // 2. 转换数据 (关键逻辑修复)
      final newList = data.map((e) {
         String content = e['content'] ?? '';
         String? cloudExtracted = e['extracted_info'];
         String? cloudType = e['type'];
         String? cloudTags = e['tags']; // 假设数据库存的是 "电话,地址" 这种字符串

         ClipboardItem item;

         // 【核心修复】：如果云端有 AI 提取过的内容，直接用云端的！
         // 不要再运行 _analyzeText(content) 去覆盖它！
         if (cloudExtracted != null && cloudExtracted.isNotEmpty && cloudExtracted != 'null' && cloudExtracted != content) {
            item = ClipboardItem(
              id: e['id'],
              content: content,
              extractedInfo: cloudExtracted, 
              type: cloudType ?? 'text',
              // 将云端逗号分隔的字符串转回 List
              tags: (cloudTags != null && cloudTags.isNotEmpty) ? cloudTags.split(',') : [cloudType ?? 'text'],
              timestamp: DateTime.parse(e['created_at']).millisecondsSinceEpoch,
              isFavorite: e['is_favorite'] ?? false,
            );
         } else {
            // 只有云端没数据时，才使用本地正则“笨”办法
            item = _analyzeText(content);
            item.id = e['id']; // 记得把 ID 贴上去
            item.isFavorite = e['is_favorite'] ?? false;
         }
         return item;
      }).toList();

      if (mounted) {
        setState(() {
          historyList = newList;
        });
        _showToast("已同步最新数据");
      }
    } catch (e) {
      print("刷新报错: $e");
      _showToast("刷新失败，请检查网络", isError: true);
    }
  }

// --- 修复：智能分析与提取逻辑 ---
  ClipboardItem _analyzeText(String text) {
    String primaryType = 'text';
    String extractedInfo = text;
    Set<String> detectedTags = {}; // 用于存放所有标签

    // 1. 定义正则
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+)|(www\.[^\s]+)');
    final phoneRegex = RegExp(r'\b1[3-9]\d{9}\b');
    final addressRegex = RegExp(r'.+(省|市|区|县).+(路|街|道|巷|号|大厦|广场|中心|单元).*');
    final codeRegex = RegExp(r'\b\d{4,8}\b'); // 4-8位数字

    String? phoneMatch;
    String? codeMatch;
    String? linkMatch;
    String? addressMatch;

    // A. 提取电话
    if (phoneRegex.hasMatch(text)) {
      phoneMatch = phoneRegex.firstMatch(text)!.group(0)!;
      detectedTags.add('phone');
    }

    // B. 提取链接
    if (urlRegex.hasMatch(text)) {
      linkMatch = urlRegex.firstMatch(text)!.group(0)!;
      detectedTags.add('link');
    }

    // C. 提取验证码 (排除年份)
    Iterable<RegExpMatch> codeMatches = codeRegex.allMatches(text);
    for (var match in codeMatches) {
      String val = match.group(0)!;
      // 排除 1900-2050 这种像年份的数字
      if (val.length == 4) {
        int year = int.tryParse(val) ?? 0;
        if (year >= 1900 && year <= 2050) {
          continue; 
        }
      }
      codeMatch = val;
      detectedTags.add('code');
      break; 
    }

    // D. 提取地址
    if (addressRegex.hasMatch(text)) {
      // 去掉“地址：”这种前缀
      String addr = text.replaceAll(RegExp(r'^(地址|收货地址|位置|location)[:：]\s*', caseSensitive: false), '');
      addressMatch = addr;
      detectedTags.add('address');
    }

    // 2. 决定优先级 (电话 > 验证码 > 链接 > 地址 > 文本)
    if (phoneMatch != null) {
      primaryType = 'phone';
      extractedInfo = phoneMatch;
    } else if (codeMatch != null) {
      primaryType = 'code';
      extractedInfo = codeMatch;
    } else if (linkMatch != null) {
      primaryType = 'link';
      extractedInfo = linkMatch;
    } else if (addressMatch != null) {
      primaryType = 'address';
      extractedInfo = addressMatch;
    } else {
      primaryType = 'text';
      extractedInfo = text;
      detectedTags.add('text'); // 如果没别的，就是纯文本
    }

    return ClipboardItem(
      content: text,
      extractedInfo: extractedInfo,
      type: primaryType,
      tags: detectedTags.toList(), // 存入标签
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

// --- 导航功能: 自动识别安卓/iOS并唤起地图 ---
  Future<void> _openMap(String address) async {
    if (address.isEmpty) return;
    
    // 对地址进行 URL 编码，防止中文乱码
    final encodedAddress = Uri.encodeComponent(address);

    // 1. Android: 直接调用 geo 协议，系统会自动弹出已安装的地图列表
    if (Platform.isAndroid) {
      final Uri geoUri = Uri.parse("geo:0,0?q=$encodedAddress");
      try {
        // 直接尝试启动，不依赖 canLaunchUrl（它在某些设备上不可靠）
        await launchUrl(geoUri);
      } catch (e) {
        // geo 协议失败，尝试打开网页版高德地图
        final webUri = Uri.parse("https://www.amap.com/search?query=$encodedAddress");
        try {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        } catch (e2) {
          try { _showToast("无法调用地图应用"); } catch(e) {}
        }
      }
      return;
    }

    // 2. iOS: 只能手动弹窗让用户选 (因为 iOS 没有通用的 geo 选择器)
    if (Platform.isIOS) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("选择地图导航", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  const Divider(height: 1),

                  // 苹果自带地图
                  ListTile(
                    leading: const Icon(Icons.map, color: Colors.blue),
                    title: const Text("Apple 地图"),
                    onTap: () async {
                      Navigator.pop(context);
                      final Uri uri = Uri.parse("http://maps.apple.com/?q=$encodedAddress");
                      if (await canLaunchUrl(uri)) await launchUrl(uri);
                    },
                  ),

                  // 高德地图 (iOS)
                  ListTile(
                    leading: const Icon(Icons.near_me, color: Colors.orange),
                    title: const Text("高德地图"),
                    onTap: () async {
                      Navigator.pop(context);
                      final Uri uri = Uri.parse("iosamap://path?sourceApplication=clipboard_app&dname=$encodedAddress&dev=0&t=0");
                      if (await canLaunchUrl(uri)) await launchUrl(uri);
                      else try { _showToast("未安装高德地图"); } catch(e) {}
                    },
                  ),

                  // 百度地图 (iOS)
                  ListTile(
                    leading: const Icon(Icons.navigation, color: Colors.red),
                    title: const Text("百度地图"),
                    onTap: () async {
                      Navigator.pop(context);
                      final Uri uri = Uri.parse("baidumap://map/direction?destination=$encodedAddress&coord_type=bd09ll&mode=driving");
                      if (await canLaunchUrl(uri)) await launchUrl(uri);
                      else try { _showToast("未安装百度地图"); } catch(e) {}
                    },
                  ),

                  const Divider(height: 1),
                  ListTile(
                    title: const Center(child: Text("取消", style: TextStyle(color: Colors.grey))),
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    // 3. Windows/macOS/Linux/Web: 打开网页版地图
    final webUri = Uri.parse("https://www.amap.com/search?query=$encodedAddress");
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } else {
      try { _showToast("无法打开地图"); } catch(e) { print("无法打开地图"); }
    }
  }


  // --- 修改：读取剪贴板 (自动触发 AI) ---
 // --- 修复后的：读取剪贴板 (本地立即显示 + 后台静默上传) ---
Future<void> _readClipboard() async {
  ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
  if (data != null && data.text != null && data.text!.isNotEmpty) {
    String text = data.text!;
    
    // 1. 查重
    if (historyList.isNotEmpty && historyList.first.content == text) {
       _showToast("内容已存在");
       return;
    }

    _showToast("正在读取并进行 AI 分析...");
    _triggerVibration();

    // ================= 【核心修改开始：乐观更新】 =================
    
    // A. 本地快速分析出基础信息 (使用本地的 _analyzeText)
    ClipboardItem tempItem = _analyzeText(text); 
    
    // B. 【关键】立即更新 UI 列表
    if (mounted) {
      setState(() {
        historyList.insert(0, tempItem);
      });
    }

    // ================= 【核心修改结束】 =================

    // 2. 后台异步上传 (将原来的步骤 2 变为后台任务)
    // 这一步会生成真实的 ID，并插入数据库
    final newItemId = await _uploadToCloud(text, 'text', isTemp: true);

    // 3. 拿到 ID 后，触发 AI 分析
    if (newItemId != null) {
      // 构造一个带 ID 的 item 传给 AI
      tempItem.id = newItemId; 
      
      // 调用 AI 分析，AI 分析完成后会 update 数据库。
      // 数据库 update 会触发 Realtime Stream 刷新，将 AI 结果带回 UI，替换掉本地的临时数据。
      _analyzeWithKimi(tempItem); 
    }

  } else {
    _showToast("剪贴板为空");
  }
}

  // --- 修复：添加历史记录 (即时响应) ---
  void _addHistory(String text, {bool fromCloud = false}) {
    // 1. 查重
    if (historyList.any((e) => e.content == text)) return;
    
    // 2. 智能分析
    final newItem = _analyzeText(text);

    // 3. 【关键】立刻更新本地 UI (不需要等云端)
    if (mounted) {
      setState(() {
        historyList.insert(0, newItem);
        // 限制本地数量
        if (historyList.length > maxRecordCount) {
          historyList.removeWhere((item) => !item.isFavorite);
          if (historyList.length > maxRecordCount) historyList.removeLast();
        }
      });
    }

    // 4. 如果是本地读取的，后台静默上传到云端
    if (!fromCloud) {
      _uploadToCloud(newItem.content, newItem.type);
    }
  }

 // --- 修复：收藏状态同步云端 ---
  void _toggleFavorite(ClipboardItem item) async {
    // 1. 本地立刻变色 (UI 响应)
    setState(() => item.isFavorite = !item.isFavorite);
    _triggerVibration();

    // 2. 如果有 ID，发送更新指令给云端
    if (item.id != null) {
      try {
        await _supabase.from('history').update({
          'is_favorite': item.isFavorite, // 更新字段
        }).eq('id', item.id!);
      } catch (e) {
        print("收藏同步失败: $e");
        // 失败了最好回滚状态，或者提示用户，这里为了体验暂不回滚
      }
    }
  }

  // --- 修复：一键清除（保留收藏 + 同步云端） ---
  void _clearAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("清空记录"),
        content: const Text("确定要清空所有未收藏的历史记录吗？\n(收藏的内容会被保留)"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () async {
              _triggerVibration();
              
              // 1. 找出所有【非收藏】且【有ID】的数据
              final idsToDelete = historyList
                  .where((item) => !item.isFavorite && item.id != null)
                  .map((item) => item.id!)
                  .toList();
                  
              // 2. 本地立刻清除 (只保留收藏的)
              setState(() {
                historyList.removeWhere((item) => !item.isFavorite);
              });
              
              Navigator.pop(ctx); // 关闭弹窗
              
              // 3. 云端批量删除
              if (idsToDelete.isNotEmpty) {
                try {
                   // 批量删除 ID 在列表里的数据
                   await _supabase.from('history').delete().filter('id', 'in', idsToDelete);
                   _showToast("已同步清空");
                } catch (e) {
                   // 失败不打扰用户
                   print("云端清空失败: $e");
                }
              }
            },
            child: const Text("确认清空", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _goToDetailPage(ClipboardItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DetailPage(
          item: item,
          onDelete: () {
            _deleteItem(item); // 这里的删除已经包含了云端删除
            Navigator.pop(context);
          },
          onFavorite: () => _toggleFavorite(item),
        ),
      ),
    );
  }

 // --- 更新：设置弹窗 (含打赏彩蛋) ---
  void _showSettings(BuildContext context) {
    // 获取当前用户信息
    final user = _supabase.auth.currentUser;
    final userEmail = user?.email ?? "未知账号";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75, 
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               const Text("应用设置", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
               const SizedBox(height: 20),
               
               // 1. 基础设置
               ListTile(
                 leading: const Icon(Icons.vibration),
                 title: const Text("震动反馈"),
                 trailing: Switch(
                   value: enableVibration,
                   onChanged: (val) {
                     setState(() => enableVibration = val);
                     _saveData();
                     Navigator.pop(ctx);
                   },
                 ),
               ),
               ListTile(
                 leading: const Icon(Icons.color_lens),
                 title: const Text("主题设置"),
                 trailing: DropdownButton<ThemeMode>(
                   value: widget.currentTheme,
                   underline: Container(),
                   items: const [
                     DropdownMenuItem(value: ThemeMode.system, child: Text("自动")),
                     DropdownMenuItem(value: ThemeMode.light, child: Text("浅色")),
                     DropdownMenuItem(value: ThemeMode.dark, child: Text("深色")),
                   ],
                   onChanged: (val) {
                     if (val != null) {
                       widget.onThemeChanged(val);
                       Navigator.pop(ctx);
                     }
                   },
                 ),
               ),

               const Divider(height: 30),
               const Text("关于", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
               const SizedBox(height: 10),

               // --- 开发者彩蛋 (全屏流星版) ---
               ListTile(
                 leading: const Icon(Icons.person),
                 title: const Text("开发者"),
                 subtitle: const Text("太空人"),
                 onTap: () {
                   // 先关闭当前的设置弹窗
                   Navigator.pop(context);

                   // 然后跳转到全屏流星页面
                   // 使用 PageRouteBuilder 来实现自定义的淡入效果，而不是普通的侧滑跳转
                   Navigator.of(context).push(
                     PageRouteBuilder(
                       opaque: false, // 【关键】设为透明，这样可以看到底下主页隐约的影子(如果背景不是全黑的话)
                       pageBuilder: (context, _, __) => const MeteorFullScreen(),
                       transitionsBuilder: (context, animation, secondaryAnimation, child) {
                         return FadeTransition(opacity: animation, child: child);
                       },
                     ),
                   );
                 },
               ),
               
               ListTile(
                 leading: const Icon(Icons.email_outlined),
                 title: const Text("意见反馈"),
                 subtitle: const Text("3403938458@qq.com"),
                 onTap: () async {
                    final uri = Uri.parse("mailto:3403938458@qq.com");
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                 },
               ),
               ListTile(
                 leading: const Icon(Icons.group),
                 title: const Text("交流QQ群"),
                 subtitle: const Text("1072752343 (点击复制)"),
                 onTap: () {
                    Clipboard.setData(const ClipboardData(text: "1072752343"));
                    _showToast("QQ群号已复制");
                 },
               ),
               ListTile(
                 leading: const Icon(Icons.code),
                 title: const Text("Github 开源"),
                 subtitle: const Text("github.com/chendi126/supercopy"),
                 onTap: () async {
                    final uri = Uri.parse("https://github.com/chendi126/supercopy");
                    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                 },
               ),

               const Divider(height: 30),

               ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text("退出登录", style: TextStyle(color: Colors.red)),
                  onTap: () async {
                     Navigator.pop(ctx);
                     await _supabase.auth.signOut();
                  },
               ),

               Padding(
                 padding: const EdgeInsets.only(top: 10, bottom: 20),
                 child: Center(
                   child: Column(
                     children: [
                       Text("当前登录账号", style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                       const SizedBox(height: 4),
                       Text(userEmail, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                       const SizedBox(height: 10),
                       const Text("Version 1.3.0 Pro", style: TextStyle(fontSize: 12, color: Colors.grey)),
                     ],
                   ),
                 ),
               ),
            ],
          ),
        ),
      ),
    );
  }


  // --- 注销 ---
  void _signOut() async {
    await _supabase.auth.signOut();
  }

  // --- UI 构建 ---
  @override
  Widget build(BuildContext context) {
    final filteredList = historyList.where((item) =>
        searchText.isEmpty || item.content.toLowerCase().contains(searchText.toLowerCase())
    ).toList();

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              // 顶部栏
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.settings), onPressed: () => _showSettings(context)),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text("云同步", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          Text("超级剪切板Pro", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const Spacer(),

// --- 新增：一键清除按钮 ---
                      IconButton(
                        icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent), // 垃圾桶图标
                        tooltip: "清空非收藏内容",
                        onPressed: _clearAll, // 绑定清空函数
                      ),

                      // 刷新按钮 (也可以下拉)
                      IconButton(
                        icon: const Icon(Icons.refresh), 
                        onPressed: _onRefresh,
                      ),
                    ],
                  ),
                ),
              ),
              // 搜索框
               Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: TextField(
                  decoration: const InputDecoration(hintText: '搜索...', prefixIcon: Icon(Icons.search), filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(30)), borderSide: BorderSide.none)),
                  onChanged: (val) => setState(() => searchText = val),
                ),
              ),

              // 列表区域
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _onRefresh,
                  child: filteredList.isEmpty
                      ? ListView(children: const [SizedBox(height: 300, child: Center(child: Text("暂无数据，请尝试下拉刷新")))])
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 100, top: 10, left: 16, right: 16),
                          itemCount: filteredList.length,
                          itemBuilder: (ctx, index) {
                            final item = filteredList[index];
                            return Dismissible(
                              key: Key(item.id?.toString() ?? item.timestamp.toString()),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              // 修复：必须同步更新界面，否则报错
                              onDismissed: (_) => _deleteItem(item),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () => _goToDetailPage(item),
                                    child: _buildListCardContent(item),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
           Positioned(
            bottom: 30, left: 20, right: 20,
            child: ElevatedButton(
              onPressed: _readClipboard, 
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text("读取剪贴板", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ),
        ],
      ),
    );
  }

  // --- 卡片 UI (保持你的样式) ---
  Widget _buildListCardContent(ClipboardItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: item.isFavorite ? Border.all(color: Colors.orange, width: 2) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ...item.tags.map((tag) => Padding(padding: const EdgeInsets.only(right: 6), child: _getTypeBadge(tag))),
              const Spacer(),
              if (item.isFavorite) const Padding(padding: EdgeInsets.only(left: 8), child: Text("⭐", style: TextStyle(fontSize: 12))),
              Text(
                DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.timestamp)),
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),

            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.type == 'text' ? item.content : item.extractedInfo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: item.type == 'text' ? 14 : 18,
              fontWeight: item.type == 'text' ? FontWeight.normal : FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _actionChip("复制", false, () {
                 Clipboard.setData(ClipboardData(text: item.extractedInfo));
                 _showToast("已复制");
                 _triggerVibration();
              }),
              if (['link', 'phone', 'address'].contains(item.type))
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _actionChip(_getTypeActionText(item.type), true, () async {
                     final text = item.extractedInfo;
                     if (item.type == 'link') {
                        final uri = Uri.parse(text.startsWith('http') ? text : 'https://$text');
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                     }
                     if (item.type == 'phone') {
                        final uri = Uri.parse('tel:$text');
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                     }
                     // 3. 【新增】处理地址导航 (调用 _openMap)
                     if (['address'].contains(item.type)) {
                     await _openMap(text); // <--- 这里调用刚才添加的导航函数
                     }
                  }),
                ),
            ],
          )
        ],
      ),
    );
  }

  Widget _getTypeBadge(String type) {
    Color bg = Colors.grey;
    String text = type; 

    // 1. 验证码 (红色/粉色 醒目)
    if (type == 'verification' || type == '验证码') { 
      bg = Colors.redAccent; // 验证码通常比较紧急，用红色
      text = "验证码"; 
    } 
    // 2. 取件码 (橙色)
    else if (type == 'pickup' || type == 'code' || type == '取件码') { 
      bg = Colors.orange; 
      text = "取件码"; 
    } 
    // 3. 链接 (蓝色)
    else if (type == 'link' || type == '链接') { 
      bg = Colors.blue; 
      text = "链接"; 
    } 
    // 4. 电话 (绿色)
    else if (type == 'phone' || type == '电话' || type == '手机号') { 
      bg = Colors.green; 
      text = "电话"; 
    } 
    // 5. 地址 (紫色)
    else if (type == 'address' || type == '地址') { 
      bg = Colors.purple; 
      text = "地址"; 
    }

    if (text == 'text') text = '文本';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  String _getTypeActionText(String type) {
    if (type == 'link') return "打开";
    if (type == 'phone') return "拨打";
    if (type == 'address') return "导航";
    return "";
  }

  Widget _actionChip(String label, bool isPrimary, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isPrimary ? Colors.blueAccent : Colors.transparent,
          border: isPrimary ? null : Border.all(color: Colors.grey.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(color: isPrimary ? Colors.white : Colors.grey[700], fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }
}