import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bcaichat_app/services/api_service.dart';
import 'package:bcaichat_app/services/push_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockHttpOverrides extends HttpOverrides {
  _MockHttpOverrides(this.onRequest);
  final Future<void> Function(
    String method,
    Uri uri,
    Map<String, String> headers,
    String body,
  ) onRequest;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _MockHttpClient(onRequest);
}

class _MockHttpClient implements HttpClient {
  _MockHttpClient(this.onRequest);
  final Future<void> Function(
    String method,
    Uri uri,
    Map<String, String> headers,
    String body,
  ) onRequest;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _MockHttpClientRequest(method, url, onRequest);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  _MockHttpClientRequest(this.method, this.uri, this.onRequest);
  @override
  final String method;
  @override
  final Uri uri;
  final Future<void> Function(
    String method,
    Uri uri,
    Map<String, String> headers,
    String body,
  ) onRequest;

  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  int contentLength = -1;
  @override
  bool persistentConnection = true;

  @override
  final HttpHeaders headers = _MockHttpHeaders();
  final BytesBuilder _buffer = BytesBuilder();

  @override
  void add(List<int> data) => _buffer.add(data);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _buffer.add(chunk);
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    final body = utf8.decode(_buffer.takeBytes());
    final hdrs = (headers as _MockHttpHeaders).values;
    await onRequest(method, uri, hdrs, body);
    return _MockHttpClientResponse(200, '{"status":"ok","push":true}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  final Map<String, String> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    values.forEach((k, v) => action(k, [v]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _MockHttpClientResponse(this.statusCode, String body)
    : _bytes = utf8.encode(body);

  @override
  final int statusCode;
  final List<int> _bytes;

  @override
  int get contentLength => _bytes.length;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => 'OK';

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  HttpHeaders get headers => _MockHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([_bytes]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pushChannel = MethodChannel('bcaichat/push');
  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const audioGlobalChannel = MethodChannel('xyz.luan/audioplayers.global');
  const audioChannel = MethodChannel('xyz.luan/audioplayers');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioGlobalChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, (call) async => null);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pushChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioGlobalChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, null);
  });

  test(
    'ก. Android: rotated push token (onNewToken) is sent to backend immediately and MainActivity supports closed-app token sync',
    () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'bcaichat_jwt_token': 'jwt-test-token',
        'bcaichat_device_id': 'android-dev-12345678',
        'bcaichat_alert_popup': true,
        'bcaichat_alert_sound': true,
      });
      await ApiService.instance.restoreSession();

      final registeredTokens = <String>[];
      HttpOverrides.global = _MockHttpOverrides((
        method,
        uri,
        headers,
        body,
      ) async {
        if (method == 'POST' && uri.path == '/api/devices') {
          final json = jsonDecode(body) as Map<String, dynamic>;
          registeredTokens.add(json['token'] as String);
        }
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, (call) async => true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pushChannel, (call) async {
            if (call.method == 'getToken') return 'fcm-token-initial';
            if (call.method == 'takeOpenedConversation') return null;
            return null;
          });

      await PushService.instance.start();
      expect(registeredTokens, ['fcm-token-initial']);

      final codec = const StandardMethodCodec();
      final completer = Completer<ByteData?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'bcaichat/push',
            codec.encodeMethodCall(
              const MethodCall('onNewToken', 'fcm-token-rotated-immediate'),
            ),
            completer.complete,
          );
      await completer.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        registeredTokens,
        ['fcm-token-initial', 'fcm-token-rotated-immediate'],
        reason: 'Rotated token must be POSTed to /api/devices immediately',
      );

      final kt = File(
        'android/app/src/main/kotlin/com/bcaichat/app/MainActivity.kt',
      ).readAsStringSync();
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(kt, contains('package com.bcaichat.app'));
      expect(kt, contains('bcaichat/push'));
      expect(kt, contains('FirebaseMessagingService'));
      expect(kt, contains('override fun onNewToken'));
      expect(kt, contains('/api/devices'));
      expect(manifest, contains('com.google.firebase.MESSAGING_EVENT'));
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    },
  );

  test(
    'ข. Native Android: listenForOpens opens initial tapped notification room and later openConversation callbacks',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pushChannel, (call) async {
            if (call.method == 'takeOpenedConversation') return 'conv_boot_1';
            return null;
          });

      final opened = <String>[];
      await PushService.instance.listenForOpens(opened.add);
      expect(opened, ['conv_boot_1']);

      final codec = const StandardMethodCodec();
      final completer = Completer<ByteData?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'bcaichat/push',
            codec.encodeMethodCall(
              const MethodCall('openConversation', 'conv_bg_2'),
            ),
            completer.complete,
          );
      await completer.future;
      expect(opened, ['conv_boot_1', 'conv_bg_2']);
    },
  );
}
