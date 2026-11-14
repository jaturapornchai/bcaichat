import 'package:bcaichat_app/models/models.dart';
import 'package:bcaichat_app/services/api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ApiService derives WS URL and honors custom Server URL preference', () async {
    expect(
      ApiService.deriveWsUrl('http://127.0.0.1:8096'),
      'ws://127.0.0.1:8096/ws',
    );
    expect(
      ApiService.deriveWsUrl('https://chat.bcaichat.example/'),
      'wss://chat.bcaichat.example/ws',
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(ApiService.defaultBaseUrl, 'http://10.0.2.2:8096');
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(ApiService.defaultBaseUrl, 'http://127.0.0.1:8096');
    debugDefaultTargetPlatformOverride = null;

    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.setCustomBaseUrl('http://192.168.1.50:8096/');
    expect(ApiService.baseUrl, 'http://192.168.1.50:8096');
    expect(ApiService.wsBaseUrl, 'ws://192.168.1.50:8096/ws');

    await ApiService.instance.setCustomBaseUrl('');
    expect(ApiService.baseUrl, ApiService.defaultBaseUrl);
  });

  test('Models parse Ban Chiang new fields (reactions, audio, poll, event, album, notes, friends, conv)', () {
    final user = AppUser.fromJson({
      'id': 'u1',
      'email': 'demo1@bcaichat.local',
      'display_name': 'ก้อง (Demo 1)',
      'is_favorite': true,
      'is_blocked': false,
      'is_hidden': false,
    });
    expect(user.isFavorite, isTrue);
    expect(user.department, 'เพื่อนสนิท');
    expect(user.copyWith(isHidden: true).isHidden, isTrue);

    final fallbackUser = AppUser.fromJson({
      'id': 'u_plain',
      'email': 'plain@bcaichat.local',
      'display_name': 'ชาตรี',
    });
    expect(fallbackUser.department, 'เพื่อน');

    final conv = Conversation.fromJson({
      'id': 'c1',
      'kind': 'group',
      'name': 'แก๊งเพื่อนทดสอบ',
      'folder': 'family',
      'is_muted': true,
      'is_archived': true,
      'invite_token': 'INV-999',
      'admin_ids': ['u1'],
      'member_ids': ['u1', 'user_ai'],
    });
    expect(conv.isMuted, isTrue);
    expect(conv.isArchived, isTrue);
    expect(conv.isFamily, isTrue);
    expect(conv.folderLabel, 'เก็บถาวร');
    expect(conv.inviteToken, 'INV-999');
    expect(conv.adminIds, ['u1']);

    final familyConv = Conversation.fromJson({
      'id': 'c1_family',
      'kind': 'group',
      'name': 'บ้านเราอบอุ่น',
      'folder': 'family',
    });
    expect(familyConv.isFamily, isTrue);
    expect(familyConv.folderLabel, 'ครอบครัว');

    final legacyFamilyConv = Conversation.fromJson({
      'id': 'c2',
      'kind': 'group',
      'name': 'กลุ่มบ้านเก่า',
      'folder': 'work',
    });
    expect(legacyFamilyConv.isFamily, isTrue);
    expect(legacyFamilyConv.folderLabel, 'ครอบครัว');

    final secretMsg = ChatMessage.fromJson({
      'id': 'm_sec1',
      'conversation_id': 'c1',
      'sender_id': 'u1',
      'sender_name': 'ก้อง',
      'type': 'text',
      'content': '[ลับส่วนตัว] รหัสเปิดประตูบ้าน 2468',
    });
    expect(secretMsg.isConfidential, isTrue);
    expect(secretMsg.cleanContent, 'รหัสเปิดประตูบ้าน 2468');

    final legacySecretMsg = ChatMessage.fromJson({
      'id': 'm_sec2',
      'conversation_id': 'c1',
      'sender_id': 'u1',
      'sender_name': 'ก้อง',
      'type': 'text',
      'content': '[ลับเฉพาะองค์กร] ข้อความเก่า',
    });
    expect(legacySecretMsg.isConfidential, isTrue);
    expect(legacySecretMsg.cleanContent, 'ข้อความเก่า');

    final pollMsg = ChatMessage.fromJson({
      'id': 'm_poll',
      'conversation_id': 'c1',
      'sender_id': 'u1',
      'sender_name': 'สมชาย',
      'type': 'poll',
      'content': 'กินข้าวไหน',
      'reactions': {
        '👍': ['u1', 'u2'],
      },
      'mentions': ['all', 'user_ai'],
      'poll': {
        'question': 'เลือกเมนู',
        'options': [
          {'id': 'o1', 'text': 'ก๋วยเตี๋ยว', 'voter_ids': ['u1']},
          {'id': 'o2', 'text': 'ส้มตำ', 'voter_ids': []},
        ],
        'allow_multiple': false,
        'is_anonymous': false,
        'is_closed': false,
      },
    });
    expect(pollMsg.reactions['👍'], ['u1', 'u2']);
    expect(pollMsg.mentions, ['all', 'user_ai']);
    expect(pollMsg.poll?.totalVotes, 1);

    final eventMsg = ChatMessage.fromJson({
      'id': 'm_ev',
      'conversation_id': 'c1',
      'sender_id': 'u1',
      'sender_name': 'ก้อง',
      'type': 'event',
      'content': 'นัดปิกนิกวันเสาร์',
      'event_data': {
        'title': 'ปิกนิกบ้านเชียง',
        'starts_at': '2026-11-15T09:00:00Z',
        'location': 'คาเฟ่ริมน้ำ',
        'going_ids': ['u1'],
        'maybe_ids': ['u2'],
        'not_going_ids': [],
      },
    });
    expect(eventMsg.eventData?.title, 'ปิกนิกบ้านเชียง');
    expect(eventMsg.eventData?.goingIds, ['u1']);

    final audioMsg = ChatMessage.fromJson({
      'id': 'm_aud',
      'conversation_id': 'c1',
      'sender_id': 'u1',
      'sender_name': 'ก้อง',
      'type': 'audio',
      'content': 'voice.mp3',
      'audio_duration_sec': 42,
    });
    expect(audioMsg.audioDurationSec, 42);
    expect(audioMsg.previewText, contains('42s'));

    final note = NoteItem.fromJson({
      'id': 'n1',
      'user_id': 'u1',
      'title': 'บันทึก',
      'content': 'รายละเอียด',
      'is_pinned': true,
      'liked_by': ['u1', 'u2'],
      'comments': [
        {
          'id': 'cm1',
          'user_id': 'u2',
          'user_name': 'นิดา',
          'content': 'รับทราบค่ะ',
          'created_at': '2026-11-14T10:00:00Z',
        },
      ],
    });
    expect(note.isPinned, isTrue);
    expect(note.likedBy, hasLength(2));
    expect(note.comments.first.userName, 'นิดา');

    final album = AlbumItem.fromJson({
      'id': 'a1',
      'conversation_id': 'c1',
      'title': 'ทริปเชียงใหม่',
      'photos': [
        {
          'key': 'k1',
          'url': 'http://127.0.0.1:8096/api/files/k1',
          'file_name': 'trip.jpg',
          'mime_type': 'image/jpeg',
          'file_size': 1024,
        },
      ],
      'created_by': 'u1',
      'created_by_name': 'ก้อง',
    });
    expect(album.photos.single.fileName, 'trip.jpg');
  });
}
