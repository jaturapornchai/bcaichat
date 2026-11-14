import 'package:intl/intl.dart';

String _extractId(Map<String, dynamic> json) {
  final rawId = json['id'] ?? json['_id'];
  if (rawId is String) return rawId;
  if (rawId is Map && rawId['\$oid'] != null) {
    return rawId['\$oid'].toString();
  }
  return rawId?.toString() ?? '';
}

int _toInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

bool _toBool(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  if (value is num) return value != 0;
  return fallback;
}

String inferDepartment({
  String? rawDepartment,
  String? email,
  String? name,
  String? role,
}) {
  if (rawDepartment != null && rawDepartment.trim().isNotEmpty) {
    return rawDepartment.trim();
  }
  final lowerEmail = (email ?? '').toLowerCase();
  final lowerName = (name ?? '').toLowerCase();
  final lowerRole = (role ?? '').toLowerCase();

  if (lowerRole == 'admin' ||
      lowerEmail.contains('jead') ||
      lowerName.contains('ลุงจืด') ||
      lowerName.contains('admin')) {
    return 'เจ้าของระบบ';
  }
  if (lowerEmail.contains('ai@') ||
      lowerName.contains('bc ai') ||
      lowerName.contains('ผู้ช่วย')) {
    return 'AI ส่วนตัว';
  }
  if (lowerEmail.contains('demo3') ||
      lowerEmail.contains('nida') ||
      lowerName.contains('บอส') ||
      lowerName.contains('นิดา') ||
      lowerName.contains('พี่สาว') ||
      lowerName.contains('ครอบครัว')) {
    return 'ครอบครัว';
  }
  if (lowerEmail.contains('demo5') ||
      lowerName.contains('ต้น') ||
      lowerName.contains('กีฬา')) {
    return 'ก๊วนกีฬา';
  }
  if (lowerEmail.contains('somchai') ||
      lowerName.contains('สมชาย') ||
      lowerName.contains('เพื่อนบ้าน')) {
    return 'เพื่อนบ้าน';
  }
  if (lowerEmail.contains('official') ||
      lowerName.contains('ข่าวสาร') ||
      lowerName.contains('ประกาศ')) {
    return 'ข่าวสารแอป';
  }
  if (lowerEmail.contains('demo1') ||
      lowerEmail.contains('demo2') ||
      lowerEmail.contains('demo4') ||
      lowerName.contains('ก้อง') ||
      lowerName.contains('แพร') ||
      lowerName.contains('มายด์')) {
    return 'เพื่อนสนิท';
  }
  return 'เพื่อน';
}

String formatThaiTime(String? iso) {
  if (iso == null || iso.trim().isEmpty) return '';
  final parsed = DateTime.tryParse(iso)?.toLocal();
  if (parsed == null) return iso;
  final now = DateTime.now();
  final isToday =
      parsed.year == now.year &&
      parsed.month == now.month &&
      parsed.day == now.day;
  if (isToday) {
    return '${DateFormat('HH:mm').format(parsed)} น.';
  }
  return DateFormat('dd/MM HH:mm').format(parsed);
}

String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(2)} MB';
}

class AppUser {
  final String id;
  final String email;
  final String displayName;
  final String bcId;
  final String avatarUrl;
  final String statusMessage;
  final String qrToken;
  final String role;
  final String department;
  final bool isOfficial;
  final bool isOnline;
  final bool isFavorite;
  final bool isBlocked;
  final bool isHidden;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.bcId,
    required this.avatarUrl,
    required this.statusMessage,
    required this.qrToken,
    required this.role,
    required this.department,
    this.isOfficial = false,
    this.isOnline = true,
    this.isFavorite = false,
    this.isBlocked = false,
    this.isHidden = false,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';

  AppUser copyWith({
    String? displayName,
    String? bcId,
    String? avatarUrl,
    String? statusMessage,
    String? role,
    String? department,
    bool? isFavorite,
    bool? isBlocked,
    bool? isHidden,
  }) => AppUser(
    id: id,
    email: email,
    displayName: displayName ?? this.displayName,
    bcId: bcId ?? this.bcId,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    statusMessage: statusMessage ?? this.statusMessage,
    qrToken: qrToken,
    role: role ?? this.role,
    department: department ?? this.department,
    isOfficial: isOfficial,
    isOnline: isOnline,
    isFavorite: isFavorite ?? this.isFavorite,
    isBlocked: isBlocked ?? this.isBlocked,
    isHidden: isHidden ?? this.isHidden,
  );

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final email = (json['email'] ?? '').toString();
    final displayName =
        (json['display_name'] ?? json['displayName'] ?? json['name'] ?? '')
            .toString();
    final role = (json['role'] ?? 'user').toString();

    return AppUser(
      id: _extractId(json),
      email: email,
      displayName: displayName,
      bcId: (json['bc_id'] ?? json['bcId'] ?? '').toString(),
      avatarUrl: (json['avatar_url'] ?? json['avatarUrl'] ?? '').toString(),
      statusMessage:
          (json['status_message'] ??
                  json['statusMessage'] ??
                  'พร้อมแชทบน BC Ai Chat')
              .toString(),
      qrToken: (json['qr_token'] ?? json['qrToken'] ?? '').toString(),
      role: role,
      department: inferDepartment(
        rawDepartment: json['department']?.toString(),
        email: email,
        name: displayName,
        role: role,
      ),
      isOfficial: _toBool(json['is_official'] ?? json['isOfficial'], false),
      isOnline: _toBool(json['is_online'] ?? json['isOnline'], true),
      isFavorite: _toBool(json['is_favorite'] ?? json['isFavorite'], false),
      isBlocked: _toBool(json['is_blocked'] ?? json['isBlocked'], false),
      isHidden: _toBool(json['is_hidden'] ?? json['isHidden'], false),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'bc_id': bcId,
    'avatar_url': avatarUrl,
    'status_message': statusMessage,
    'qr_token': qrToken,
    'role': role,
    'department': department,
    'is_official': isOfficial,
    'is_online': isOnline,
    'is_favorite': isFavorite,
    'is_blocked': isBlocked,
    'is_hidden': isHidden,
  };
}

class AttachmentInfo {
  final String key;
  final String url;
  final String fileName;
  final String mimeType;
  final int fileSize;

  const AttachmentInfo({
    required this.key,
    required this.url,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
  });

  bool get isImage => mimeType.toLowerCase().startsWith('image/');

  factory AttachmentInfo.fromJson(Map<String, dynamic> json) {
    return AttachmentInfo(
      key: (json['key'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      fileName: (json['file_name'] ?? json['fileName'] ?? 'เอกสารแนบ')
          .toString(),
      mimeType:
          (json['mime_type'] ?? json['mimeType'] ?? 'application/octet-stream')
              .toString(),
      fileSize: _toInt(json['file_size'] ?? json['fileSize']),
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'url': url,
    'file_name': fileName,
    'mime_type': mimeType,
    'file_size': fileSize,
  };
}

class ReplySummary {
  final String id;
  final String senderName;
  final String content;
  final String type;

  const ReplySummary({
    required this.id,
    required this.senderName,
    required this.content,
    required this.type,
  });

  factory ReplySummary.fromJson(Map<String, dynamic> json) {
    return ReplySummary(
      id: _extractId(json),
      senderName: (json['sender_name'] ?? json['senderName'] ?? 'สมาชิก')
          .toString(),
      content: (json['content'] ?? '').toString(),
      type: (json['type'] ?? 'text').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sender_name': senderName,
    'content': content,
    'type': type,
  };
}

class PollOption {
  final String id;
  final String text;
  final List<String> voterIds;

  const PollOption({
    required this.id,
    required this.text,
    this.voterIds = const [],
  });

  factory PollOption.fromJson(Map<String, dynamic> json) {
    final raw = json['voter_ids'] ?? json['voterIds'];
    return PollOption(
      id: (json['id'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      voterIds: raw is List ? raw.map((e) => e.toString()).toList() : const [],
    );
  }
}

class PollData {
  final String question;
  final List<PollOption> options;
  final bool allowMultiple;
  final bool isAnonymous;
  final bool isClosed;
  final String? closedAt;

  const PollData({
    required this.question,
    this.options = const [],
    this.allowMultiple = false,
    this.isAnonymous = false,
    this.isClosed = false,
    this.closedAt,
  });

  int get totalVotes => options.fold(0, (sum, o) => sum + o.voterIds.length);

  int get uniqueVotersCount =>
      options.expand((o) => o.voterIds).toSet().length;

  factory PollData.fromJson(Map<String, dynamic> json) {
    final rawOpts = json['options'];
    return PollData(
      question: (json['question'] ?? '').toString(),
      options: rawOpts is List
          ? rawOpts
                .whereType<Map>()
                .map((e) => PollOption.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      allowMultiple: _toBool(
        json['allow_multiple'] ?? json['allowMultiple'],
        false,
      ),
      isAnonymous: _toBool(json['is_anonymous'] ?? json['isAnonymous'], false),
      isClosed: _toBool(json['is_closed'] ?? json['isClosed'], false),
      closedAt: json['closed_at']?.toString(),
    );
  }
}

class EventData {
  final String title;
  final String description;
  final String startsAt;
  final String? endsAt;
  final String location;
  final List<String> goingIds;
  final List<String> maybeIds;
  final List<String> notGoingIds;

  const EventData({
    required this.title,
    this.description = '',
    required this.startsAt,
    this.endsAt,
    this.location = '',
    this.goingIds = const [],
    this.maybeIds = const [],
    this.notGoingIds = const [],
  });

  factory EventData.fromJson(Map<String, dynamic> json) {
    List<String> listOf(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const [];
    return EventData(
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      startsAt: (json['starts_at'] ?? json['startsAt'] ?? '').toString(),
      endsAt: json['ends_at']?.toString() ?? json['endsAt']?.toString(),
      location: (json['location'] ?? '').toString(),
      goingIds: listOf(json['going_ids'] ?? json['goingIds']),
      maybeIds: listOf(json['maybe_ids'] ?? json['maybeIds']),
      notGoingIds: listOf(json['not_going_ids'] ?? json['notGoingIds']),
    );
  }
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String senderDepartment;
  final String type; // text | sticker | image | file | audio | rich_card | poll | event | system
  final String content;
  final String? stickerCode;
  final AttachmentInfo? attachment;
  final Map<String, dynamic>? cardPayload;
  final ReplySummary? replyTo;
  final String? replyToId;
  final List<String> readBy;
  final int readCount;
  final bool isUnsent;
  final bool isConfidential;
  final String priority; // normal | urgent | silent
  final String? taskStatus; // open | accepted | done
  final String? acceptedBy;
  final String? acceptedAt;
  final Map<String, List<String>> reactions;
  final List<String> mentions;
  final int? audioDurationSec;
  final PollData? poll;
  final EventData? eventData;
  final String createdAt;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.senderDepartment,
    required this.type,
    required this.content,
    this.stickerCode,
    this.attachment,
    this.cardPayload,
    this.replyTo,
    this.replyToId,
    required this.readBy,
    required this.readCount,
    required this.isUnsent,
    this.isConfidential = false,
    this.priority = 'normal',
    this.taskStatus,
    this.acceptedBy,
    this.acceptedAt,
    this.reactions = const {},
    this.mentions = const [],
    this.audioDurationSec,
    this.poll,
    this.eventData,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawAttachment = json['attachment'];
    final rawCard = json['card_payload'] ?? json['cardPayload'];
    final rawReply = json['reply_to'] ?? json['replyTo'];
    final rawReadBy = json['read_by'] ?? json['readBy'];

    final readByList = rawReadBy is List
        ? rawReadBy.map((e) => e.toString()).toList()
        : <String>[];

    final cardMap = rawCard is Map<String, dynamic>
        ? rawCard
        : (rawCard is Map ? Map<String, dynamic>.from(rawCard) : null);

    final rawReactions = json['reactions'];
    final parsedReactions = <String, List<String>>{};
    if (rawReactions is Map) {
      for (final entry in rawReactions.entries) {
        if (entry.value is List) {
          parsedReactions[entry.key.toString()] = (entry.value as List)
              .map((e) => e.toString())
              .toList();
        }
      }
    }

    final rawMentions = json['mentions'];
    final mentionsList = rawMentions is List
        ? rawMentions.map((e) => e.toString()).toList()
        : const <String>[];

    final rawPoll = json['poll'];
    final parsedPoll = rawPoll is Map
        ? PollData.fromJson(Map<String, dynamic>.from(rawPoll))
        : null;

    final rawEvent = json['event_data'] ?? json['eventData'];
    final parsedEvent = rawEvent is Map
        ? EventData.fromJson(Map<String, dynamic>.from(rawEvent))
        : null;

    final senderName =
        (json['sender_name'] ?? json['senderName'] ?? 'ผู้ใช้งาน').toString();
    final rawContent = (json['content'] ?? '').toString();

    final confidentialFlag =
        _toBool(json['is_confidential'] ?? json['isConfidential'], false) ||
        _toBool(cardMap?['is_confidential'], false) ||
        rawContent.startsWith('[ลับส่วนตัว]') ||
        rawContent.startsWith('[ลับเฉพาะองค์กร]');

    final rawPriority =
        (json['priority'] ?? cardMap?['priority'] ?? 'normal').toString();
    final rawTaskStatus =
        (json['task_status'] ?? json['taskStatus'] ?? cardMap?['task_status'])
            ?.toString();
    final rawAcceptedBy =
        (json['accepted_by'] ?? json['acceptedBy'] ?? cardMap?['accepted_by'])
            ?.toString();
    final rawAcceptedAt =
        (json['accepted_at'] ?? json['acceptedAt'] ?? cardMap?['accepted_at'])
            ?.toString();

    final rawType = (json['type'] ?? json['message_type'] ?? 'text').toString();
    final normalizedType = rawType.endsWith('_card') && cardMap != null
        ? 'rich_card'
        : rawType;

    final rawAudioDur =
        json['audio_duration_sec'] ?? json['audioDurationSec'];

    return ChatMessage(
      id: _extractId(json),
      conversationId:
          (json['conversation_id'] ?? json['conversationId'] ?? '').toString(),
      senderId: (json['sender_id'] ?? json['senderId'] ?? '').toString(),
      senderName: senderName,
      senderAvatar:
          (json['sender_avatar'] ?? json['senderAvatar'] ?? '').toString(),
      senderDepartment: inferDepartment(
        rawDepartment:
            (json['sender_department'] ?? json['senderDepartment'])?.toString(),
        name: senderName,
      ),
      type: normalizedType,
      content: rawContent,
      stickerCode: json['sticker_code']?.toString(),
      attachment: rawAttachment is Map<String, dynamic>
          ? AttachmentInfo.fromJson(rawAttachment)
          : (rawAttachment is Map
                ? AttachmentInfo.fromJson(
                    Map<String, dynamic>.from(rawAttachment),
                  )
                : null),
      cardPayload: cardMap,
      replyTo: rawReply is Map<String, dynamic>
          ? ReplySummary.fromJson(rawReply)
          : (rawReply is Map
                ? ReplySummary.fromJson(Map<String, dynamic>.from(rawReply))
                : null),
      replyToId: json['reply_to_id']?.toString(),
      readBy: readByList,
      readCount: _toInt(
        json['read_count'] ?? json['readCount'],
        readByList.length > 1 ? readByList.length - 1 : 0,
      ),
      isUnsent: _toBool(json['is_unsent'] ?? json['isUnsent'], false),
      isConfidential: confidentialFlag,
      priority: rawPriority.isEmpty ? 'normal' : rawPriority,
      taskStatus: rawTaskStatus,
      acceptedBy: rawAcceptedBy,
      acceptedAt: rawAcceptedAt,
      reactions: parsedReactions,
      mentions: mentionsList,
      audioDurationSec: rawAudioDur != null ? _toInt(rawAudioDur) : null,
      poll: parsedPoll,
      eventData: parsedEvent,
      createdAt: (json['created_at'] ?? json['createdAt'] ?? '').toString(),
    );
  }

  String get cleanContent {
    for (final tag in const ['[ลับส่วนตัว] ', '[ลับส่วนตัว]', '[ลับเฉพาะองค์กร] ', '[ลับเฉพาะองค์กร]']) {
      if (content.startsWith(tag)) {
        return content.substring(tag.length).trimLeft();
      }
    }
    return content;
  }

  String get previewText {
    if (isUnsent) return 'ยกเลิกข้อความและลบข้อมูลแล้ว';
    final prefix = isConfidential ? '🔒 [ลับส่วนตัว] ' : '';
    switch (type) {
      case 'sticker':
        return '$prefix[สติ๊กเกอร์] $cleanContent';
      case 'image':
        return '$prefix[รูปภาพ] ${attachment?.fileName ?? cleanContent}';
      case 'file':
        return '$prefix[ไฟล์เอกสาร] ${attachment?.fileName ?? cleanContent}';
      case 'audio':
        final dur = audioDurationSec != null && audioDurationSec! > 0
            ? ' (${audioDurationSec}s)'
            : '';
        return '$prefix[ข้อความเสียง]$dur';
      case 'rich_card':
        final title = cardPayload?['title']?.toString() ?? cleanContent;
        return '$prefix[การ์ดโต้ตอบ] $title';
      case 'poll':
        final q = poll?.question ?? cleanContent;
        return '$prefix[โพล] $q';
      case 'event':
        final t = eventData?.title ?? cleanContent;
        return '$prefix[นัดหมาย] $t';
      default:
        return '$prefix$cleanContent';
    }
  }
}

class Conversation {
  final String id;
  final String kind; // direct | group | official
  final String name;
  final String avatarUrl;
  final String folder; // personal | work | official
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final String inviteToken;
  final List<String> adminIds;
  final List<String> memberIds;
  final int memberCount;
  final int unreadCount;
  final ChatMessage? pinnedMessage;
  final ChatMessage? lastMessage;
  final AppUser? peerUser;
  final String updatedAt;

  const Conversation({
    required this.id,
    required this.kind,
    required this.name,
    required this.avatarUrl,
    required this.folder,
    required this.isPinned,
    this.isMuted = false,
    this.isArchived = false,
    this.inviteToken = '',
    this.adminIds = const [],
    required this.memberIds,
    required this.memberCount,
    required this.unreadCount,
    this.pinnedMessage,
    this.lastMessage,
    this.peerUser,
    required this.updatedAt,
  });

  bool get isGroup => kind == 'group';
  bool get isOfficial => kind == 'official' || folder == 'official';
  bool get isFamily => folder == 'family' || folder == 'work';
  bool get isWork => isFamily;

  String get folderLabel {
    if (isArchived || folder == 'archived') return 'เก็บถาวร';
    switch (folder) {
      case 'family':
      case 'work':
        return 'ครอบครัว';
      case 'official':
        return 'ข่าวสารแอป';
      default:
        return 'ส่วนตัว';
    }
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['member_ids'] ?? json['memberIds'];
    final members = rawMembers is List
        ? rawMembers.map((e) => e.toString()).toList()
        : <String>[];

    final rawPinned = json['pinned_message'] ?? json['pinnedMessage'];
    final rawLast = json['last_message'] ?? json['lastMessage'];
    final rawPeer = json['peer_user'] ?? json['peerUser'];

    final rawAdmins = json['admin_ids'] ?? json['adminIds'];
    final adminList = rawAdmins is List
        ? rawAdmins.map((e) => e.toString()).toList()
        : const <String>[];

    return Conversation(
      id: _extractId(json),
      kind: (json['kind'] ?? json['type'] ?? 'direct').toString(),
      name: (json['name'] ?? json['title'] ?? 'ห้องสนทนา').toString(),
      avatarUrl: (json['avatar_url'] ?? json['avatarUrl'] ?? '').toString(),
      folder: (json['folder'] ?? 'personal').toString(),
      isPinned: _toBool(json['is_pinned'] ?? json['isPinned'], false),
      isMuted: _toBool(json['is_muted'] ?? json['isMuted'], false),
      isArchived: _toBool(json['is_archived'] ?? json['isArchived'], false),
      inviteToken:
          (json['invite_token'] ?? json['inviteToken'] ?? '').toString(),
      adminIds: adminList,
      memberIds: members,
      memberCount: _toInt(
        json['member_count'] ?? json['memberCount'],
        members.isNotEmpty ? members.length : 2,
      ),
      unreadCount: _toInt(json['unread_count'] ?? json['unreadCount'], 0),
      pinnedMessage: rawPinned is Map<String, dynamic>
          ? ChatMessage.fromJson(rawPinned)
          : (rawPinned is Map
                ? ChatMessage.fromJson(Map<String, dynamic>.from(rawPinned))
                : null),
      lastMessage: rawLast is Map<String, dynamic>
          ? ChatMessage.fromJson(rawLast)
          : (rawLast is Map
                ? ChatMessage.fromJson(Map<String, dynamic>.from(rawLast))
                : null),
      peerUser: rawPeer is Map<String, dynamic>
          ? AppUser.fromJson(rawPeer)
          : (rawPeer is Map
                ? AppUser.fromJson(Map<String, dynamic>.from(rawPeer))
                : null),
      updatedAt: (json['updated_at'] ?? json['updatedAt'] ?? '').toString(),
    );
  }
}

class VaultData {
  final List<ChatMessage> images;
  final List<ChatMessage> files;
  final List<ChatMessage> links;

  const VaultData({
    required this.images,
    required this.files,
    required this.links,
  });

  factory VaultData.fromJson(Map<String, dynamic> json) {
    List<ChatMessage> parseList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return VaultData(
      images: parseList(json['images']),
      files: parseList(json['files']),
      links: parseList(json['links']),
    );
  }
}

class MiniAppItem {
  final String id;
  final String code;
  final String title;
  final String subtitle;
  final String category;
  final String icon;
  final String color;
  final String url;
  final bool enabled;

  const MiniAppItem({
    required this.id,
    required this.code,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.color,
    required this.url,
    required this.enabled,
  });

  factory MiniAppItem.fromJson(Map<String, dynamic> json) {
    return MiniAppItem(
      id: _extractId(json),
      code: (json['code'] ?? 'custom_app').toString(),
      title: (json['title'] ?? json['name'] ?? 'Mini-App').toString(),
      subtitle:
          (json['subtitle'] ?? json['description'] ?? 'บริการเสริม BC Ai Chat')
              .toString(),
      category: (json['category'] ?? 'ไลฟ์สไตล์ & เพื่อน').toString(),
      icon: (json['icon'] ?? 'widgets').toString(),
      color: (json['color'] ?? '#812920').toString(),
      url: (json['url'] ?? '').toString(),
      enabled: _toBool(json['enabled'] ?? json['is_enabled'], true),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'title': title,
    'subtitle': subtitle,
    'category': category,
    'icon': icon,
    'color': color,
    'url': url,
    'enabled': enabled,
  };
}

class NoteComment {
  final String id;
  final String userId;
  final String userName;
  final String content;
  final String createdAt;

  const NoteComment({
    required this.id,
    required this.userId,
    required this.userName,
    required this.content,
    required this.createdAt,
  });

  factory NoteComment.fromJson(Map<String, dynamic> json) {
    return NoteComment(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      userName: (json['user_name'] ?? json['userName'] ?? 'สมาชิก').toString(),
      content: (json['content'] ?? '').toString(),
      createdAt: (json['created_at'] ?? json['createdAt'] ?? '').toString(),
    );
  }
}

class NoteItem {
  final String id;
  final String userId;
  final String ownerName;
  final String? conversationId;
  final String title;
  final String content;
  final String category;
  final String color;
  final bool isPinned;
  final List<String> likedBy;
  final List<NoteComment> comments;
  final List<AttachmentInfo> attachments;
  final AttachmentInfo? attachment;
  final String createdAt;

  const NoteItem({
    required this.id,
    required this.userId,
    this.ownerName = '',
    this.conversationId,
    required this.title,
    required this.content,
    required this.category,
    required this.color,
    this.isPinned = false,
    this.likedBy = const [],
    this.comments = const [],
    this.attachments = const [],
    this.attachment,
    required this.createdAt,
  });

  factory NoteItem.fromJson(Map<String, dynamic> json) {
    final rawAtt = json['attachment'];
    final rawAtts = json['attachments'];
    final atts = rawAtts is List
        ? rawAtts
              .whereType<Map>()
              .map((e) => AttachmentInfo.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : const <AttachmentInfo>[];
    final singleAtt = rawAtt is Map
        ? AttachmentInfo.fromJson(Map<String, dynamic>.from(rawAtt))
        : (atts.isNotEmpty ? atts.first : null);
    final rawLikes = json['liked_by'] ?? json['likedBy'];
    final rawComments = json['comments'];
    return NoteItem(
      id: _extractId(json),
      userId:
          (json['user_id'] ?? json['userId'] ?? json['owner_id'] ?? '')
              .toString(),
      ownerName: (json['owner_name'] ?? json['ownerName'] ?? '').toString(),
      conversationId: json['conversation_id']?.toString(),
      title: (json['title'] ?? 'บันทึกสำคัญ').toString(),
      content: (json['content'] ?? '').toString(),
      category: (json['category'] ?? 'ทั่วไป').toString(),
      color: (json['color'] ?? '#812920').toString(),
      isPinned: _toBool(json['is_pinned'] ?? json['isPinned'], false),
      likedBy: rawLikes is List
          ? rawLikes.map((e) => e.toString()).toList()
          : const [],
      comments: rawComments is List
          ? rawComments
                .whereType<Map>()
                .map((e) => NoteComment.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      attachments: atts,
      attachment: singleAtt,
      createdAt: (json['created_at'] ?? json['createdAt'] ?? '').toString(),
    );
  }
}

class AlbumItem {
  final String id;
  final String conversationId;
  final String title;
  final String description;
  final List<AttachmentInfo> photos;
  final String createdBy;
  final String createdByName;
  final String createdAt;
  final String updatedAt;

  const AlbumItem({
    required this.id,
    required this.conversationId,
    required this.title,
    this.description = '',
    this.photos = const [],
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AlbumItem.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'];
    return AlbumItem(
      id: _extractId(json),
      conversationId:
          (json['conversation_id'] ?? json['conversationId'] ?? '').toString(),
      title: (json['title'] ?? 'อัลบั้มรูปภาพ').toString(),
      description: (json['description'] ?? '').toString(),
      photos: rawPhotos is List
          ? rawPhotos
                .whereType<Map>()
                .map(
                  (e) => AttachmentInfo.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
      createdBy: (json['created_by'] ?? json['createdBy'] ?? '').toString(),
      createdByName:
          (json['created_by_name'] ?? json['createdByName'] ?? '').toString(),
      createdAt: (json['created_at'] ?? json['createdAt'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? json['updatedAt'] ?? '').toString(),
    );
  }
}

class AdminOverview {
  final int totalUsers;
  final int totalConversations;
  final int totalMessages;
  final int totalFiles;
  final int totalStorageBytes;
  final int totalMiniApps;
  final String minioBucket;
  final String mongoDb;

  const AdminOverview({
    required this.totalUsers,
    required this.totalConversations,
    required this.totalMessages,
    required this.totalFiles,
    required this.totalStorageBytes,
    required this.totalMiniApps,
    required this.minioBucket,
    required this.mongoDb,
  });

  factory AdminOverview.fromJson(Map<String, dynamic> json) {
    return AdminOverview(
      totalUsers: _toInt(json['total_users'] ?? json['users_count']),
      totalConversations: _toInt(
        json['total_conversations'] ?? json['conversations_count'],
      ),
      totalMessages: _toInt(json['total_messages'] ?? json['messages_count']),
      totalFiles: _toInt(json['total_files'] ?? json['files_count']),
      totalStorageBytes: _toInt(
        json['total_storage_bytes'] ?? json['storage_bytes'],
      ),
      totalMiniApps: _toInt(json['total_mini_apps'] ?? json['mini_apps_count']),
      minioBucket: (json['minio_bucket'] ?? 'bcaichat-storage').toString(),
      mongoDb: (json['mongo_db'] ?? 'bcaichat (127.0.0.1:27030)').toString(),
    );
  }
}

class AiSummaryResult {
  final String summary;
  final List<String> actionItems;
  final List<String> decisions;
  final String model;

  const AiSummaryResult({
    required this.summary,
    required this.actionItems,
    required this.decisions,
    required this.model,
  });

  factory AiSummaryResult.fromJson(Map<String, dynamic> json) {
    List<String> toStrList(dynamic raw) {
      if (raw is List) {
        return raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    final rawSummary =
        (json['summary'] ??
                json['executive_summary'] ??
                json['result'] ??
                json['content'] ??
                '')
            .toString()
            .trim();

    var actions = toStrList(json['action_items'] ?? json['actionItems']);
    var decisions = toStrList(json['decisions'] ?? json['key_decisions']);

    if (actions.isEmpty && rawSummary.isNotEmpty) {
      final lines = rawSummary
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.startsWith('- ') || l.startsWith('• '))
          .map((l) => l.substring(2).trim())
          .toList();
      if (lines.isNotEmpty) {
        actions = lines.take(4).toList();
      }
    }

    return AiSummaryResult(
      summary: rawSummary.isNotEmpty
          ? rawSummary
          : 'สรุปผลการสนทนาในห้องแชทเรียบร้อยแล้ว',
      actionItems: actions,
      decisions: decisions,
      model: (json['model'] ?? 'deepseek-chat').toString(),
    );
  }

  String toFormattedNote() {
    final buf = StringBuffer();
    buf.writeln('✨ สรุปแชทโดยสมองกล DeepSeek AI ($model)');
    buf.writeln('📌 สรุปประเด็นสำคัญ:');
    buf.writeln(summary);
    if (actionItems.isNotEmpty) {
      buf.writeln('\n✅ สิ่งที่ต้องทำต่อ:');
      for (final item in actionItems) {
        buf.writeln('• $item');
      }
    }
    if (decisions.isNotEmpty) {
      buf.writeln('\n💡 ข้อตกลงและการตัดสินใจ:');
      for (final d in decisions) {
        buf.writeln('• $d');
      }
    }
    return buf.toString().trim();
  }
}

class AiAssistResult {
  final String suggestion;
  final List<String> alternatives;
  final String mode;
  final String model;

  const AiAssistResult({
    required this.suggestion,
    required this.alternatives,
    required this.mode,
    required this.model,
  });

  factory AiAssistResult.fromJson(Map<String, dynamic> json) {
    final mainText =
        (json['suggestion'] ??
                json['result'] ??
                json['content'] ??
                json['reply'] ??
                json['text'] ??
                '')
            .toString()
            .trim();
    final rawAlt = json['alternatives'] ?? json['options'] ?? json['suggestions'];
    final altList = rawAlt is List
        ? rawAlt
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];

    return AiAssistResult(
      suggestion: mainText,
      alternatives: altList,
      mode: (json['mode'] ?? 'polite').toString(),
      model: (json['model'] ?? 'deepseek-chat').toString(),
    );
  }
}

class AiAdminSettings {
  final String model;
  final String maskedKey;
  final bool hasKey;
  final String systemPrompt;
  final bool enabled;

  const AiAdminSettings({
    required this.model,
    required this.maskedKey,
    required this.hasKey,
    required this.systemPrompt,
    required this.enabled,
  });

  factory AiAdminSettings.fromJson(Map<String, dynamic> json) {
    final masked =
        (json['masked_key'] ?? json['api_key_masked'] ?? json['maskedKey'] ?? '')
            .toString();
    return AiAdminSettings(
      model: (json['model'] ?? 'deepseek-chat').toString(),
      maskedKey: masked.isNotEmpty ? masked : 'ตั้งค่าผ่านระบบหลังบ้าน',
      hasKey: _toBool(
        json['has_key'] ?? json['hasKey'] ?? json['configured'],
        masked.isNotEmpty,
      ),
      systemPrompt:
          (json['system_prompt'] ??
                  json['systemPrompt'] ??
                  'คุณคือ BC AI ผู้ช่วยส่วนตัวประจำทุกห้องแชทของ BC Ai Chat ช่วยคิดคำตอบ เกลาข้อความ สรุปนัดหมาย และช่วยวางแผนกับครอบครัวและเพื่อนๆ อย่างเป็นกันเอง')
              .toString(),
      enabled: _toBool(json['enabled'], true),
    );
  }
}
