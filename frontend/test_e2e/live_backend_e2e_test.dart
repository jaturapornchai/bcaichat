import 'dart:convert';
import 'dart:io';

import 'package:bcaichat_app/models/models.dart';
import 'package:bcaichat_app/services/api_service.dart';
import 'package:bcaichat_app/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Live E2E HTTP + WebSocket verification using Flutter's real [ApiService]
/// and [models.dart] against the running Rust backend on :8096.
///
/// Run when backend (:8096) is running:
///   flutter test test_e2e/live_backend_e2e_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Kept in test_e2e/ so bare `flutter test` remains deterministic offline.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    // Restore real dart:io HTTP/WS sockets (TestWidgetsFlutterBinding mocks them).
    HttpOverrides.global = null;
    await ApiService.instance.setCustomBaseUrl('http://127.0.0.1:8096');
  });

  tearDown(() async {
    await ApiService.instance.logout();
  });

  test('Live :8096 E2E: health, Ban Chiang theme, 5 Demo + admin logins, WS, reactions, poll, event, album, notes, group AI', () async {
    // 1. Health + default Ban Chiang theme
    final healthRes = await http.get(
      Uri.parse('${ApiService.baseUrl}/api/health'),
    );
    expect(healthRes.statusCode, 200);
    final health = jsonDecode(healthRes.body) as Map<String, dynamic>;
    expect(health['status'], 'ok');
    expect(health['mongodb'], isTrue);
    expect(health['minio'], isTrue);

    await ApiService.instance.loadBusinessTheme();
    expect(AppTheme.preset.value.code, 'ban_chiang');

    // 2. Verify jead + all 5 Demo accounts log in cleanly via ApiService
    final jead = await ApiService.instance.loginWithGoogle(
      email: 'jead@bcaichat.local',
      displayName: 'ลุงจืด',
    );
    expect(jead.email, 'jead@bcaichat.local');
    expect(jead.isAdmin, isTrue);

    final demos = <AppUser>[];
    for (var i = 1; i <= 5; i++) {
      final u = await ApiService.instance.loginWithGoogle(
        email: 'demo$i@bcaichat.local',
        displayName: 'Demo $i',
      );
      expect(u.email, 'demo$i@bcaichat.local');
      demos.add(u);
    }

    // Stay signed in as Demo 1 for room + WS actions
    final demo1 = await ApiService.instance.loginWithGoogle(
      email: 'demo1@bcaichat.local',
      displayName: 'ก้อง (Demo 1)',
    );
    final convs = await ApiService.instance.fetchConversations();
    final demoRoom = convs.firstWhere(
      (c) => c.id == 'conv_group_demo5' || c.name.contains('5 คน'),
    );
    expect(demoRoom.memberIds, contains(demo1.id));

    // Also verify a secondary WebSocket client (Demo 2) receives live broadcasts
    final demo2LoginRes = await http.post(
      Uri.parse('${ApiService.baseUrl}/api/auth/google'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'email': 'demo2@bcaichat.local',
        'display_name': 'แพร (Demo 2)',
      }),
    );
    expect(demo2LoginRes.statusCode, 200);
    final demo2Token =
        (jsonDecode(demo2LoginRes.body) as Map<String, dynamic>)['token']
            .toString();
    final demo2WsEvents = <Map<String, dynamic>>[];
    final demo2Ws = WebSocketChannel.connect(
      Uri.parse(
        '${ApiService.wsBaseUrl}?token=${Uri.encodeComponent(demo2Token)}&device=flutter_e2e_d2',
      ),
    );
    final demo2Sub = demo2Ws.stream.listen((raw) {
      if (raw is String && raw.isNotEmpty) {
        try {
          final parsed = jsonDecode(raw);
          if (parsed is Map) {
            demo2WsEvents.add(Map<String, dynamic>.from(parsed));
          }
        } catch (_) {}
      }
    });

    try {
      // Wait briefly for Demo 2 WS registration on backend
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // 3. Send message with @all mention & verify WS broadcast on Demo 2
      final tagText = 'ทดสอบ Flutter E2E @all #${DateTime.now().millisecondsSinceEpoch}';
      final sent = await ApiService.instance.sendMessage(
        demoRoom.id,
        type: 'text',
        content: tagText,
        mentions: const ['all'],
      );
      expect(sent.content, tagText);
      expect(sent.mentions, contains('all'));

      await _waitForCondition(
        () => demo2WsEvents.any(
          (e) =>
              jsonEncode(e).contains(sent.id),
        ),
        timeout: const Duration(seconds: 6),
        reason: 'Demo 2 WebSocket did not receive Flutter sent message event',
      );

      // 4. Emoji reaction + delete-for-me
      final reacted = await ApiService.instance.reactMessage(sent.id, '👍');
      expect(reacted?.reactions['👍'], contains(demo1.id));

      await ApiService.instance.deleteMessageForMe(sent.id);
      final afterDelete = await ApiService.instance.fetchMessages(demoRoom.id);
      expect(afterDelete.any((m) => m.id == sent.id), isFalse);

      // Clean up sent message for everyone too so room stays clean
      await ApiService.instance.unsendMessage(sent.id, hard: true);

      // 5. Polls: create -> vote -> close
      final pollMsg = await ApiService.instance.createPoll(
        demoRoom.id,
        question: 'เมนูมื้อเที่ยง E2E?',
        options: const ['ก๋วยเตี๋ยว', 'ส้มตำ'],
      );
      expect(pollMsg.type, 'poll');
      expect(pollMsg.poll?.options.length, 2);
      final firstOptionId = pollMsg.poll!.options.first.id;
      final voted = await ApiService.instance.votePoll(
        pollMsg.id,
        [firstOptionId],
      );
      expect(voted.poll?.totalVotes, greaterThanOrEqualTo(1));
      final closed = await ApiService.instance.closePoll(pollMsg.id);
      expect(closed.poll?.isClosed, isTrue);
      await ApiService.instance.unsendMessage(pollMsg.id, hard: true);

      // 6. Events: create -> RSVP going -> fetchEvents
      final evMsg = await ApiService.instance.createEvent(
        demoRoom.id,
        title: 'นัดเจอแก๊งเพื่อน Flutter E2E',
        startsAt: '2026-11-20T09:00:00Z',
        location: 'คาเฟ่บ้านเชียง',
      );
      expect(evMsg.type, 'event');
      final rsvped = await ApiService.instance.rsvpEvent(evMsg.id, 'going');
      expect(rsvped.eventData?.goingIds, contains(demo1.id));
      final evList = await ApiService.instance.fetchEvents(demoRoom.id);
      expect(evList.any((e) => e.id == evMsg.id), isTrue);
      await ApiService.instance.unsendMessage(evMsg.id, hard: true);

      // 7. Albums: create -> fetchAlbums -> deleteAlbum
      final album = await ApiService.instance.createAlbum(
        demoRoom.id,
        title: 'อัลบั้มทดสอบ Flutter E2E',
        description: 'สร้างอัตโนมัติและลบทิ้งหลังตรวจ',
      );
      final albums = await ApiService.instance.fetchAlbums(demoRoom.id);
      expect(albums.any((a) => a.id == album.id), isTrue);
      await ApiService.instance.deleteAlbum(album.id);

      // 8. Notes: create -> toggle like -> comment -> delete
      final note = await ApiService.instance.createNote(
        conversationId: demoRoom.id,
        title: 'โน้ตทดสอบ Flutter E2E',
        content: 'ทดสอบถูกใจและคอมเมนต์',
      );
      final likedNote = await ApiService.instance.toggleNoteLike(note.id);
      expect(likedNote.likedBy, contains(demo1.id));
      final commentedNote = await ApiService.instance.addNoteComment(
        note.id,
        'ทดสอบคอมเมนต์จาก Flutter',
      );
      expect(
        commentedNote.comments.any((c) => c.content.contains('Flutter')),
        isTrue,
      );
      await ApiService.instance.deleteNote(note.id);

      // 9. Friend meta toggle + restore
      final friends = await ApiService.instance.fetchFriends();
      final targetFriend = friends.firstWhere(
        (f) => f.id != demo1.id && f.id != 'user_ai',
      );
      final origFav = targetFriend.isFavorite;
      final toggledFav = await ApiService.instance.updateFriendMeta(
        targetFriend.id,
        isFavorite: !origFav,
      );
      expect(toggledFav?.isFavorite, !origFav);
      await ApiService.instance.updateFriendMeta(
        targetFriend.id,
        isFavorite: origFav,
      );

      // 10. Group create -> invite BC AI -> Demo 3 join by inviteToken -> leave
      final tempGroup = await ApiService.instance.createGroupConversation(
        name: 'กลุ่มเพื่อนชั่วคราว Flutter E2E',
        folder: 'family',
        memberIds: [demos[1].id],
      );
      expect(tempGroup.inviteToken, isNotEmpty);
      final withAi = await ApiService.instance.addConversationMembers(
        tempGroup.id,
        const ['user_ai'],
      );
      expect(withAi.memberIds, contains('user_ai'));

      // Demo 3 joins via inviteToken then leaves
      final demo3 = await ApiService.instance.loginWithGoogle(
        email: 'demo3@bcaichat.local',
        displayName: 'บอส (Demo 3)',
      );
      final joined = await ApiService.instance.joinConversationByToken(
        tempGroup.inviteToken,
      );
      expect(joined.id, tempGroup.id);
      expect(joined.memberIds, contains(demo3.id));
      await ApiService.instance.removeConversationMember(tempGroup.id, demo3.id);

      // Clean leave for Demo 1 & Demo 2 too
      await ApiService.instance.loginWithGoogle(
        email: 'demo1@bcaichat.local',
        displayName: 'ก้อง (Demo 1)',
      );
      await ApiService.instance.removeConversationMember(tempGroup.id, demo1.id);
    } finally {
      await demo2Sub.cancel();
      await demo2Ws.sink.close();
    }
  });
}

Future<void> _waitForCondition(
  bool Function() predicate, {
  required Duration timeout,
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail(reason);
}
