import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'mini_app_runner_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  final Conversation conversation;
  final List<Conversation> allConversations;
  final List<MiniAppItem> miniApps;
  final List<AppUser> friends;
  final bool isEmbedded;
  final VoidCallback? onConversationUpdated;
  final VoidCallback? onConversationLeft;
  final ValueChanged<ChatRoomThemeMode>? onThemeChanged;

  const ChatRoomScreen({
    super.key,
    required this.conversation,
    required this.allConversations,
    required this.miniApps,
    this.friends = const [],
    this.isEmbedded = false,
    this.onConversationUpdated,
    this.onConversationLeft,
    this.onThemeChanged,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final TextEditingController _roomSearchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  late Conversation _conversation;
  List<ChatMessage> _messages = const [];
  bool _isLoading = true;
  bool _isUploading = false;
  String? _activeComposerTray; // null | sticker | attachment | miniapp | ai_assist
  String _aiAssistMode = 'polish';
  String? _activeRoomPanel; // null | vault | albums | events | poll | manage | ai_summary
  int _vaultInitialTab = 0;
  ChatMessage? _selectedActionMessage;
  bool _selectedActionCanRecall = false;
  String? _previewImageUrl;
  String? _previewImageTitle;
  bool _showSearchBar = false;
  bool _isConfidentialMode = false;
  String _selectedPriority = 'normal'; // normal | urgent | silent
  final Set<String> _revealedMessageIds = <String>{};
  // Message ids already shown once; only first-time rows play the fade-in.
  final Set<String> _animatedMessageIds = <String>{};
  String _searchQuery = '';
  ChatMessage? _replyingTo;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<void>? _audioDoneSub;
  String? _playingAudioMsgId;
  bool _showMentionSuggestions = false;
  String _mentionQuery = '';
  final Set<String> _pendingMentionIds = <String>{};

  static const List<Map<String, String>> _thaiStickers = [
    {'code': 'ok_friend', 'emoji': '🫡✨', 'label': 'รับทราบเลยเพื่อน!'},
    {'code': 'thank_you', 'emoji': '🙏🧡', 'label': 'ขอบคุณมากๆ นะ'},
    {'code': 'arrived', 'emoji': '🏡✅', 'label': 'ถึงบ้านแล้วจ้า'},
    {'code': 'love_it', 'emoji': '👍💯', 'label': 'เห็นด้วยเต็มร้อย!'},
    {'code': 'fighting', 'emoji': '✌️🔥', 'label': 'สู้ๆ นะ เป็นกำลังใจให้'},
    {'code': 'on_the_way', 'emoji': '🚗💨', 'label': 'กำลังรีบไปเลย!'},
    {'code': 'meetup', 'emoji': '☕🍽️', 'label': 'เจอกันตามนัดนะ'},
    {'code': 'celebrate', 'emoji': '🎉🥳', 'label': 'ฉลองกันหน่อย!'},
  ];

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    NotificationService.instance.openConversationId = _conversation.id;
    _msgCtrl.addListener(_onComposerTextChanged);
    _audioDoneSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingAudioMsgId = null);
    });
    _loadRoomData();
    _wsSub = ApiService.instance.wsEvents.listen(_handleWsEvent);
  }

  @override
  void didUpdateWidget(covariant ChatRoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.id != widget.conversation.id) {
      _conversation = widget.conversation;
      NotificationService.instance.openConversationId = _conversation.id;
      _replyingTo = null;
      _activeComposerTray = null;
      _activeRoomPanel = null;
      _selectedActionMessage = null;
      _previewImageUrl = null;
      _previewImageTitle = null;
      _showSearchBar = false;
      _showMentionSuggestions = false;
      _mentionQuery = '';
      _pendingMentionIds.clear();
      _searchQuery = '';
      _roomSearchCtrl.clear();
      _loadRoomData();
    } else {
      _conversation = widget.conversation;
    }
  }

  @override
  void dispose() {
    _msgCtrl.removeListener(_onComposerTextChanged);
    _wsSub?.cancel();
    _audioDoneSub?.cancel();
    _audioPlayer.dispose();
    if (NotificationService.instance.openConversationId == _conversation.id) {
      NotificationService.instance.openConversationId = null;
    }
    _msgCtrl.dispose();
    _roomSearchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onComposerTextChanged() {
    final text = _msgCtrl.text;
    final cursor = _msgCtrl.selection.baseOffset;
    final upToCursor =
        (cursor >= 0 && cursor <= text.length) ? text.substring(0, cursor) : text;
    final match = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(upToCursor);
    final nextShow = match != null;
    final nextQuery = match?.group(1) ?? '';
    if (nextShow != _showMentionSuggestions || nextQuery != _mentionQuery) {
      setState(() {
        _showMentionSuggestions = nextShow;
        _mentionQuery = nextQuery;
      });
    }
  }

  void _handleWsEvent(Map<String, dynamic> event) {
    final type = (event['type'] ?? event['event'] ?? '').toString();
    final convId =
        (event['conversation_id'] ??
                (event['message'] is Map
                    ? event['message']['conversation_id']
                    : null) ??
                '')
            .toString();

    if (convId == _conversation.id ||
        type == 'message_new' ||
        type == 'message_read' ||
        type == 'message_unsend' ||
        type == 'message_deleted' ||
        type == 'message_updated' ||
        type == 'message_reaction' ||
        type == 'poll_voted' ||
        type == 'poll_closed' ||
        type == 'event_rsvp' ||
        type == 'note_updated' ||
        type == 'album_created' ||
        type == 'task_updated' ||
        type == 'card_approved' ||
        type == 'conversation_updated') {
      _refreshMessagesQuietly();
    }
  }

  Future<void> _loadRoomData() async {
    setState(() => _isLoading = true);
    try {
      final msgs = await ApiService.instance.fetchMessages(_conversation.id);
      await ApiService.instance.markConversationRead(_conversation.id);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
      _scrollToBottom();
      widget.onConversationUpdated?.call();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshMessagesQuietly() async {
    try {
      final msgs = await ApiService.instance.fetchMessages(_conversation.id);
      await ApiService.instance.markConversationRead(_conversation.id);
      if (!mounted) return;
      // Follow new messages from others only if the reader is already at the end.
      final follow = msgs.length > _messages.length &&
          (!_scrollCtrl.hasClients || _scrollCtrl.position.extentAfter < 200);
      setState(() => _messages = msgs);
      if (follow) _scrollToBottom();
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // ListView.builder only measures the tail once it is laid out, so
      // maxScrollExtent grows while we scroll; chase it until it settles.
      for (var i = 0; i < 6 && mounted && _scrollCtrl.hasClients; i++) {
        final target = _scrollCtrl.position.maxScrollExtent;
        await _scrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        if (!_scrollCtrl.hasClients ||
            _scrollCtrl.position.maxScrollExtent <= target) {
          break;
        }
      }
    });
  }

  Future<void> _sendTextMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    final replyId = _replyingTo?.id;
    final confidential = _isConfidentialMode;
    final priority = _selectedPriority;
    final mentions = <String>{..._pendingMentionIds};
    final lower = text.toLowerCase();
    if (lower.contains('@all')) mentions.add('all');
    if (lower.contains('@ai')) mentions.add('user_ai');
    _msgCtrl.clear();
    setState(() {
      _replyingTo = null;
      _showMentionSuggestions = false;
      _mentionQuery = '';
      _pendingMentionIds.clear();
    });

    try {
      final sent = await ApiService.instance.sendMessage(
        _conversation.id,
        type: 'text',
        content: text,
        replyToId: replyId,
        isConfidential: confidential,
        priority: priority,
        taskStatus: 'open',
        mentions: mentions.toList(),
      );
      if (!mounted) return;
      setState(() {
        if (confidential) _revealedMessageIds.add(sent.id);
        _messages = [..._messages, sent];
      });
      _scrollToBottom();
      widget.onConversationUpdated?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ส่งข้อความไม่สำเร็จ: $e')));
    }
  }

  void _cyclePriority() {
    setState(() {
      if (_selectedPriority == 'normal') {
        _selectedPriority = 'urgent';
      } else if (_selectedPriority == 'urgent') {
        _selectedPriority = 'silent';
      } else {
        _selectedPriority = 'normal';
      }
    });
  }

  Future<void> _handleTaskAction(ChatMessage msg, String action) async {
    try {
      final updated = await ApiService.instance.updateTaskAction(
        msg.id,
        action,
      );
      if (!mounted) return;
      setState(() {
        _messages = _messages.map((m) => m.id == msg.id ? updated : m).toList();
      });
      widget.onConversationUpdated?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('อัปเดตสถานะงานไม่สำเร็จ: $e')));
    }
  }

  Future<void> _handleApproveRichCard(ChatMessage msg, String status) async {
    try {
      final updated = await ApiService.instance.approveRichCard(msg.id, status);
      if (!mounted) return;
      setState(() {
        _messages = _messages.map((m) => m.id == msg.id ? updated : m).toList();
      });
      widget.onConversationUpdated?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: status == 'อนุมัติแล้ว'
              ? AppTheme.brandDeep
              : AppTheme.dangerRed,
          content: Text('ประทับตรา "$status" ลงในการ์ดเรียบร้อยแล้ว'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('อนุมัติการ์ดไม่สำเร็จ: $e')));
    }
  }

  Future<void> _sendSticker(Map<String, String> sticker) async {
    setState(() => _activeComposerTray = null);
    try {
      final sent = await ApiService.instance.sendMessage(
        _conversation.id,
        type: 'sticker',
        content: sticker['label']!,
        stickerCode: sticker['code']!,
        replyToId: _replyingTo?.id,
        isConfidential: _isConfidentialMode,
      );
      if (!mounted) return;
      setState(() {
        _replyingTo = null;
        _messages = [..._messages, sent];
      });
      _scrollToBottom();
      widget.onConversationUpdated?.call();
    } catch (_) {}
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      final picked = files.first;
      final bytes = await picked.readAsBytes();

      await _uploadBytesAndSend(
        fileName: picked.name,
        bytes: bytes,
        extension: picked.extension ?? '',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ไม่สามารถเลือกไฟล์ได้: $e')));
    }
  }

  Future<void> _pickAndUploadAudio() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.audio);
      if (files.isEmpty) return;
      final picked = files.first;
      final bytes = await picked.readAsBytes();
      await _uploadBytesAndSend(
        fileName: picked.name,
        bytes: bytes,
        extension: picked.extension ?? 'mp3',
        forceAudio: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ไม่สามารถเลือกไฟล์เสียงได้: $e')));
    }
  }

  Future<void> _uploadBytesAndSend({
    required String fileName,
    required List<int> bytes,
    required String extension,
    bool forceAudio = false,
    int? audioDurationSec,
  }) async {
    setState(() => _isUploading = true);
    try {
      final ext = extension.toLowerCase();
      final isAudioExt = [
        'mp3',
        'wav',
        'm4a',
        'aac',
        'ogg',
        'flac',
        'webm',
      ].contains(ext);
      String mimeType = 'application/octet-stream';
      if (['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
        mimeType = ext == 'jpg' ? 'image/jpeg' : 'image/$ext';
      } else if (ext == 'pdf') {
        mimeType = 'application/pdf';
      } else if (ext == 'txt' || ext == 'csv') {
        mimeType = 'text/plain; charset=utf-8';
      } else if (ext == 'mp3') {
        mimeType = 'audio/mpeg';
      } else if (ext == 'wav') {
        mimeType = 'audio/wav';
      } else if (isAudioExt) {
        mimeType = 'audio/$ext';
      }

      final b64 = base64Encode(bytes);
      final attachment = await ApiService.instance.uploadFileBase64(
        fileName: fileName,
        mimeType: mimeType,
        dataBase64: b64,
      );

      final isAudio =
          forceAudio || isAudioExt || attachment.mimeType.startsWith('audio/');
      final msgType = isAudio
          ? 'audio'
          : attachment.isImage
          ? 'image'
          : 'file';
      final sent = await ApiService.instance.sendMessage(
        _conversation.id,
        type: msgType,
        content: fileName,
        attachment: attachment,
        replyToId: _replyingTo?.id,
        isConfidential: _isConfidentialMode,
        audioDurationSec: isAudio ? (audioDurationSec ?? 15) : null,
      );

      if (!mounted) return;
      setState(() {
        _replyingTo = null;
        if (_isConfidentialMode) _revealedMessageIds.add(sent.id);
        _messages = [..._messages, sent];
      });
      _scrollToBottom();
      widget.onConversationUpdated?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.brandDeep,
          content: Text(
            'อัปโหลด "$fileName" เก็บถาวรบน MinIO เรียบร้อย (ส่งผิดกดลบทำลายไฟล์ได้ทันที)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.dangerRed,
          content: Text('อัปโหลดไฟล์ไม่สำเร็จ: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showAttachmentMenu() {
    setState(() {
      _selectedActionMessage = null;
      _activeComposerTray =
          _activeComposerTray == 'attachment' ? null : 'attachment';
    });
  }

  Future<void> _toggleFolderCategory() async {
    final nextFolder = _conversation.isFamily ? 'personal' : 'family';
    final updated = await ApiService.instance.updateConversationMeta(
      _conversation.id,
      folder: nextFolder,
    );
    if (!mounted) return;
    setState(() {
      if (updated != null) {
        _conversation = updated;
      } else {
        _conversation = Conversation(
          id: _conversation.id,
          kind: _conversation.kind,
          name: _conversation.name,
          avatarUrl: _conversation.avatarUrl,
          folder: nextFolder,
          isPinned: _conversation.isPinned,
          isMuted: _conversation.isMuted,
          isArchived: _conversation.isArchived,
          inviteToken: _conversation.inviteToken,
          adminIds: _conversation.adminIds,
          memberIds: _conversation.memberIds,
          memberCount: _conversation.memberCount,
          unreadCount: _conversation.unreadCount,
          pinnedMessage: _conversation.pinnedMessage,
          lastMessage: _conversation.lastMessage,
          peerUser: _conversation.peerUser,
          updatedAt: _conversation.updatedAt,
        );
      }
    });
    widget.onConversationUpdated?.call();
  }

  Future<void> _togglePinRoom() async {
    final nextPin = !_conversation.isPinned;
    final updated = await ApiService.instance.updateConversationMeta(
      _conversation.id,
      isPinned: nextPin,
    );
    if (!mounted) return;
    setState(() {
      _conversation = updated ??
          Conversation(
            id: _conversation.id,
            kind: _conversation.kind,
            name: _conversation.name,
            avatarUrl: _conversation.avatarUrl,
            folder: _conversation.folder,
            isPinned: nextPin,
            isMuted: _conversation.isMuted,
            isArchived: _conversation.isArchived,
            inviteToken: _conversation.inviteToken,
            adminIds: _conversation.adminIds,
            memberIds: _conversation.memberIds,
            memberCount: _conversation.memberCount,
            unreadCount: _conversation.unreadCount,
            pinnedMessage: _conversation.pinnedMessage,
            lastMessage: _conversation.lastMessage,
            peerUser: _conversation.peerUser,
            updatedAt: _conversation.updatedAt,
          );
    });
    widget.onConversationUpdated?.call();
  }

  Future<void> _toggleMuteRoom(bool nextMuted) async {
    final updated = await ApiService.instance.updateConversationMeta(
      _conversation.id,
      isMuted: nextMuted,
    );
    if (!mounted) return;
    setState(() {
      _conversation = updated ??
          Conversation(
            id: _conversation.id,
            kind: _conversation.kind,
            name: _conversation.name,
            avatarUrl: _conversation.avatarUrl,
            folder: _conversation.folder,
            isPinned: _conversation.isPinned,
            isMuted: nextMuted,
            isArchived: _conversation.isArchived,
            inviteToken: _conversation.inviteToken,
            adminIds: _conversation.adminIds,
            memberIds: _conversation.memberIds,
            memberCount: _conversation.memberCount,
            unreadCount: _conversation.unreadCount,
            pinnedMessage: _conversation.pinnedMessage,
            lastMessage: _conversation.lastMessage,
            peerUser: _conversation.peerUser,
            updatedAt: _conversation.updatedAt,
          );
    });
    widget.onConversationUpdated?.call();
  }

  Future<void> _toggleArchiveRoom(bool nextArchived) async {
    final updated = await ApiService.instance.updateConversationMeta(
      _conversation.id,
      isArchived: nextArchived,
    );
    if (!mounted) return;
    setState(() {
      _conversation = updated ??
          Conversation(
            id: _conversation.id,
            kind: _conversation.kind,
            name: _conversation.name,
            avatarUrl: _conversation.avatarUrl,
            folder: _conversation.folder,
            isPinned: _conversation.isPinned,
            isMuted: _conversation.isMuted,
            isArchived: nextArchived,
            inviteToken: _conversation.inviteToken,
            adminIds: _conversation.adminIds,
            memberIds: _conversation.memberIds,
            memberCount: _conversation.memberCount,
            unreadCount: _conversation.unreadCount,
            pinnedMessage: _conversation.pinnedMessage,
            lastMessage: _conversation.lastMessage,
            peerUser: _conversation.peerUser,
            updatedAt: _conversation.updatedAt,
          );
    });
    widget.onConversationUpdated?.call();
  }

  Future<void> _pinMessageToBanner(ChatMessage? msg) async {
    await ApiService.instance.pinConversationMessage(_conversation.id, msg?.id);
    if (!mounted) return;
    setState(() {
      _conversation = Conversation(
        id: _conversation.id,
        kind: _conversation.kind,
        name: _conversation.name,
        avatarUrl: _conversation.avatarUrl,
        folder: _conversation.folder,
        isPinned: _conversation.isPinned,
        isMuted: _conversation.isMuted,
        isArchived: _conversation.isArchived,
        inviteToken: _conversation.inviteToken,
        adminIds: _conversation.adminIds,
        memberIds: _conversation.memberIds,
        memberCount: _conversation.memberCount,
        unreadCount: _conversation.unreadCount,
        pinnedMessage: msg,
        lastMessage: _conversation.lastMessage,
        peerUser: _conversation.peerUser,
        updatedAt: _conversation.updatedAt,
      );
    });
    widget.onConversationUpdated?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.slateDark,
        content: Text(
          msg != null
              ? 'ปักหมุดประกาศไว้บนหัวห้องแชทเรียบร้อยแล้ว'
              : 'ยกเลิกปักหมุดประกาศบนหัวห้องแชทแล้ว',
        ),
      ),
    );
  }

  Future<void> _saveMessageToNotebook(ChatMessage msg) async {
    try {
      await ApiService.instance.createNote(
        conversationId: _conversation.id,
        title: 'จากห้อง ${_conversation.name} (${msg.senderName})',
        content: msg.cleanContent.isNotEmpty
            ? msg.cleanContent
            : msg.previewText,
        category: _conversation.isFamily ? 'ครอบครัว' : 'บันทึกสำคัญ',
        color: '#812920',
        attachment: msg.attachment,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.brandDeep,
          content: const Text(
            'บันทึกข้อความเข้าสมุดบันทึก BC & โน้ตประจำห้องเรียบร้อยแล้ว',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text('บันทึกเข้าสมุดบันทึก BC ไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _handleReactMessage(ChatMessage msg, String emoji) async {
    try {
      final updated = await ApiService.instance.reactMessage(msg.id, emoji);
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _messages = _messages.map((m) => m.id == msg.id ? updated : m).toList();
        });
      } else {
        await _refreshMessagesQuietly();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ส่งอีโมจิตอบสนองไม่สำเร็จ: $e')));
    }
  }

  Future<void> _handleDeleteForMe(ChatMessage msg) async {
    try {
      await ApiService.instance.deleteMessageForMe(msg.id);
      if (!mounted) return;
      setState(() {
        _messages = _messages.where((m) => m.id != msg.id).toList();
      });
      widget.onConversationUpdated?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ลบข้อความออกจากหน้าจอของคุณแล้ว')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ลบข้อความเฉพาะฉันไม่สำเร็จ: $e')));
    }
  }

  /// Instant Recall / Unsend & Purge MinIO File ("ส่งผิดสามารถลบได้ทันที")
  Future<void> _unsendOrHardRecall(ChatMessage msg, {bool hard = false}) async {
    try {
      await ApiService.instance.unsendMessage(msg.id, hard: hard);
      if (!mounted) return;
      if (hard) {
        setState(() {
          _messages = _messages.where((m) => m.id != msg.id).toList();
        });
      }
      await _refreshMessagesQuietly();
      widget.onConversationUpdated?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.dangerRed,
          content: Text(
            'ลบข้อความและทำลายไฟล์ออกจากเซิร์ฟเวอร์เรียบร้อยแล้ว',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ลบข้อความไม่สำเร็จ: $e')));
    }
  }

  void _openMiniAppPicker() {
    if (widget.miniApps.isEmpty) return;
    setState(() {
      _selectedActionMessage = null;
      _activeComposerTray = _activeComposerTray == 'miniapp' ? null : 'miniapp';
    });
  }

  void _openPermanentVaultDialog({int initialTab = 0}) {
    setState(() {
      _selectedActionMessage = null;
      _activeComposerTray = null;
      _vaultInitialTab = initialTab;
      _activeRoomPanel =
          (_activeRoomPanel == 'vault' && initialTab == 0) ? null : 'vault';
    });
  }

  void _openAlbumsDialog() {
    setState(() {
      _selectedActionMessage = null;
      _activeComposerTray = null;
      _activeRoomPanel = _activeRoomPanel == 'albums' ? null : 'albums';
    });
  }

  void _openEventsDialog() {
    setState(() {
      _selectedActionMessage = null;
      _activeComposerTray = null;
      _activeRoomPanel = _activeRoomPanel == 'events' ? null : 'events';
    });
  }

  void _openCreatePollDialog() {
    setState(() {
      _selectedActionMessage = null;
      _activeComposerTray = null;
      _activeRoomPanel = _activeRoomPanel == 'poll' ? null : 'poll';
    });
  }

  void _openGroupManagementSheet() {
    setState(() {
      _selectedActionMessage = null;
      _activeComposerTray = null;
      _activeRoomPanel = _activeRoomPanel == 'manage' ? null : 'manage';
    });
  }

  void _openAiSummarizeModal() {
    setState(() {
      _selectedActionMessage = null;
      _activeComposerTray = null;
      _activeRoomPanel =
          _activeRoomPanel == 'ai_summary' ? null : 'ai_summary';
    });
  }

  void _openAiAssistModal({String initialMode = 'polish'}) {
    setState(() {
      _selectedActionMessage = null;
      final closeSame =
          _activeComposerTray == 'ai_assist' && _aiAssistMode == initialMode;
      _aiAssistMode = initialMode;
      _activeComposerTray = closeSame ? null : 'ai_assist';
    });
  }

  Future<void> _sendAiSummaryToRoom(String formattedText) async {
    final sent = await ApiService.instance.sendMessage(
      _conversation.id,
      type: 'text',
      content: formattedText,
    );
    if (!mounted) return;
    setState(() => _messages = [..._messages, sent]);
    _scrollToBottom();
    widget.onConversationUpdated?.call();
  }

  void _insertAiMention() {
    final current = _msgCtrl.text;
    if (!current.startsWith('@ai ')) {
      setState(() {
        _msgCtrl.text = '@ai ${current.trimLeft()}';
        _msgCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _msgCtrl.text.length),
        );
      });
    }
  }

  List<ChatMessage> get _filteredMessages {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _messages;
    return _messages.where((m) {
      return m.content.toLowerCase().contains(q) ||
          m.senderName.toLowerCase().contains(q) ||
          (m.attachment?.fileName.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ApiService.instance.chatTheme;
    final currentUser = ApiService.instance.currentUser;
    final currentUserId = currentUser?.id ?? '';
    final isAdmin = currentUser?.isAdmin ?? false;
    final visibleMessages = _filteredMessages;

    final isCompactLayout = MediaQuery.sizeOf(context).width < 600;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: themeMode.backgroundColor,
          body: Column(
            children: [
              _buildRoomHeader(themeMode),
              if (_showSearchBar) _buildInRoomSearchBar(),
              if (_conversation.pinnedMessage != null)
                _buildPinnedAnnouncementBanner(_conversation.pinnedMessage!),
              Expanded(
                child: Stack(
                  children: [
                    _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          )
                        : visibleMessages.isEmpty
                        ? Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              margin: const EdgeInsets.symmetric(horizontal: 24),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.30),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.14),
                                ),
                              ),
                              child: const Text(
                                'เริ่มส่งข้อความ ภาพความทรงจำ หรือไฟล์ถาวรกับเพื่อนและครอบครัวได้เลย (ส่งผิดลบได้ 100%)',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 16,
                            ),
                            itemCount: visibleMessages.length,
                            itemBuilder: (ctx, index) {
                              final msg = visibleMessages[index];
                              final isMe = msg.senderId == currentUserId;
                              return _buildMessageRow(
                                msg,
                                isMe,
                                isAdmin,
                                themeMode,
                              );
                            },
                          ),
                    if (_activeRoomPanel != null)
                      Positioned.fill(
                        child: _buildInlineRoomOverlayPanel(isCompactLayout),
                      ),
                  ],
                ),
              ),
              if (_selectedActionMessage != null) _buildSelectedMessageActionBar(),
              if (_activeComposerTray == 'sticker') _buildStickerPickerPanel(),
              if (_activeComposerTray == 'attachment') _buildInlineAttachmentTray(),
              if (_activeComposerTray == 'miniapp') _buildInlineMiniAppTray(),
              if (_activeComposerTray == 'ai_assist')
                _AiWritingAssistPanel(
                  key: ValueKey('assist-${_conversation.id}-$_aiAssistMode'),
                  conversation: _conversation,
                  initialDraft: _msgCtrl.text,
                  initialMode: _aiAssistMode,
                  onClose: () => setState(() => _activeComposerTray = null),
                  onApplyToComposer: (text) {
                    setState(() {
                      _activeComposerTray = null;
                      _msgCtrl.text = text;
                      _msgCtrl.selection = TextSelection.fromPosition(
                        TextPosition(offset: _msgCtrl.text.length),
                      );
                    });
                  },
                  onSendImmediately: (text) async {
                    setState(() => _activeComposerTray = null);
                    _msgCtrl.text = text;
                    await _sendTextMessage();
                  },
                ),
              if (_replyingTo != null) _buildReplyBanner(_replyingTo!),
              _buildComposerBar(),
            ],
          ),
        ),
        if (_previewImageUrl != null)
          Positioned.fill(child: _buildInlineImagePreviewOverlay()),
      ],
    );
  }

  Widget _buildInlineRoomOverlayPanel(bool isCompact) {
    Widget child;
    switch (_activeRoomPanel) {
      case 'vault':
        child = _RoomVaultPanel(
          key: ValueKey('vault-${_conversation.id}-$_vaultInitialTab'),
          conversation: _conversation,
          initialTab: _vaultInitialTab,
          onClose: () => setState(() => _activeRoomPanel = null),
        );
        break;
      case 'albums':
        child = _RoomAlbumsPanel(
          key: ValueKey('albums-${_conversation.id}'),
          conversation: _conversation,
          onClose: () => setState(() => _activeRoomPanel = null),
        );
        break;
      case 'events':
        child = _RoomEventsPanel(
          key: ValueKey('events-${_conversation.id}'),
          conversation: _conversation,
          onClose: () => setState(() => _activeRoomPanel = null),
          onEventCreated: (_) => _refreshMessagesQuietly(),
        );
        break;
      case 'poll':
        child = _InlineCreatePollPanel(
          conversationId: _conversation.id,
          onClose: () => setState(() => _activeRoomPanel = null),
          onCreated: (sent) {
            setState(() {
              _activeRoomPanel = null;
              _messages = [..._messages, sent];
            });
            _scrollToBottom();
            widget.onConversationUpdated?.call();
          },
        );
        break;
      case 'manage':
        child = _InlineGroupManagePanel(
          conversation: _conversation,
          friends: widget.friends,
          isEmbedded: widget.isEmbedded,
          onClose: () => setState(() => _activeRoomPanel = null),
          onToggleMute: _toggleMuteRoom,
          onToggleArchive: _toggleArchiveRoom,
          onConversationChanged: (updated) {
            setState(() => _conversation = updated);
            widget.onConversationUpdated?.call();
          },
          onConversationLeft: () {
            setState(() => _activeRoomPanel = null);
            widget.onConversationLeft?.call();
            if (!widget.isEmbedded) {
              Navigator.of(context).pop();
            }
          },
        );
        break;
      case 'ai_summary':
        child = _AiSummaryPanel(
          key: ValueKey('summary-${_conversation.id}'),
          conversation: _conversation,
          onClose: () => setState(() => _activeRoomPanel = null),
          onSendToRoom: _sendAiSummaryToRoom,
          onSaveToNotebook: (formattedText) async {
            // Save to both the room notebook and personal vault.
            for (final roomId in [_conversation.id, null]) {
              await ApiService.instance.createNote(
                conversationId: roomId,
                title: '✨ AI สรุปห้อง ${_conversation.name}',
                content: formattedText,
                category: 'AI สรุปแชท',
                color: '#7C3AED',
              );
            }
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.brandDeep,
                content: const Text(
                  'บันทึกผลสรุป AI เข้าสมุดบันทึก BC & โน้ตห้องเรียบร้อยแล้ว!',
                ),
              ),
            );
          },
        );
        break;
      default:
        child = const SizedBox.shrink();
    }

    return Container(
      color: Colors.black.withValues(alpha: 0.35),
      padding: EdgeInsets.all(isCompact ? 6 : 14),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 580),
        child: Material(
          color: Colors.white,
          elevation: 8,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }

  Widget _buildInlineImagePreviewOverlay() {
    final user = ApiService.instance.currentUser;
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      '${_previewImageTitle ?? ""} · เปิดดูโดย ${user?.displayName ?? "คุณ"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _previewImageUrl = null;
                      _previewImageTitle = null;
                    }),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                child: Image.network(_previewImageUrl!, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyChatTheme(ChatRoomThemeMode mode) async {
    await ApiService.instance.setChatTheme(mode);
    if (!mounted) return;
    setState(() {});
    widget.onThemeChanged?.call(mode);
  }

  void _toggleSearchBar() {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (!_showSearchBar) {
        _searchQuery = '';
        _roomSearchCtrl.clear();
      }
    });
  }

  List<PopupMenuEntry<Object>> _themeMenuEntries(ChatRoomThemeMode current) {
    return ChatRoomThemeMode.values.map((m) {
      return PopupMenuItem<Object>(
        value: m,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: m.backgroundColor,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.borderSubtle),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              m.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: m == current ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  /// Square 36px header icon button (tooltip carries the full Thai label).
  Widget _headerIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      icon: Icon(icon, size: 19, color: color),
    );
  }

  /// Gradient action: icon-only on narrow layouts, labeled pill on wide ones.
  Widget _headerActionButton({
    required bool compact,
    required Gradient gradient,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Container(
            height: 36,
            width: compact ? 36 : null,
            padding: compact
                ? null
                : const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: compact
                ? Icon(icon, size: 18, color: Colors.white)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(icon, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomHeader(ChatRoomThemeMode themeMode) {
    final isFamily = _conversation.isFamily;
    final peerDept =
        _conversation.peerUser?.department ??
        (_conversation.isGroup ? 'กลุ่มเพื่อน & ครอบครัว' : 'เพื่อน');
    const iconIdle = Color(0xFFCBD5E1);

    final header = LayoutBuilder(
      builder: (context, constraints) {
        // Use the real pane width (embedded split-view is narrower than the window).
        final isCompact = constraints.maxWidth < 600;
        final folderBadge = InkWell(
          onTap: _toggleFolderCategory,
          borderRadius: BorderRadius.circular(999),
          child: PillBadge(
            text: _conversation.folderLabel,
            backgroundColor: isFamily
                ? AppTheme.workBlue.withValues(alpha: 0.25)
                : AppTheme.brandPrimary.withValues(alpha: 0.22),
            textColor: isFamily
                ? const Color(0xFF93C5FD)
                : AppTheme.goldClay,
          ),
        );

        return Container(
          height: 64,
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 14),
          decoration: const BoxDecoration(
            gradient: AppTheme.navyGradient,
            border: Border(
              bottom: BorderSide(color: Color(0x1FFFFFFF), width: 0.8),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!widget.isEmbedded)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  color: Colors.white,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  tooltip: 'ย้อนกลับ',
                ),
              if (isCompact && widget.isEmbedded) const SizedBox(width: 6),
              UserAvatar(
                name: _conversation.name,
                avatarUrl: _conversation.avatarUrl,
                radius: isCompact ? 17 : 19,
                showOnline: !_conversation.isGroup,
                isOfficial: _conversation.isOfficial,
                isGroup: _conversation.isGroup,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            _conversation.isGroup
                                ? '${_conversation.name} (${_conversation.memberCount})'
                                : _conversation.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isCompact ? 15 : 16,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (!isCompact) ...[
                          const SizedBox(width: 8),
                          PillBadge(
                            text: peerDept,
                            backgroundColor: const Color(0xFF4B211B),
                            textColor: const Color(0xFFFDE68A),
                            icon: Icons.badge_outlined,
                          ),
                          const SizedBox(width: 6),
                          folderBadge,
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (isCompact) ...[
                          folderBadge,
                          const SizedBox(width: 6),
                        ] else ...[
                          const Icon(
                            Icons.lock_rounded,
                            size: 11,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            isCompact
                                ? 'ส่งผิดลบได้ 100%'
                                : 'แชทส่วนตัว · เก็บรูปและไฟล์ถาวรบน MinIO · ส่งผิดกดลบทันที',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (!isCompact)
                _headerIconButton(
                  icon: _conversation.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  tooltip: _conversation.isPinned
                      ? 'เลิกปักหมุดห้องแชท'
                      : 'ปักหมุดห้องแชท',
                  onPressed: _togglePinRoom,
                  color: _conversation.isPinned ? AppTheme.goldPin : iconIdle,
                ),
              _headerIconButton(
                icon: Icons.search_rounded,
                tooltip: 'ค้นหาข้อความในห้องนี้',
                onPressed: _toggleSearchBar,
                color: _showSearchBar ? AppTheme.brandPrimary : iconIdle,
              ),
              // Theme picker (wide) / overflow menu with the hidden actions (compact).
              PopupMenuButton<Object>(
                tooltip: isCompact
                    ? 'เมนูเพิ่มเติม'
                    : 'เปลี่ยนสีพื้นหลังห้องแชท',
                padding: EdgeInsets.zero,
                icon: Icon(
                  isCompact ? Icons.more_vert_rounded : Icons.palette_outlined,
                  size: 19,
                  color: iconIdle,
                ),
                onSelected: (v) {
                  if (v is ChatRoomThemeMode) {
                    _applyChatTheme(v);
                  } else if (v == 'albums') {
                    _openAlbumsDialog();
                  } else if (v == 'notes') {
                    _openPermanentVaultDialog(initialTab: 2);
                  } else if (v == 'poll') {
                    _openCreatePollDialog();
                  } else if (v == 'events') {
                    _openEventsDialog();
                  } else if (v == 'manage') {
                    _openGroupManagementSheet();
                  } else if (v == 'pin') {
                    _togglePinRoom();
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem<Object>(
                    value: 'albums',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('อัลบั้มรูปภาพ (Albums)', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<Object>(
                    value: 'notes',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.sticky_note_2_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('โน้ตกลุ่ม (ถูกใจ & คอมเมนต์)', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<Object>(
                    value: 'poll',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.poll_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('สร้างโพลโหวต (Poll)', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<Object>(
                    value: 'events',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.event_available_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('นัดหมาย & ตอบรับ (Events)', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<Object>(
                    value: 'manage',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.tune_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('จัดการกลุ่ม & ตั้งค่าห้อง', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  if (isCompact) ...[
                    PopupMenuItem<Object>(
                      value: 'pin',
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            _conversation.isPinned
                                ? Icons.push_pin_rounded
                                : Icons.push_pin_outlined,
                            size: 18,
                            color: AppTheme.goldPin,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _conversation.isPinned
                                ? 'เลิกปักหมุดห้องแชท'
                                : 'ปักหมุดห้องแชท',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                  ],
                  ..._themeMenuEntries(themeMode),
                ],
              ),
              const SizedBox(width: 4),
              _headerActionButton(
                compact: isCompact,
                gradient: AppTheme.aiGradient,
                icon: Icons.auto_awesome_rounded,
                label: 'AI สรุปแชท',
                onPressed: _openAiSummarizeModal,
              ),
              const SizedBox(width: 6),
              _headerActionButton(
                compact: isCompact,
                gradient: AppTheme.brandGradient,
                icon: Icons.folder_copy_rounded,
                label: 'คลังรูป & ไฟล์ถาวร',
                onPressed: _openPermanentVaultDialog,
              ),
            ],
          ),
        );
      },
    );

    return widget.isEmbedded
        ? header
        : ColoredBox(
            color: AppTheme.slateDark,
            child: SafeArea(bottom: false, child: header),
          );
  }

  Widget _buildInRoomSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.slateNavy,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _roomSearchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: const InputDecoration(
                hintText: 'ค้นหาข้อความ ชื่อไฟล์ หรือชื่อผู้ส่งในห้องนี้...',
                prefixIcon: Icon(Icons.search_rounded, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              setState(() {
                _showSearchBar = false;
                _searchQuery = '';
                _roomSearchCtrl.clear();
              });
            },
            child: const Text('ปิด', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedAnnouncementBanner(ChatMessage pinned) {
    return GlassPanel(
      blur: 16,
      tint: const Color(0xEBFFF7E0),
      border: Border(
        bottom: BorderSide(
          color: AppTheme.goldPin.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(
                color: AppTheme.goldPin.withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              color: AppTheme.warningAmber,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'ประกาศปักหมุดประจำห้อง',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.warningAmber,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'โดย ${pinned.senderName} (${pinned.senderDepartment})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slateMuted,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  pinned.previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slateDark,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _pinMessageToBanner(null),
            tooltip: 'เอาประกาศปักหมุดออก',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppTheme.slateMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageRow(
    ChatMessage msg,
    bool isMe,
    bool isAdmin,
    ChatRoomThemeMode themeMode,
  ) {
    if (msg.isUnsent) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 14,
                  color: Color(0xFFFCA5A5),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${isMe ? "คุณ" : msg.senderName} ยกเลิกข้อความและทำลายไฟล์แล้ว',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final timeStr = formatThaiTime(msg.createdAt);
    final readLabel = _conversation.isGroup && msg.readCount > 1
        ? 'อ่านแล้ว ${msg.readCount}'
        : 'อ่านแล้ว';
    final canRecall = isMe || isAdmin;

    // Pick readable meta colors for dark, mid-tone (sky) and light backgrounds.
    final bg = themeMode.backgroundColor;
    final onLight = !themeMode.isDark && bg.computeLuminance() > 0.6;
    final metaText = themeMode.isDark
        ? const Color(0xFF94A3B8)
        : onLight
        ? AppTheme.slateMuted
        : Colors.white.withValues(alpha: 0.92);
    final readColor = themeMode.isDark
        ? AppTheme.goldClay
        : onLight
        ? AppTheme.brandDeep
        : Colors.white;
    final nameColor = themeMode.isDark
        ? const Color(0xFFE2E8F0)
        : onLight
        ? AppTheme.slateDark
        : Colors.white;

    final metaColumn = Column(
      crossAxisAlignment: isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isMe) ...[
          // Quick 1-click "ส่งผิดลบได้" recall right beside own message
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _unsendOrHardRecall(msg, hard: false),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppTheme.dangerRed.withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.undo_rounded,
                      size: 12,
                      color: AppTheme.dangerRed,
                    ),
                    SizedBox(width: 3),
                    Text(
                      'ส่งผิดลบได้',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.dangerRed,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.done_all_rounded, size: 12, color: readColor),
              const SizedBox(width: 3),
              Text(
                readLabel,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: readColor,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ] else if (canRecall)
          InkWell(
            onTap: () => _unsendOrHardRecall(msg, hard: true),
            child: Text(
              'แอดมินสั่งลบ',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: onLight || themeMode.isDark
                    ? AppTheme.dangerRed
                    : const Color(0xFFFECACA),
                height: 1.3,
              ),
            ),
          ),
        Text(
          timeStr,
          style: TextStyle(fontSize: 10.5, color: metaText, height: 1.3),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Reserve room for avatar + meta column + menu so the row never overflows.
          final reserved = (isMe ? 0 : 42) + 28 + 6 + 92;
          final bubbleMax = math.max(
            140.0,
            math.min(430.0, constraints.maxWidth - reserved),
          );
          final isNew = _animatedMessageIds.add(msg.id);

          final nameHeader = Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: isMe ? WrapAlignment.end : WrapAlignment.start,
              children: [
                if (!isMe)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: bubbleMax * 0.62),
                    child: Text(
                      msg.senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: nameColor,
                        height: 1.3,
                      ),
                    ),
                  ),
                PillBadge(
                  text: msg.senderDepartment,
                  backgroundColor: Colors.white.withValues(alpha: 0.88),
                  textColor: AppTheme.slateDark,
                ),
                if (msg.priority == 'urgent')
                  PillBadge(
                    text: '⚡ เรื่องด่วน',
                    backgroundColor: AppTheme.dangerRed.withValues(alpha: 0.92),
                    textColor: Colors.white,
                  ),
                if (msg.priority == 'silent')
                  const PillBadge(
                    text: '🌙 ส่งเงียบ (ไม่ส่งเสียงรบกวน)',
                    backgroundColor: Color(0xFF312E81),
                    textColor: Color(0xFFE0E7FF),
                  ),
                if (msg.isConfidential)
                  const PillBadge(
                    text: '🔒 ความลับส่วนตัว',
                    backgroundColor: Color(0xFF7F1D1D),
                    textColor: Color(0xFFFECACA),
                  ),
              ],
            ),
          );

          // Menu + meta hug the bubble and share its bottom edge.
          final bubbleRow = Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isMe) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildMessageActionMenu(msg, canRecall, metaText),
                    metaColumn,
                  ],
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: bubbleMax),
                  child: GestureDetector(
                    onLongPress: () => _showMessageSheetActions(msg, canRecall),
                    child: msg.isConfidential
                        ? _buildConfidentialWrapper(msg, isMe)
                        : _buildBubbleContent(msg, isMe),
                  ),
                ),
              ),
              if (!isMe) ...[
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    metaColumn,
                    _buildMessageActionMenu(msg, canRecall, metaText),
                  ],
                ),
              ],
            ],
          );

          final content = Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe) ...[
                UserAvatar(
                  name: msg.senderName,
                  avatarUrl: msg.senderAvatar,
                  radius: 17,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    nameHeader,
                    bubbleRow,
                    if (msg.reactions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _buildReactionsRow(
                          msg,
                          ApiService.instance.currentUser?.id ?? '',
                          isMe,
                        ),
                      ),
                    if (msg.type != 'sticker' &&
                        msg.type != 'rich_card' &&
                        msg.type != 'poll' &&
                        msg.type != 'event')
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _buildTaskClaimBar(msg),
                      ),
                  ],
                ),
              ),
            ],
          );

          // Cheap one-shot fade + slide for rows that first appear.
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: isNew ? 0.0 : 1.0, end: 1.0),
            duration: const Duration(milliseconds: 220),
            curve: AppTheme.motionCurve,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 10),
                child: child,
              ),
            ),
            child: content,
          );
        },
      ),
    );
  }

  /// Confidential Message Wrapper: hidden on screen until tapped by reader
  Widget _buildConfidentialWrapper(ChatMessage msg, bool isMe) {
    final isRevealed = _revealedMessageIds.contains(msg.id);
    final currentUser = ApiService.instance.currentUser;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDC2626), width: 1.6),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF991B1B),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_rounded,
                  size: 14,
                  color: Color(0xFFFDE68A),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '🔒 ความลับส่วนตัว — แตะเปิดอ่านเฉพาะบนหน้าจอนี้',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isRevealed)
                  InkWell(
                    onTap: () =>
                        setState(() => _revealedMessageIds.remove(msg.id)),
                    child: const Text(
                      'ซ่อนข้อมูล',
                      style: TextStyle(
                        color: Color(0xFFFDE68A),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!isRevealed)
            InkWell(
              onTap: () => setState(() => _revealedMessageIds.add(msg.id)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.visibility_off_rounded,
                      color: Color(0xFF991B1B),
                      size: 28,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'เนื้อหาความลับถูกซ่อนไว้เพื่อความปลอดภัย',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'แตะเพื่อเปิดดูข้อมูลความลับ (บันทึกชื่อผู้เปิดอ่าน: ${currentUser?.displayName ?? "คุณ"})',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.dangerRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: _buildBubbleContent(msg, isMe),
                ),
                Positioned(
                  right: 10,
                  bottom: 6,
                  child: IgnorePointer(
                    child: Text(
                      'เปิดอ่านโดย ${currentUser?.email ?? ""}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.dangerRed.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMessageActionMenu(
    ChatMessage msg,
    bool canRecall,
    Color iconColor,
  ) {
    return SizedBox(
      width: 28,
      height: 28,
      child: PopupMenuButton<String>(
        tooltip: 'จัดการข้อความ / ส่งผิดลบได้',
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_vert_rounded, size: 17, color: iconColor),
        onSelected: (action) {
          if (action.startsWith('react:')) {
            _handleReactMessage(msg, action.substring(6));
          } else if (action == 'reply') {
            setState(() => _replyingTo = msg);
          } else if (action == 'pin') {
            _pinMessageToBanner(msg);
          } else if (action == 'notebook') {
            _saveMessageToNotebook(msg);
          } else if (action == 'delete_for_me') {
            _handleDeleteForMe(msg);
          } else if (action == 'unsend') {
            _unsendOrHardRecall(msg, hard: false);
          } else if (action == 'hard_recall') {
            _unsendOrHardRecall(msg, hard: true);
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem(
            enabled: false,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ['❤️', '👍', '😂', '😮', '😢', '🙏'].map((emoji) {
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleReactMessage(msg, emoji);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(emoji, style: const TextStyle(fontSize: 18)),
                  ),
                );
              }).toList(),
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'reply',
            child: Row(
              children: [
                Icon(Icons.reply_rounded, size: 17),
                SizedBox(width: 8),
                Text('ตอบกลับข้อความ (Reply)', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'pin',
            child: Row(
              children: [
                Icon(
                  Icons.push_pin_rounded,
                  size: 17,
                  color: AppTheme.warningAmber,
                ),
                SizedBox(width: 8),
                Text('ปักหมุดประกาศบนหัวห้อง', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'notebook',
            child: Row(
              children: [
                Icon(
                  Icons.bookmark_add_rounded,
                  size: 17,
                  color: AppTheme.brandPrimary,
                ),
                const SizedBox(width: 8),
                const Text('บันทึกเข้าสมุดบันทึก BC ถาวร', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'delete_for_me',
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded, size: 17, color: AppTheme.slateBody),
                SizedBox(width: 8),
                Text('ลบเฉพาะฉัน', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          if (canRecall) ...[
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'unsend',
              child: Row(
                children: [
                  Icon(Icons.undo_rounded, size: 17, color: AppTheme.dangerRed),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ยกเลิกข้อความ & ลบไฟล์ทันที (ส่งผิดลบได้ 100%)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.dangerRed,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'hard_recall',
              child: Row(
                children: [
                  Icon(
                    Icons.delete_forever_rounded,
                    size: 18,
                    color: Color(0xFF991B1B),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ลบไร้ร่องรอย (Hard Recall)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showMessageSheetActions(ChatMessage msg, bool canRecall) {
    setState(() {
      _activeComposerTray = null;
      _selectedActionMessage = msg;
      _selectedActionCanRecall = canRecall;
    });
  }

  Widget _buildSelectedMessageActionBar() {
    final msg = _selectedActionMessage;
    if (msg == null) return const SizedBox.shrink();
    final canRecall = _selectedActionCanRecall;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFDF8F6),
        border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'จัดการข้อความ:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slateDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: ['❤️', '👍', '😂', '😮', '😢', '🙏'].map((emoji) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          setState(() => _selectedActionMessage = null);
                          _handleReactMessage(msg, emoji);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(emoji, style: const TextStyle(fontSize: 19)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _selectedActionMessage = null),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.reply_rounded, size: 15),
                  label: const Text('ตอบกลับ', style: TextStyle(fontSize: 12)),
                  onPressed: () => setState(() {
                    _replyingTo = msg;
                    _selectedActionMessage = null;
                  }),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(
                    Icons.push_pin_rounded,
                    size: 15,
                    color: AppTheme.warningAmber,
                  ),
                  label: const Text('ปักหมุดหัวห้อง', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    setState(() => _selectedActionMessage = null);
                    _pinMessageToBanner(msg);
                  },
                ),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: Icon(
                    Icons.bookmark_add_rounded,
                    size: 15,
                    color: AppTheme.brandPrimary,
                  ),
                  label: const Text('บันทึกโน้ต', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    setState(() => _selectedActionMessage = null);
                    _saveMessageToNotebook(msg);
                  },
                ),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(Icons.delete_outline_rounded, size: 15),
                  label: const Text('ลบเฉพาะฉัน', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    setState(() => _selectedActionMessage = null);
                    _handleDeleteForMe(msg);
                  },
                ),
                if (canRecall) ...[
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(
                      Icons.undo_rounded,
                      size: 15,
                      color: AppTheme.dangerRed,
                    ),
                    label: const Text(
                      'ยกเลิก & ลบไฟล์',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.dangerRed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () {
                      setState(() => _selectedActionMessage = null);
                      _unsendOrHardRecall(msg, hard: false);
                    },
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(
                      Icons.delete_forever_rounded,
                      size: 15,
                      color: Color(0xFF991B1B),
                    ),
                    label: const Text(
                      'ลบไร้ร่องรอย',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF991B1B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () {
                      setState(() => _selectedActionMessage = null);
                      _unsendOrHardRecall(msg, hard: true);
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubbleContent(ChatMessage msg, bool isMe) {
    switch (msg.type) {
      case 'sticker':
        return _buildStickerBubble(msg);
      case 'image':
        return _buildImageBubble(msg, isMe);
      case 'file':
        return _buildFileBubble(msg, isMe);
      case 'audio':
        return _buildAudioBubble(msg, isMe);
      case 'rich_card':
        return _buildRichCardBubble(msg);
      case 'poll':
        return _buildPollBubble(msg);
      case 'event':
        return _buildEventBubble(msg);
      default:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? null : AppTheme.receivedBubble,
            gradient: isMe
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [const Color(0xFFFEECE8), AppTheme.sentBubble],
                  )
                : null,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isMe ? 18 : 5),
              topRight: Radius.circular(isMe ? 5 : 18),
              bottomLeft: const Radius.circular(18),
              bottomRight: const Radius.circular(18),
            ),
            boxShadow: AppTheme.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msg.replyTo != null)
                _buildReplyQuoteInsideBubble(msg.replyTo!),
              SelectableText(
                msg.cleanContent,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppTheme.slateDark,
                  height: 1.45,
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildReplyQuoteInsideBubble(ReplySummary reply) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: AppTheme.brandDeep, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ตอบกลับ ${reply.senderName}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.brandDeep,
            ),
          ),
          Text(
            reply.content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppTheme.slateBody),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerBubble(ChatMessage msg) {
    final matched = _thaiStickers.firstWhere(
      (s) => s['code'] == msg.stickerCode,
      orElse: () => {'emoji': '🧡✨', 'label': msg.cleanContent},
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(matched['emoji'] ?? '🧡', style: const TextStyle(fontSize: 38)),
          const SizedBox(height: 4),
          Text(
            msg.cleanContent.isNotEmpty
                ? msg.cleanContent
                : (matched['label'] ?? ''),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slateDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageBubble(ChatMessage msg, bool isMe) {
    final url = msg.attachment?.url ?? '';
    final fileName = msg.attachment?.fileName ?? msg.cleanContent;

    return Container(
      decoration: BoxDecoration(
        color: isMe ? AppTheme.sentBubble : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (url.isNotEmpty)
            InkWell(
              onTap: () => _showImagePreviewDialog(url, fileName),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 220,
                  minWidth: 180,
                ),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 120,
                    color: AppTheme.surfaceBg,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_outlined,
                      size: 40,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_done_rounded,
                  size: 14,
                  color: AppTheme.brandDeep,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '$fileName · เก็บถาวรบน MinIO (ไม่หมดอายุ)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.brandDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showImagePreviewDialog(String url, String title) {
    setState(() {
      _previewImageUrl = url;
      _previewImageTitle = title;
    });
  }

  Widget _buildFileBubble(ChatMessage msg, bool isMe) {
    final att = msg.attachment;
    final fileName = att?.fileName ?? msg.cleanContent;
    final sizeText = formatFileSize(att?.fileSize ?? 0);
    final url = att?.url ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? AppTheme.sentBubble : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.workBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.insert_drive_file_rounded,
                  color: AppTheme.workBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          sizeText,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        PillBadge(
                          text: 'MinIO ไม่หมดอายุ',
                          backgroundColor: AppTheme.brandSoft,
                          textColor: AppTheme.brandDeep,
                          icon: Icons.verified_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (url.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    final uri = Uri.tryParse(url);
                    if (uri != null) {
                      launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  tooltip: 'ดาวน์โหลด / เปิดไฟล์จาก MinIO',
                  icon: Icon(Icons.download_rounded, color: AppTheme.brandDeep),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskClaimBar(ChatMessage msg) {
    final status = msg.taskStatus ?? 'open';
    final actor = (msg.acceptedBy != null && msg.acceptedBy!.trim().isNotEmpty)
        ? msg.acceptedBy!
        : 'เพื่อน';

    Widget chip({
      required IconData icon,
      required String label,
      required Color fg,
      required Color bg,
      required Color border,
      VoidCallback? onTap,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
              boxShadow: AppTheme.shadowSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (status == 'done') {
      return chip(
        icon: Icons.task_alt_rounded,
        label: 'เรียบร้อยแล้วโดย: $actor',
        fg: Colors.white,
        bg: const Color(0xFF13795B),
        border: const Color(0xFF6EE7B7),
      );
    }

    if (status == 'accepted') {
      return chip(
        icon: Icons.check_circle_rounded,
        label: 'รับช่วยโดย: $actor • กดเมื่อเสร็จ',
        fg: AppTheme.brandDeep,
        bg: AppTheme.brandSoft,
        border: AppTheme.brandPrimary,
        onTap: () => _handleTaskAction(msg, 'done'),
      );
    }

    return chip(
      icon: Icons.pan_tool_alt_rounded,
      label: 'อาสาช่วยเรื่องนี้',
      fg: AppTheme.workBlue,
      bg: Colors.white.withValues(alpha: 0.95),
      border: AppTheme.borderSubtle,
      onTap: () => _handleTaskAction(msg, 'accept'),
    );
  }

  Widget _buildReactionsRow(ChatMessage msg, String currentUserId, bool isMe) {
    final entries = msg.reactions.entries
        .where((e) => e.value.isNotEmpty)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      alignment: isMe ? WrapAlignment.end : WrapAlignment.start,
      children: entries.map((e) {
        final reacted = e.value.contains(currentUserId);
        return InkWell(
          onTap: () => _handleReactMessage(msg, e.key),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: reacted
                  ? AppTheme.brandSoft
                  : Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: reacted ? AppTheme.brandPrimary : AppTheme.borderSubtle,
              ),
              boxShadow: AppTheme.shadowSm,
            ),
            child: Text(
              '${e.key} ${e.value.length}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: reacted ? AppTheme.brandDeep : AppTheme.slateDark,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _toggleAudioPlayback(ChatMessage msg) async {
    final url = msg.attachment?.url ?? '';
    if (url.isEmpty) return;
    if (_playingAudioMsgId == msg.id) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingAudioMsgId = null);
      return;
    }
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
      if (mounted) setState(() => _playingAudioMsgId = msg.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('เล่นเสียงไม่สำเร็จ: $e')));
    }
  }

  Widget _buildAudioBubble(ChatMessage msg, bool isMe) {
    final playing = _playingAudioMsgId == msg.id;
    final dur = msg.audioDurationSec ?? 0;
    final durLabel = dur > 0
        ? '${(dur ~/ 60).toString().padLeft(2, '0')}:${(dur % 60).toString().padLeft(2, '0')}'
        : 'ข้อความเสียง';
    final fileName = msg.attachment?.fileName ?? msg.cleanContent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? AppTheme.sentBubble : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            onTap: () => _toggleAudioPlayback(msg),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.brandPrimary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName.isNotEmpty ? fileName : 'บันทึกเสียงสนทนา',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  playing ? 'กำลังเล่นเสียง... ($durLabel)' : 'ความยาว $durLabel',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slateMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPollBubble(ChatMessage msg) {
    final poll = msg.poll;
    if (poll == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(msg.cleanContent),
      );
    }
    final currentUser = ApiService.instance.currentUser;
    final myId = currentUser?.id ?? '';
    final canClose =
        !poll.isClosed && (msg.senderId == myId || (currentUser?.isAdmin ?? false));
    final total = poll.totalVotes;
    final cardWidth = math.min(310.0, MediaQuery.of(context).size.width * 0.68);

    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderSubtle),
        boxShadow: AppTheme.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.poll_rounded, size: 18, color: AppTheme.brandPrimary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  poll.isClosed ? 'โพล (ปิดโหวตแล้ว)' : 'โพลสำรวจความคิดเห็น',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.brandDeep,
                  ),
                ),
              ),
              Text(
                '${poll.uniqueVotersCount} คนโหวต',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.slateMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            poll.question,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.slateDark,
            ),
          ),
          const SizedBox(height: 10),
          ...poll.options.map((opt) {
            final voted = opt.voterIds.contains(myId);
            final ratio = total > 0 ? opt.voterIds.length / total : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: poll.isClosed
                    ? null
                    : () async {
                        final selected = <String>{};
                        for (final o in poll.options) {
                          if (o.voterIds.contains(myId)) selected.add(o.id);
                        }
                        if (poll.allowMultiple) {
                          if (voted) {
                            selected.remove(opt.id);
                          } else {
                            selected.add(opt.id);
                          }
                        } else {
                          selected
                            ..clear()
                            ..add(opt.id);
                        }
                        try {
                          final updated = await ApiService.instance.votePoll(
                            msg.id,
                            selected.toList(),
                          );
                          if (!mounted) return;
                          setState(() {
                            _messages = _messages
                                .map((m) => m.id == msg.id ? updated : m)
                                .toList();
                          });
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('โหวตไม่สำเร็จ: $e')),
                          );
                        }
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: voted ? AppTheme.brandSoft : AppTheme.surfaceBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: voted ? AppTheme.brandPrimary : AppTheme.borderSubtle,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            voted
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 16,
                            color: voted ? AppTheme.brandPrimary : AppTheme.slateMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              opt.text,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: voted ? FontWeight.w700 : FontWeight.w500,
                                color: AppTheme.slateDark,
                              ),
                            ),
                          ),
                          Text(
                            '${opt.voterIds.length}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.brandDeep,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      LinearProgressIndicator(
                        value: ratio,
                        minHeight: 4,
                        backgroundColor: Colors.white,
                        color: AppTheme.brandPrimary,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (canClose)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  try {
                    final updated = await ApiService.instance.closePoll(msg.id);
                    if (!mounted) return;
                    setState(() {
                      _messages = _messages
                          .map((m) => m.id == msg.id ? updated : m)
                          .toList();
                    });
                  } catch (_) {}
                },
                child: const Text('ปิดโพลนี้'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEventBubble(ChatMessage msg) {
    final ev = msg.eventData;
    if (ev == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(msg.cleanContent),
      );
    }
    final myId = ApiService.instance.currentUser?.id ?? '';
    final isGoing = ev.goingIds.contains(myId);
    final isMaybe = ev.maybeIds.contains(myId);
    final isNo = ev.notGoingIds.contains(myId);
    final cardWidth = math.min(310.0, MediaQuery.of(context).size.width * 0.68);

    Widget rsvpBtn(String status, String label, bool active, int count) {
      return Expanded(
        child: OutlinedButton(
          onPressed: () async {
            try {
              final updated = await ApiService.instance.rsvpEvent(msg.id, status);
              if (!mounted) return;
              setState(() {
                _messages = _messages
                    .map((m) => m.id == msg.id ? updated : m)
                    .toList();
              });
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('ตอบรับนัดหมายไม่สำเร็จ: $e')),
              );
            }
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            backgroundColor: active ? AppTheme.brandSoft : Colors.white,
            foregroundColor: active ? AppTheme.brandDeep : AppTheme.slateBody,
            side: BorderSide(
              color: active ? AppTheme.brandPrimary : AppTheme.borderSubtle,
            ),
          ),
          child: Text(
            '$label ($count)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderSubtle),
        boxShadow: AppTheme.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_rounded, size: 18, color: AppTheme.brandPrimary),
              const SizedBox(width: 6),
              Text(
                'นัดหมาย / กิจกรรม',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.brandDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ev.title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.slateDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '🕒 ${formatThaiTime(ev.startsAt)}',
            style: const TextStyle(fontSize: 12, color: AppTheme.slateBody),
          ),
          if (ev.location.isNotEmpty)
            Text(
              '📍 ${ev.location}',
              style: const TextStyle(fontSize: 12, color: AppTheme.slateMuted),
            ),
          if (ev.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              ev.description,
              style: const TextStyle(fontSize: 12, color: AppTheme.slateBody),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              rsvpBtn('going', 'ไป', isGoing, ev.goingIds.length),
              const SizedBox(width: 6),
              rsvpBtn('maybe', 'อาจจะ', isMaybe, ev.maybeIds.length),
              const SizedBox(width: 6),
              rsvpBtn('not_going', 'ไม่ไป', isNo, ev.notGoingIds.length),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRichCardBubble(ChatMessage msg) {
    final card = msg.cardPayload ?? const <String, dynamic>{};
    final appTitle = (card['app_title'] ?? 'BC Ai Chat Mini-App').toString();
    final title = (card['title'] ?? msg.cleanContent).toString();
    final subtitle = (card['subtitle'] ?? '').toString();
    final highlight = (card['highlight'] ?? '').toString();
    final badge = (card['badge'] ?? 'การ์ดโต้ตอบ').toString();
    final note = (card['note'] ?? '').toString();
    final colorHex = (card['color'] ?? '#812920').toString();
    final iconName = (card['icon'] ?? 'widgets').toString();
    final accent = AppTheme.parseHexColor(colorHex);

    final approvalStatus = (card['approval_status'] ?? card['status'] ?? '')
        .toString();
    final approvedBy = (card['approved_by'] ?? '').toString();
    final isApproved =
        approvalStatus == 'อนุมัติแล้ว' ||
        (approvedBy.isNotEmpty && !approvalStatus.contains('ไม่อนุมัติ'));
    final isRejected = approvalStatus == 'ไม่อนุมัติ';
    final cardWidth = math.min(290.0, MediaQuery.of(context).size.width * 0.64);

    return Container(
      width: cardWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: AppTheme.shadowMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, Color.lerp(accent, Colors.black, 0.2)!],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  AppTheme.resolveMiniAppIcon(iconName),
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    appTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slateDark,
                    height: 1.4,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.slateBody,
                      height: 1.4,
                    ),
                  ),
                ],
                if (highlight.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceBg,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'รายละเอียด',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            highlight,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    note,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.slateMuted,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // Digital Approval Stamp or In-Chat Live Approval Buttons
                if (isApproved || isRejected)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isRejected
                          ? const Color(0xFFFEF2F2)
                          : AppTheme.brandSoft,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(
                        color: isRejected
                            ? AppTheme.dangerRed
                            : AppTheme.brandPrimary,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          isRejected
                              ? Icons.cancel_rounded
                              : Icons.verified_rounded,
                          size: 16,
                          color: isRejected
                              ? AppTheme.dangerRed
                              : AppTheme.brandDeep,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isRejected
                                ? 'ไม่สะดวกโดย ${approvedBy.isNotEmpty ? approvedBy : "ผู้รับ"}'
                                : 'ตกลงโดย ${approvedBy.isNotEmpty ? approvedBy : "ผู้รับ"}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: isRejected
                                  ? AppTheme.dangerRed
                                  : AppTheme.brandDeep,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _handleApproveRichCard(msg, 'อนุมัติแล้ว'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.brandPrimary,
                              foregroundColor: Colors.white,
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSm,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text(
                              'อนุมัติทันที',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _handleApproveRichCard(msg, 'ไม่อนุมัติ'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.dangerRed,
                              minimumSize: Size.zero,
                              side: const BorderSide(
                                color: AppTheme.dangerRed,
                                width: 1.2,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSm,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: const Text(
                              'ไม่อนุมัติ',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final appCode = (card['app_code'] ?? '').toString();
                      final targetApp = widget.miniApps.isNotEmpty
                          ? widget.miniApps.firstWhere(
                              (a) => a.code == appCode,
                              orElse: () => widget.miniApps.first,
                            )
                          : MiniAppItem(
                              id: 'custom',
                              code: appCode.isEmpty ? 'leave' : appCode,
                              title: appTitle,
                              subtitle: subtitle,
                              category: 'บริการเสริม',
                              icon: iconName,
                              color: colorHex,
                              url: '/miniapp/$appCode',
                              enabled: true,
                            );
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MiniAppRunnerScreen(
                            miniApp: targetApp,
                            conversations: widget.allConversations,
                            initialConversationId: _conversation.id,
                            onCardSent: (_) {
                              _refreshMessagesQuietly();
                              widget.onConversationUpdated?.call();
                            },
                          ),
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.open_in_new_rounded,
                      size: 13,
                      color: accent,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size.zero,
                      side: BorderSide(color: accent.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                    ),
                    label: Text(
                      'เปิดระบบเสริม ($appTitle)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerPickerPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xF5FFFFFF),
        border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'สติกเกอร์ "อารมณ์ดีดินเผาไทย" (คลิกเพื่อส่งทันที)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slateDark,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _activeComposerTray = null),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _thaiStickers.map((stk) {
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _sendSticker(stk),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(stk['emoji']!, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 6),
                      Text(
                        stk['label']!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slateDark,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineAttachmentTray() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(
        color: Color(0xF5FFFFFF),
        border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_upload_rounded,
                color: AppTheme.brandPrimary,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'แนบรูป ไฟล์ถาวรบน MinIO & กิจกรรมในห้อง',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _activeComposerTray = null),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ActionChip(
                  avatar: Icon(
                    Icons.folder_open_rounded,
                    size: 16,
                    color: AppTheme.brandPrimary,
                  ),
                  label: const Text('เลือกรูป/ไฟล์จากเครื่อง'),
                  onPressed: () {
                    setState(() => _activeComposerTray = null);
                    _pickAndUploadFile();
                  },
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(
                    Icons.map_rounded,
                    size: 16,
                    color: AppTheme.workBlue,
                  ),
                  label: const Text('ส่งไฟล์แพลนเที่ยวตัวอย่าง'),
                  onPressed: () {
                    setState(() => _activeComposerTray = null);
                    final sampleContent = utf8.encode(
                      'บันทึกแพลนเที่ยว & ของฝาก BC Ai Chat\n'
                      'ทริป: เชียงใหม่ - บ้านเชียง 3 วัน 2 คืน\n'
                      'จุดแวะ: คาเฟ่ริมน้ำ, ตลาดเช้า, บ้านญาติ\n'
                      'จัดเก็บถาวรบน MinIO Object Storage (ส่งผิดกดลบทันที)\n',
                    );
                    _uploadBytesAndSend(
                      fileName:
                          'trip-plan-${DateTime.now().millisecondsSinceEpoch % 10000}.txt',
                      bytes: sampleContent,
                      extension: 'txt',
                    );
                  },
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: Icon(
                    Icons.mic_rounded,
                    size: 16,
                    color: AppTheme.brandPrimary,
                  ),
                  label: const Text('ส่งไฟล์เสียง'),
                  onPressed: () {
                    setState(() => _activeComposerTray = null);
                    _pickAndUploadAudio();
                  },
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.poll_outlined, size: 16),
                  label: const Text('สร้างโพลโหวต'),
                  onPressed: () {
                    setState(() => _activeComposerTray = null);
                    _openCreatePollDialog();
                  },
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.event_available_outlined, size: 16),
                  label: const Text('นัดเจอ / กิจกรรม'),
                  onPressed: () {
                    setState(() => _activeComposerTray = null);
                    _openEventsDialog();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineMiniAppTray() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(
        color: Color(0xF5FFFFFF),
        border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.widgets_rounded,
                color: AppTheme.brandPrimary,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'เลือกผู้ช่วยส่วนตัวเพื่อส่งการ์ดเข้าห้องแชท',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _activeComposerTray = null),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 62,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.miniApps.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final app = widget.miniApps[i];
                final color = AppTheme.parseHexColor(app.color);
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    setState(() => _activeComposerTray = null);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MiniAppRunnerScreen(
                          miniApp: app,
                          conversations: widget.allConversations,
                          initialConversationId: _conversation.id,
                          onCardSent: (_) {
                            _refreshMessagesQuietly();
                            widget.onConversationUpdated?.call();
                          },
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 168,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            AppTheme.resolveMiniAppIcon(app.icon),
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            app.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slateDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBanner(ChatMessage replyMsg) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
      decoration: const BoxDecoration(
        color: Color(0xF5F8FAFC),
        border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.reply_rounded, size: 18, color: AppTheme.brandDeep),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ตอบกลับ ${replyMsg.senderName}: ${replyMsg.previewText}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.slateDark,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _replyingTo = null),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  /// Compact pill used by the composer mode row (priority, confidential, AI shortcuts).
  Widget _modeChip({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required Color fg,
    Color? bg,
    Gradient? gradient,
    Color? borderColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppTheme.motionFast,
          curve: AppTheme.motionCurve,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            gradient: gradient,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor ?? Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposerModeRow() {
    final isUrgent = _selectedPriority == 'urgent';
    final isSilent = _selectedPriority == 'silent';
    final isNormal = !isUrgent && !isSilent;
    // Soft fade at both edges tells the user the chip row scrolls.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        colors: [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent,
        ],
        stops: [0.0, 0.03, 0.95, 1.0],
      ).createShader(rect),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Priority mode: ปกติ -> เรื่องด่วน -> ส่งเงียบนอกเวลา
            _modeChip(
              onTap: _cyclePriority,
              icon: isUrgent
                  ? Icons.notifications_active_rounded
                  : isSilent
                  ? Icons.nights_stay_rounded
                  : Icons.chat_bubble_outline_rounded,
              label: isUrgent
                  ? 'เรื่องด่วน'
                  : isSilent
                  ? 'ส่งเงียบนอกเวลา'
                  : 'โหมดส่ง: ปกติ',
              fg: isNormal ? AppTheme.slateBody : Colors.white,
              bg: isUrgent
                  ? AppTheme.dangerRed
                  : isSilent
                  ? const Color(0xFF312E81)
                  : AppTheme.surfaceBg,
              borderColor: isNormal ? AppTheme.borderSubtle : null,
            ),
            const SizedBox(width: 8),
            _modeChip(
              onTap: () =>
                  setState(() => _isConfidentialMode = !_isConfidentialMode),
              icon: _isConfidentialMode
                  ? Icons.lock_rounded
                  : Icons.lock_open_rounded,
              label: 'โหมดความลับ',
              fg: _isConfidentialMode ? Colors.white : AppTheme.slateBody,
              bg: _isConfidentialMode
                  ? const Color(0xFF991B1B)
                  : AppTheme.surfaceBg,
              borderColor: _isConfidentialMode
                  ? const Color(0xFF991B1B)
                  : AppTheme.borderSubtle,
            ),
            const SizedBox(width: 8),
            _modeChip(
              onTap: _insertAiMention,
              icon: Icons.psychology_rounded,
              label: '@ai ถามเพื่อน AI ในห้อง',
              fg: Colors.white,
              gradient: AppTheme.aiGradient,
            ),
            const SizedBox(width: 8),
            _modeChip(
              onTap: () => _openAiAssistModal(initialMode: 'polish'),
              icon: Icons.auto_fix_high_rounded,
              label: 'AI เกลาคำพูด',
              fg: AppTheme.personalPurple,
              bg: const Color(0xFFF3E8FF),
              borderColor: AppTheme.personalPurple.withValues(alpha: 0.3),
            ),
            const SizedBox(width: 8),
            _modeChip(
              onTap: () => _openAiAssistModal(initialMode: 'suggest_reply'),
              icon: Icons.tips_and_updates_rounded,
              label: 'คิดคำตอบไวจากแชทล่าสุด',
              fg: AppTheme.brandDeep,
              bg: AppTheme.brandSoft,
            ),
            const SizedBox(width: 8),
            _modeChip(
              onTap: _openAiSummarizeModal,
              icon: Icons.summarize_rounded,
              label: 'AI สรุปแชทสำคัญ',
              fg: AppTheme.workBlue,
              bg: const Color(0xFFE0E7FF),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMentionSuggestionStrip() {
    final q = _mentionQuery.trim().toLowerCase();
    final candidates = <(String id, String tag, String label)>[
      ('all', '@all', '@all (ทุกคนในห้อง)'),
      ('user_ai', '@ai', '@ai (BC AI สมองกล)'),
      ...widget.friends
          .where((f) =>
              _conversation.memberIds.isEmpty ||
              _conversation.memberIds.contains(f.id))
          .map((f) => (f.id, '@${f.displayName}', '@${f.displayName}')),
    ].where((item) {
      if (q.isEmpty) return true;
      return item.$2.toLowerCase().contains(q) ||
          item.$3.toLowerCase().contains(q);
    }).take(6).toList();

    if (candidates.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 36,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: candidates.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final c = candidates[i];
          return ActionChip(
            backgroundColor: AppTheme.brandSoft,
            label: Text(
              c.$3,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.brandDeep,
              ),
            ),
            onPressed: () {
              final text = _msgCtrl.text;
              final replaced = text.replaceFirst(
                RegExp(r'@(?:[^\s@]*)$'),
                '${c.$2} ',
              );
              setState(() {
                _pendingMentionIds.add(c.$1);
                _showMentionSuggestions = false;
                _mentionQuery = '';
                _msgCtrl.text = replaced;
                _msgCtrl.selection = TextSelection.fromPosition(
                  TextPosition(offset: replaced.length),
                );
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildComposerBar() {
    final accent = _isConfidentialMode
        ? const Color(0xFF991B1B)
        : _selectedPriority == 'urgent'
        ? AppTheme.dangerRed
        : AppTheme.brandPrimary;

    return GlassPanel(
      blur: 20,
      tint: _isConfidentialMode
          ? const Color(0xF2FFFBEB)
          : const Color(0xE6FFFFFF),
      border: Border(
        top: BorderSide(
          color: _isConfidentialMode
              ? AppTheme.dangerRed
              : AppTheme.borderSubtle,
          width: _isConfidentialMode ? 1.5 : 0.8,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildComposerModeRow(),
            ),
            if (_showMentionSuggestions) _buildMentionSuggestionStrip(),
            if (_isConfidentialMode)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.dangerRed.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.lock_rounded,
                      size: 15,
                      color: AppTheme.dangerRed,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'โหมดความลับส่วนตัว: ซ่อนเนื้อหาบนหน้าจอก่อนแตะเปิด · ส่งผิดสั่งลบทำลายไฟล์ได้ทันที',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.dangerRed,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => setState(() => _isConfidentialMode = false),
                      child: const Text(
                        'ปิดโหมดความลับ',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slateBody,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _isUploading ? null : _showAttachmentMenu,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'แนบรูปภาพ / ไฟล์เอกสารเก็บถาวรบน MinIO',
                  icon: _isUploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.attach_file_rounded,
                          color: AppTheme.slateBody,
                        ),
                ),
                IconButton(
                  onPressed: _openMiniAppPicker,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'ส่งการ์ดจากระบบเสริม (การ์ดโต้ตอบ)',
                  icon: Icon(Icons.widgets_outlined, color: AppTheme.brandDeep),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _selectedActionMessage = null;
                    _activeComposerTray =
                        _activeComposerTray == 'sticker' ? null : 'sticker';
                  }),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'ส่งสติ๊กเกอร์',
                  icon: Icon(
                    Icons.emoji_emotions_outlined,
                    color: _activeComposerTray == 'sticker'
                        ? AppTheme.brandPrimary
                        : AppTheme.slateBody,
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    onSubmitted: (_) => _sendTextMessage(),
                    textInputAction: TextInputAction.send,
                    style: const TextStyle(fontSize: 14.5, height: 1.4),
                    decoration: InputDecoration(
                      hintText: _isConfidentialMode
                          ? 'พิมพ์ข้อความลับส่วนตัว...'
                          : _selectedPriority == 'urgent'
                          ? 'พิมพ์ข้อความเรื่องด่วน...'
                          : 'พิมพ์ข้อความถึง ${_conversation.name}...',
                      hintMaxLines: 1,
                      isDense: true,
                      filled: true,
                      fillColor: _isConfidentialMode
                          ? Colors.white
                          : AppTheme.surfaceBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: accent.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _msgCtrl,
                  builder: (context, value, _) {
                    final ready = value.text.trim().isNotEmpty;
                    return AnimatedScale(
                      scale: ready ? 1.0 : 0.9,
                      duration: AppTheme.motionFast,
                      curve: AppTheme.motionCurve,
                      child: AnimatedContainer(
                        duration: AppTheme.motionMed,
                        curve: AppTheme.motionCurve,
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: ready ? accent : const Color(0xFFCBD5E1),
                          shape: BoxShape.circle,
                          boxShadow: ready ? AppTheme.glow(accent) : const [],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _sendTextMessage,
                            child: const Center(
                              child: Icon(
                                Icons.send_rounded,
                                size: 19,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline Panel showing Permanent MinIO Vault (Images, Files) & Group Notes
class _RoomVaultPanel extends StatefulWidget {
  final Conversation conversation;
  final int initialTab;
  final VoidCallback onClose;

  const _RoomVaultPanel({
    super.key,
    required this.conversation,
    this.initialTab = 0,
    required this.onClose,
  });

  @override
  State<_RoomVaultPanel> createState() => _RoomVaultPanelState();
}

class _RoomVaultPanelState extends State<_RoomVaultPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  VaultData _vault = const VaultData(images: [], files: [], links: []);
  List<NoteItem> _roomNotes = const [];
  bool _loading = true;
  bool _showAddNoteForm = false;
  final TextEditingController _noteTitleCtrl = TextEditingController();
  final TextEditingController _noteContentCtrl = TextEditingController();
  String? _commentingNoteId;
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _loadVault();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _noteTitleCtrl.dispose();
    _noteContentCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVault() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.fetchVault(widget.conversation.id),
        ApiService.instance.fetchNotes(conversationId: widget.conversation.id),
      ]);
      if (!mounted) return;
      setState(() {
        _vault = results[0] as VaultData;
        _roomNotes = results[1] as List<NoteItem>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitNewRoomNote() async {
    final title = _noteTitleCtrl.text.trim();
    if (title.isEmpty) return;
    await ApiService.instance.createNote(
      conversationId: widget.conversation.id,
      title: title,
      content: _noteContentCtrl.text.trim(),
      category: 'โน้ตประจำห้อง',
    );
    if (!mounted) return;
    _noteTitleCtrl.clear();
    _noteContentCtrl.clear();
    setState(() => _showAddNoteForm = false);
    _loadVault();
  }

  Future<void> _submitNoteComment(String noteId) async {
    final txt = _commentCtrl.text.trim();
    if (txt.isEmpty) return;
    await ApiService.instance.addNoteComment(noteId, txt);
    if (!mounted) return;
    _commentCtrl.clear();
    setState(() => _commentingNoteId = null);
    _loadVault();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 10, 6),
          decoration: const BoxDecoration(gradient: AppTheme.navyGradient),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_done_rounded,
                    color: AppTheme.brandPrimary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'คลังรูปภาพ ไฟล์ถาวร & โน้ต — ${widget.conversation.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: PillBadge(
                  text:
                      'เก็บถาวรบน MinIO (bcaichat-storage) · ส่งผิดกดลบทำลายไฟล์ได้ทันที',
                  backgroundColor: Color(0xFF3E1914),
                  textColor: AppTheme.goldClay,
                  icon: Icons.verified_rounded,
                ),
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabCtrl,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
                indicatorColor: AppTheme.brandPrimary,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF94A3B8),
                tabs: [
                  Tab(text: 'รูปภาพ (${_vault.images.length})'),
                  Tab(text: 'ไฟล์เก็บไว้ (${_vault.files.length})'),
                  Tab(text: 'โน้ตประจำห้อง (${_roomNotes.length})'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildImagesGrid(),
                    _buildFilesList(),
                    _buildRoomNotesList(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildImagesGrid() {
    if (_vault.images.isEmpty) {
      return const Center(
        child: Text(
          'ยังไม่มีรูปภาพในคลังของห้องแชทนี้',
          style: TextStyle(color: AppTheme.slateMuted),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _vault.images.length,
      itemBuilder: (ctx, i) {
        final msg = _vault.images[i];
        final url = msg.attachment?.url ?? '';
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url.isNotEmpty)
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.image),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  color: Colors.black54,
                  child: Text(
                    msg.attachment?.fileName ?? msg.cleanContent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilesList() {
    if (_vault.files.isEmpty) {
      return const Center(
        child: Text(
          'ยังไม่มีไฟล์ในคลังถาวรของห้องนี้',
          style: TextStyle(color: AppTheme.slateMuted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _vault.files.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final msg = _vault.files[i];
        final att = msg.attachment;
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.borderSubtle),
          ),
          leading: const Icon(
            Icons.description_rounded,
            color: AppTheme.workBlue,
          ),
          title: Text(
            att?.fileName ?? msg.cleanContent,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
          subtitle: Text(
            'ส่งโดย ${msg.senderName} (${msg.senderDepartment}) · ${formatFileSize(att?.fileSize ?? 0)}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () {
                  final url = att?.url ?? '';
                  final uri = Uri.tryParse(url);
                  if (uri != null) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                tooltip: 'ดาวน์โหลดไฟล์',
                icon: Icon(Icons.download_rounded, color: AppTheme.brandDeep),
              ),
              IconButton(
                onPressed: () async {
                  await ApiService.instance.unsendMessage(msg.id, hard: true);
                  await _loadVault();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppTheme.dangerRed,
                      content: Text(
                        'ลบข้อความและทำลายไฟล์ออกจากเซิร์ฟเวอร์เรียบร้อยแล้ว',
                      ),
                    ),
                  );
                },
                tooltip: 'สั่งลบและทำลายไฟล์ออกจาก MinIO',
                icon: const Icon(
                  Icons.delete_forever_rounded,
                  color: AppTheme.dangerRed,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoomNotesList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'สมุดโน้ตและเรื่องที่คุยกันไว้ในห้อง',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () =>
                    setState(() => _showAddNoteForm = !_showAddNoteForm),
                icon: Icon(
                  _showAddNoteForm ? Icons.close_rounded : Icons.add_rounded,
                  size: 16,
                ),
                label: Text(_showAddNoteForm ? 'ปิด' : 'เพิ่มโน้ตห้อง'),
              ),
            ],
          ),
        ),
        if (_showAddNoteForm)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _noteTitleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'หัวข้อโน้ต',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteContentCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'รายละเอียด / สิ่งที่ตกลงกัน',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _showAddNoteForm = false),
                      child: const Text('ยกเลิก'),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      onPressed: _submitNewRoomNote,
                      child: const Text('บันทึกโน้ต'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: _roomNotes.isEmpty
              ? const Center(
                  child: Text(
                    'ยังไม่มีโน้ตประจำห้องแชทนี้',
                    style: TextStyle(color: AppTheme.slateMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _roomNotes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final note = _roomNotes[i];
                    final myId = ApiService.instance.currentUser?.id ?? '';
                    final liked = note.likedBy.contains(myId);
                    final isCommenting = _commentingNoteId == note.id;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (note.isPinned) ...[
                                const Icon(
                                  Icons.push_pin_rounded,
                                  size: 15,
                                  color: AppTheme.goldPin,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  note.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: note.isPinned
                                    ? 'เลิกปักหมุด'
                                    : 'ปักหมุดโน้ต',
                                iconSize: 18,
                                onPressed: () async {
                                  await ApiService.instance.updateNote(
                                    note.id,
                                    isPinned: !note.isPinned,
                                  );
                                  _loadVault();
                                },
                                icon: Icon(
                                  note.isPinned
                                      ? Icons.push_pin_rounded
                                      : Icons.push_pin_outlined,
                                  color: AppTheme.goldPin,
                                ),
                              ),
                              IconButton(
                                tooltip: 'ลบโน้ต',
                                iconSize: 18,
                                onPressed: () async {
                                  await ApiService.instance.deleteNote(note.id);
                                  _loadVault();
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppTheme.dangerRed,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            note.content,
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  await ApiService.instance.toggleNoteLike(
                                    note.id,
                                  );
                                  _loadVault();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        liked
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                        size: 16,
                                        color: liked
                                            ? AppTheme.brandPrimary
                                            : AppTheme.slateMuted,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${note.likedBy.length}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 14,
                                color: AppTheme.slateMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${note.comments.length} ความคิดเห็น',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.slateMuted,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () => setState(() {
                                  _commentCtrl.clear();
                                  _commentingNoteId =
                                      isCommenting ? null : note.id;
                                }),
                                child: Text(isCommenting ? 'ยกเลิก' : 'คอมเมนต์'),
                              ),
                            ],
                          ),
                          if (isCommenting)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _commentCtrl,
                                      onSubmitted: (_) =>
                                          _submitNoteComment(note.id),
                                      decoration: const InputDecoration(
                                        hintText: 'พิมพ์ความคิดเห็น...',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton(
                                    onPressed: () =>
                                        _submitNoteComment(note.id),
                                    child: const Text('ส่ง'),
                                  ),
                                ],
                              ),
                            ),
                          if (note.comments.isNotEmpty) ...[
                            const Divider(height: 12),
                            ...note.comments.map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '${c.userName}: ${c.content}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.slateBody,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// DeepSeek AI Room Summary Inline Panel
class _AiSummaryPanel extends StatefulWidget {
  final Conversation conversation;
  final VoidCallback onClose;
  final Future<void> Function(String formattedText) onSendToRoom;
  final Future<void> Function(String formattedText) onSaveToNotebook;

  const _AiSummaryPanel({
    super.key,
    required this.conversation,
    required this.onClose,
    required this.onSendToRoom,
    required this.onSaveToNotebook,
  });

  @override
  State<_AiSummaryPanel> createState() => _AiSummaryPanelState();
}

class _AiSummaryPanelState extends State<_AiSummaryPanel> {
  AiSummaryResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runSummarize();
  }

  Future<void> _runSummarize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.instance.summarizeConversation(
        widget.conversation.id,
      );
      if (!mounted) return;
      setState(() {
        _result = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _result;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4C1D95), Color(0xFF1E3A8A)],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFFDE68A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '✨ BC AI สรุปแชทให้เข้าใจไว',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'ห้อง: ${widget.conversation.name} · โมเดล: ${res?.model ?? "deepseek-chat"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFDDD6FE),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
        Flexible(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: AppTheme.personalPurple,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'BC AI กำลังอ่านแชทและสรุปประเด็นสำคัญ...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slateBody,
                        ),
                      ),
                    ],
                  ),
                )
              : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppTheme.dangerRed,
                        size: 36,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.dangerRed),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: _runSummarize,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('ลองใหม่อีกครั้ง'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F3FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFDDD6FE),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 17,
                                  color: AppTheme.personalPurple,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  '📌 สรุปประเด็นสำคัญในห้องแชท',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.personalPurple,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              res?.summary ?? '-',
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: AppTheme.slateDark,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (res != null && res.actionItems.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.brandSoft,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.brandPrimary.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.task_alt_rounded,
                                    size: 17,
                                    color: AppTheme.brandDeep,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '✅ สิ่งที่ต้องทำต่อ:',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.brandDeep,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...res.actionItems.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '• ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.brandDeep,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          item,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.slateDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (res != null && res.decisions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFBFDBFE),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.lightbulb_rounded,
                                    size: 17,
                                    color: AppTheme.workBlue,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    '💡 ข้อสรุปที่คุยกันไว้',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.workBlue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...res.decisions.map(
                                (d) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '• $d',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        if (!_loading && res != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final text = res.toFormattedNote();
                    widget.onClose();
                    await widget.onSaveToNotebook(text);
                  },
                  icon: Icon(
                    Icons.bookmark_add_rounded,
                    size: 17,
                    color: AppTheme.brandDeep,
                  ),
                  label: const Text('บันทึกเข้าสมุดบันทึก BC'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final text = res.toFormattedNote();
                    widget.onClose();
                    await widget.onSendToRoom(text);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.personalPurple,
                  ),
                  icon: const Icon(Icons.send_rounded, size: 17),
                  label: const Text('ส่งสรุปนี้เข้าห้องแชท'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// DeepSeek AI Writing Assistant & Smart Reply Inline Panel
class _AiWritingAssistPanel extends StatefulWidget {
  final Conversation conversation;
  final String initialDraft;
  final String initialMode;
  final VoidCallback onClose;
  final ValueChanged<String> onApplyToComposer;
  final Future<void> Function(String text) onSendImmediately;

  const _AiWritingAssistPanel({
    super.key,
    required this.conversation,
    required this.initialDraft,
    required this.initialMode,
    required this.onClose,
    required this.onApplyToComposer,
    required this.onSendImmediately,
  });

  @override
  State<_AiWritingAssistPanel> createState() => _AiWritingAssistPanelState();
}

class _AiWritingAssistPanelState extends State<_AiWritingAssistPanel> {
  late TextEditingController _draftCtrl;
  late String _mode;
  AiAssistResult? _result;
  bool _loading = false;

  static const List<(String, String, IconData)> _modes = [
    ('polish', 'เกลาให้น่ารัก/สุภาพ', Icons.auto_fix_high_rounded),
    ('suggest_reply', 'แนะนำคำตอบจากแชทล่าสุด', Icons.tips_and_updates_rounded),
    ('action_plan', 'จัดเป็นลิสต์ขั้นตอน', Icons.checklist_rounded),
    ('translate_en', 'แปลเป็นภาษาอังกฤษ', Icons.translate_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _draftCtrl = TextEditingController(text: widget.initialDraft);
    _mode = widget.initialMode;
    _runAssist();
  }

  @override
  void dispose() {
    _draftCtrl.dispose();
    super.dispose();
  }

  // Each mode chip re-runs the AI; a slower earlier reply must not overwrite the
  // answer for the mode the user picked last.
  int _runSeq = 0;

  Future<void> _runAssist() async {
    final seq = ++_runSeq;
    setState(() => _loading = true);
    try {
      final res = await ApiService.instance.requestAiAssist(
        conversationId: widget.conversation.id,
        mode: _mode,
        text: _draftCtrl.text,
      );
      if (!mounted || seq != _runSeq) return;
      setState(() {
        _result = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _runSeq) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('เรียก AI ไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _result;

    return Container(
      constraints: const BoxConstraints(maxHeight: 350),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.psychology_rounded,
                    color: AppTheme.personalPurple,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🪄 ผู้ช่วย BC AI เกลาคำพูด & คิดคำตอบ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      Text(
                        'ช่วยเกลาข้อความ คิดคำตอบให้เพื่อน สรุปลิสต์ หรือแปลภาษาในคลิกเดียว',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.slateMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _modes.map((m) {
                  final active = _mode == m.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      selected: active,
                      selectedColor: const Color(0xFFEDE9FE),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            m.$3,
                            size: 14,
                            color: active
                                ? AppTheme.personalPurple
                                : AppTheme.slateBody,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            m.$2,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: active
                                  ? AppTheme.personalPurple
                                  : AppTheme.slateBody,
                            ),
                          ),
                        ],
                      ),
                      onSelected: (_) {
                        setState(() => _mode = m.$1);
                        _runAssist();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _draftCtrl,
                    onSubmitted: (_) => _runAssist(),
                    decoration: const InputDecoration(
                      labelText:
                          'ข้อความร่างของคุณ (เว้นว่างเพื่อให้ AI อ่านจากแชทล่าสุด)',
                      isDense: true,
                      prefixIcon: Icon(Icons.edit_note_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _runAssist,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.personalPurple,
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: const Text('ให้ AI ช่วยคิด'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.personalPurple,
                  ),
                ),
              )
            else if (res != null && res.suggestion.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDDD6FE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '✨ ข้อความที่ BC AI แนะนำ:',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.personalPurple,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      res.suggestion,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () =>
                              widget.onApplyToComposer(res.suggestion),
                          icon: const Icon(Icons.input_rounded, size: 15),
                          label: const Text('ใส่ช่องพิมพ์'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () =>
                              widget.onSendImmediately(res.suggestion),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandPrimary,
                          ),
                          icon: const Icon(Icons.send_rounded, size: 15),
                          label: const Text('ส่งทันที'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (res.alternatives.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...res.alternatives
                    .take(2)
                    .map(
                      (alt) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => widget.onApplyToComposer(alt),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppTheme.borderSubtle,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    alt,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const Icon(
                                  Icons.north_west_rounded,
                                  size: 14,
                                  color: AppTheme.personalPurple,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _RoomAlbumsPanel extends StatefulWidget {
  final Conversation conversation;
  final VoidCallback onClose;

  const _RoomAlbumsPanel({
    super.key,
    required this.conversation,
    required this.onClose,
  });

  @override
  State<_RoomAlbumsPanel> createState() => _RoomAlbumsPanelState();
}

class _RoomAlbumsPanelState extends State<_RoomAlbumsPanel> {
  List<AlbumItem> _albums = const [];
  bool _loading = true;
  bool _showCreateForm = false;
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.instance.fetchAlbums(
        widget.conversation.id,
      );
      if (!mounted) return;
      setState(() {
        _albums = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<AttachmentInfo>> _pickPhotos() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return const [];
    final out = <AttachmentInfo>[];
    for (final picked in files) {
      final bytes = await picked.readAsBytes();
      final ext = (picked.extension ?? 'png').toLowerCase();
      final mime = ext == 'jpg' ? 'image/jpeg' : 'image/$ext';
      final att = await ApiService.instance.uploadFileBase64(
        fileName: picked.name,
        mimeType: mime,
        dataBase64: base64Encode(bytes),
      );
      out.add(att);
    }
    return out;
  }

  Future<void> _submitCreateAlbum() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    try {
      final photos = await _pickPhotos();
      await ApiService.instance.createAlbum(
        widget.conversation.id,
        title: title,
        description: _descCtrl.text.trim(),
        photos: photos,
      );
      if (!mounted) return;
      _titleCtrl.clear();
      _descCtrl.clear();
      setState(() => _showCreateForm = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('สร้างอัลบั้มไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: const BoxDecoration(gradient: AppTheme.navyGradient),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.photo_library_rounded, color: AppTheme.goldClay),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'อัลบั้มรูปภาพ — ${widget.conversation.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () =>
                    setState(() => _showCreateForm = !_showCreateForm),
                icon: Icon(
                  _showCreateForm
                      ? Icons.close_rounded
                      : Icons.add_photo_alternate_rounded,
                  size: 15,
                ),
                label: Text(_showCreateForm ? 'ปิด' : 'สร้างอัลบั้ม'),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
        if (_showCreateForm)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ชื่ออัลบั้ม (เช่น ทริปเชียงใหม่)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'คำอธิบาย (ไม่บังคับ)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _showCreateForm = false),
                      child: const Text('ยกเลิก'),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      onPressed: _submitCreateAlbum,
                      child: const Text('เลือกรูป & สร้าง'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _albums.isEmpty
              ? const Center(
                  child: Text(
                    'ยังไม่มีอัลบั้มรูปภาพ กดปุ่ม "สร้างอัลบั้ม" ด้านบนเพื่อเก็บรูปถาวร',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.slateMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _albums.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final alb = _albums[i];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${alb.title} (${alb.photos.length} รูป)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  try {
                                    final photos = await _pickPhotos();
                                    if (photos.isEmpty) return;
                                    await ApiService.instance.addAlbumPhotos(
                                      alb.id,
                                      photos,
                                    );
                                    await _load();
                                  } catch (_) {}
                                },
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('เพิ่มรูป'),
                              ),
                              IconButton(
                                onPressed: () async {
                                  await ApiService.instance.deleteAlbum(alb.id);
                                  await _load();
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppTheme.dangerRed,
                                ),
                              ),
                            ],
                          ),
                          if (alb.description.isNotEmpty)
                            Text(
                              alb.description,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.slateMuted,
                              ),
                            ),
                          if (alb.photos.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 92,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: alb.photos.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, pIdx) {
                                  final photo = alb.photos[pIdx];
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(
                                      photo.url,
                                      width: 92,
                                      height: 92,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stack) =>
                                          Container(
                                            width: 92,
                                            height: 92,
                                            color: AppTheme.borderSubtle,
                                            child: const Icon(Icons.image),
                                          ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RoomEventsPanel extends StatefulWidget {
  final Conversation conversation;
  final VoidCallback onClose;
  final ValueChanged<ChatMessage> onEventCreated;

  const _RoomEventsPanel({
    super.key,
    required this.conversation,
    required this.onClose,
    required this.onEventCreated,
  });

  @override
  State<_RoomEventsPanel> createState() => _RoomEventsPanelState();
}

class _RoomEventsPanelState extends State<_RoomEventsPanel> {
  List<ChatMessage> _events = const [];
  bool _loading = true;
  bool _showCreateForm = false;
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _locCtrl =
      TextEditingController(text: 'คาเฟ่ / ออนไลน์');
  final TextEditingController _descCtrl = TextEditingController();
  DateTime _pickedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _pickedTime = const TimeOfDay(hour: 10, minute: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.instance.fetchEvents(
        widget.conversation.id,
      );
      if (!mounted) return;
      setState(() {
        _events = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitCreateEvent() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final startsAt = DateTime(
      _pickedDate.year,
      _pickedDate.month,
      _pickedDate.day,
      _pickedTime.hour,
      _pickedTime.minute,
    ).toUtc().toIso8601String();
    try {
      final created = await ApiService.instance.createEvent(
        widget.conversation.id,
        title: title,
        description: _descCtrl.text.trim(),
        startsAt: startsAt,
        location: _locCtrl.text.trim(),
      );
      if (!mounted) return;
      _titleCtrl.clear();
      _descCtrl.clear();
      setState(() => _showCreateForm = false);
      widget.onEventCreated(created);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('สร้างนัดหมายไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = ApiService.instance.currentUser?.id ?? '';
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: const BoxDecoration(gradient: AppTheme.navyGradient),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.event_available_rounded, color: AppTheme.goldClay),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'นัดหมาย & กิจกรรม — ${widget.conversation.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () =>
                    setState(() => _showCreateForm = !_showCreateForm),
                icon: Icon(
                  _showCreateForm ? Icons.close_rounded : Icons.add_rounded,
                  size: 15,
                ),
                label: Text(_showCreateForm ? 'ปิด' : 'สร้างนัดหมาย'),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
        if (_showCreateForm)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'หัวข้อนัดหมาย (เช่น นัดทานข้าวเย็นวันเสาร์)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _locCtrl,
                  decoration: const InputDecoration(
                    labelText: 'สถานที่ / ลิงก์วิดีโอคอล',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'รายละเอียดเพิ่มเติม',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _pickedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (d != null && mounted) {
                            setState(() => _pickedDate = d);
                          }
                        },
                        icon: const Icon(Icons.calendar_today_rounded, size: 15),
                        label: Text(
                          '${_pickedDate.day}/${_pickedDate.month}/${_pickedDate.year}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: _pickedTime,
                          );
                          if (t != null && mounted) {
                            setState(() => _pickedTime = t);
                          }
                        },
                        icon: const Icon(Icons.access_time_rounded, size: 15),
                        label: Text(
                          '${_pickedTime.hour.toString().padLeft(2, '0')}:${_pickedTime.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _showCreateForm = false),
                      child: const Text('ยกเลิก'),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      onPressed: _submitCreateEvent,
                      child: const Text('ส่งนัดหมายเข้าห้อง'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _events.isEmpty
              ? const Center(
                  child: Text(
                    'ยังไม่มีนัดหมายในห้องนี้ กดปุ่ม "สร้างนัดหมาย" ด้านบนเพื่อส่งเชิญเพื่อน',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.slateMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _events.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final msg = _events[i];
                    final ev = msg.eventData;
                    if (ev == null) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ev.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '🕒 ${formatThaiTime(ev.startsAt)}  📍 ${ev.location}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.slateBody,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: Text('ไป (${ev.goingIds.length})'),
                                selected: ev.goingIds.contains(myId),
                                onSelected: (_) async {
                                  await ApiService.instance.rsvpEvent(
                                    msg.id,
                                    'going',
                                  );
                                  _load();
                                },
                              ),
                              ChoiceChip(
                                label: Text('อาจจะ (${ev.maybeIds.length})'),
                                selected: ev.maybeIds.contains(myId),
                                onSelected: (_) async {
                                  await ApiService.instance.rsvpEvent(
                                    msg.id,
                                    'maybe',
                                  );
                                  _load();
                                },
                              ),
                              ChoiceChip(
                                label: Text(
                                  'ไม่ไป (${ev.notGoingIds.length})',
                                ),
                                selected: ev.notGoingIds.contains(myId),
                                onSelected: (_) async {
                                  await ApiService.instance.rsvpEvent(
                                    msg.id,
                                    'not_going',
                                  );
                                  _load();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _InlineCreatePollPanel extends StatefulWidget {
  final String conversationId;
  final VoidCallback onClose;
  final ValueChanged<ChatMessage> onCreated;

  const _InlineCreatePollPanel({
    required this.conversationId,
    required this.onClose,
    required this.onCreated,
  });

  @override
  State<_InlineCreatePollPanel> createState() => _InlineCreatePollPanelState();
}

class _InlineCreatePollPanelState extends State<_InlineCreatePollPanel> {
  final TextEditingController _questionCtrl = TextEditingController();
  final List<TextEditingController> _optCtrls = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _allowMultiple = false;
  bool _isAnonymous = false;
  bool _submitting = false;

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final c in _optCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final q = _questionCtrl.text.trim();
    final opts = _optCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (q.isEmpty || opts.length < 2 || _submitting) return;
    setState(() => _submitting = true);
    try {
      final sent = await ApiService.instance.createPoll(
        widget.conversationId,
        question: q,
        options: opts,
        allowMultiple: _allowMultiple,
        isAnonymous: _isAnonymous,
      );
      if (!mounted) return;
      widget.onCreated(sent);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('สร้างโพลไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
          decoration: const BoxDecoration(gradient: AppTheme.navyGradient),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.poll_rounded, color: AppTheme.goldClay),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'สร้างโพลโหวตในห้องแชท',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _questionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'หัวข้อ / คำถามโพล (เช่น เย็นนี้กินอะไรดี?)',
                    prefixIcon: Icon(Icons.poll_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                ...List.generate(_optCtrls.length, (idx) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _optCtrls[idx],
                            decoration: InputDecoration(
                              labelText: 'ตัวเลือกที่ ${idx + 1}',
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_optCtrls.length > 2)
                          IconButton(
                            onPressed: () {
                              final removed = _optCtrls.removeAt(idx);
                              removed.dispose();
                              setState(() {});
                            },
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                      ],
                    ),
                  );
                }),
                if (_optCtrls.length < 6)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(
                        () => _optCtrls.add(TextEditingController()),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('เพิ่มตัวเลือก'),
                    ),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allowMultiple,
                  onChanged: (v) =>
                      setState(() => _allowMultiple = v ?? false),
                  title: const Text('อนุญาตให้เลือกหลายข้อ'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isAnonymous,
                  onChanged: (v) => setState(() => _isAnonymous = v ?? false),
                  title: const Text('โหวตแบบไม่ระบุชื่อ'),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: widget.onClose,
                      child: const Text('ยกเลิก'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      child: const Text('ส่งโพลเข้าห้อง'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineGroupManagePanel extends StatefulWidget {
  final Conversation conversation;
  final List<AppUser> friends;
  final bool isEmbedded;
  final VoidCallback onClose;
  final Future<void> Function(bool muted) onToggleMute;
  final Future<void> Function(bool archived) onToggleArchive;
  final ValueChanged<Conversation> onConversationChanged;
  final VoidCallback onConversationLeft;

  const _InlineGroupManagePanel({
    required this.conversation,
    required this.friends,
    required this.isEmbedded,
    required this.onClose,
    required this.onToggleMute,
    required this.onToggleArchive,
    required this.onConversationChanged,
    required this.onConversationLeft,
  });

  @override
  State<_InlineGroupManagePanel> createState() =>
      _InlineGroupManagePanelState();
}

class _InlineGroupManagePanelState extends State<_InlineGroupManagePanel> {
  final Set<String> _selectedToAdd = <String>{};
  late bool _muted;
  late bool _archived;

  @override
  void initState() {
    super.initState();
    _muted = widget.conversation.isMuted;
    _archived = widget.conversation.isArchived;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ApiService.instance.currentUser;
    final meId = currentUser?.id ?? '';
    final conv = widget.conversation;
    final hasAi = conv.memberIds.contains('user_ai');
    final candidateFriends = widget.friends
        .where((f) => !conv.memberIds.contains(f.id) && f.id != meId)
        .toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
          decoration: const BoxDecoration(gradient: AppTheme.navyGradient),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.tune_rounded, color: AppTheme.goldClay),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  conv.isGroup
                      ? 'จัดการกลุ่ม & ตั้งค่าห้องแชท'
                      : 'ตั้งค่าห้องแชท',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.notifications_off_outlined),
                  title: const Text('ปิดเสียงแจ้งเตือนห้องนี้'),
                  value: _muted,
                  onChanged: (v) async {
                    setState(() => _muted = v);
                    await widget.onToggleMute(v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.inventory_2_outlined),
                  title: const Text('เก็บห้องแชทเข้าถาวร (Archive)'),
                  value: _archived,
                  onChanged: (v) async {
                    setState(() => _archived = v);
                    await widget.onToggleArchive(v);
                  },
                ),
                if (conv.isGroup) ...[
                  const Divider(),
                  if (conv.inviteToken.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.brandSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'รหัสเชิญเข้ากลุ่ม (Invite Token)',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.slateMuted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                SelectableText(
                                  conv.inviteToken,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.brandDeep,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: conv.inviteToken),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('คัดลอกรหัสเชิญเข้ากลุ่มแล้ว'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 15),
                            label: const Text('คัดลอก'),
                          ),
                        ],
                      ),
                    ),
                  if (!hasAi)
                    ElevatedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final updated = await ApiService.instance
                              .addConversationMembers(conv.id, ['user_ai']);
                          if (!mounted) return;
                          widget.onConversationChanged(updated);
                          widget.onClose();
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'เชิญ 🤖 BC AI เข้ากลุ่มเรียบร้อยแล้ว!',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text('เชิญ AI ไม่สำเร็จ: $e')),
                          );
                        }
                      },
                      icon: const Icon(Icons.psychology_rounded),
                      label: const Text('เชิญ 🤖 BC AI เข้ากลุ่ม'),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.psychology_rounded,
                            color: AppTheme.personalPurple,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '🤖 BC AI อยู่ในกลุ่มนี้แล้ว (พิมพ์ @ai ถามได้ทันที)',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.personalPurple,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'สมาชิกในกลุ่ม (${conv.memberCount} คน)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slateDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: conv.memberIds.map((mid) {
                      if (mid == 'user_ai') {
                        return const Chip(label: Text('🤖 BC AI'));
                      }
                      if (mid == meId && currentUser != null) {
                        return Chip(
                          label: Text('${currentUser.displayName} (คุณ)'),
                        );
                      }
                      final matched = widget.friends
                          .where((f) => f.id == mid)
                          .toList();
                      final label = matched.isNotEmpty
                          ? matched.first.displayName
                          : mid;
                      return Chip(label: Text(label));
                    }).toList(),
                  ),
                  if (candidateFriends.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'เชิญเพื่อนเข้ากลุ่มเพิ่ม:',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: candidateFriends.map((f) {
                        final picked = _selectedToAdd.contains(f.id);
                        return FilterChip(
                          label: Text(f.displayName),
                          selected: picked,
                          onSelected: (v) => setState(() {
                            if (v) {
                              _selectedToAdd.add(f.id);
                            } else {
                              _selectedToAdd.remove(f.id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    if (_selectedToAdd.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final updated = await ApiService.instance
                                .addConversationMembers(
                                  conv.id,
                                  _selectedToAdd.toList(),
                                );
                            if (!mounted) return;
                            widget.onConversationChanged(updated);
                            widget.onClose();
                          } catch (e) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('เชิญสมาชิกไม่สำเร็จ: $e'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: Text(
                          'เชิญเพื่อนที่เลือก (${_selectedToAdd.length} คน)',
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.dangerRed,
                      side: const BorderSide(color: AppTheme.dangerRed),
                    ),
                    onPressed: () async {
                      if (meId.isEmpty) return;
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await ApiService.instance.removeConversationMember(
                          conv.id,
                          meId,
                        );
                        if (!mounted) return;
                        widget.onConversationLeft();
                      } catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('ออกจากกลุ่มไม่สำเร็จ: $e'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.exit_to_app_rounded),
                    label: const Text('ออกจากกลุ่มนี้'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
