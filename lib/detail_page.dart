import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'main.dart'; // 引入 main.dart 以获取 ClipboardItem 定义

class DetailPage extends StatefulWidget {
  final ClipboardItem item;
  final VoidCallback onDelete;
  final VoidCallback onFavorite;

  const DetailPage({
    super.key,
    required this.item,
    required this.onDelete,
    required this.onFavorite,
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  // 辅助方法：保持你原有的逻辑
  String _getTypeName(String type) {
    if (type == 'code') return "验证码";
    if (type == 'link') return "网页链接";
    if (type == 'phone') return "电话号码";
    if (type == 'address') return "地图位置";
    return "文本内容";
  }

  String _getTypeActionText(String type) {
    if (type == 'link') return "打开";
    if (type == 'phone') return "拨打";
    if (type == 'address') return "导航";
    return "";
  }

  void _copyToSystem(String text) {
    Clipboard.setData(ClipboardData(text: text));
    Fluttertoast.showToast(msg: "已复制");
  }

  void _openLink(String url) async {
    final Uri uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _callNumber(String phone) async {
    final Uri uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _openMap(String address) async {
    final Uri uri = Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _openLink('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              // 导航栏
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context), // 这里改为 pop
                    ),
                    Text(_getTypeName(item.type),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(item.isFavorite ? Icons.star : Icons.star_border,
                              color: item.isFavorite ? Colors.orange : null),
                          onPressed: () {
                            widget.onFavorite();
                            setState(() {}); // 刷新本地状态显示星星变化
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: widget.onDelete,
                        ),
                      ],
                    )
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[850] : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 20,
                                offset: const Offset(0, 10))
                          ],
                        ),
                        child: Column(
                          children: [
                            if (item.type == 'code')
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  item.extractedInfo,
                                  style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                      letterSpacing: 2),
                                ),
                              )
                            else
                              Text(
                                item.extractedInfo,
                                style: const TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Divider(),
                            ),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text("原始内容",
                                  style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(item.content,
                                  style: const TextStyle(height: 1.5)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _copyToSystem(item.content),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30)),
                              ),
                              child: const Text("复制全部"),
                            ),
                          ),
                          if (['link', 'phone', 'address'].contains(item.type)) ...[
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  if (item.type == 'link') _openLink(item.extractedInfo);
                                  if (item.type == 'phone') _callNumber(item.extractedInfo);
                                  if (item.type == 'address') _openMap(item.extractedInfo);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30)),
                                ),
                                child: Text(_getTypeActionText(item.type)),
                              ),
                            ),
                          ]
                        ],
                      )
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}