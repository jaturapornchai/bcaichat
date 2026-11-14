import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String src(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  // "บันทึกเข้าสมุดบันทึก BC" must persist both a room note and a personal note
  // so it shows up in both places.
  test('saving an AI summary also creates a personal notebook entry', () {
    final ui = src('lib/screens/chat_room_screen.dart');
    final start = ui.indexOf('onSaveToNotebook:');
    expect(start, isNot(-1));
    final body = ui.substring(start, ui.indexOf('showSnackBar', start));
    expect(body, contains('[_conversation.id, null]'));
  });

  // Opening the สมุดบันทึก BC tab must reload notes on both nav bars.
  test('opening the notebook tab reloads its notes', () {
    final ui = src('lib/screens/main_shell.dart');
    expect(
      'if (idx == 2) _reloadNotebookNotes();'.allMatches(ui).length,
      2,
      reason: 'both the bottom bar and the side rail must reload',
    );
  });
}
