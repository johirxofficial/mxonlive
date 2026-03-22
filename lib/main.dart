import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

void main() {
  runApp(const MxonliveApp());
}

// ==================== MODELS ====================
class AppConfig {
  final String appName;
  final String version;
  final String welcomeMessage;
  final String notification;
  final String m3uUrl;
  final String updateTitle;
  final String updateDescription;
  final String apkDownloadUrl;
  final String webUrl;
  final String disclaimer;
  final String creditPlatform;
  final String telegramUser;
  final String telegramGroup;
  final String website;
  final bool welcomeEnabled;
  final bool notificationEnabled;

  AppConfig({
    required this.appName,
    required this.version,
    required this.welcomeMessage,
    required this.notification,
    required this.m3uUrl,
    required this.updateTitle,
    required this.updateDescription,
    required this.apkDownloadUrl,
    required this.webUrl,
    required this.disclaimer,
    required this.creditPlatform,
    required this.telegramUser,
    required this.telegramGroup,
    required this.website,
    required this.welcomeEnabled,
    required this.notificationEnabled,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      appName: json['app']['name'] ?? 'mxonlive',
      version: json['app']['version'] ?? '1.0.0',
      welcomeMessage: json['app']['welcome_message'] ?? 'Welcome to mxonlive',
      notification: json['app']['notification'] ?? '',
      m3uUrl: json['app']['m3u_url'] ?? '',
      updateTitle: json['updates']['title'] ?? 'What\'s New',
      updateDescription: json['updates']['description'] ?? '',
      apkDownloadUrl: json['downloads']['apk'] ?? '',
      webUrl: json['downloads']['web'] ?? '',
      disclaimer: json['legal']['disclaimer'] ?? '',
      creditPlatform: json['credits']['platform'] ?? 'mxonlive IPTV Platform',
      telegramUser: json['contact']['telegram_user'] ?? '',
      telegramGroup: json['contact']['telegram_group'] ?? '',
      website: json['contact']['website'] ?? '',
      welcomeEnabled: json['features']['welcome_enabled'] ?? true,
      notificationEnabled: json['features']['notification_enabled'] ?? true,
    );
  }

  factory AppConfig.fallback() {
    return AppConfig(
      appName: 'mxonlive',
      version: '1.0.0',
      welcomeMessage: 'Welcome to mxonlive – Enjoy Live TV Anytime',
      notification: '📢 New channels added! Enjoy uninterrupted streaming.',
      m3uUrl: 'https://private-zone-by-xfireflix.pages.dev/playlist-isp-bdix.m3u',
      updateTitle: 'What\'s New',
      updateDescription: 'Improved player stability, faster channel loading, bug fixes.',
      apkDownloadUrl: 'https://mxonlive.github.io/download/mxonlive.apk',
      webUrl: 'https://mxonlive.github.io',
      disclaimer: 'mxonlive does not host any content. All streams belong to their respective owners.',
      creditPlatform: 'mxonlive IPTV Platform',
      telegramUser: 'https://t.me/sultanarabi161',
      telegramGroup: 'https://t.me/mxonlive',
      website: 'https://mxonlive.github.io',
      welcomeEnabled: true,
      notificationEnabled: true,
    );
  }
}

class Channel {
  final String name;
  final String url;
  final String? logo;
  final String groupTitle;

  Channel({
    required this.name,
    required this.url,
    this.logo,
    required this.groupTitle,
  });

  @override
  String toString() => name;
}

// ==================== SERVICES ====================
class ConfigService extends ChangeNotifier {
  AppConfig? _config;
  String? _error;

  AppConfig? get config => _config;
  String? get error => _error;

  Future<void> loadConfig(String configUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final response = await http.get(
        Uri.parse(configUrl),
        headers: {'Accept': 'application/json'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => http.Response('timeout', 408),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        _config = AppConfig.fromJson(json);
        _error = null;
        await prefs.setString('app_config_cache', response.body);
        notifyListeners();
        return;
      }

      // Fallback to cache
      final cachedConfig = prefs.getString('app_config_cache');
      if (cachedConfig != null) {
        _config = AppConfig.fromJson(jsonDecode(cachedConfig));
        _error = 'Using cached configuration';
        notifyListeners();
        return;
      }

      // Final fallback
      _config = AppConfig.fallback();
      _error = 'Server unreachable. Using default config.';
      notifyListeners();
    } catch (e) {
      _error = 'Error loading config: $e';
      _config = AppConfig.fallback();
      notifyListeners();
    }
  }
}

class PlaylistService extends ChangeNotifier {
  List<Channel> _channels = [];
  String? _error;

  List<Channel> get channels => _channels;
  String? get error => _error;

  Future<void> loadPlaylist(String m3uUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final response = await http.get(Uri.parse(m3uUrl)).timeout(
        const Duration(seconds: 15),
        onTimeout: () => http.Response('timeout', 408),
      );

      if (response.statusCode == 200) {
        _channels = _parseM3U(response.body);
        _error = null;
        await prefs.setString('playlist_cache', response.body);
        notifyListeners();
        return;
      }

      // Fallback to cache
      final cachedPlaylist = prefs.getString('playlist_cache');
      if (cachedPlaylist != null) {
        _channels = _parseM3U(cachedPlaylist);
        _error = 'Using cached playlist';
        notifyListeners();
        return;
      }

      _error = 'Failed to load playlist';
      notifyListeners();
    } catch (e) {
      _error = 'Error loading playlist: $e';
      final prefs = await SharedPreferences.getInstance();
      final cachedPlaylist = prefs.getString('playlist_cache');
      if (cachedPlaylist != null) {
        _channels = _parseM3U(cachedPlaylist);
      }
      notifyListeners();
    }
  }

  List<Channel> _parseM3U(String content) {
    final lines = content.split('\n');
    final channels = <Channel>[];
    String? currentName;
    String? currentLogo;
    String? currentGroup;

    for (var line in lines) {
      line = line.trim();

      if (line.startsWith('#EXTINF:')) {
        currentName = null;
        currentLogo = null;
        currentGroup = 'Uncategorized';

        // Extract channel name (after last comma)
        final colonIndex = line.indexOf(',');
        if (colonIndex != -1) {
          currentName = line.substring(colonIndex + 1).trim();
        }

        // Extract tvg-logo
        final logoRegex = RegExp(r'tvg-logo="([^"]*)"');
        final logoMatch = logoRegex.firstMatch(line);
        if (logoMatch != null) {
          currentLogo = logoMatch.group(1);
        }

        // Extract group-title
        final groupRegex = RegExp(r'group-title="([^"]*)"');
        final groupMatch = groupRegex.firstMatch(line);
        if (groupMatch != null) {
          currentGroup = groupMatch.group(1);
        }
      } else if (currentName != null && !line.startsWith('#') && line.isNotEmpty) {
        channels.add(Channel(
          name: currentName,
          url: line,
          logo: currentLogo,
          groupTitle: currentGroup ?? 'Uncategorized',
        ));
        currentName = null;
      }
    }

    return channels;
  }

  List<String> getGroupTitles() {
    final groups = <String>{};
    for (var channel in _channels) {
      groups.add(channel.groupTitle);
    }
    return groups.toList()..sort();
  }

  List<Channel> getChannelsByGroup(String group) {
    return _channels.where((ch) => ch.groupTitle == group).toList();
  }

  List<Channel> searchChannels(String query) {
    if (query.isEmpty) return _channels;
    final lowerQuery = query.toLowerCase();
    return _channels
        .where((ch) =>
            ch.name.toLowerCase().contains(lowerQuery) ||
            ch.groupTitle.toLowerCase().contains(lowerQuery))
        .toList();
  }
}

// ==================== UI - MAIN APP ====================
class MxonliveApp extends StatelessWidget {
  const MxonliveApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConfigService()),
        ChangeNotifierProvider(create: (_) => PlaylistService()),
      ],
      child: MaterialApp(
        title: 'mxonlive',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueAccent,
            brightness: Brightness.dark,
          ),
        ),
        home: const SplashScreen(),
        routes: {
          '/home': (context) => const HomePage(),
          '/player': (context) => const PlayerPage(),
          '/info': (context) => const InfoPage(),
        },
      ),
    );
  }
}

// ==================== SPLASH SCREEN ====================
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final configService = Provider.of<ConfigService>(context, listen: false);
    const configUrl = 'https://raw.githubusercontent.com/sultanarabi161/mxonlive/main/config.json';
    
    await configService.loadConfig(configUrl);

    if (mounted) {
      final config = configService.config;
      if (config != null) {
        final playlistService = Provider.of<PlaylistService>(context, listen: false);
        await playlistService.loadPlaylist(config.m3uUrl);
      }

      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.live_tv, size: 60, color: Colors.blueAccent),
            ),
            const SizedBox(height: 30),
            const Text(
              'mxonlive',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const SpinKitWave(color: Colors.blueAccent, size: 40),
            const SizedBox(height: 40),
            const Text(
              'Loading channels...',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== HOME PAGE ====================
class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  List<Channel> _filteredChannels = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final playlistService = Provider.of<PlaylistService>(context, listen: false);
    setState(() {
      _filteredChannels = playlistService.searchChannels(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'mxonlive',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 24),
            onPressed: () => Navigator.of(context).pushNamed('/info'),
          ),
          const SizedBox(width: 8),
        ],
        elevation: 0,
      ),
      body: Consumer2<ConfigService, PlaylistService>(
        builder: (context, configService, playlistService, _) {
          final config = configService.config ?? AppConfig.fallback();

          return CustomScrollView(
            slivers: [
              // Welcome Message
              if (config.welcomeEnabled)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blueAccent.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        config.welcomeMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),

              // Notification Capsule
              if (config.notificationEnabled && config.notification.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.orangeAccent.withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        config.notification,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),

              // Search Box
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search channels...',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _filteredChannels = playlistService.channels;
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.blueAccent,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey.withOpacity(0.1),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),

              // Error Handling
              if (playlistService.error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.redAccent.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_outlined, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              playlistService.error!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Channels Grid
              if (playlistService.channels.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.live_tv_outlined,
                          size: 60,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No channels found',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.75,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final channel = _filteredChannels.isNotEmpty
                            ? _filteredChannels[index]
                            : playlistService.channels[index];
                        return _ChannelCard(channel: channel);
                      },
                      childCount: _filteredChannels.isNotEmpty
                          ? _filteredChannels.length
                          : playlistService.channels.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ==================== CHANNEL CARD ====================
class _ChannelCard extends StatelessWidget {
  final Channel channel;

  const _ChannelCard({Key? key, required this.channel}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pushNamed(
          '/player',
          arguments: channel,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).pushNamed(
              '/player',
              arguments: channel,
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey.withOpacity(0.1),
              border: Border.all(
                color: Colors.grey.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      color: Colors.grey.withOpacity(0.15),
                    ),
                    child: channel.logo != null && channel.logo!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: channel.logo!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const Center(
                              child: SpinKitRipple(color: Colors.blueAccent, size: 30),
                            ),
                            errorWidget: (context, url, error) => Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.grey[600],
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.live_tv,
                              color: Colors.blueAccent.withOpacity(0.5),
                              size: 30,
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    channel.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== PLAYER PAGE ====================
class PlayerPage extends StatefulWidget {
  const PlayerPage({Key? key}) : super(key: key);

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late VideoPlayerController _videoController;
  bool _isPlaying = false;
  bool _showControls = true;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  void _initializePlayer() {
    final channel = ModalRoute.of(context)!.settings.arguments as Channel;
    _videoController = VideoPlayerController.network(
      channel.url,
      httpHeaders: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36',
      },
    )
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isPlaying = true;
            _videoController.play();
          });
          _startControlsTimer();
        }
      })
      ..addListener(_onVideoStateChanged);
  }

  void _onVideoStateChanged() {
    if (mounted) {
      setState(() {
        _isPlaying = _videoController.value.isPlaying;
      });
    }
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    if (mounted) {
      setState(() {
        _showControls = !_showControls;
      });
      if (_showControls) {
        _startControlsTimer();
      } else {
        _controlsTimer?.cancel();
      }
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = ModalRoute.of(context)!.settings.arguments as Channel;
    final playlistService = Provider.of<PlaylistService>(context);
    final relatedChannels = playlistService.getChannelsByGroup(channel.groupTitle);

    return Scaffold(
      appBar: AppBar(
        title: Text(channel.name),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Video Player
          Container(
            color: Colors.black,
            height: 250,
            child: GestureDetector(
              onTap: _toggleControls,
              child: Stack(
                children: [
                  _videoController.value.isInitialized
                      ? VideoPlayer(_videoController)
                      : const Center(
                          child: SpinKitWave(color: Colors.blueAccent, size: 40),
                        ),
                  if (_showControls)
                    Container(
                      color: Colors.black.withOpacity(0.3),
                      child: Center(
                        child: IconButton(
                          iconSize: 50,
                          icon: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            if (_isPlaying) {
                              _videoController.pause();
                            } else {
                              _videoController.play();
                            }
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Channel Info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Group: ${channel.groupTitle}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

          // Related Channels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'More from ${channel.groupTitle}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: relatedChannels.isEmpty
                ? Center(
                    child: Text(
                      'No more channels in this group',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: relatedChannels.length,
                    itemBuilder: (context, index) {
                      final ch = relatedChannels[index];
                      final isActive = ch.name == channel.name;
                      return GestureDetector(
                        onTap: () {
                          if (!isActive) {
                            _videoController.pause();
                            Navigator.of(context).pushReplacementNamed(
                              '/player',
                              arguments: ch,
                            );
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: isActive ? Colors.blueAccent.withOpacity(0.3) : Colors.grey.withOpacity(0.1),
                            border: Border.all(
                              color: isActive ? Colors.blueAccent : Colors.grey.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (ch.logo != null && ch.logo!.isNotEmpty)
                                CachedNetworkImage(
                                  imageUrl: ch.logo!,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  borderRadius: BorderRadius.circular(4),
                                  placeholder: (context, url) => Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: Colors.grey.withOpacity(0.2),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: Colors.grey.withOpacity(0.2),
                                    ),
                                    child: Icon(
                                      Icons.live_tv,
                                      color: Colors.grey[600],
                                      size: 24,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color: Colors.grey.withOpacity(0.2),
                                  ),
                                  child: Icon(
                                    Icons.live_tv,
                                    color: Colors.grey[600],
                                    size: 24,
                                  ),
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ch.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                                        color: isActive ? Colors.blueAccent : Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isActive)
                                const Icon(Icons.play_arrow, color: Colors.blueAccent, size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== INFO PAGE ====================
class InfoPage extends StatelessWidget {
  const InfoPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ConfigService>(
      builder: (context, configService, _) {
        final config = configService.config ?? AppConfig.fallback();

        return Scaffold(
          appBar: AppBar(
            title: const Text('About mxonlive'),
            elevation: 0,
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App Header
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.live_tv,
                          size: 50,
                          color: Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'mxonlive',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'v${config.version}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),

                const Divider(),

                // What's New
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.updateTitle,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        config.updateDescription,
                        style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),

                const Divider(),

                // Downloads
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Downloads',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _InfoButton(
                        icon: Icons.android,
                        label: 'Download APK',
                        onTap: () => _launchUrl(config.apkDownloadUrl),
                      ),
                      const SizedBox(height: 8),
                      _InfoButton(
                        icon: Icons.language,
                        label: 'Open Web Version',
                        onTap: () => _launchUrl(config.webUrl),
                      ),
                    ],
                  ),
                ),

                const Divider(),

                // Disclaimer
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Legal Notice',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        config.disclaimer,
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),

                const Divider(),

                // Credits
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Credits',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        config.creditPlatform,
                        style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),

                const Divider(),

                // Contact
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Connect With Us',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _InfoButton(
                        icon: Icons.person,
                        label: 'Telegram (Personal)',
                        onTap: () => _launchUrl(config.telegramUser),
                      ),
                      const SizedBox(height: 8),
                      _InfoButton(
                        icon: Icons.group,
                        label: 'Telegram (Group)',
                        onTap: () => _launchUrl(config.telegramGroup),
                      ),
                      const SizedBox(height: 8),
                      _InfoButton(
                        icon: Icons.language,
                        label: 'Visit Website',
                        onTap: () => _launchUrl(config.website),
                      ),
                    ],
                  ),
                ),

                const Divider(),

                // Footer
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'Web Developer: Sultan Muhammad A\'rabi',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Fallback: just show a message
    }
  }
}

// Import needed for URL launching
import 'package:url_launcher/url_launcher.dart';

class _InfoButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _InfoButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.blueAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
