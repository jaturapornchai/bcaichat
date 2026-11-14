import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'push_service.dart';

class ApiService {
  static final ApiService instance = ApiService._internal();
  ApiService._internal();

  static const String _envApiBase = String.fromEnvironment('API_BASE_URL');
  static String _overrideBaseUrl = '';

  static String get defaultBaseUrl =>
      defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8096'
      : 'http://127.0.0.1:8096';

  static String get baseUrl {
    if (_overrideBaseUrl.isNotEmpty) return _overrideBaseUrl;
    if (_envApiBase.isNotEmpty) return _normalizeBaseUrl(_envApiBase);
    return defaultBaseUrl;
  }

  static String get wsBaseUrl => deriveWsUrl(baseUrl);

  static String get customBaseUrl => _overrideBaseUrl;

  static String _normalizeBaseUrl(String raw) {
    var trimmed = raw.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static String deriveWsUrl(String httpUrl) {
    final normalized = _normalizeBaseUrl(httpUrl);
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'ws://127.0.0.1:8096/ws';
    }
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final basePath = uri.path == '/' ? '' : uri.path;
    return uri
        .replace(
          scheme: wsScheme,
          path: '$basePath/ws',
          query: null,
          fragment: null,
        )
        .toString();
  }

  static const String _prefTokenKey = 'bcaichat_jwt_token';
  static const String _prefUserKey = 'bcaichat_user_json';
  static const String _prefChatThemeKey = 'bcaichat_chat_theme';
  static const String _prefDeviceKey = 'bcaichat_device_id';
  static const String _prefApiBaseKey = 'bcaichat_api_base';

  String? _token;
  AppUser? _currentUser;
  ChatRoomThemeMode _chatTheme = ChatRoomThemeMode.banChiangCream;

  Future<void> initServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefApiBaseKey);
    _overrideBaseUrl = saved != null && saved.trim().isNotEmpty
        ? _normalizeBaseUrl(saved)
        : '';
  }

  Future<void> setCustomBaseUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = url == null ? '' : _normalizeBaseUrl(url);
    _overrideBaseUrl = cleaned;
    if (cleaned.isEmpty) {
      await prefs.remove(_prefApiBaseKey);
    } else {
      await prefs.setString(_prefApiBaseKey, cleaned);
    }
    if (_token != null && _token!.isNotEmpty) {
      connectWebSocket();
      unawaited(PushService.instance.start());
    }
  }

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSub;
  Timer? _wsRetryTimer;
  int _wsGen = 0; // bumped on disconnect so stale retries stop
  int _wsRetries = 0;
  String? _deviceId;
  final StreamController<Map<String, dynamic>> _wsController =
      StreamController<Map<String, dynamic>>.broadcast();

  String? get token => _token;
  AppUser? get currentUser => _currentUser;
  ChatRoomThemeMode get chatTheme => _chatTheme;
  Stream<Map<String, dynamic>> get wsEvents => _wsController.stream;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json; charset=utf-8',
    if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
  };

  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_prefTokenKey);
    _chatTheme = ChatRoomThemeMode.fromCode(prefs.getString(_prefChatThemeKey));
    final rawUser = prefs.getString(_prefUserKey);
    if (rawUser != null && rawUser.isNotEmpty) {
      try {
        _currentUser = AppUser.fromJson(
          jsonDecode(rawUser) as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    if (_token != null && _token!.isNotEmpty) {
      try {
        final fresh = await fetchMe();
        if (fresh != null) {
          _currentUser = fresh;
          connectWebSocket();
          return true;
        }
      } catch (_) {
        if (_currentUser != null) {
          connectWebSocket();
          return true;
        }
      }
    }
    return false;
  }

  Future<void> setChatTheme(ChatRoomThemeMode mode) async {
    _chatTheme = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefChatThemeKey, mode.code);
  }

  /// Test windows share one prefs file, so they must not overwrite the
  /// real saved session.
  bool persistSession = true;

  Future<void> _saveAuth(String token, AppUser user) async {
    _token = token;
    _currentUser = user;
    if (!persistSession) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefTokenKey, token);
    await prefs.setString(_prefUserKey, jsonEncode(user.toJson()));
  }

  /// Random id of this app install, kept across sign-ins (push target).
  Future<String> deviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefDeviceKey);
    if (id == null || id.length < 8) {
      final r = Random.secure();
      id = List.generate(
        16,
        (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await prefs.setString(_prefDeviceKey, id);
    }
    return _deviceId = id;
  }

  /// Push notification client configuration if configured on backend.
  Future<Map<String, dynamic>> fetchPushConfig() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/push/config'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const {};
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  Future<void> registerDevice(Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/devices'),
      headers: _headers,
      body: jsonEncode({...body, 'device_id': await deviceId()}),
    );
    if (res.statusCode != 200) {
      throw Exception('register device: ${res.statusCode}');
    }
  }

  Future<void> logout() async {
    disconnectWebSocket();
    if (_token != null) {
      // Stop push to this device for the account that signs out.
      try {
        await http
            .delete(
              Uri.parse('$baseUrl/api/devices/${await deviceId()}'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    _token = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefTokenKey);
    await prefs.remove(_prefUserKey);
    await PushService.instance.stop();
  }

  void connectWebSocket() {
    disconnectWebSocket();
    _openWebSocket(_wsGen);
  }

  Future<void> _openWebSocket(int gen) async {
    final jwt = _token;
    if (jwt == null || jwt.isEmpty) return;
    final device = await deviceId();
    if (gen != _wsGen) return; // disconnected while reading the id

    try {
      final uri = Uri.parse(
        '$wsBaseUrl?token=${Uri.encodeComponent(jwt)}&device=$device',
      );
      _wsChannel = WebSocketChannel.connect(uri);
      _wsSub = _wsChannel!.stream.listen(
        (raw) {
          _wsRetries = 0;
          if (raw is String && raw.isNotEmpty) {
            try {
              final decoded = jsonDecode(raw);
              if (decoded is Map<String, dynamic>) {
                if (decoded['event'] == 'theme_changed') {
                  AppTheme.applyPreset(decoded['preset']?.toString());
                }
                _wsController.add(decoded);
              } else if (decoded is Map) {
                _wsController.add(Map<String, dynamic>.from(decoded));
              }
            } catch (_) {}
          }
        },
        onError: (_) => _retryWebSocket(gen),
        onDone: () => _retryWebSocket(gen),
      );
    } catch (_) {
      _retryWebSocket(gen);
    }
  }

  /// The socket dropped (network change, server restart): reconnect after
  /// 2, 4, 8, 16 then every 30 seconds so live updates and alerts return.
  void _retryWebSocket(int gen) {
    if (gen != _wsGen || _token == null || _wsRetryTimer?.isActive == true) {
      return;
    }
    final wait = Duration(seconds: min(30, 2 << min(_wsRetries++, 4)));
    _wsRetryTimer = Timer(wait, () {
      if (gen != _wsGen) return;
      _closeWebSocket();
      _openWebSocket(gen);
    });
  }

  void disconnectWebSocket() {
    _wsGen++;
    _wsRetries = 0;
    _wsRetryTimer?.cancel();
    _closeWebSocket();
  }

  void _closeWebSocket() {
    _wsSub?.cancel();
    _wsSub = null;
    try {
      _wsChannel?.sink.close();
    } catch (_) {}
    _wsChannel = null;
  }

  String resolveMiniAppUrl(MiniAppItem app) {
    final jwt = Uri.encodeComponent(_token ?? '');
    if (app.url.startsWith('http://') || app.url.startsWith('https://')) {
      final separator = app.url.contains('?') ? '&' : '?';
      return '${app.url}${separator}token=$jwt';
    }
    final path = app.url.isNotEmpty ? app.url : '/miniapp/${app.code}';
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final separator = normalizedPath.contains('?') ? '&' : '?';
    return '$baseUrl$normalizedPath${separator}token=$jwt';
  }

  // ---------------------------------------------------------------------------
  // 1-3. Authentication & Profile
  // ---------------------------------------------------------------------------
  Future<AppUser> loginWithGoogle({
    required String email,
    required String displayName,
    String? avatarUrl,
    String? googleId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/google'),
      headers: _headers,
      body: jsonEncode({
        'email': email.trim(),
        'display_name': displayName.trim(),
        'avatar_url': avatarUrl ?? '',
        'google_id': googleId ?? 'google_${email.trim().hashCode.abs()}',
      }),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('เข้าสู่ระบบไม่สำเร็จ (${res.statusCode}): ${res.body}');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final token = (data['token'] ?? '').toString();
    final userMap = (data['user'] ?? data) as Map<String, dynamic>;
    final user = AppUser.fromJson(userMap);
    await _saveAuth(token, user);
    connectWebSocket();
    return user;
  }

  Future<AppUser?> fetchMe() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: _headers,
    );
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['user'] is Map<String, dynamic>
              ? decoded['user'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    final user = AppUser.fromJson(map);
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUserKey, jsonEncode(user.toJson()));
    return user;
  }

  Future<AppUser> updateProfile({
    required String displayName,
    required String bcId,
    required String statusMessage,
    String? avatarUrl,
  }) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/auth/profile'),
      headers: _headers,
      body: jsonEncode({
        'display_name': displayName.trim(),
        'bc_id': bcId.trim(),
        'status_message': statusMessage.trim(),
        'avatar_url': avatarUrl ?? _currentUser?.avatarUrl ?? '',
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('อัปเดตโปรไฟล์ไม่สำเร็จ: ${utf8.decode(res.bodyBytes)}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['user'] is Map<String, dynamic>
              ? decoded['user'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    final user = AppUser.fromJson(map);
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUserKey, jsonEncode(user.toJson()));
    return user;
  }

  // ---------------------------------------------------------------------------
  // 4-6. Friends & Search
  // ---------------------------------------------------------------------------
  Future<List<AppUser>> fetchFriends() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/friends'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['friends'] is List
              ? decoded['friends'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => AppUser.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AppUser>> searchUsers(String query) async {
    final q = Uri.encodeQueryComponent(query.trim());
    final res = await http.get(
      Uri.parse('$baseUrl/api/users/search?q=$q'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['users'] is List
              ? decoded['users'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => AppUser.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> addFriend({
    String? targetId,
    String? bcId,
    String? email,
    String? qrToken,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/friends/add'),
      headers: _headers,
      body: jsonEncode({
        if (targetId != null && targetId.isNotEmpty) 'target_id': targetId,
        if (bcId != null && bcId.isNotEmpty) 'bc_id': bcId,
        if (email != null && email.isNotEmpty) 'email': email,
        if (qrToken != null && qrToken.isNotEmpty) 'qr_token': qrToken,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ไม่พบผู้ใช้หรือไม่สามารถเพิ่มเพื่อนได้');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<AppUser?> updateFriendMeta(
    String friendId, {
    bool? isFavorite,
    bool? isBlocked,
    bool? isHidden,
  }) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/friends/$friendId'),
      headers: _headers,
      body: jsonEncode({
        'is_favorite': ?isFavorite,
        'is_blocked': ?isBlocked,
        'is_hidden': ?isHidden,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      final target = decoded['friend'] is Map<String, dynamic>
          ? decoded['friend'] as Map<String, dynamic>
          : decoded;
      return AppUser.fromJson(target);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 7-11. Conversations
  // ---------------------------------------------------------------------------
  Future<List<Conversation>> fetchConversations({String folder = 'all'}) async {
    final res = await http.get(
      Uri.parse(
        '$baseUrl/api/conversations?folder=${Uri.encodeQueryComponent(folder)}',
      ),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['conversations'] is List
              ? decoded['conversations'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Conversation> openDirectConversation(String friendId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/conversations/direct'),
      headers: _headers,
      body: jsonEncode({'friend_id': friendId}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ไม่สามารถเปิดห้องแชทได้');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['conversation'] is Map<String, dynamic>
              ? decoded['conversation'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return Conversation.fromJson(map);
  }

  Future<Conversation> createGroupConversation({
    required String name,
    required String folder,
    required List<String> memberIds,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/conversations/group'),
      headers: _headers,
      body: jsonEncode({
        'name': name.trim(),
        'folder': folder,
        'member_ids': memberIds,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ไม่สามารถสร้างกลุ่มได้');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['conversation'] is Map<String, dynamic>
              ? decoded['conversation'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return Conversation.fromJson(map);
  }

  Future<Conversation?> updateConversationMeta(
    String conversationId, {
    String? folder,
    bool? isPinned,
    bool? isMuted,
    bool? isArchived,
    String? name,
    String? avatarUrl,
  }) async {
    final payload = <String, dynamic>{
      'folder': ?folder,
      'is_pinned': ?isPinned,
      'is_muted': ?isMuted,
      'is_archived': ?isArchived,
      'name': ?name,
      'avatar_url': ?avatarUrl,
    };
    final res = await http.put(
      Uri.parse('$baseUrl/api/conversations/$conversationId/meta'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      final target = decoded['conversation'] is Map<String, dynamic>
          ? decoded['conversation'] as Map<String, dynamic>
          : decoded;
      return Conversation.fromJson(target);
    }
    return null;
  }

  Future<Conversation> addConversationMembers(
    String conversationId,
    List<String> memberIds,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/conversations/$conversationId/members'),
      headers: _headers,
      body: jsonEncode({'member_ids': memberIds}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('เชิญสมาชิกเข้ากลุ่มไม่สำเร็จ (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final target = decoded is Map<String, dynamic>
        ? (decoded['conversation'] is Map<String, dynamic>
              ? decoded['conversation'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return Conversation.fromJson(target);
  }

  Future<void> removeConversationMember(
    String conversationId,
    String memberId,
  ) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/conversations/$conversationId/members/$memberId'),
      headers: _headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('นำสมาชิกออกจากกลุ่มไม่สำเร็จ (${res.statusCode})');
    }
  }

  Future<Conversation> joinConversationByToken(String inviteToken) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/conversations/join'),
      headers: _headers,
      body: jsonEncode({'invite_token': inviteToken.trim()}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('รหัสเชิญไม่ถูกต้องหรือไม่พบกลุ่ม (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final target = decoded is Map<String, dynamic>
        ? (decoded['conversation'] is Map<String, dynamic>
              ? decoded['conversation'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return Conversation.fromJson(target);
  }

  Future<void> pinConversationMessage(
    String conversationId,
    String? messageId,
  ) async {
    await http.put(
      Uri.parse('$baseUrl/api/conversations/$conversationId/pin-message'),
      headers: _headers,
      body: jsonEncode({'message_id': messageId ?? ''}),
    );
  }

  // ---------------------------------------------------------------------------
  // 12-17. Messages, Read Receipts, Unsend, Vault & Global Search
  // ---------------------------------------------------------------------------
  Future<List<ChatMessage>> fetchMessages(String conversationId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/conversations/$conversationId/messages'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['messages'] is List
              ? decoded['messages'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<ChatMessage> sendMessage(
    String conversationId, {
    required String type,
    required String content,
    String? stickerCode,
    AttachmentInfo? attachment,
    Map<String, dynamic>? cardPayload,
    String? replyToId,
    bool isConfidential = false,
    String priority = 'normal',
    String? taskStatus,
    List<String>? mentions,
    int? audioDurationSec,
  }) async {
    final effectiveCard = cardPayload != null
        ? {
            ...cardPayload,
            if (isConfidential) 'is_confidential': true,
            if (priority != 'normal') 'priority': priority,
          }
        : (isConfidential || priority != 'normal'
              ? <String, dynamic>{
                  if (isConfidential) 'is_confidential': true,
                  if (priority != 'normal') 'priority': priority,
                }
              : null);

    final effectiveContent =
        isConfidential &&
            !content.startsWith('[ลับส่วนตัว]') &&
            !content.startsWith('[ลับเฉพาะองค์กร]')
        ? '[ลับส่วนตัว] $content'
        : content;

    final attachmentJson = attachment?.toJson();
    final res = await http.post(
      Uri.parse('$baseUrl/api/conversations/$conversationId/messages'),
      headers: _headers,
      body: jsonEncode({
        'type': type,
        'content': effectiveContent,
        'is_confidential': isConfidential,
        'priority': priority,
        'task_status': ?taskStatus,
        'sticker_code': ?stickerCode,
        'attachment': ?attachmentJson,
        'card_payload': ?effectiveCard,
        if (mentions != null && mentions.isNotEmpty) 'mentions': mentions,
        'audio_duration_sec': ?audioDurationSec,
        if (replyToId != null && replyToId.isNotEmpty) 'reply_to_id': replyToId,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ส่งข้อความไม่สำเร็จ (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['message'] is Map<String, dynamic>
              ? decoded['message'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return ChatMessage.fromJson(map);
  }

  Future<ChatMessage> updateTaskAction(String messageId, String action) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/messages/$messageId/task-action'),
      headers: _headers,
      body: jsonEncode({'action': action}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('อัปเดตสถานะงานไม่สำเร็จ (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['message'] is Map<String, dynamic>
              ? decoded['message'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return ChatMessage.fromJson(map);
  }

  Future<ChatMessage> approveRichCard(String messageId, String status) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/messages/$messageId/approve-card'),
      headers: _headers,
      body: jsonEncode({'status': status}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('อนุมัติการ์ดโต้ตอบไม่สำเร็จ (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['message'] is Map<String, dynamic>
              ? decoded['message'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return ChatMessage.fromJson(map);
  }

  Future<ChatMessage?> reactMessage(String messageId, String emoji) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/messages/$messageId/react'),
      headers: _headers,
      body: jsonEncode({'emoji': emoji}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['message'] is Map<String, dynamic>
              ? decoded['message'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return ChatMessage.fromJson(map);
  }

  Future<void> deleteMessageForMe(String messageId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/messages/$messageId/delete-for-me'),
      headers: _headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ลบข้อความเฉพาะฉันไม่สำเร็จ (${res.statusCode})');
    }
  }

  Future<ChatMessage> createPoll(
    String conversationId, {
    required String question,
    required List<String> options,
    bool allowMultiple = false,
    bool isAnonymous = false,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/conversations/$conversationId/polls'),
      headers: _headers,
      body: jsonEncode({
        'question': question.trim(),
        'options': options.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'allow_multiple': allowMultiple,
        'is_anonymous': isAnonymous,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('สร้างแบบโหวตไม่สำเร็จ (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['message'] is Map<String, dynamic>
              ? decoded['message'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return ChatMessage.fromJson(map);
  }

  Future<ChatMessage> votePoll(String messageId, List<String> optionIds) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/messages/$messageId/vote'),
      headers: _headers,
      body: jsonEncode({'option_ids': optionIds}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('โหวตไม่สำเร็จ (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['message'] is Map<String, dynamic>
              ? decoded['message'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return ChatMessage.fromJson(map);
  }

  Future<ChatMessage> closePoll(String messageId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/messages/$messageId/close-poll'),
      headers: _headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ปิดโพลไม่สำเร็จ (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['message'] is Map<String, dynamic>
              ? decoded['message'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return ChatMessage.fromJson(map);
  }

  Future<ChatMessage> createEvent(
    String conversationId, {
    required String title,
    String description = '',
    required String startsAt,
    String? endsAt,
    String location = '',
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/conversations/$conversationId/events'),
      headers: _headers,
      body: jsonEncode({
        'title': title.trim(),
        'description': description.trim(),
        'starts_at': startsAt.trim(),
        if (endsAt != null && endsAt.trim().isNotEmpty) 'ends_at': endsAt.trim(),
        'location': location.trim(),
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('สร้างนัดหมายไม่สำเร็จ (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['message'] is Map<String, dynamic>
              ? decoded['message'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return ChatMessage.fromJson(map);
  }

  Future<ChatMessage> rsvpEvent(String messageId, String status) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/messages/$messageId/rsvp'),
      headers: _headers,
      body: jsonEncode({'status': status}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ตอบรับนัดหมายไม่สำเร็จ (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['message'] is Map<String, dynamic>
              ? decoded['message'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return ChatMessage.fromJson(map);
  }

  Future<List<ChatMessage>> fetchEvents(String conversationId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/conversations/$conversationId/events'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['events'] is List
              ? decoded['events'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AlbumItem>> fetchAlbums(String conversationId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/conversations/$conversationId/albums'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['albums'] is List
              ? decoded['albums'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => AlbumItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<AlbumItem> createAlbum(
    String conversationId, {
    required String title,
    String description = '',
    List<AttachmentInfo> photos = const [],
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/conversations/$conversationId/albums'),
      headers: _headers,
      body: jsonEncode({
        'title': title.trim(),
        'description': description.trim(),
        'photos': photos.map((p) => p.toJson()).toList(),
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('สร้างอัลบั้มไม่สำเร็จ (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['album'] is Map<String, dynamic>
              ? decoded['album'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return AlbumItem.fromJson(map);
  }

  Future<AlbumItem> addAlbumPhotos(
    String albumId,
    List<AttachmentInfo> photos,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/albums/$albumId/photos'),
      headers: _headers,
      body: jsonEncode({'photos': photos.map((p) => p.toJson()).toList()}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('เพิ่มรูปในอัลบั้มไม่สำเร็จ (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['album'] is Map<String, dynamic>
              ? decoded['album'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return AlbumItem.fromJson(map);
  }

  Future<void> deleteAlbum(String albumId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/albums/$albumId'),
      headers: _headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ลบอัลบั้มไม่สำเร็จ (${res.statusCode})');
    }
  }

  Future<void> markConversationRead(String conversationId) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/conversations/$conversationId/read'),
        headers: _headers,
      );
    } catch (_) {}
  }

  Future<void> unsendMessage(String messageId, {bool hard = false}) async {
    final suffix = hard ? '?hard=true' : '';
    await http.delete(
      Uri.parse('$baseUrl/api/messages/$messageId/unsend$suffix'),
      headers: _headers,
    );
  }

  Future<VaultData> fetchVault(String conversationId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/conversations/$conversationId/vault'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      return const VaultData(images: [], files: [], links: []);
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return VaultData.fromJson(decoded);
    }
    return const VaultData(images: [], files: [], links: []);
  }

  Future<List<ChatMessage>> searchMessages(String query) async {
    final q = Uri.encodeQueryComponent(query.trim());
    final res = await http.get(
      Uri.parse('$baseUrl/api/messages/search?q=$q'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['messages'] is List
              ? decoded['messages'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // 18. สมุดบันทึก BC & โน้ตกลุ่ม
  // ---------------------------------------------------------------------------
  Future<List<NoteItem>> fetchNotes({String? conversationId}) async {
    final uri = conversationId != null && conversationId.isNotEmpty
        ? Uri.parse(
            '$baseUrl/api/notes?conversation_id=${Uri.encodeQueryComponent(conversationId)}',
          )
        : Uri.parse('$baseUrl/api/notes');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['notes'] is List
              ? decoded['notes'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => NoteItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<NoteItem> createNote({
    String? conversationId,
    required String title,
    required String content,
    String category = 'บันทึกสำคัญ',
    String color = '#812920',
    AttachmentInfo? attachment,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/notes'),
      headers: _headers,
      body: jsonEncode({
        if (conversationId != null && conversationId.isNotEmpty)
          'conversation_id': conversationId,
        'title': title.trim(),
        'content': content.trim(),
        'category': category,
        'color': color,
        if (attachment != null) 'attachment': attachment.toJson(),
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('สร้างโน้ตไม่สำเร็จ');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['note'] is Map<String, dynamic>
              ? decoded['note'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return NoteItem.fromJson(map);
  }

  Future<NoteItem> updateNote(
    String noteId, {
    String? title,
    String? content,
    bool? isPinned,
  }) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/notes/$noteId'),
      headers: _headers,
      body: jsonEncode({
        'title': ?title,
        'content': ?content,
        'is_pinned': ?isPinned,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('อัปเดตโน้ตไม่สำเร็จ');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['note'] is Map<String, dynamic>
              ? decoded['note'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return NoteItem.fromJson(map);
  }

  Future<NoteItem> toggleNoteLike(String noteId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/notes/$noteId/like'),
      headers: _headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ถูกใจโน้ตไม่สำเร็จ');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['note'] is Map<String, dynamic>
              ? decoded['note'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return NoteItem.fromJson(map);
  }

  Future<NoteItem> addNoteComment(String noteId, String content) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/notes/$noteId/comments'),
      headers: _headers,
      body: jsonEncode({'content': content.trim()}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('แสดงความคิดเห็นไม่สำเร็จ');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['note'] is Map<String, dynamic>
              ? decoded['note'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return NoteItem.fromJson(map);
  }

  Future<void> deleteNote(String noteId) async {
    await http.delete(
      Uri.parse('$baseUrl/api/notes/$noteId'),
      headers: _headers,
    );
  }

  // ---------------------------------------------------------------------------
  // 19. MinIO Permanent File Upload
  // ---------------------------------------------------------------------------
  Future<AttachmentInfo> uploadFileBase64({
    required String fileName,
    required String mimeType,
    required String dataBase64,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/upload'),
      headers: _headers,
      body: jsonEncode({
        'file_name': fileName,
        'mime_type': mimeType,
        'data_base64': dataBase64,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('อัปโหลดไฟล์เข้า MinIO ไม่สำเร็จ (${res.statusCode})');
    }
    final decoded =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return AttachmentInfo.fromJson(decoded);
  }

  // ---------------------------------------------------------------------------
  // 20-24. Mini-Apps & Admin Backoffice
  // ---------------------------------------------------------------------------
  Future<List<MiniAppItem>> fetchMiniApps() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/mini-apps'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['mini_apps'] is List
              ? decoded['mini_apps'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => MiniAppItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<AdminOverview?> fetchAdminOverview() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/admin/overview'),
      headers: _headers,
    );
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return AdminOverview.fromJson(decoded);
    }
    return null;
  }

  Future<List<AppUser>> fetchAdminUsers() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/admin/users'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['users'] is List
              ? decoded['users'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => AppUser.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> updateUserRole(String userId, String role) async {
    await http.put(
      Uri.parse('$baseUrl/api/admin/users/$userId/role'),
      headers: _headers,
      body: jsonEncode({'role': role}),
    );
  }

  Future<List<MiniAppItem>> fetchAdminMiniApps() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/admin/mini-apps'),
      headers: _headers,
    );
    if (res.statusCode != 200) return fetchMiniApps();
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['mini_apps'] is List
              ? decoded['mini_apps'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => MiniAppItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<MiniAppItem> createAdminMiniApp(Map<String, dynamic> payload) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/admin/mini-apps'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('เพิ่มระบบเสริมไม่สำเร็จ');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['mini_app'] is Map<String, dynamic>
              ? decoded['mini_app'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return MiniAppItem.fromJson(map);
  }

  Future<MiniAppItem> updateAdminMiniApp(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/admin/mini-apps/$id'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('แก้ไขระบบเสริมไม่สำเร็จ');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['mini_app'] is Map<String, dynamic>
              ? decoded['mini_app'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return MiniAppItem.fromJson(map);
  }

  Future<void> deleteAdminMiniApp(String id) async {
    await http.delete(
      Uri.parse('$baseUrl/api/admin/mini-apps/$id'),
      headers: _headers,
    );
  }

  Future<void> sendAdminBroadcast({
    required String title,
    required String content,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/admin/broadcast'),
      headers: _headers,
      body: jsonEncode({'title': title.trim(), 'content': content.trim()}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ส่งประกาศ Broadcast ไม่สำเร็จ');
    }
  }

  // ---------------------------------------------------------------------------
  // 25-28. DeepSeek AI Brain (Summarize, Assist, @ai Group Brain, Admin Settings)
  // ---------------------------------------------------------------------------
  Future<AiSummaryResult> summarizeConversation(String conversationId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/ai/summarize'),
      headers: _headers,
      body: jsonEncode({'conversation_id': conversationId}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'ไม่สามารถสรุปห้องแชทด้วย AI ได้ (${res.statusCode}): ${utf8.decode(res.bodyBytes)}',
      );
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return AiSummaryResult.fromJson(decoded);
    }
    return AiSummaryResult(
      summary: decoded.toString(),
      actionItems: const [],
      decisions: const [],
      model: 'deepseek-chat',
    );
  }

  Future<AiAssistResult> requestAiAssist({
    required String conversationId,
    required String mode,
    required String text,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/ai/assist'),
      headers: _headers,
      body: jsonEncode({
        'conversation_id': conversationId,
        'mode': mode,
        'text': text.trim(),
        'prompt': text.trim(),
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'เรียกสมองกล DeepSeek AI ไม่สำเร็จ (${res.statusCode}): ${utf8.decode(res.bodyBytes)}',
      );
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return AiAssistResult.fromJson(decoded);
    }
    return AiAssistResult(
      suggestion: decoded.toString(),
      alternatives: const [],
      mode: mode,
      model: 'deepseek-chat',
    );
  }

  /// Public endpoint, so the login screen is themed before sign-in.
  Future<void> loadBusinessTheme() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/settings/theme'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        AppTheme.applyPreset(decoded['preset']?.toString());
      }
    } catch (_) {
      // Offline: keep the current colours.
    }
  }

  Future<void> updateBusinessTheme(String code) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/settings/theme'),
      headers: _headers,
      body: jsonEncode({'preset': code}),
    );
    if (res.statusCode != 200) {
      throw Exception(
        res.statusCode == 403
            ? 'เฉพาะผู้ดูแลระบบเท่านั้นที่เปลี่ยนธีมได้'
            : 'บันทึกธีมไม่สำเร็จ',
      );
    }
    AppTheme.applyPreset(code);
  }

  Future<AiAdminSettings> fetchAdminAiSettings() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/admin/ai-settings'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      return const AiAdminSettings(
        model: 'deepseek-chat',
        maskedKey: 'ตั้งค่าบนเซิร์ฟเวอร์เรียบร้อย',
        hasKey: true,
        systemPrompt:
            'คุณคือ BC AI ผู้ช่วยส่วนตัวประจำทุกห้องแชทของ BC Ai Chat ช่วยคิดคำตอบ เกลาข้อความ สรุปนัดหมาย และช่วยวางแผนกับครอบครัวและเพื่อนๆ อย่างเป็นกันเอง',
        enabled: true,
      );
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return AiAdminSettings.fromJson(decoded);
    }
    return const AiAdminSettings(
      model: 'deepseek-chat',
      maskedKey: 'ตั้งค่าบนเซิร์ฟเวอร์เรียบร้อย',
      hasKey: true,
      systemPrompt: '',
      enabled: true,
    );
  }

  Future<AiAdminSettings> updateAdminAiSettings({
    required String model,
    String? apiKey,
    required String systemPrompt,
    bool enabled = true,
  }) async {
    final cleanKey = apiKey?.trim();
    final res = await http.put(
      Uri.parse('$baseUrl/api/admin/ai-settings'),
      headers: _headers,
      body: jsonEncode({
        'model': model,
        if (cleanKey != null && cleanKey.isNotEmpty) 'api_key': cleanKey,
        'system_prompt': systemPrompt.trim(),
        'enabled': enabled,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('บันทึกตั้งค่า DeepSeek AI ไม่สำเร็จ');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return AiAdminSettings.fromJson(decoded);
    }
    return fetchAdminAiSettings();
  }
}
