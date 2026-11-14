import 'package:flutter_test/flutter_test.dart';
import 'package:bcaichat_app/models/models.dart';
import 'package:bcaichat_app/services/notification_service.dart';

ChatMessage _msg(Map<String, dynamic> extra) => ChatMessage.fromJson({
  'id': 'm1',
  'conversation_id': 'c1',
  'sender_id': 'u_kong',
  'sender_name': 'ก้อง',
  'type': 'text',
  'content': 'สวัสดีครับ',
  ...extra,
});

void main() {
  final group = Conversation.fromJson({
    'id': 'c1',
    'kind': 'group',
    'name': 'ห้องทดสอบ',
  });

  test('direct message: sender is the title, text is the body', () {
    final a = NotificationService.describe(_msg({}), myUserId: 'me')!;
    expect(a.title, 'ก้อง');
    expect(a.body, 'สวัสดีครับ');
  });

  test('group message: room is the title, body names the sender', () {
    final a = NotificationService.describe(
      _msg({}),
      myUserId: 'me',
      room: group,
    )!;
    expect(a.title, 'ห้องทดสอบ');
    expect(a.body, 'ก้อง: สวัสดีครับ');
  });

  test('own, system and unsent messages do not alert', () {
    expect(NotificationService.describe(_msg({}), myUserId: 'u_kong'), isNull);
    expect(
      NotificationService.describe(_msg({'type': 'system'}), myUserId: 'me'),
      isNull,
    );
    expect(
      NotificationService.describe(_msg({'is_unsent': true}), myUserId: 'me'),
      isNull,
    );
  });

  test('confidential text is hidden; media, poll, event, rich_card & urgent previews', () {
    final secret = NotificationService.describe(
      _msg({'is_confidential': true, 'content': 'รหัสลับ'}),
      myUserId: 'me',
    )!;
    expect(secret.body, isNot(contains('รหัสลับ')));
    expect(
      NotificationService.describe(_msg({'type': 'image'}), myUserId: 'me')!
          .body,
      'ส่งรูปภาพ',
    );
    expect(
      NotificationService.describe(_msg({'type': 'audio'}), myUserId: 'me')!
          .body,
      'ส่งข้อความเสียง',
    );
    expect(
      NotificationService.describe(_msg({'type': 'poll'}), myUserId: 'me')!
          .body,
      'สร้างแบบโหวต',
    );
    expect(
      NotificationService.describe(_msg({'type': 'event'}), myUserId: 'me')!
          .body,
      'สร้างนัดหมาย',
    );
    expect(
      NotificationService.describe(
        _msg({'type': 'rich_card'}),
        myUserId: 'me',
      )!.body,
      'ส่งการ์ดโต้ตอบ',
    );
    expect(
      NotificationService.describe(
        _msg({
          'type': 'file',
          'attachment': {'file_name': 'ทริปเชียงใหม่.pdf'},
        }),
        myUserId: 'me',
      )!.body,
      'ส่งไฟล์ ทริปเชียงใหม่.pdf',
    );
    expect(
      NotificationService.describe(
        _msg({'priority': 'urgent'}),
        myUserId: 'me',
      )!.body,
      '⚡ ด่วน: สวัสดีครับ',
    );
  });
}
