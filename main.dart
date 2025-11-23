import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart'; // Ensure this is in pubspec.yaml

// ---------------------------------------------------------------------------
// 0. INTERNATIONALIZATION (I18N)
// ---------------------------------------------------------------------------

class Strings {
  static bool isZh = false;

  static void init() {
    // Simple locale detection
    try {
      final locale = ui.window.locale.languageCode;
      isZh = locale == 'zh';
    } catch (e) {
      isZh = false;
    }
  }

  static String get(String key) {
    return _data[key]?[isZh ? 'zh' : 'en'] ?? key;
  }

  static const Map<String, Map<String, String>> _data = {
    'welcome': {'en': 'Welcome,', 'zh': '欢迎，'},
    'daily_streak': {'en': 'Total Scans 🔥', 'zh': '累计扫描 🔥'},
    'items_count': {'en': 'Items', 'zh': '次'},
    'scan': {'en': 'Scan', 'zh': '扫描'},
    'upload': {'en': 'Upload', 'zh': '上传'},
    'profile': {'en': 'Profile', 'zh': '个人中心'},
    'collection': {'en': 'Collection', 'zh': '收藏本'},
    'settings': {'en': 'Settings', 'zh': '设置'},
    'nickname': {'en': 'Nickname', 'zh': '昵称'},
    'api_key': {'en': 'Tongyi API Key', 'zh': '通义千问 API Key'},
    'save_changes': {'en': 'Save Changes', 'zh': '保存修改'},
    'saved': {'en': 'Saved', 'zh': '已保存'},
    'add': {'en': 'Add', 'zh': '添加'},
    'dual': {'en': 'Dual', 'zh': '双语'},
    'rescan': {'en': 'Re-Scan', 'zh': '重扫'},
    'save': {'en': 'Save', 'zh': '保存'},
    'export_title': {'en': 'Image Saved', 'zh': '图片已保存'},
    'export_msg': {'en': 'Saved to:', 'zh': '保存路径：'},
    'collect_word': {'en': 'Collect Word', 'zh': '收藏单词'},
    'word_collected': {'en': 'Word Collected!', 'zh': '单词已收藏！'},
    'tap_avatar': {'en': 'Tap to change avatar', 'zh': '点击更换头像'},
    'api_guide_title': {'en': 'Get API Key', 'zh': '获取 API Key'},
    'api_guide_desc': {'en': 'Click to visit Alibaba Cloud console', 'zh': '点击前往阿里云百炼控制台获取'},
    'dev_intro': {'en': 'Developer', 'zh': '开发者'},
    'dev_name': {'en': 'Lang Lai', 'zh': '浪来'},
    'dev_desc': {'en': 'Click to visit Bilibili', 'zh': '点击跳转 B 站主页'},
    'english_only': {'en': 'English Only', 'zh': '仅英文'},
    'chinese_only': {'en': 'Chinese Mode', 'zh': '中文模式'},
    'scanning': {'en': 'AI Scanning...', 'zh': 'AI 识别中...'},
    'error': {'en': 'Error', 'zh': '错误'},
    'check_api': {'en': 'Check API Key in Settings', 'zh': '请检查设置中的 API Key'},
    'no_key': {'en': 'Please set API Key first!', 'zh': '请先设置 API Key！'},
    'added_images': {'en': 'Added images', 'zh': '已添加图片'},
  };
}

// ---------------------------------------------------------------------------
// 1. SERVICES (API & STORAGE)
// ---------------------------------------------------------------------------

class TongyiService {
  static const String _baseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'; 

  static Future<List<AnalyzedItem>> analyzeImage(String apiKey, String imagePath) async {
    final File imageFile = File(imagePath);
    final List<int> imageBytes = await imageFile.readAsBytes();
    final String base64Image = base64Encode(imageBytes);
    
    String mimeType = 'image/jpeg';
    if (imagePath.toLowerCase().endsWith('.png')) mimeType = 'image/png';
    else if (imagePath.toLowerCase().endsWith('.webp')) mimeType = 'image/webp';

    final String systemPrompt = Strings.isZh 
    ? """
      你是一个英语学习助手。识别图中的3-5个不同物体。
      仅返回符合此结构的有效JSON：
      [
        {
          "label": "英文名称",
          "chinese": "中文名称",
          "pronunciation": "/音标/",
          "example": "英文例句。",
          "example_cn": "例句中文翻译。",
          "x": 0.5, 
          "y": 0.5
        }
      ]
      坐标 x/y 为相对值 (0.0-1.0)。不要使用markdown格式。
      """
    : """
      You are an English learning assistant. Identify 3-5 distinct objects in the image.
      Return ONLY valid JSON matching this structure:
      [
        {
          "label": "English Name",
          "chinese": "Chinese Name",
          "pronunciation": "/IPA/",
          "example": "English example sentence.",
          "example_cn": "Chinese translation of example.",
          "x": 0.5, 
          "y": 0.5
        }
      ]
      Coordinates x/y relative (0.0-1.0). No markdown.
      """;

    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          "model": "qwen-vl-max",
          "messages": [
            {
              "role": "user",
              "content": [
                {"type": "text", "text": systemPrompt},
                {"type": "image_url", "image_url": {"url": "data:$mimeType;base64,$base64Image"}}
              ]
            }
          ],
          "max_tokens": 1000,
        }),
      );

      if (response.statusCode == 200) {
        AppState.instance.incrementRecognitionCount();
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content = data['choices'][0]['message']['content'];
        final cleanJson = content.replaceAll('```json', '').replaceAll('```', '').trim();
        final List<dynamic> jsonList = jsonDecode(cleanJson);
        return jsonList.map((e) => AnalyzedItem.fromJson(e)).toList();
      } else {
        throw Exception("API Error: ${response.statusCode}");
      }
    } catch (e) {
      if (e.toString().contains("401")) throw Exception(Strings.get('check_api'));
      await Future.delayed(const Duration(seconds: 2));
      return _getMockData();
    }
  }

  static List<AnalyzedItem> _getMockData() {
    return [
      AnalyzedItem(
        label: "Smartphone",
        chinese: "智能手机",
        pronunciation: "/ˈsmɑːrt.foʊn/",
        example: "She checked her messages.",
        exampleCn: "她查看了信息。",
        x: 0.3, y: 0.6,
      ),
      AnalyzedItem(
        label: "Coffee",
        chinese: "咖啡",
        pronunciation: "/ˈkɒf.i/",
        example: "I love hot coffee.",
        exampleCn: "我喜欢热咖啡。",
        x: 0.7, y: 0.4,
      ),
    ];
  }
}

class VocabularyService {
  static const String _key = 'vocab_list_v2';

  static Future<List<AnalyzedItem>> loadVocabulary() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_key);
    if (jsonString == null) return [];
    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded.map((e) => AnalyzedItem.fromJson(e)).toList();
  }

  static Future<void> saveWord(AnalyzedItem item) async {
    final prefs = await SharedPreferences.getInstance();
    List<AnalyzedItem> current = await loadVocabulary();
    if (!current.any((e) => e.label == item.label)) {
      current.insert(0, item);
      await prefs.setString(_key, jsonEncode(current.map((e) => e.toJson()).toList()));
    }
  }

  static Future<void> deleteWord(String label) async {
    final prefs = await SharedPreferences.getInstance();
    List<AnalyzedItem> current = await loadVocabulary();
    current.removeWhere((e) => e.label == label);
    await prefs.setString(_key, jsonEncode(current.map((e) => e.toJson()).toList()));
  }
}

// ---------------------------------------------------------------------------
// 2. GLOBAL STATE
// ---------------------------------------------------------------------------

class AppState extends ChangeNotifier {
  static final AppState instance = AppState();

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;
  String _nickname = "Learner";
  String? _avatarPath;
  String _apiKey = "";
  int _recognitionCount = 0;
  
  String get nickname => _nickname;
  String? get avatarPath => _avatarPath;
  String get apiKey => _apiKey;
  int get recognitionCount => _recognitionCount;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = (prefs.getBool('isDark') ?? false) ? ThemeMode.dark : ThemeMode.light;
    _nickname = prefs.getString('nickname') ?? "Learner";
    _avatarPath = prefs.getString('avatarPath');
    _apiKey = prefs.getString('tongyi_api_key') ?? "";
    _recognitionCount = prefs.getInt('recognitionCount') ?? 0;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', _themeMode == ThemeMode.dark);
    notifyListeners();
  }

  Future<void> updateProfile(String name, String? path) async {
    _nickname = name;
    _avatarPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nickname', name);
    if (path != null) await prefs.setString('avatarPath', path);
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tongyi_api_key', key);
    notifyListeners();
  }

  Future<void> incrementRecognitionCount() async {
    _recognitionCount++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('recognitionCount', _recognitionCount);
    notifyListeners();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Strings.init(); // Initialize i18n
  await AppState.instance.loadSettings();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  // Disable auto-rotation generally
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const EnglishLearningApp());
}

class EnglishLearningApp extends StatelessWidget {
  const EnglishLearningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'Vision Learn',
          debugShowCheckedModeBanner: false,
          themeMode: AppState.instance.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF5F6FA),
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C5CE7)),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0F0F1A),
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C5CE7), brightness: Brightness.dark),
          ),
          home: const MainNavigationWrapper(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 3. UI HELPERS (STYLES & ANIMATIONS)
// ---------------------------------------------------------------------------

class ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const ScaleButton({super.key, required this.child, this.onTap});
  @override
  State<ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<ScaleButton> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _s;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _s = Tween<double>(begin: 1.0, end: 0.95).animate(_c);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _c.forward(),
      onTapUp: (_) { _c.reverse(); widget.onTap?.call(); },
      onTapCancel: () => _c.reverse(),
      child: ScaleTransition(scale: _s, child: widget.child),
    );
  }
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final Color? color;
  final Border? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 15,
    this.opacity = 0.2,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = color ?? (isDark ? Colors.black : Colors.white);
    final br = borderRadius ?? BorderRadius.circular(24);
    
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: baseColor.withOpacity(opacity),
              borderRadius: br,
              border: border ?? Border.all(color: Colors.white.withOpacity(isDark ? 0.1 : 0.4), width: 1.0),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool active;

  const LiquidGlassContainer({super.key, required this.child, this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.black : Colors.white;
    final shadow = isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.1);

    return ScaleButton(
      onTap: onTap,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    active ? const Color(0xFF6C5CE7).withOpacity(0.4) : baseColor.withOpacity(0.3),
                    active ? const Color(0xFF6C5CE7).withOpacity(0.1) : baseColor.withOpacity(0.05),
                  ],
                ),
                border: Border.all(
                  color: active ? const Color(0xFF6C5CE7).withOpacity(0.5) : Colors.white.withOpacity(0.3), 
                  width: 1.5
                ),
                boxShadow: [
                  BoxShadow(color: shadow, blurRadius: 15, spreadRadius: -2, offset: const Offset(0, 8)),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class AnimatedMeshGradient extends StatefulWidget {
  final Widget child;
  const AnimatedMeshGradient({super.key, required this.child});
  @override
  State<AnimatedMeshGradient> createState() => _AnimatedMeshGradientState();
}

class _AnimatedMeshGradientState extends State<AnimatedMeshGradient> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Container(color: Theme.of(context).scaffoldBackgroundColor),
        
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              return Stack(
                children: [
                  Positioned(
                    top: -100 + (50 * sin(t * 2 * pi)),
                    right: -50 + (30 * cos(t * 2 * pi)),
                    child: _blob(const Color(0xFF6C5CE7), 300),
                  ),
                  Positioned(
                    bottom: 100 - (50 * sin(t * 2 * pi)),
                    left: -100 + (30 * cos(t * 2 * pi)),
                    child: _blob(const Color(0xFF00CEC9), 400),
                  ),
                  Positioned(
                    top: 300 + (40 * cos(t * pi)),
                    left: 50 + (20 * sin(t * pi)),
                    child: _blob(const Color(0xFFA29BFE).withOpacity(0.6), 250),
                  ),
                ],
              );
            },
          ),
        ),

        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Container(color: isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.2)),
          ),
        ),
        widget.child,
      ],
    );
  }

  Widget _blob(Color color, double size) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.5)),
  );
}

// ---------------------------------------------------------------------------
// 4. MAIN SCREENS
// ---------------------------------------------------------------------------

class MainNavigationWrapper extends StatefulWidget {
  const MainNavigationWrapper({super.key});
  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  int _index = 0;
  final List<Widget> _screens = [const HomeScreen(), const CollectionScreen(), const ProfileSettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      drawer: _buildDrawer(), // Add Drawer here
      body: _screens[_index],
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: GlassContainer(
            blur: 25,
            opacity: Theme.of(context).brightness == Brightness.dark ? 0.6 : 0.8,
            borderRadius: BorderRadius.circular(50),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(Icons.grid_view_rounded, 0),
                _navItem(Icons.bookmarks_rounded, 1),
                _navItem(Icons.person_rounded, 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.transparent,
      child: AnimatedMeshGradient(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(Strings.get('profile'), style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 30),
              
              // API Key Guide
              GlassContainer(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Strings.get('api_guide_title'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 8),
                    Text(Strings.get('api_guide_desc'), style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7), foregroundColor: Colors.white),
                      onPressed: () async {
                        final Uri url = Uri.parse('https://bailian.console.aliyun.com/?tab=api#/api/?type=model&url=2712195');
                        if (!await launchUrl(url)) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not launch URL")));
                        }
                      },
                      child: const Text("Go to Console"),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Developer Intro
              GlassContainer(
                borderRadius: BorderRadius.circular(24),
                child: GestureDetector(
                  onTap: () async {
                    final Uri url = Uri.parse('https://space.bilibili.com/1834448890');
                    if (!await launchUrl(url)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not launch URL")));
                    }
                  },
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 30,
                        backgroundImage: NetworkImage('https://i1.hdslb.com/bfs/face/9824feed6a2fa59534662ab28a39b387e4c90275.jpg'),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(Strings.get('dev_name'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 4),
                          Text(Strings.get('dev_desc'), style: const TextStyle(fontSize: 12, color: Colors.blueAccent)),
                        ],
                      ),
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

  Widget _navItem(IconData icon, int index) {
    final isSelected = _index == index;
    return ScaleButton(
      onTap: () => setState(() => _index = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.15) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey, size: 26),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _pickImages(BuildContext context) async {
    if (AppState.instance.apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.get('no_key'))));
      return;
    }
    final picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();
    if (images.isNotEmpty) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => AnalysisScreen(initialImages: images.map((e) => e.path).toList())));
    }
  }

  Future<void> _camera(BuildContext context) async {
    if (AppState.instance.apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.get('no_key'))));
      return;
    }
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => AnalysisScreen(initialImages: [image.path])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppState.instance;
    return AnimatedMeshGradient(
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => Scaffold.of(context).openDrawer(),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
                                ),
                                child: CircleAvatar(
                                  radius: 24,
                                  backgroundImage: appState.avatarPath != null ? FileImage(File(appState.avatarPath!)) : null,
                                  child: appState.avatarPath == null ? const Icon(Icons.person) : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(Strings.get('welcome'), style: Theme.of(context).textTheme.bodyLarge),
                                Text(appState.nickname, style: Theme.of(context).textTheme.headlineMedium),
                              ],
                            ),
                          ],
                        ),
                        ScaleButton(
                          onTap: () => AppState.instance.toggleTheme(),
                          child: GlassContainer(
                            padding: const EdgeInsets.all(8),
                            borderRadius: BorderRadius.circular(12),
                            child: Icon(appState.themeMode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, size: 20),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    GlassContainer(
                      color: const Color(0xFF6C5CE7),
                      opacity: 0.85,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(Strings.get('daily_streak'), style: const TextStyle(color: Colors.white70)),
                                const SizedBox(height: 5),
                                Text("${appState.recognitionCount} ${Strings.get('items_count')}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 50),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: ScaleButton(onTap: () => _camera(context), child: _actionBtn(Icons.camera_alt_rounded, Strings.get('scan'), const Color(0xFF6C5CE7)))),
                        const SizedBox(width: 16),
                        Expanded(child: ScaleButton(onTap: () => _pickImages(context), child: _actionBtn(Icons.photo_library_rounded, Strings.get('upload'), const Color(0xFF00CEC9)))),
                      ],
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

  Widget _actionBtn(IconData icon, String label, Color color) {
    return GlassContainer(
      color: color,
      opacity: 0.15,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. ANALYSIS & RECOGNITION
// ---------------------------------------------------------------------------

class ImageItem {
  final String path;
  bool isAnalyzed = false;
  bool isAnalyzing = false;
  List<AnalyzedItem> items = [];
  ImageItem(this.path);
}

class AnalysisScreen extends StatefulWidget {
  final List<String> initialImages;
  const AnalysisScreen({super.key, required this.initialImages});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> with SingleTickerProviderStateMixin {
  late List<ImageItem> _images;
  late PageController _pageController;
  int _currentIndex = 0;
  bool _showBilingual = false;
  bool _isLandscapeImage = false; // "Wide" image detection
  final GlobalKey _repaintKey = GlobalKey(); 
  
  final FlutterTts _flutterTts = FlutterTts();
  late AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _images = widget.initialImages.map((e) => ImageItem(e)).toList();
    _pageController = PageController();
    _scanController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _initTts();
    _checkImageRatio();
    _analyzeCurrent();
  }

  void _checkImageRatio() async {
    // Check if image is wide (>1:1)
    if (_images.isNotEmpty) {
      final File image = File(_images.first.path);
      final decodedImage = await decodeImageFromList(image.readAsBytesSync());
      setState(() {
        _isLandscapeImage = decodedImage.width > decodedImage.height;
      });
      // NOTE: We do NOT rotate the device orientation. 
      // We will perform a widget rotation in build() if _isLandscapeImage is true.
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  void _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.4);
  }

  void _analyzeCurrent() async {
    final currentItem = _images[_currentIndex];
    if (currentItem.isAnalyzed || currentItem.isAnalyzing) return;

    setState(() => currentItem.isAnalyzing = true);
    try {
      final results = await TongyiService.analyzeImage(AppState.instance.apiKey, currentItem.path);
      if (mounted) {
        setState(() {
          currentItem.items = results;
          currentItem.isAnalyzed = true;
          currentItem.isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => currentItem.isAnalyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${Strings.get('error')}: $e")));
      }
    }
  }

  Future<void> _addImages() async {
    final picker = ImagePicker();
    final List<XFile> newImages = await picker.pickMultiImage();
    if (newImages.isNotEmpty) {
      setState(() {
        _images.addAll(newImages.map((e) => ImageItem(e.path)));
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${Strings.get('added_images')} ${newImages.length}")));
    }
  }

  Future<void> _reIdentify() async {
    final currentItem = _images[_currentIndex];
    setState(() {
      currentItem.isAnalyzed = false;
      currentItem.items = [];
    });
    _analyzeCurrent();
  }

  Future<void> _exportImage(bool chineseOnly) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.get('save') + "...")));
    try {
      RenderRepaintBoundary boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();
      
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/vision_learn_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);
      
      if (mounted) {
         _showExportDialog(file.path, chineseOnly ? Strings.get('chinese_only') : Strings.get('english_only'));
      }
    } catch (e) {
      print(e);
    }
  }

  void _showExportDialog(String path, String mode) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(Strings.get('export_title')),
        content: Text("${Strings.get('export_msg')}\n$path"),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLandscapeImage ? _buildWideLayout() : _buildPortraitLayout(),
    );
  }

  // --- PORTRAIT LAYOUT (Default) ---
  Widget _buildPortraitLayout() {
    final currentItem = _images[_currentIndex];
    return Stack(
      children: [
        _buildImageArea(currentItem),
        // Back Button
        Positioned(
          top: 50, left: 20,
          child: _backButton(),
        ),
        // Image Indicator
        if (_images.length > 1)
          Positioned(
            bottom: 110, left: 0, right: 0,
            child: _buildIndicator(),
          ),
        // Bottom Tools
        Positioned(
          bottom: 30, left: 20, right: 20,
          child: _buildToolsRow(),
        ),
      ],
    );
  }

  // --- WIDE LAYOUT (Force Rotated) ---
  // Rotates the image 90 deg clockwise to fill the portrait screen.
  // Places buttons on the left (which visually looks like the "bottom" if user tilts phone)
  Widget _buildWideLayout() {
    final currentItem = _images[_currentIndex];
    return Row(
      children: [
        // Tools Panel on the Left
        Container(
          width: 80,
          color: Colors.black.withOpacity(0.8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
               _backButton(),
               _capsuleBtn(Icons.add_photo_alternate_rounded, Strings.get('add'), _addImages, vertical: true),
               _capsuleBtn(Icons.translate_rounded, Strings.get('dual'), () {
                 setState(() => _showBilingual = !_showBilingual);
               }, active: _showBilingual, vertical: true),
               _capsuleBtn(Icons.refresh_rounded, Strings.get('rescan'), _reIdentify, vertical: true),
               _capsuleBtn(Icons.save_alt_rounded, Strings.get('save'), () => _showExportOptions(), vertical: true),
            ],
          ),
        ),
        // Rotated Image Area
        Expanded(
          child: RotatedBox(
            quarterTurns: 1, // Rotate 90 degrees clockwise
            child: Stack(
              children: [
                _buildImageArea(currentItem),
                if (_images.length > 1)
                   Positioned(
                     bottom: 20, left: 0, right: 0,
                     child: _buildIndicator(),
                   ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageArea(ImageItem currentItem) {
    return RepaintBoundary(
      key: _repaintKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _images.length,
            onPageChanged: (idx) {
              setState(() => _currentIndex = idx);
              _analyzeCurrent();
            },
            itemBuilder: (context, index) {
              return Image.file(File(_images[index].path), fit: BoxFit.contain);
            },
          ),
          // Loading Scanner
          if (currentItem.isAnalyzing)
            _buildScannerOverlay(),
            
          // Tags
          if (!currentItem.isAnalyzing && currentItem.isAnalyzed)
            ...currentItem.items.map((item) => Positioned(
              left: MediaQuery.of(context).size.width * item.x,
              top: MediaQuery.of(context).size.height * item.y,
              child: _buildTag(item),
            )),
        ],
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return AnimatedBuilder(
      animation: _scanController,
      builder: (context, child) {
        return Stack(
          children: [
            Positioned(
              top: MediaQuery.of(context).size.height * _scanController.value,
              left: 0, right: 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.8), blurRadius: 10, spreadRadius: 2)],
                  color: const Color(0xFF6C5CE7),
                ),
              ),
            ),
            Center(child: Text(Strings.get('scanning'), style: TextStyle(color: Colors.white.withOpacity(0.8 + (sin(_scanController.value * pi) * 0.2)), fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        );
      },
    );
  }

  Widget _backButton() {
    return ScaleButton(
      onTap: () => Navigator.pop(context),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(50),
        padding: const EdgeInsets.all(8),
        child: const Icon(Icons.arrow_back, color: Colors.white),
      ),
    );
  }

  Widget _buildIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_images.length, (index) => 
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentIndex == index ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: _currentIndex == index ? const Color(0xFF6C5CE7) : Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(4),
          ),
        )
      ),
    );
  }

  Widget _buildToolsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        color: Colors.black.withOpacity(0.3),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _capsuleBtn(Icons.add_photo_alternate_rounded, Strings.get('add'), _addImages),
          _capsuleBtn(Icons.translate_rounded, Strings.get('dual'), () {
            setState(() => _showBilingual = !_showBilingual);
          }, active: _showBilingual),
          _capsuleBtn(Icons.refresh_rounded, Strings.get('rescan'), _reIdentify),
          _capsuleBtn(Icons.save_alt_rounded, Strings.get('save'), _showExportOptions),
        ],
      ),
    );
  }

  void _showExportOptions() {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (_) => 
      GlassContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.abc), title: Text(Strings.get('english_only')), onTap: () { Navigator.pop(context); _exportImage(false); }),
            ListTile(leading: const Icon(Icons.language), title: Text(Strings.get('chinese_only')), onTap: () { Navigator.pop(context); _exportImage(true); }),
          ],
        ),
      )
    );
  }

  Widget _capsuleBtn(IconData icon, String label, VoidCallback onTap, {bool active = false, bool vertical = false}) {
    return SizedBox(
      width: 70, 
      height: 70,
      child: LiquidGlassContainer(
        active: active,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? const Color(0xFF6C5CE7) : Colors.white.withOpacity(0.9), size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, color: active ? const Color(0xFF6C5CE7) : Colors.white.withOpacity(0.8), fontWeight: FontWeight.bold))
          ],
        ),
      ),
    );
  }

  Widget _buildTag(AnalyzedItem item) {
    return GestureDetector(
      onTap: () => _showDetailedCard(item),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2), 
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.circle, size: 8, color: Color(0xFF6C5CE7)),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                    if (_showBilingual) ...[
                      Text(item.pronunciation, style: const TextStyle(fontSize: 10, color: Colors.white70)),
                      Text(item.chinese, style: const TextStyle(fontSize: 12, color: Colors.cyanAccent)),
                    ]
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetailedCard(AnalyzedItem item) {
    _flutterTts.speak(item.label);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context), 
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, 
            child: DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.85,
              builder: (_, controller) => Container(
                margin: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.1 : 0.8),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: ListView(
                        controller: controller,
                        padding: const EdgeInsets.all(24),
                        children: [
                          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.label, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                                    Text(item.pronunciation, style: const TextStyle(fontSize: 18, color: Colors.grey, fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _flutterTts.speak(item.label),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: const Color(0xFF6C5CE7).withOpacity(0.1), shape: BoxShape.circle),
                                  child: const Icon(Icons.volume_up_rounded, color: Color(0xFF6C5CE7), size: 32),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 40),
                          Text(item.chinese, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 24),
                          // EXAMPLE SENTENCE (TAP TO PLAY)
                          GestureDetector(
                            onTap: () => _flutterTts.speak(item.example),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: const Color(0xFF6C5CE7).withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.example, style: const TextStyle(fontSize: 16)),
                                        const SizedBox(height: 8),
                                        Text(item.exampleCn, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.volume_up_rounded, size: 20, color: Color(0xFF6C5CE7)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          ScaleButton(
                            onTap: () async {
                              await VocabularyService.saveWord(item);
                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.get('word_collected'))));
                              }
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(color: const Color(0xFF6C5CE7), borderRadius: BorderRadius.circular(16)),
                              alignment: Alignment.center,
                              child: Text(Strings.get('collect_word'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. COLLECTION & SETTINGS (IMPROVED PROFILE)
// ---------------------------------------------------------------------------

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});
  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  List<AnalyzedItem> _vocab = [];
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final data = await VocabularyService.loadVocabulary();
    setState(() => _vocab = data);
  }

  void _showCard(AnalyzedItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Container(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () {},
            child: DraggableScrollableSheet(
              initialChildSize: 0.5,
              builder: (_, c) => Container(
                margin: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      decoration: BoxDecoration(
                         color: Colors.white.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.85),
                         border: Border.all(color: Colors.white.withOpacity(0.3)),
                         borderRadius: BorderRadius.circular(30)
                      ),
                      child: ListView(
                        controller: c,
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text(item.label, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                          Text(item.pronunciation, style: const TextStyle(color: Colors.grey)),
                          const SizedBox(height: 20),
                          Text(item.chinese, style: const TextStyle(fontSize: 24)),
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: () => _tts.speak(item.example),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(item.example, style: const TextStyle(fontSize: 16)),
                                      Text(item.exampleCn, style: const TextStyle(color: Colors.grey)),
                                    ]),
                                  ),
                                  const Icon(Icons.volume_up_rounded, color: Color(0xFF6C5CE7)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Center(child: IconButton(onPressed: () => _tts.speak(item.label), icon: const Icon(Icons.volume_up, size: 40, color: Color(0xFF6C5CE7))))
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedMeshGradient(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Strings.get('collection'), style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: _vocab.length,
                  itemBuilder: (context, index) {
                    final item = _vocab[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ScaleButton(
                        onTap: () => _showCard(item),
                        child: GlassContainer(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Text(item.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const Spacer(),
                              Text(item.chinese, style: const TextStyle(color: Colors.grey)),
                              const SizedBox(width: 10),
                              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey)
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});
  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _nickCtrl = TextEditingController();
  final _apiCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nickCtrl.text = AppState.instance.nickname;
    _apiCtrl.text = AppState.instance.apiKey;
  }

  void _save() async {
    await AppState.instance.updateProfile(_nickCtrl.text, AppState.instance.avatarPath);
    await AppState.instance.setApiKey(_apiCtrl.text);
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.get('saved'))));
  }
  
  void _pickAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if(image != null) {
      await AppState.instance.updateProfile(_nickCtrl.text, image.path);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedMeshGradient(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(Strings.get('profile'), style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 30),
              
              // Enhanced Avatar Upload
              GestureDetector(
                onTap: _pickAvatar,
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(40),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                         Stack(
                           alignment: Alignment.bottomRight,
                           children: [
                             CircleAvatar(
                                radius: 60,
                                backgroundColor: Colors.grey.shade300,
                                backgroundImage: AppState.instance.avatarPath != null ? FileImage(File(AppState.instance.avatarPath!)) : null,
                                child: AppState.instance.avatarPath == null ? const Icon(Icons.person, size: 60, color: Colors.grey) : null,
                             ),
                             Container(
                               padding: const EdgeInsets.all(8),
                               decoration: const BoxDecoration(color: Color(0xFF6C5CE7), shape: BoxShape.circle),
                               child: const Icon(Icons.edit, color: Colors.white, size: 20),
                             )
                           ],
                         ),
                         const SizedBox(height: 16),
                         Text(Strings.get('tap_avatar'), style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              GlassContainer(
                borderRadius: BorderRadius.circular(30),
                child: Column(children: [
                  TextField(controller: _nickCtrl, decoration: InputDecoration(labelText: Strings.get('nickname'), border: InputBorder.none, prefixIcon: const Icon(Icons.person_outline))),
                  const Divider(),
                  TextField(controller: _apiCtrl, obscureText: true, decoration: InputDecoration(labelText: Strings.get('api_key'), border: InputBorder.none, prefixIcon: const Icon(Icons.key))),
                ]),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _save, 
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  backgroundColor: const Color(0xFF6C5CE7),
                  foregroundColor: Colors.white,
                ),
                child: Text(Strings.get('save_changes'))
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnalyzedItem {
  final String label, chinese, pronunciation, example, exampleCn;
  final double x, y;
  AnalyzedItem({required this.label, required this.chinese, required this.pronunciation, required this.example, required this.exampleCn, required this.x, required this.y});
  factory AnalyzedItem.fromJson(Map<String, dynamic> json) => AnalyzedItem(
    label: json['label'] ?? '',
    chinese: json['chinese'] ?? '',
    pronunciation: json['pronunciation'] ?? '',
    example: json['example'] ?? '',
    exampleCn: json['example_cn'] ?? '',
    x: (json['x'] as num?)?.toDouble() ?? 0.5,
    y: (json['y'] as num?)?.toDouble() ?? 0.5,
  );
  Map<String, dynamic> toJson() => {'label': label, 'chinese': chinese, 'pronunciation': pronunciation, 'example': example, 'example_cn': exampleCn, 'x': x, 'y': y};
}