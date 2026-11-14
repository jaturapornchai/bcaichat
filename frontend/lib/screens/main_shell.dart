import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import 'chat_room_screen.dart';
import 'mini_app_runner_screen.dart';

class MainShell extends StatefulWidget {
  final AppUser currentUser;
  final VoidCallback onLoggedOut;
  final ValueChanged<AppUser> onUserChanged;

  const MainShell({
    super.key,
    required this.currentUser,
    required this.onLoggedOut,
    required this.onUserChanged,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 1; // Mobile-first: land directly on Chats tab
  String _selectedChatFolder = 'all';

  late AppUser _user;
  List<AppUser> _friends = const [];
  List<Conversation> _conversations = const [];
  List<MiniAppItem> _miniApps = const [];
  List<NoteItem> _notebookNotes = const [];
  AdminOverview? _adminOverview;
  List<AppUser> _adminUsers = const [];
  bool _showHiddenFriends = false;

  // Inline collapsible panels (avoid modal popups)
  String? _homeInlinePanel; // 'qr' | 'profile' | 'add_friend' | 'join_group' | 'create_group'
  String? _chatInlinePanel; // 'notif' | 'join_group' | 'create_group'
  bool _showCreateNoteInline = false;
  bool _showMiniAppFormInline = false;
  MiniAppItem? _editingMiniApp;

  AiAdminSettings _aiSettings = const AiAdminSettings(
    model: 'deepseek-chat',
    maskedKey: 'ตั้งค่าบนเซิร์ฟเวอร์แล้ว',
    hasKey: true,
    systemPrompt:
        'คุณคือ BC AI ผู้ช่วยส่วนตัวประจำทุกห้องแชทของ BC Ai Chat ช่วยคิดคำตอบ เกลาข้อความ สรุปนัดหมาย และช่วยวางแผนกับครอบครัวและเพื่อนๆ อย่างเป็นกันเอง',
    enabled: true,
  );

  Conversation? _activeConversation;
  bool _isLoadingInitial = true;

  // Global search in Chats tab
  final TextEditingController _chatSearchCtrl = TextEditingController();
  String _chatSearchQuery = '';
  List<ChatMessage> _globalSearchResults = const [];
  bool _isSearchingGlobal = false;

  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    _user = widget.currentUser;
    _loadAllData().then(
      (_) => PushService.instance.listenForOpens(_openConversationById),
    );
    _wsSub = ApiService.instance.wsEvents.listen((event) {
      _refreshConversationsAndFriends();
      final convId = event['conversation_id']?.toString();
      NotificationService.instance.handleWsEvent(
        event,
        myUserId: _user.id,
        room: _conversations.where((c) => c.id == convId).firstOrNull,
      );
    });
    NotificationService.instance.onOpenConversation = _openConversationById;
    NotificationService.instance.init();
    PushService.instance.start();
  }

  /// Tap on a message pop-up: bring that room on screen.
  void _openConversationById(String conversationId) {
    if (!mounted) return;
    final conv = _conversations
        .where((c) => c.id == conversationId)
        .firstOrNull;
    if (conv == null) return;
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    if (!isWide) Navigator.of(context).popUntil((route) => route.isFirst);
    _selectConversation(conv, isWide: isWide);
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser.id != widget.currentUser.id) {
      _user = widget.currentUser;
      _activeConversation = null;
      _loadAllData();
      PushService.instance.start();
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    if (NotificationService.instance.onOpenConversation ==
        _openConversationById) {
      NotificationService.instance.onOpenConversation = null;
    }
    _chatSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoadingInitial = true);
    try {
      final results = await Future.wait([
        ApiService.instance.fetchFriends(),
        ApiService.instance.fetchConversations(folder: 'all'),
        ApiService.instance.fetchMiniApps(),
        ApiService.instance.fetchNotes(),
      ]);

      final friends = results[0] as List<AppUser>;
      final convs = results[1] as List<Conversation>;
      final apps = results[2] as List<MiniAppItem>;
      final notes = results[3] as List<NoteItem>;

      if (!mounted) return;
      setState(() {
        _friends = friends;
        _conversations = convs;
        _miniApps = apps;
        _notebookNotes = notes;
        if (_activeConversation != null) {
          final updatedActive = convs
              .where((c) => c.id == _activeConversation!.id)
              .toList();
          if (updatedActive.isNotEmpty) {
            _activeConversation = updatedActive.first;
          }
        } else if (convs.isNotEmpty) {
          _activeConversation = convs.first;
        }
        _isLoadingInitial = false;
      });

      _loadAdminDataQuietly();
    } catch (_) {
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  Future<void> _refreshConversationsAndFriends() async {
    try {
      final results = await Future.wait([
        ApiService.instance.fetchConversations(folder: 'all'),
        ApiService.instance.fetchFriends(),
        ApiService.instance.fetchMiniApps(),
      ]);
      if (!mounted) return;
      final convs = results[0] as List<Conversation>;
      setState(() {
        _conversations = convs;
        _friends = results[1] as List<AppUser>;
        _miniApps = results[2] as List<MiniAppItem>;
        if (_activeConversation != null) {
          final match = convs
              .where((c) => c.id == _activeConversation!.id)
              .toList();
          if (match.isNotEmpty) {
            _activeConversation = match.first;
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _loadAdminDataQuietly() async {
    try {
      final results = await Future.wait([
        ApiService.instance.fetchAdminOverview(),
        ApiService.instance.fetchAdminUsers(),
        ApiService.instance.fetchAdminMiniApps(),
        ApiService.instance.fetchAdminAiSettings(),
      ]);
      if (!mounted) return;
      setState(() {
        _adminOverview = results[0] as AdminOverview?;
        _adminUsers = results[1] as List<AppUser>;
        final adminApps = results[2] as List<MiniAppItem>;
        if (adminApps.isNotEmpty) {
          _miniApps = adminApps;
        }
        _aiSettings = results[3] as AiAdminSettings;
      });
    } catch (_) {}
  }

  Future<void> _performGlobalSearch(String query) async {
    setState(() => _chatSearchQuery = query);
    if (query.trim().length < 2) {
      setState(() {
        _globalSearchResults = const [];
        _isSearchingGlobal = false;
      });
      return;
    }
    setState(() => _isSearchingGlobal = true);
    try {
      final found = await ApiService.instance.searchMessages(query);
      if (!mounted) return;
      setState(() {
        _globalSearchResults = found;
        _isSearchingGlobal = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isSearchingGlobal = false);
    }
  }

  int get _totalUnreadCount {
    return _conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
  }

  List<Conversation> get _filteredConversations {
    final q = _chatSearchQuery.trim().toLowerCase();
    return _conversations.where((c) {
      final archived = c.isArchived || c.folder == 'archived';
      if (_selectedChatFolder == 'archived') {
        if (!archived) return false;
      } else {
        if (archived) return false;
      }
      if (_selectedChatFolder == 'personal' && c.folder != 'personal') {
        return false;
      }
      if (_selectedChatFolder == 'family' && !c.isFamily) {
        return false;
      }
      if (_selectedChatFolder == 'group' && !c.isGroup) {
        return false;
      }
      if (_selectedChatFolder == 'pinned' && !c.isPinned) {
        return false;
      }
      if (_selectedChatFolder == 'unread' && c.unreadCount <= 0) {
        return false;
      }
      if (q.isNotEmpty) {
        final matchName = c.name.toLowerCase().contains(q);
        final matchLast =
            c.lastMessage?.previewText.toLowerCase().contains(q) ?? false;
        return matchName || matchLast;
      }
      return true;
    }).toList();
  }

  void _selectConversation(Conversation conv, {required bool isWide}) {
    setState(() {
      _activeConversation = conv;
      if (isWide && _selectedIndex != 0 && _selectedIndex != 1) {
        _selectedIndex = 1;
      }
    });
    if (!isWide) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            conversation: conv,
            allConversations: _conversations,
            friends: _friends,
            miniApps: _miniApps.where((m) => m.enabled).toList(),
            isEmbedded: false,
            onConversationUpdated: _refreshConversationsAndFriends,
            onConversationLeft: () {
              if (mounted && _activeConversation?.id == conv.id) {
                setState(() => _activeConversation = null);
              }
              _refreshConversationsAndFriends();
            },
          ),
        ),
      );
    }
  }

  Future<void> _openChatWithFriend(
    AppUser friend, {
    required bool isWide,
  }) async {
    try {
      final conv = await ApiService.instance.openDirectConversation(friend.id);
      await _refreshConversationsAndFriends();
      if (!mounted) return;
      _selectConversation(conv, isWide: isWide);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ไม่สามารถเปิดห้องสนทนาได้: $e')));
    }
  }

  void _openMiniApp(MiniAppItem app) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MiniAppRunnerScreen(
          miniApp: app,
          conversations: _conversations,
          initialConversationId: _activeConversation?.id,
          onCardSent: (_) => _refreshConversationsAndFriends(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Inline Collapsible Panels: My QR Code, Edit Profile, Add Friend, Groups
  // ---------------------------------------------------------------------------
  void _toggleHomePanel(String panel) {
    setState(() {
      _homeInlinePanel = _homeInlinePanel == panel ? null : panel;
    });
  }

  void _toggleChatPanel(String panel) {
    setState(() {
      _chatInlinePanel = _chatInlinePanel == panel ? null : panel;
    });
  }

  Widget _buildInlinePanelWrapper({
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: AppTheme.brandPrimary.withValues(alpha: 0.35),
        ),
        boxShadow: AppTheme.shadowMd,
      ),
      child: child,
    );
  }

  Widget _buildInlineQrCard() {
    final qrData = _user.qrToken.isNotEmpty
        ? _user.qrToken
        : 'bcaichat://add/${_user.bcId.isNotEmpty ? _user.bcId : _user.email}';

    return _buildInlinePanelWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text(
                  'QR Code เพิ่มเพื่อนของฉัน',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slateDark,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _homeInlinePanel = null),
                icon: const Icon(Icons.close_rounded, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.brandPrimary.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 168,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppTheme.slateDark,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'QR Token: $qrData',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: qrData));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('คัดลอก QR Token เรียบร้อยแล้ว'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  tooltip: 'คัดลอก QR Token',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveInlinePanel(
    String? active, {
    required bool isWide,
    required VoidCallback onClose,
  }) {
    switch (active) {
      case 'qr':
        return _buildInlineQrCard();
      case 'profile':
        return _buildInlinePanelWrapper(
          child: _InlineEditProfilePanel(
            user: _user,
            onCancel: onClose,
            onSaved: (updated) {
              setState(() {
                _user = updated;
                _homeInlinePanel = null;
              });
              widget.onUserChanged(updated);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.brandDeep,
                  content: const Text('บันทึกโปรไฟล์และ BC ID เรียบร้อยแล้ว'),
                ),
              );
            },
          ),
        );
      case 'add_friend':
        return _buildInlinePanelWrapper(
          child: _InlineAddFriendPanel(
            onCancel: onClose,
            onAddedFriend: (u) async {
              onClose();
              await _refreshConversationsAndFriends();
              if (u != null && mounted) {
                await _openChatWithFriend(u, isWide: isWide);
              }
            },
          ),
        );
      case 'join_group':
        return _buildInlinePanelWrapper(
          child: _InlineJoinGroupPanel(
            onCancel: onClose,
            onJoined: (conv) async {
              onClose();
              await _refreshConversationsAndFriends();
              if (mounted) {
                _selectConversation(conv, isWide: isWide);
              }
            },
          ),
        );
      case 'create_group':
        return _buildInlinePanelWrapper(
          child: _InlineCreateGroupPanel(
            friends: _friends,
            onCancel: onClose,
            onCreated: (conv) async {
              onClose();
              await _refreshConversationsAndFriends();
              if (mounted) {
                _selectConversation(conv, isWide: isWide);
              }
            },
          ),
        );
      case 'notif':
        return _buildInlinePanelWrapper(
          child: _InlineNotificationPanel(onClose: onClose),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------------------------
  // Build Responsive Shell
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            _buildDesktopNavRail(),
            if (_selectedIndex == 0 || _selectedIndex == 1) ...[
              SizedBox(
                width: 390,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      right: BorderSide(color: AppTheme.borderSubtle),
                    ),
                    boxShadow: AppTheme.shadowSm,
                  ),
                  child: AnimatedSwitcher(
                    duration: AppTheme.motionMed,
                    transitionBuilder: AppTheme.fadeSlideTransition,
                    child: KeyedSubtree(
                      key: ValueKey('list-$_selectedIndex'),
                      child: _selectedIndex == 0
                          ? _buildHomeTab(isWide: true)
                          : _buildChatsTab(isWide: true),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppTheme.motionMed,
                  transitionBuilder: AppTheme.fadeSlideTransition,
                  child: _activeConversation != null
                      ? ChatRoomScreen(
                          key: ValueKey('room-${_activeConversation!.id}'),
                          conversation: _activeConversation!,
                          allConversations: _conversations,
                          friends: _friends,
                          miniApps: _miniApps.where((m) => m.enabled).toList(),
                          isEmbedded: true,
                          onConversationUpdated:
                              _refreshConversationsAndFriends,
                          onConversationLeft: () {
                            setState(() => _activeConversation = null);
                            _refreshConversationsAndFriends();
                          },
                          onThemeChanged: (_) => setState(() {}),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('room-empty'),
                          child: _buildEmptyChatPlaceholder(),
                        ),
                ),
              ),
            ] else
              Expanded(child: _buildSelectedTabBody(isWide: true)),
          ],
        ),
      );
    }

    // Mobile / Narrow Layout
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: AppTheme.motionMed,
          transitionBuilder: AppTheme.fadeSlideTransition,
          child: KeyedSubtree(
            key: ValueKey('tab-$_selectedIndex'),
            child: _buildSelectedTabBody(isWide: false),
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
          boxShadow: [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 18,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex.clamp(0, 3),
          onDestinationSelected: (idx) {
            setState(() => _selectedIndex = idx);
            if (idx == 2) _reloadNotebookNotes();
            if (idx == 3 && _user.isAdmin) _loadAdminDataQuietly();
          },
          backgroundColor: Colors.white,
          indicatorColor: AppTheme.brandSoft,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: AppTheme.brandDeep),
              label: 'หน้าหลัก',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _totalUnreadCount > 0,
                backgroundColor: AppTheme.brandPrimary,
                label: Text('$_totalUnreadCount'),
                child: const Icon(Icons.chat_bubble_outline_rounded),
              ),
              selectedIcon: Badge(
                isLabelVisible: _totalUnreadCount > 0,
                backgroundColor: AppTheme.brandPrimary,
                label: Text('$_totalUnreadCount'),
                child: Icon(
                  Icons.chat_bubble_rounded,
                  color: AppTheme.brandDeep,
                ),
              ),
              label: 'แชท',
            ),
            NavigationDestination(
              icon: const Icon(Icons.bookmark_border_rounded),
              selectedIcon: Icon(
                Icons.bookmark_rounded,
                color: AppTheme.brandDeep,
              ),
              label: 'สมุดบันทึก',
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: Icon(
                Icons.settings_rounded,
                color: AppTheme.brandDeep,
              ),
              label: 'ตั้งค่า',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedTabBody({required bool isWide}) {
    switch (_selectedIndex) {
      case 0:
        return _buildHomeTab(isWide: isWide);
      case 1:
        return _buildChatsTab(isWide: isWide);
      case 2:
        return _buildNotebookVaultTab();
      case 3:
        return _buildSettingsAndToolsTab();
      default:
        return _buildChatsTab(isWide: isWide);
    }
  }

  Widget _buildDesktopNavRail() {
    final navItems = [
      (0, Icons.home_rounded, 'หน้าหลัก', 0),
      (1, Icons.chat_bubble_rounded, 'แชท', _totalUnreadCount),
      (2, Icons.bookmark_rounded, 'สมุดบันทึก', 0),
      (3, Icons.settings_rounded, 'ตั้งค่า', 0),
    ];
    const idleColor = Color(0xFF94A3B8);

    return Container(
      width: 84,
      decoration: const BoxDecoration(gradient: AppTheme.navyGradient),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            onTap: () => setState(() {
              _selectedIndex = 0;
              _homeInlinePanel = 'profile';
            }),
            borderRadius: BorderRadius.circular(999),
            child: UserAvatar(
              name: _user.displayName,
              avatarUrl: _user.avatarUrl,
              radius: 21,
              showOnline: true,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.brandPrimary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'BC Ai Chat',
              maxLines: 1,
              style: TextStyle(
                color: AppTheme.goldClay,
                fontSize: 9.5,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Column(
              children: navItems.map((item) {
                final idx = item.$1;
                final icon = item.$2;
                final label = item.$3;
                final badgeCount = item.$4;
                final selected = _selectedIndex == idx;
                final fg = selected ? Colors.white : idleColor;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      hoverColor: Colors.white.withValues(alpha: 0.08),
                      onTap: () {
                        setState(() => _selectedIndex = idx);
                        if (idx == 2) _reloadNotebookNotes();
                        if (idx == 3 && _user.isAdmin) _loadAdminDataQuietly();
                      },
                      child: AnimatedContainer(
                        duration: AppTheme.motionMed,
                        curve: AppTheme.motionCurve,
                        width: 68,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          gradient: selected ? AppTheme.brandGradient : null,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          boxShadow: selected
                              ? AppTheme.glow(AppTheme.brandPrimary)
                              : const [],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Badge(
                              isLabelVisible: badgeCount > 0,
                              backgroundColor: AppTheme.dangerRed,
                              label: Text('$badgeCount'),
                              child: Icon(icon, color: fg, size: 22),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: fg,
                                fontSize: 10.5,
                                height: 1.35,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          IconButton(
            onPressed: () => setState(() {
              _selectedIndex = 0;
              _homeInlinePanel = 'qr';
            }),
            tooltip: 'QR Code ของฉัน',
            icon: const Icon(Icons.qr_code_2_rounded, color: Color(0xFFCBD5E1)),
          ),
          IconButton(
            onPressed: widget.onLoggedOut,
            tooltip: 'สลับบัญชี Gmail / ออกจากระบบ',
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFF87171)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChatPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.surfaceBg, AppTheme.brandSoft],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          boxShadow: AppTheme.shadowLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                shape: BoxShape.circle,
                boxShadow: AppTheme.glow(AppTheme.brandPrimary),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 34,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'เลือกห้องแชทหรือเพื่อนด้านซ้ายเพื่อเริ่มสนทนา',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'ซิงค์แชทข้ามเครื่องด้วย Gmail · ไฟล์และรูปภาพเก็บถาวรบน MinIO ไม่หมดอายุ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppTheme.slateMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 0: หน้าหลัก (HOME — โปรไฟล์, QR, เพิ่มเพื่อน, บริการเสริม, กลุ่ม & เพื่อน)
  // ---------------------------------------------------------------------------
  /// หัวข้อส่วน (titleMedium w700 + คำอธิบายจาง ๆ) ใช้ร่วมทุกแท็บ
  Widget _sectionHeader(
    String title, {
    String? subtitle,
    Widget? trailing,
    EdgeInsetsGeometry padding = const EdgeInsets.only(bottom: 12),
  }) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppTheme.slateMuted,
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// ปุ่มลัด: ไอคอนในกรอบมนสีอ่อน + ป้ายชื่อ อยู่กึ่งกลาง
  Widget _quickActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: AppTheme.borderSubtle),
            boxShadow: AppTheme.shadowSm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTab({required bool isWide}) {
    final groups = _conversations.where((c) => c.isGroup).toList();
    final officials = _conversations.where((c) => c.isOfficial).toList();
    final enabledMiniApps = _miniApps.where((m) => m.enabled).toList();

    return Column(
      children: [
        // Top Header
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'หน้าหลัก',
                style: TextStyle(
                  fontSize: 20,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slateDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PillBadge(
                    text: 'Gmail Cloud Sync',
                    backgroundColor: AppTheme.brandSoft,
                    textColor: AppTheme.brandDeep,
                    icon: Icons.cloud_done_rounded,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _toggleHomePanel('add_friend'),
                tooltip: 'เพิ่มเพื่อนด้วย BC ID / Gmail / QR',
                icon: Icon(
                  Icons.person_add_alt_1_rounded,
                  color: _homeInlinePanel == 'add_friend'
                      ? AppTheme.brandPrimary
                      : AppTheme.slateDark,
                ),
              ),
              IconButton(
                onPressed: () => _toggleHomePanel('create_group'),
                tooltip: 'สร้างกลุ่มแชทใหม่',
                icon: Icon(
                  Icons.group_add_rounded,
                  color: _homeInlinePanel == 'create_group'
                      ? AppTheme.brandPrimary
                      : AppTheme.slateDark,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // My Profile Card (hero)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.navyGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  boxShadow: AppTheme.shadowMd,
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        UserAvatar(
                          name: _user.displayName,
                          avatarUrl: _user.avatarUrl,
                          radius: 24,
                          showOnline: true,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _user.displayName,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        height: 1.35,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  PillBadge(
                                    text: _user.department,
                                    backgroundColor: AppTheme.brandPrimary
                                        .withValues(alpha: 0.25),
                                    textColor: AppTheme.goldClay,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'BC ID: @${_user.bcId} · ${_user.email}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.goldClay,
                                  fontSize: 12,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _user.statusMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFCBD5E1),
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: ElevatedButton.icon(
                              onPressed: () => _toggleHomePanel('qr'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.brandPrimary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                              icon: const Icon(Icons.qr_code_rounded, size: 16),
                              label: const Text(
                                'QR ของฉัน',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: OutlinedButton.icon(
                              onPressed: () => _toggleHomePanel('profile'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.25),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                              icon: const Icon(Icons.edit_rounded, size: 15),
                              label: const Text(
                                'ตั้งค่า BC ID',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Quick Action Buttons (Add Friend, Join Token, Create Group) — inline, no popup
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _quickActionTile(
                      icon: Icons.person_add_alt_1_rounded,
                      label: 'เพิ่มเพื่อน',
                      color: AppTheme.brandDeep,
                      onTap: () => _toggleHomePanel('add_friend'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _quickActionTile(
                      icon: Icons.group_add_rounded,
                      label: 'สร้างกลุ่ม',
                      color: AppTheme.workBlue,
                      onTap: () => _toggleHomePanel('create_group'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AnimatedSize(
                duration: AppTheme.motionMed,
                curve: AppTheme.motionCurve,
                child: _buildActiveInlinePanel(
                  _homeInlinePanel,
                  isWide: isWide,
                  onClose: () => setState(() => _homeInlinePanel = null),
                ),
              ),
              const SizedBox(height: 10),

              // Quick Mini-Apps Strip
              _sectionHeader(
                'เครื่องมือเสริมในแชท',
                subtitle: 'หารค่าข้าว จัดทริป นัดเจอ และผู้ช่วย AI ส่วนตัว',
                padding: const EdgeInsets.only(bottom: 8),
                trailing: TextButton(
                  onPressed: () => setState(() {
                    _selectedIndex = 3;
                    if (_user.isAdmin) _loadAdminDataQuietly();
                  }),
                  child: const Text(
                    'ตั้งค่า & ทั้งหมด',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 64,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: enabledMiniApps.length,
                itemBuilder: (ctx, i) {
                  final app = enabledMiniApps[i];
                  final color = AppTheme.parseHexColor(app.color);
                  return InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    onTap: () => _openMiniApp(app),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(color: AppTheme.borderSubtle),
                        boxShadow: AppTheme.shadowSm,
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
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              app.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.35,
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
              const SizedBox(height: 24),

              // App News Section
              if (officials.isNotEmpty) ...[
                _sectionHeader(
                  'ข่าวสารแอป (${officials.length})',
                  subtitle: 'อัปเดตฟีเจอร์และข่าวสารส่วนตัว',
                  padding: const EdgeInsets.only(bottom: 4),
                ),
                ...officials.map(
                  (c) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                    leading: UserAvatar(
                      name: c.name,
                      avatarUrl: c.avatarUrl,
                      radius: 20,
                      isOfficial: true,
                    ),
                    title: Text(
                      c.name,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      c.lastMessage?.previewText ?? 'อัปเดตล่าสุดจาก BC Ai Chat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => _selectConversation(c, isWide: isWide),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Groups Section
              _sectionHeader(
                'กลุ่มสนทนา (${groups.length})',
                padding: const EdgeInsets.only(bottom: 4),
              ),
              ...groups.map(
                (g) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: UserAvatar(
                    name: g.name,
                    avatarUrl: g.avatarUrl,
                    radius: 20,
                    isGroup: true,
                  ),
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          '${g.name} (${g.memberCount})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      PillBadge(
                        text: g.folderLabel,
                        backgroundColor: g.isFamily
                            ? const Color(0xFFDBEAFE)
                            : AppTheme.brandSoft,
                        textColor: g.isFamily
                            ? AppTheme.workBlue
                            : AppTheme.brandDeep,
                      ),
                    ],
                  ),
                  subtitle: Text(
                    g.lastMessage?.previewText ?? 'แตะเพื่อเปิดห้องสนทนากลุ่ม',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => _selectConversation(g, isWide: isWide),
                ),
              ),
              const SizedBox(height: 12),

              // Friends Section (favorites sorted first, hidden toggle + actions)
              Builder(
                builder: (_) {
                  final hiddenCount = _friends.where((f) => f.isHidden).length;
                  final visibleFriends = _friends
                      .where((f) => _showHiddenFriends || !f.isHidden)
                      .toList()
                    ..sort((a, b) {
                      if (a.isFavorite != b.isFavorite) {
                        return a.isFavorite ? -1 : 1;
                      }
                      return a.displayName.compareTo(b.displayName);
                    });
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader(
                        'เพื่อนและครอบครัว (${visibleFriends.length})',
                        padding: const EdgeInsets.only(bottom: 4),
                        trailing: hiddenCount > 0
                            ? TextButton(
                                onPressed: () => setState(
                                  () => _showHiddenFriends = !_showHiddenFriends,
                                ),
                                child: Text(
                                  _showHiddenFriends
                                      ? 'ซ่อนรายชื่อที่พัก ($hiddenCount)'
                                      : 'แสดงที่ซ่อน ($hiddenCount)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              )
                            : null,
                      ),
                      ...visibleFriends.map(
                        (f) => ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                          ),
                          leading: UserAvatar(
                            name: f.displayName,
                            avatarUrl: f.avatarUrl,
                            radius: 20,
                            showOnline: f.isOnline && !f.isBlocked,
                            isOfficial: f.isOfficial,
                          ),
                          title: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (f.isFavorite) ...[
                                const Icon(
                                  Icons.star_rounded,
                                  size: 16,
                                  color: AppTheme.goldPin,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  f.displayName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              PillBadge(
                                text: f.isBlocked ? 'บล็อกแล้ว' : f.department,
                                backgroundColor: f.isBlocked
                                    ? const Color(0xFFFEE2E2)
                                    : const Color(0xFFE0E7FF),
                                textColor: f.isBlocked
                                    ? AppTheme.dangerRed
                                    : AppTheme.workBlue,
                              ),
                            ],
                          ),
                          subtitle: Text(
                            f.statusMessage.isNotEmpty
                                ? f.statusMessage
                                : f.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 18,
                                  color: AppTheme.brandDeep,
                                ),
                                onPressed: () =>
                                    _openChatWithFriend(f, isWide: isWide),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'จัดการเพื่อน',
                                icon: const Icon(
                                  Icons.more_vert_rounded,
                                  size: 18,
                                ),
                                onSelected: (action) async {
                                  if (action == 'chat') {
                                    await _openChatWithFriend(
                                      f,
                                      isWide: isWide,
                                    );
                                    return;
                                  }
                                  if (action == 'favorite') {
                                    await ApiService.instance.updateFriendMeta(
                                      f.id,
                                      isFavorite: !f.isFavorite,
                                    );
                                  } else if (action == 'hide') {
                                    await ApiService.instance.updateFriendMeta(
                                      f.id,
                                      isHidden: !f.isHidden,
                                    );
                                  } else if (action == 'block') {
                                    await ApiService.instance.updateFriendMeta(
                                      f.id,
                                      isBlocked: !f.isBlocked,
                                    );
                                  }
                                  await _refreshConversationsAndFriends();
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'favorite',
                                    child: Text(
                                      f.isFavorite
                                          ? 'เอาออกจากรายการโปรด'
                                          : 'เพิ่มในรายการโปรด ⭐',
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'hide',
                                    child: Text(
                                      f.isHidden
                                          ? 'ยกเลิกซ่อนเพื่อน'
                                          : 'ซ่อนจากรายชื่อ',
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'block',
                                    child: Text(
                                      f.isBlocked
                                          ? 'ปลดบล็อกเพื่อน'
                                          : 'บล็อกการติดต่อ',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => _openChatWithFriend(f, isWide: isWide),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: แชท (CHATS — แยกหมวดโฟลเดอร์ + ค้นหาข้ามห้อง + รายการแชท)
  // ---------------------------------------------------------------------------
  Widget _buildChatsTab({required bool isWide}) {
    final folders = [
      ('all', 'ทั้งหมด'),
      ('personal', 'ส่วนตัว'),
      ('family', 'ครอบครัว'),
      ('group', 'กลุ่ม'),
      ('pinned', 'ปักหมุด'),
      ('unread', 'ยังไม่อ่าน'),
      ('archived', 'เก็บถาวร'),
    ];
    final items = _filteredConversations;

    return Column(
      children: [
        // Header
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'แชท',
                style: TextStyle(
                  fontSize: 20,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slateDark,
                ),
              ),
              const SizedBox(width: 8),
              if (_totalUnreadCount > 0)
                PillBadge(
                  text: 'ยังไม่อ่าน $_totalUnreadCount',
                  backgroundColor: AppTheme.brandPrimary,
                  textColor: Colors.white,
                ),
              const Spacer(),
              IconButton(
                onPressed: () => _toggleChatPanel('notif'),
                tooltip: 'เสียงและการแจ้งเตือน',
                icon: Icon(
                  Icons.notifications_rounded,
                  color: _chatInlinePanel == 'notif'
                      ? AppTheme.brandPrimary
                      : null,
                ),
              ),
              IconButton(
                onPressed: () => _toggleChatPanel('join_group'),
                tooltip: 'เข้ากลุ่มด้วยรหัสเชิญ',
                icon: Icon(
                  Icons.vpn_key_outlined,
                  color: _chatInlinePanel == 'join_group'
                      ? AppTheme.brandPrimary
                      : null,
                ),
              ),
              IconButton(
                onPressed: () => _toggleChatPanel('create_group'),
                tooltip: 'สร้างกลุ่มแชทใหม่',
                icon: Icon(
                  Icons.group_add_rounded,
                  color: _chatInlinePanel == 'create_group'
                      ? AppTheme.brandPrimary
                      : null,
                ),
              ),
              IconButton(
                onPressed: _refreshConversationsAndFriends,
                tooltip: 'รีเฟรชรายการแชท',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),

        if (_chatInlinePanel != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: _buildActiveInlinePanel(
                _chatInlinePanel,
                isWide: isWide,
                onClose: () => setState(() => _chatInlinePanel = null),
              ),
            ),
          ),

        // Search input
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: _chatSearchCtrl,
            onChanged: _performGlobalSearch,
            decoration: InputDecoration(
              hintText: 'ค้นหาห้องแชท ข้อความ หรือชื่อไฟล์ถาวร...',
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: _chatSearchQuery.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _chatSearchCtrl.clear();
                        _performGlobalSearch('');
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    )
                  : null,
            ),
          ),
        ),

        // Folder Filter Bar (Solves Work vs Personal Chat Clutter!)
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: folders.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final code = folders[i].$1;
              final label = folders[i].$2;
              final active = _selectedChatFolder == code;

              return Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _selectedChatFolder = code),
                    child: AnimatedContainer(
                      duration: AppTheme.motionFast,
                      curve: AppTheme.motionCurve,
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? AppTheme.slateDark : AppTheme.surfaceBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: active
                              ? AppTheme.slateDark
                              : AppTheme.borderSubtle,
                        ),
                        boxShadow: active ? AppTheme.shadowSm : const [],
                      ),
                      child: AnimatedDefaultTextStyle(
                        duration: AppTheme.motionFast,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: active ? Colors.white : AppTheme.slateBody,
                        ),
                        child: Text(label, maxLines: 1),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),

        // Global message search hits (if searching)
        if (_chatSearchQuery.trim().length >= 2 &&
            (_isSearchingGlobal || _globalSearchResults.isNotEmpty))
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            color: const Color(0xFFF8FAFC),
            child: _isSearchingGlobal
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _globalSearchResults.length,
                    itemBuilder: (ctx, i) {
                      final m = _globalSearchResults[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.manage_search_rounded,
                          color: AppTheme.brandDeep,
                        ),
                        title: Text(
                          m.previewText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        subtitle: Text(
                          'โดย ${m.senderName} · ${formatThaiTime(m.createdAt)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () {
                          final target = _conversations
                              .where((c) => c.id == m.conversationId)
                              .toList();
                          if (target.isNotEmpty) {
                            _selectConversation(target.first, isWide: isWide);
                          }
                        },
                      );
                    },
                  ),
          ),

        // Conversation List
        Expanded(
          child: _isLoadingInitial
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
              ? const Center(
                  child: Text(
                    'ไม่มีห้องแชทในหมวดหมู่นี้',
                    style: TextStyle(color: AppTheme.slateMuted),
                  ),
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const Divider(indent: 76, height: 1),
                  itemBuilder: (ctx, i) {
                    final conv = items[i];
                    final isSelected =
                        isWide && _activeConversation?.id == conv.id;
                    final timeText = formatThaiTime(
                      conv.lastMessage?.createdAt ?? conv.updatedAt,
                    );

                    final hasUnread = conv.unreadCount > 0;
                    return Material(
                      color: isSelected ? AppTheme.brandSoft : Colors.white,
                      child: InkWell(
                        onTap: () => _selectConversation(conv, isWide: isWide),
                        hoverColor: AppTheme.surfaceBg,
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  UserAvatar(
                                    name: conv.name,
                                    avatarUrl: conv.avatarUrl,
                                    radius: 23,
                                    showOnline: !conv.isGroup,
                                    isOfficial: conv.isOfficial,
                                    isGroup: conv.isGroup,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // แถว 1: ปักหมุด · ชื่อ · โฟลเดอร์ · เวลา
                                        SizedBox(
                                          height: 22,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              if (conv.isPinned) ...[
                                                const Icon(
                                                  Icons.push_pin_rounded,
                                                  size: 14,
                                                  color: AppTheme.goldPin,
                                                ),
                                                const SizedBox(width: 4),
                                              ],
                                              if (conv.isMuted) ...[
                                                const Icon(
                                                  Icons.notifications_off_outlined,
                                                  size: 14,
                                                  color: AppTheme.slateMuted,
                                                ),
                                                const SizedBox(width: 4),
                                              ],
                                              Expanded(
                                                child: Text(
                                                  conv.isGroup
                                                      ? '${conv.name} (${conv.memberCount})'
                                                      : conv.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 14.5,
                                                    height: 1.35,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppTheme.slateDark,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              PillBadge(
                                                text: conv.folderLabel,
                                                backgroundColor: conv.isFamily
                                                    ? const Color(0xFFDBEAFE)
                                                    : AppTheme.brandSoft,
                                                textColor: conv.isFamily
                                                    ? AppTheme.workBlue
                                                    : AppTheme.brandDeep,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                timeText,
                                                maxLines: 1,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  height: 1.35,
                                                  color: hasUnread
                                                      ? AppTheme.brandDeep
                                                      : AppTheme.slateMuted,
                                                  fontWeight: hasUnread
                                                      ? FontWeight.w700
                                                      : FontWeight.w400,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        // แถว 2: ข้อความล่าสุด · จำนวนที่ยังไม่อ่าน
                                        SizedBox(
                                          height: 22,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  conv
                                                          .lastMessage
                                                          ?.previewText ??
                                                      'เริ่มการสนทนา...',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    height: 1.35,
                                                    color: hasUnread
                                                        ? AppTheme.slateDark
                                                        : AppTheme.slateMuted,
                                                    fontWeight: hasUnread
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                                  ),
                                                ),
                                              ),
                                              if (hasUnread) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  height: 20,
                                                  constraints:
                                                      const BoxConstraints(
                                                        minWidth: 20,
                                                      ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                      ),
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color:
                                                        AppTheme.brandPrimary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${conv.unreadCount}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      height: 1.2,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Positioned(
                                left: 0,
                                top: 10,
                                bottom: 10,
                                child: Container(
                                  width: 4,
                                  decoration: BoxDecoration(
                                    color: AppTheme.brandPrimary,
                                    borderRadius: BorderRadius.horizontal(
                                      right: Radius.circular(4),
                                    ),
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
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: สมุดบันทึก BC (คลังบันทึกส่วนตัวถาวร ซิงค์ตาม Gmail)
  // ---------------------------------------------------------------------------
  // Notes are also saved from chat rooms (AI summaries), so refetch on every visit.
  Future<void> _reloadNotebookNotes() async {
    final fresh = await ApiService.instance.fetchNotes();
    if (!mounted) return;
    setState(() => _notebookNotes = fresh);
  }

  Widget _buildNotebookVaultTab() {
    final isCompact = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        title: const Text(
          'สมุดบันทึก BC — คลังบันทึกถาวร',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: ElevatedButton.icon(
                onPressed: () => setState(
                  () => _showCreateNoteInline = !_showCreateNoteInline,
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: Icon(
                  _showCreateNoteInline ? Icons.close_rounded : Icons.add_rounded,
                  size: 16,
                ),
                label: Text(
                  _showCreateNoteInline
                      ? 'ปิดฟอร์ม'
                      : (isCompact ? 'สร้างโน้ต' : 'สร้างบันทึกใหม่'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isCompact ? 14 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1020),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.brandSoft,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(
                      color: AppTheme.brandPrimary.withValues(alpha: 0.35),
                    ),
                    boxShadow: AppTheme.shadowSm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_done_rounded, color: AppTheme.brandDeep),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'สมุดบันทึก BC ซิงค์อัตโนมัติตามบัญชี Gmail (${_user.email}) เก็บข้อความ ลิงก์ รูปและไฟล์สำคัญถาวร ไม่มีวันหมดอายุ',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.brandDeep,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: AppTheme.motionMed,
                  curve: AppTheme.motionCurve,
                  child: _showCreateNoteInline
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _buildInlinePanelWrapper(
                            child: _InlineCreateNotePanel(
                              onCancel: () =>
                                  setState(() => _showCreateNoteInline = false),
                              onCreated: () async {
                                setState(() => _showCreateNoteInline = false);
                                await _reloadNotebookNotes();
                              },
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 20),
                if (_notebookNotes.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(36),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      boxShadow: AppTheme.shadowSm,
                    ),
                    child: const Text(
                      'ยังไม่มีรายการในสมุดบันทึก BC กดปุ่ม "สร้างบันทึกใหม่" หรือกดบันทึกจากข้อความในห้องแชทได้เลย',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.slateMuted, height: 1.5),
                    ),
                  )
                else
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: _notebookNotes.map((note) {
                      return Container(
                        width: isCompact ? double.infinity : 320,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusLg,
                          ),
                          border: Border.all(color: AppTheme.borderSubtle),
                          boxShadow: AppTheme.shadowSm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: PillBadge(
                                      text: note.category,
                                      backgroundColor: AppTheme.brandSoft,
                                      textColor: AppTheme.brandDeep,
                                      icon: Icons.bookmark_rounded,
                                    ),
                                  ),
                                ),
                                Text(
                                  formatThaiTime(note.createdAt),
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.35,
                                    color: AppTheme.slateMuted,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    await ApiService.instance.deleteNote(
                                      note.id,
                                    );
                                    await _reloadNotebookNotes();
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: AppTheme.dangerRed,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              note.title,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.35,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slateDark,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              note.content,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: AppTheme.slateBody,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () async {
                                    await ApiService.instance.toggleNoteLike(
                                      note.id,
                                    );
                                    await _reloadNotebookNotes();
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
                                          note.likedBy.contains(_user.id)
                                              ? Icons.favorite_rounded
                                              : Icons.favorite_border_rounded,
                                          size: 15,
                                          color: note.likedBy.contains(_user.id)
                                              ? AppTheme.brandPrimary
                                              : AppTheme.slateMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${note.likedBy.length}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.slateMuted,
                                          ),
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
                                  '${note.comments.length}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.slateMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: ตั้งค่า & เครื่องมือส่วนตัว (รวมเสียงแจ้งเตือน ธีม เครื่องมือเสริม และตั้งค่าระบบ)
  // ---------------------------------------------------------------------------
  Widget _buildSettingsAndToolsTab() {
    final ov = _adminOverview;
    final isCompact = MediaQuery.of(context).size.width < 600;
    final enabledApps = _miniApps.where((m) => m.enabled).toList();

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        title: const Text(
          'ตั้งค่า & เครื่องมือส่วนตัว',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_user.isAdmin)
            IconButton(
              onPressed: _loadAdminDataQuietly,
              tooltip: 'รีเฟรชข้อมูลระบบ',
              icon: const Icon(Icons.refresh_rounded),
            ),
          IconButton(
            onPressed: widget.onLoggedOut,
            tooltip: 'สลับบัญชี / ออกจากระบบ',
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isCompact ? 14 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Personal Profile Quick Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(color: AppTheme.borderSubtle),
                    boxShadow: AppTheme.shadowSm,
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          UserAvatar(
                            name: _user.displayName,
                            avatarUrl: _user.avatarUrl,
                            radius: 22,
                            showOnline: true,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _user.displayName,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                              Text(
                                'BC ID: @${_user.bcId} · ${_user.department}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.slateMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => setState(() {
                              _selectedIndex = 0;
                              _homeInlinePanel = 'profile';
                            }),
                            icon: const Icon(Icons.edit_rounded, size: 16),
                            label: const Text('แก้ไขโปรไฟล์'),
                          ),
                          OutlinedButton.icon(
                            onPressed: widget.onLoggedOut,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.dangerRed,
                            ),
                            icon: const Icon(Icons.logout_rounded, size: 16),
                            label: const Text('ออกจากระบบ'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Inline Notification & Sound Settings (for everyone, zero popup)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(color: AppTheme.borderSubtle),
                    boxShadow: AppTheme.shadowSm,
                  ),
                  child: const _InlineNotificationPanel(showCloseButton: false),
                ),
                const SizedBox(height: 18),

                // Personal Theme Card (7 Ban Chiang + Thai Heritage themes)
                _buildPersonalThemeCard(),
                const SizedBox(height: 18),

                // Personal Mini-Apps Hub (plus Admin editor if admin)
                Container(
                  padding: EdgeInsets.all(isCompact ? 16 : 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(color: AppTheme.borderSubtle),
                    boxShadow: AppTheme.shadowSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.widgets_rounded,
                                color: AppTheme.brandPrimary,
                              ),
                              const SizedBox(width: 8),
                              const Flexible(
                                child: Text(
                                  'เครื่องมือเสริมในแชท (Personal Mini-Apps)',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_user.isAdmin)
                            ElevatedButton.icon(
                              onPressed: () => setState(() {
                                _editingMiniApp = null;
                                _showMiniAppFormInline =
                                    !_showMiniAppFormInline;
                              }),
                              icon: Icon(
                                _showMiniAppFormInline
                                    ? Icons.close_rounded
                                    : Icons.add_rounded,
                                size: 17,
                              ),
                              label: Text(
                                _showMiniAppFormInline
                                    ? 'ปิดฟอร์ม'
                                    : 'เพิ่มเครื่องมือใหม่',
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'เปิดใช้หารค่าข้าว จัดทริปเที่ยว ลิสต์ของฝาก การ์ดชวนนัดเจอ หรือผู้ช่วย AI แล้วส่งเป็นการ์ดเข้าห้องแชทได้ทันที',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.slateMuted,
                        ),
                      ),
                      if (_user.isAdmin)
                        AnimatedSize(
                          duration: AppTheme.motionMed,
                          curve: AppTheme.motionCurve,
                          child: _showMiniAppFormInline
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: _buildInlinePanelWrapper(
                                    child: _InlineMiniAppFormPanel(
                                      key: ValueKey(
                                        _editingMiniApp?.id ?? 'new',
                                      ),
                                      existing: _editingMiniApp,
                                      onCancel: () => setState(() {
                                        _showMiniAppFormInline = false;
                                        _editingMiniApp = null;
                                      }),
                                      onSaved: () async {
                                        setState(() {
                                          _showMiniAppFormInline = false;
                                          _editingMiniApp = null;
                                        });
                                        await _loadAdminDataQuietly();
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            backgroundColor: AppTheme.brandDeep,
                                            content: const Text(
                                              'อัปเดตเครื่องมือเสริมเรียบร้อย! ทุกห้องใช้งานได้ทันที',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: (_user.isAdmin ? _miniApps : enabledApps).map(
                          (app) {
                            final color = AppTheme.parseHexColor(app.color);
                            return Container(
                              width: isCompact ? double.infinity : 320,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceBg,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                                border: Border.all(
                                  color: AppTheme.borderSubtle,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          AppTheme.resolveMiniAppIcon(app.icon),
                                          color: Colors.white,
                                          size: 19,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              app.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13.5,
                                              ),
                                            ),
                                            Text(
                                              app.category,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: color,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_user.isAdmin) ...[
                                        Switch(
                                          value: app.enabled,
                                          activeThumbColor:
                                              AppTheme.brandPrimary,
                                          onChanged: (val) async {
                                            await ApiService.instance
                                                .updateAdminMiniApp(app.id, {
                                                  ...app.toJson(),
                                                  'enabled': val,
                                                });
                                            await _loadAdminDataQuietly();
                                          },
                                        ),
                                        IconButton(
                                          onPressed: () => setState(() {
                                            _editingMiniApp = app;
                                            _showMiniAppFormInline = true;
                                          }),
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'แก้ไขเครื่องมือเสริม',
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    app.subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.slateBody,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _openMiniApp(app),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: color,
                                          ),
                                          icon: const Icon(
                                            Icons.rocket_launch_rounded,
                                            size: 15,
                                          ),
                                          label: const Text('เปิดใช้งาน'),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        onPressed: () {
                                          final url = ApiService.instance
                                              .resolveMiniAppUrl(app);
                                          final uri = Uri.tryParse(url);
                                          if (uri != null) {
                                            launchUrl(
                                              uri,
                                              mode:
                                                  LaunchMode.externalApplication,
                                            );
                                          }
                                        },
                                        tooltip: 'เปิด URL ภายนอก',
                                        icon: const Icon(
                                          Icons.open_in_new_rounded,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ).toList(),
                      ),
                    ],
                  ),
                ),

                if (_user.isAdmin) ...[
                  const SizedBox(height: 24),
                  _sectionHeader(
                    'ระบบจัดการสำหรับเจ้าของระบบ',
                    subtitle: 'สถิติพื้นที่เก็บไฟล์ ความจำ AI และข่าวสารแอป',
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, box) {
                      final compact = box.maxWidth < 600;
                      final tileWidth = compact
                          ? (box.maxWidth - 12) / 2
                          : 255.0;
                      return Wrap(
                        spacing: compact ? 12 : 14,
                        runSpacing: compact ? 12 : 14,
                        children: [
                          _buildMetricCard(
                            'สมาชิกทั้งหมด (Gmail)',
                            '${ov?.totalUsers ?? _adminUsers.length} บัญชี',
                            Icons.people_alt_rounded,
                            AppTheme.brandPrimary,
                            width: tileWidth,
                            compact: compact,
                          ),
                          _buildMetricCard(
                            'ห้องสนทนาทั้งหมด',
                            '${ov?.totalConversations ?? _conversations.length} ห้อง',
                            Icons.forum_rounded,
                            AppTheme.workBlue,
                            width: tileWidth,
                            compact: compact,
                          ),
                          _buildMetricCard(
                            'ข้อความทั้งหมดบน MongoDB',
                            '${ov?.totalMessages ?? 0} ข้อความ',
                            Icons.mark_chat_read_rounded,
                            AppTheme.personalPurple,
                            width: tileWidth,
                            compact: compact,
                          ),
                          _buildMetricCard(
                            'คลังรูป & ไฟล์ถาวร MinIO',
                            '${ov?.totalFiles ?? 0} ไฟล์ (${formatFileSize(ov?.totalStorageBytes ?? 0)})',
                            Icons.cloud_done_rounded,
                            AppTheme.warningAmber,
                            width: tileWidth,
                            compact: compact,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  _buildAiBrainSettingsCard(),
                  const SizedBox(height: 18),
                  _buildBroadcastCard(),
                  const SizedBox(height: 18),
                  _buildUserManagementCard(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    double width = 255,
    bool compact = false,
  }) {
    final iconTile = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Icon(icon, color: color, size: 22),
    );
    final labelText = Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 12,
        height: 1.4,
        color: AppTheme.slateMuted,
      ),
    );
    final valueText = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 15.5,
        height: 1.35,
        fontWeight: FontWeight.w800,
        color: AppTheme.slateDark,
      ),
    );
    if (compact) {
      return Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: AppTheme.borderSubtle),
          boxShadow: AppTheme.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            iconTile,
            const SizedBox(height: 12),
            // Two label lines reserved so every tile in the grid is equal height.
            SizedBox(height: 34, child: labelText),
            const SizedBox(height: 4),
            valueText,
          ],
        ),
      );
    }
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderSubtle),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          iconTile,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 4), valueText],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalThemeCard() {
    final current = AppTheme.preset.value;
    final tileWidth = MediaQuery.sizeOf(context).width < 600
        ? double.infinity
        : 236.0;
    return Container(
      padding: const EdgeInsets.all(20),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.palette_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ธีมสีของแอป (บ้านเชียง & 7 โทนสีไทยร่วมสมัย)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _user.isAdmin
                          ? 'เลือกโทนสีที่ชอบ เปลี่ยนแล้วซิงค์สดทุกเครื่อง'
                          : 'ธีมปัจจุบัน: ${current.name} (เปลี่ยนได้โดยเจ้าของระบบ)',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.slateMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final p in ThemePreset.all)
                SizedBox(
                  width: tileWidth,
                  child: _ThemePresetTile(
                    preset: p,
                    selected: p.code == current.code,
                    onTap: () => _changeBusinessTheme(p),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _changeBusinessTheme(ThemePreset preset) async {
    if (preset.code == AppTheme.preset.value.code) return;
    final snack = ScaffoldMessenger.of(context);
    try {
      await ApiService.instance.updateBusinessTheme(preset.code);
      snack.showSnackBar(
        SnackBar(content: Text('เปลี่ยนธีมเป็น "${preset.name}" แล้ว')),
      );
    } catch (e) {
      snack.showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Widget _buildAiBrainSettingsCard() {
    String selectedModel = _aiSettings.model;
    final apiKeyCtrl = TextEditingController();
    final promptCtrl = TextEditingController(text: _aiSettings.systemPrompt);

    return StatefulBuilder(
      builder: (ctx, setCardState) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(
              color: AppTheme.personalPurple.withValues(alpha: 0.3),
            ),
            boxShadow: AppTheme.shadowMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6D28D9), Color(0xFF2563EB)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.psychology_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              '🧠 ตั้งค่าสมองกล DeepSeek AI ส่วนตัว',
                              style: TextStyle(
                                fontSize: 15.5,
                                height: 1.35,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slateDark,
                              ),
                            ),
                            PillBadge(
                              text:
                                  'API Key: ${_aiSettings.maskedKey.isNotEmpty ? _aiSettings.maskedKey : "พร้อมใช้งาน"}',
                              backgroundColor: AppTheme.brandSoft,
                              textColor: AppTheme.brandDeep,
                              icon: Icons.verified_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'ทำหน้าที่เป็นผู้ช่วยอัจฉริยะให้ครอบครัวและเพื่อนทุกห้องแชท (@ai ถามในกลุ่ม, สรุปแชท, เกลาคำพูด)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'เลือกโมเดล DeepSeek:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slateDark,
                    ),
                  ),
                  ChoiceChip(
                    selected: selectedModel == 'deepseek-chat',
                    label: const Text('deepseek-chat (DeepSeek-V3)'),
                    onSelected: (_) =>
                        setCardState(() => selectedModel = 'deepseek-chat'),
                  ),
                  ChoiceChip(
                    selected: selectedModel == 'deepseek-reasoner',
                    label: const Text('deepseek-reasoner (DeepSeek-R1)'),
                    onSelected: (_) =>
                        setCardState(() => selectedModel = 'deepseek-reasoner'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiKeyCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText:
                      'อัปเดต DeepSeek API Key (ปัจจุบัน: ${_aiSettings.maskedKey})',
                  hintText:
                      'เว้นว่างไว้หากใช้ API Key เดิมที่ตั้งค่าแล้วบนเซิร์ฟเวอร์',
                  prefixIcon: const Icon(Icons.key_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText:
                      'System Prompt (กำหนดนิสัยและโทนการตอบของ BC AI)',
                  prefixIcon: Icon(Icons.tune_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final updated = await ApiService.instance
                          .updateAdminAiSettings(
                            model: selectedModel,
                            apiKey: apiKeyCtrl.text,
                            systemPrompt: promptCtrl.text,
                          );
                      if (!mounted) return;
                      setState(() => _aiSettings = updated);
                      apiKeyCtrl.clear();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppTheme.brandDeep,
                          content: Text(
                            'บันทึกการตั้งค่าสมองกล DeepSeek AI ส่วนตัวเรียบร้อยแล้ว!',
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.personalPurple,
                  ),
                  icon: const Icon(Icons.save_rounded, size: 17),
                  label: const Text('บันทึกตั้งค่าสมองกล DeepSeek AI'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBroadcastCard() {
    final titleCtrl = TextEditingController(
      text: 'อัปเดตฟีเจอร์ใหม่ BC Ai Chat สำหรับทุกคน',
    );
    final contentCtrl = TextEditingController(
      text:
          'ตอนนี้ชวนเพื่อนหารค่าข้าว จัดทริปเที่ยว ลิสต์ของฝาก และส่งการ์ดชวนนัดเจอได้จากแท็บตั้งค่าและในห้องแชทเลยครับ!',
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderSubtle),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.campaign_rounded, color: AppTheme.warningAmber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ส่งประกาศข่าวสารเข้าห้องข่าวสาร BC Ai Chat ถึงทุกคน',
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: titleCtrl,
            decoration: const InputDecoration(labelText: 'หัวข้อข่าวสาร'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: contentCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'ข้อความข่าวสาร'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () async {
                await ApiService.instance.sendAdminBroadcast(
                  title: titleCtrl.text,
                  content: contentCtrl.text,
                );
                await _refreshConversationsAndFriends();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.brandDeep,
                    content: Text(
                      'ส่งข่าวสารเข้าห้องข่าวสาร BC Ai Chat เรียบร้อยแล้ว!',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.send_rounded, size: 17),
              label: const Text('ส่งข่าวสารทันที'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserManagementCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderSubtle),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_rounded, color: AppTheme.workBlue),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'รายชื่อสมาชิกที่ซิงค์ด้วยบัญชี Gmail',
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _adminUsers.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (ctx, i) {
              final u = _adminUsers[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(
                  name: u.displayName,
                  avatarUrl: u.avatarUrl,
                  radius: 19,
                ),
                title: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      u.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    PillBadge(
                      text: u.department,
                      backgroundColor: const Color(0xFFE0E7FF),
                      textColor: AppTheme.workBlue,
                    ),
                  ],
                ),
                subtitle: Text(
                  '${u.email} · BC ID: @${u.bcId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: PillBadge(
                  text: u.role.toUpperCase(),
                  backgroundColor: u.isAdmin
                      ? AppTheme.brandSoft
                      : AppTheme.surfaceBg,
                  textColor: u.isAdmin
                      ? AppTheme.brandDeep
                      : AppTheme.slateBody,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ThemePresetTile extends StatelessWidget {
  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _ThemePresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Material(
      color: selected ? preset.soft : Colors.white,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? preset.primary : AppTheme.borderSubtle,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: preset.gradient),
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 18,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      preset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                        height: 1.3,
                      ),
                    ),
                    Text(
                      preset.suitsFor,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.slateMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineEditProfilePanel extends StatefulWidget {
  final AppUser user;
  final VoidCallback onCancel;
  final ValueChanged<AppUser> onSaved;

  const _InlineEditProfilePanel({
    required this.user,
    required this.onCancel,
    required this.onSaved,
  });

  @override
  State<_InlineEditProfilePanel> createState() => _InlineEditProfilePanelState();
}

class _InlineEditProfilePanelState extends State<_InlineEditProfilePanel> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bcIdCtrl;
  late final TextEditingController _statusCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.displayName);
    _bcIdCtrl = TextEditingController(text: widget.user.bcId);
    _statusCtrl = TextEditingController(text: widget.user.statusMessage);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bcIdCtrl.dispose();
    _statusCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Text(
                'แก้ไขโปรไฟล์ & ตั้งค่า BC ID',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'ชื่อที่แสดง (Display Name)',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _bcIdCtrl,
          decoration: const InputDecoration(
            labelText: 'BC ID (ให้เพื่อนใช้ค้นหาคุณ)',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _statusCtrl,
          decoration: const InputDecoration(
            labelText: 'คำคม / สถานะส่วนตัว',
            prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: widget.onCancel, child: const Text('ยกเลิก')),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _saving
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _saving = true);
                      try {
                        final updated = await ApiService.instance.updateProfile(
                          displayName: _nameCtrl.text,
                          bcId: _bcIdCtrl.text,
                          statusMessage: _statusCtrl.text,
                        );
                        if (mounted) widget.onSaved(updated);
                      } catch (e) {
                        if (mounted) {
                          setState(() => _saving = false);
                          messenger.showSnackBar(
                            SnackBar(content: Text('อัปเดตไม่สำเร็จ: $e')),
                          );
                        }
                      }
                    },
              child: const Text('บันทึกการเปลี่ยนแปลง'),
            ),
          ],
        ),
      ],
    );
  }
}

class _InlineAddFriendPanel extends StatefulWidget {
  final VoidCallback onCancel;
  final Future<void> Function(AppUser? friend) onAddedFriend;

  const _InlineAddFriendPanel({
    required this.onCancel,
    required this.onAddedFriend,
  });

  @override
  State<_InlineAddFriendPanel> createState() => _InlineAddFriendPanelState();
}

class _InlineAddFriendPanelState extends State<_InlineAddFriendPanel> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<AppUser> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    final found = await ApiService.instance.searchUsers(q);
    if (!mounted) return;
    setState(() {
      _results = found;
      _searching = false;
    });
  }

  Future<void> _addDirectByInput() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    try {
      await ApiService.instance.addFriend(
        bcId: q.contains('@') ? null : q,
        email: q.contains('@') ? q : null,
        qrToken: q,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.brandDeep,
            content: const Text('เพิ่มเพื่อนและสร้างห้องแชทเรียบร้อยแล้ว!'),
          ),
        );
        await widget.onAddedFriend(null);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ไม่พบผู้ใช้: $q')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Text(
                'เพิ่มเพื่อนใหม่ (BC ID / Gmail / QR Token)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onSubmitted: (_) => _runSearch(),
                decoration: const InputDecoration(
                  hintText: 'พิมพ์ @kong.bc, demo2@bcaichat.local หรือ QR Token',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _runSearch, child: const Text('ค้นหา')),
          ],
        ),
        if (_searching)
          const Padding(
            padding: EdgeInsets.all(14),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_results.isNotEmpty) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _results.length,
              separatorBuilder: (_, _) => const Divider(height: 8),
              itemBuilder: (_, idx) {
                final u = _results[idx];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: UserAvatar(
                    name: u.displayName,
                    avatarUrl: u.avatarUrl,
                    radius: 17,
                  ),
                  title: Text(
                    u.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    'BC ID: @${u.bcId} · ${u.email}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: ElevatedButton(
                    onPressed: () async {
                      await ApiService.instance.addFriend(targetId: u.id);
                      await widget.onAddedFriend(u);
                    },
                    child: const Text('เพิ่ม & แชท'),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: widget.onCancel, child: const Text('ปิด')),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _addDirectByInput,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('เพิ่มเพื่อนทันที'),
            ),
          ],
        ),
      ],
    );
  }
}

class _InlineJoinGroupPanel extends StatefulWidget {
  final VoidCallback onCancel;
  final Future<void> Function(Conversation conv) onJoined;

  const _InlineJoinGroupPanel({
    required this.onCancel,
    required this.onJoined,
  });

  @override
  State<_InlineJoinGroupPanel> createState() => _InlineJoinGroupPanelState();
}

class _InlineJoinGroupPanelState extends State<_InlineJoinGroupPanel> {
  final TextEditingController _tokenCtrl = TextEditingController();

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Text(
                'เข้ากลุ่มด้วยรหัสเชิญ',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tokenCtrl,
          decoration: const InputDecoration(
            labelText: 'รหัสเชิญเข้ากลุ่ม (Invite Token)',
            hintText: 'วางรหัสเชิญที่ได้รับจากเพื่อนหรือคนในบ้าน',
            prefixIcon: Icon(Icons.vpn_key_rounded),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: widget.onCancel, child: const Text('ยกเลิก')),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () async {
                final token = _tokenCtrl.text.trim();
                if (token.isEmpty) return;
                final snack = ScaffoldMessenger.of(context);
                try {
                  final conv = await ApiService.instance.joinConversationByToken(
                    token,
                  );
                  await widget.onJoined(conv);
                } catch (e) {
                  snack.showSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceAll('Exception: ', '')),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.login_rounded, size: 17),
              label: const Text('เข้าร่วมกลุ่ม'),
            ),
          ],
        ),
      ],
    );
  }
}

class _InlineCreateGroupPanel extends StatefulWidget {
  final List<AppUser> friends;
  final VoidCallback onCancel;
  final Future<void> Function(Conversation conv) onCreated;

  const _InlineCreateGroupPanel({
    required this.friends,
    required this.onCancel,
    required this.onCreated,
  });

  @override
  State<_InlineCreateGroupPanel> createState() =>
      _InlineCreateGroupPanelState();
}

class _InlineCreateGroupPanelState extends State<_InlineCreateGroupPanel> {
  final TextEditingController _nameCtrl = TextEditingController();
  String _folder = 'family';
  final Set<String> _selectedMemberIds = {};
  bool _includeAi = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectable = widget.friends.where((f) => f.id != 'user_ai').toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Text(
                'สร้างกลุ่มแชทใหม่',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'ชื่อกลุ่มแชท',
            hintText: 'เช่น แก๊งเที่ยวเชียงใหม่ หรือ กลุ่มครอบครัว',
            prefixIcon: Icon(Icons.groups_rounded),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: const Text('ครอบครัว'),
              selected: _folder == 'family',
              onSelected: (_) => setState(() => _folder = 'family'),
            ),
            ChoiceChip(
              label: const Text('ส่วนตัว / เพื่อน'),
              selected: _folder == 'personal',
              onSelected: (_) => setState(() => _folder = 'personal'),
            ),
          ],
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _includeAi,
          title: const Text(
            'เชิญ 🤖 BC AI เข้ากลุ่มด้วยทันที',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          onChanged: (v) => setState(() => _includeAi = v ?? true),
        ),
        if (selectable.isNotEmpty) ...[
          const Text(
            'เลือกสมาชิกเข้ากลุ่ม:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: ListView(
              shrinkWrap: true,
              children: selectable.map((f) {
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _selectedMemberIds.contains(f.id),
                  title: Text(
                    f.displayName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedMemberIds.add(f.id);
                    } else {
                      _selectedMemberIds.remove(f.id);
                    }
                  }),
                );
              }).toList(),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: widget.onCancel, child: const Text('ยกเลิก')),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () async {
                if (_nameCtrl.text.trim().isEmpty) return;
                final members = {
                  ..._selectedMemberIds,
                  if (_includeAi) 'user_ai',
                }.toList();
                final conv = await ApiService.instance.createGroupConversation(
                  name: _nameCtrl.text.trim(),
                  folder: _folder,
                  memberIds: members,
                );
                await widget.onCreated(conv);
              },
              icon: const Icon(Icons.check_rounded, size: 17),
              label: const Text('สร้างกลุ่มแชท'),
            ),
          ],
        ),
      ],
    );
  }
}

class _InlineNotificationPanel extends StatefulWidget {
  final VoidCallback? onClose;
  final bool showCloseButton;

  const _InlineNotificationPanel({
    this.onClose,
    this.showCloseButton = true,
  });

  @override
  State<_InlineNotificationPanel> createState() =>
      _InlineNotificationPanelState();
}

class _InlineNotificationPanelState extends State<_InlineNotificationPanel> {
  final _n = NotificationService.instance;

  Future<void> _update(Future<void> Function() fn) async {
    await fn();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_active_rounded,
              color: AppTheme.brandPrimary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'เสียงและการแจ้งเตือน',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            if (widget.showCloseButton && widget.onClose != null)
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded, size: 20),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _n.popupEnabled,
          activeThumbColor: AppTheme.brandPrimary,
          title: const Text(
            'แจ้งเตือนเมื่อมีแชทเข้า',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          onChanged: (v) => _update(() => _n.setPopupEnabled(v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _n.soundEnabled,
          activeThumbColor: AppTheme.brandPrimary,
          title: const Text(
            'เปิดเสียงแจ้งเตือน',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          onChanged: (v) => _update(() => _n.setSoundEnabled(v)),
        ),
        if (_n.soundEnabled) ...[
          const SizedBox(height: 6),
          for (final kind in AlertKind.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      kind.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DropdownButton<String>(
                    value: _n.soundOf(kind),
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final s in NotificationService.sounds)
                        DropdownMenuItem(
                          value: s.code,
                          child: Text(
                            s.name,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                    ],
                    onChanged: (code) {
                      if (code == null) return;
                      _update(() async {
                        await _n.setSoundOf(kind, code);
                        _n.playSound(code);
                      });
                    },
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _InlineCreateNotePanel extends StatefulWidget {
  final VoidCallback onCancel;
  final Future<void> Function() onCreated;

  const _InlineCreateNotePanel({
    required this.onCancel,
    required this.onCreated,
  });

  @override
  State<_InlineCreateNotePanel> createState() => _InlineCreateNotePanelState();
}

class _InlineCreateNotePanelState extends State<_InlineCreateNotePanel> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  String _category = 'บันทึกสำคัญ';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Text(
                'สร้างบันทึกใหม่ในสมุดบันทึก BC',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final cat in const ['บันทึกสำคัญ', 'ครอบครัว', 'ทริป & รูปถ่าย'])
              ChoiceChip(
                label: Text(cat),
                selected: _category == cat,
                onSelected: (_) => setState(() => _category = cat),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(
            labelText: 'หัวข้อบันทึก',
            prefixIcon: Icon(Icons.title_rounded),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _contentCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'ข้อความ / ลิงก์ / รายละเอียดที่ต้องการเก็บถาวร',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: widget.onCancel, child: const Text('ยกเลิก')),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                if (_titleCtrl.text.trim().isEmpty) return;
                await ApiService.instance.createNote(
                  title: _titleCtrl.text.trim(),
                  content: _contentCtrl.text.trim(),
                  category: _category,
                );
                await widget.onCreated();
              },
              child: const Text('บันทึกเข้าสมุดบันทึก BC'),
            ),
          ],
        ),
      ],
    );
  }
}

class _InlineMiniAppFormPanel extends StatefulWidget {
  final MiniAppItem? existing;
  final VoidCallback onCancel;
  final Future<void> Function() onSaved;

  const _InlineMiniAppFormPanel({
    super.key,
    this.existing,
    required this.onCancel,
    required this.onSaved,
  });

  @override
  State<_InlineMiniAppFormPanel> createState() =>
      _InlineMiniAppFormPanelState();
}

class _InlineMiniAppFormPanelState extends State<_InlineMiniAppFormPanel> {
  late TextEditingController _codeCtrl;
  late TextEditingController _titleCtrl;
  late TextEditingController _subtitleCtrl;
  late TextEditingController _categoryCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _colorCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _codeCtrl = TextEditingController(text: e?.code ?? 'trip_checklist');
    _titleCtrl = TextEditingController(
      text: e?.title ?? 'เช็กลิสต์จัดกระเป๋าเที่ยว',
    );
    _subtitleCtrl = TextEditingController(
      text: e?.subtitle ?? 'จดของที่ต้องเตรียมก่อนออกทริปกับเพื่อนๆ',
    );
    _categoryCtrl = TextEditingController(
      text: e?.category ?? 'ไลฟ์สไตล์ & ท่องเที่ยว',
    );
    _urlCtrl = TextEditingController(text: e?.url ?? '/miniapp/trip_checklist');
    _colorCtrl = TextEditingController(text: e?.color ?? '#812920');
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _categoryCtrl.dispose();
    _urlCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                existing == null
                    ? 'เพิ่มเครื่องมือเสริมใหม่'
                    : 'แก้ไขเครื่องมือ ${existing.title}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _codeCtrl,
          decoration: const InputDecoration(labelText: 'รหัสเครื่องมือ (Code)'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(labelText: 'ชื่อเครื่องมือ'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _subtitleCtrl,
          decoration: const InputDecoration(labelText: 'คำอธิบายสั้นๆ'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _categoryCtrl,
          decoration: const InputDecoration(labelText: 'หมวดหมู่'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _urlCtrl,
          decoration: const InputDecoration(labelText: 'Path หรือ URL'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _colorCtrl,
          decoration: const InputDecoration(labelText: 'สีประจำเครื่องมือ (Hex)'),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: widget.onCancel, child: const Text('ยกเลิก')),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                final payload = {
                  'code': _codeCtrl.text.trim(),
                  'title': _titleCtrl.text.trim(),
                  'subtitle': _subtitleCtrl.text.trim(),
                  'category': _categoryCtrl.text.trim(),
                  'url': _urlCtrl.text.trim(),
                  'color': _colorCtrl.text.trim(),
                  'icon': existing?.icon ?? 'celebration',
                  'enabled': existing?.enabled ?? true,
                };
                if (existing == null) {
                  await ApiService.instance.createAdminMiniApp(payload);
                } else {
                  await ApiService.instance.updateAdminMiniApp(
                    existing.id,
                    payload,
                  );
                }
                await widget.onSaved();
              },
              child: const Text('บันทึกเครื่องมือ'),
            ),
          ],
        ),
      ],
    );
  }
}
