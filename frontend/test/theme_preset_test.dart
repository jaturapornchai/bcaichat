import 'package:bcaichat_app/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ban Chiang personal theme presets & 3 chat room modes', () {
    expect(ThemePreset.all.map((p) => p.code), [
      'ban_chiang',
      'silk_amber',
      'indigo_kram',
      'jade_celadon',
      'lotus_rose',
      'spice_cinnamon',
      'royal_amethyst',
    ]);
    expect(ThemePreset.all.first.primary.toARGB32(), 0xFF812920);
    expect(ThemePreset.all.first.deep.toARGB32(), 0xFF681F18);
    expect(ThemePreset.all.first.soft.toARGB32(), 0xFFFFDAD5);
    expect(ThemePreset.all.first.bubble.toARGB32(), 0xFFFADBD4);
    expect(ThemePreset.byCode('nope').code, 'ban_chiang');
    expect(ThemePreset.byCode(null).code, 'ban_chiang');

    AppTheme.applyPreset('indigo_kram');
    expect(AppTheme.brandPrimary, ThemePreset.byCode('indigo_kram').primary);
    AppTheme.applyPreset('ban_chiang');
    expect(AppTheme.brandPrimary, ThemePreset.all.first.primary);
    expect(AppTheme.surfaceBg.toARGB32(), 0xFFFBF9F8);
    expect(AppTheme.borderSubtle.toARGB32(), 0xFFDCC0BC);

    expect(ChatRoomThemeMode.values, [
      ChatRoomThemeMode.banChiangCream,
      ChatRoomThemeMode.terracottaNight,
      ChatRoomThemeMode.mistIvory,
    ]);
    expect(
      ChatRoomThemeMode.banChiangCream.backgroundColor.toARGB32(),
      0xFFF5EFEA,
    );
    expect(
      ChatRoomThemeMode.terracottaNight.backgroundColor.toARGB32(),
      0xFF1C1412,
    );
    expect(
      ChatRoomThemeMode.mistIvory.backgroundColor.toARGB32(),
      0xFFFBF9F8,
    );
  });
}
