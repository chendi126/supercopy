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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 【重要】请填入你的 Supabase URL 和 Anon Key
  await Supabase.initialize(
    url: 'https://ecqzdwemcwdmchzetwhr.supabase.co', // 替换你的 URL
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVjcXpkd2VtY3dkbWNoemV0d2hyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUxMjcyMTAsImV4cCI6MjA4MDcwMzIxMH0.NNbVk2U7rJcW4cRQpdOYQPNnfIqfPVQOXlvSvhAKICM', // 替换你的 Key
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

  // --- 修复：云端数据同步逻辑 ---
  void _startCloudSync() {
    _cloudSubscription = _supabase
        .from('history')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(maxRecordCount)
        .listen((List<Map<String, dynamic>> data) {
          
          final newList = data.map((e) {
             // 1. 拿到云端的原始内容
             String content = e['content'] ?? '';
             
             // 2. 【关键】重新放入“大脑”进行智能提取！
             // 这样云端下来的数据就和本地刚复制的一样聪明了
             ClipboardItem smartItem = _analyzeText(content);
             
             // 3. 把云端的身份证号 (ID) 和时间戳贴上去
             smartItem.id = e['id']; 
             // 如果云端有存时间，尽量用云端的，这里假设用当前或保留原逻辑
             // smartItem.timestamp = ... 
             
             // 3. 【关键】同步云端的收藏状态！
             // 注意：这里必须用 e['is_favorite']，因为这是数据库的原始数据
             smartItem.isFavorite = e['is_favorite'] ?? false;
             // 4. 恢复收藏状态 (如果数据库有存的话，目前假设本地逻辑)
             // smartItem.isFavorite = ...

             return smartItem;
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

 // --- 修复：上传后立刻获取身份ID ---
  Future<void> _uploadToCloud(String text, String type) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // 1. 先删旧的 (去重)
      await _supabase.from('history').delete().eq('content', text);

      // 2. 【关键】插入数据，并使用 .select() 立刻把生成的数据拿回来！
      final res = await _supabase.from('history').insert({
        'content': text,
        'type': type,
        'user_id': userId,
      }).select().single(); // .single() 表示只要这一条

      // 3. 【关键】找到本地那个 ID 为空的“临时工”，把云端的 ID 赋给它
      // 这样本地数据就有了“正式编制”，这时候你再点删除，它就有 ID 了！
      if (mounted) {
        setState(() {
          // 找到内容一样、且没有ID的那条数据
          try {
            final localItem = historyList.firstWhere(
              (item) => item.content == text && item.id == null
            );
            localItem.id = res['id']; // 赋予 ID
          } catch (e) {
            // 没找到就算了，Stream 稍后会自动更新整个列表
          }
        });
      }
      
    } catch (e) {
      // 静默失败
      print("同步异常: $e");
    }
  }

  // --- 修复：真正的下拉刷新逻辑 ---
  Future<void> _onRefresh() async {
    // 震动反馈
    _triggerVibration();
    
    try {
      // 1. 主动向 Supabase 请求最新的前 50 条数据
      final response = await _supabase
          .from('history')
          .select()
          .order('created_at', ascending: false)
          .limit(maxRecordCount);
      
      // 2. 将拿到的数据重新“智能分析”一遍
      final data = response as List<dynamic>;
      final newList = data.map((e) {
         String content = e['content'] ?? '';
         // 重新放入大脑分析，提取验证码等
         ClipboardItem smartItem = _analyzeText(content);
         // 贴上身份证号
         smartItem.id = e['id'];
         return smartItem;
      }).toList();

      // 3. 更新界面
      if (mounted) {
        setState(() {
          historyList = newList;
        });
        _showToast("已同步最新数据");
      }
    } catch (e) {
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


  // --- 修复：读取剪贴板 ---
  Future<void> _readClipboard() async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      // 防止重复点击
      if (historyList.isNotEmpty && historyList.first.content == data.text) {
         _showToast("内容已存在");
         return;
      }
      
      _addHistory(data.text!); // 添加到列表
      _showToast("已读取");
      _triggerVibration();
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

 // --- UI 优化：设置弹窗 (含账号信息) ---
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

               // 2. 开发者信息
               ListTile(
                 leading: const Icon(Icons.person),
                 title: const Text("开发者"),
                 subtitle: const Text("太空人"),
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

               // 3. 退出登录
               ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text("退出登录", style: TextStyle(color: Colors.red)),
                  onTap: () async {
                     Navigator.pop(ctx);
                     await _supabase.auth.signOut();
                  },
               ),

               // --- 新增：显示当前账号信息 ---
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
    String text = "文本";
    if (type == 'code') { bg = Colors.orange; text = "验证码"; }
    if (type == 'link') { bg = Colors.blue; text = "链接"; }
    if (type == 'phone') { bg = Colors.green; text = "电话"; }
    if (type == 'address') { bg = Colors.purple; text = "地址"; }
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