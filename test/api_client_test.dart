import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:im_app/core/api_client.dart';

import 'support.dart';

void main() {
  test('captcha accepts image bytes and rejects an HTML error page', () async {
    final api = ApiClient('http://test.invalid');
    api.dio.httpClientAdapter = FakeAdapter(
      (options) => ResponseBody.fromBytes(
        [255, 216, 255],
        200,
        headers: {
          'content-type': ['image/jpeg'],
        },
      ),
    );
    expect(await api.captcha(), [255, 216, 255]);
    api.dio.httpClientAdapter = FakeAdapter(
      (options) => ResponseBody.fromString(
        '<html>wrong server</html>',
        200,
        headers: {
          'content-type': ['text/html'],
        },
      ),
    );
    await expectLater(api.captcha(), throwsA(isA<ApiException>()));
    api.dio.close();
  });
  test('gateway refreshPaths use long token while regular endpoints use access token', () async {
    final api = ApiClient('http://test.invalid')
      ..accessToken = 'short'
      ..refreshToken = 'long'
      ..userId = '100';
    final adapter = FakeAdapter((o) => success([]));
    api.dio.httpClientAdapter = adapter;
    for (final path in [
      '/conversation/init/list',
      '/friend/init/list',
      '/message/init/list/200_100',
      '/message/verifyUploadToken/hash',
      '/message/merge',
      '/wallet/info',
    ]) {
      await api.get(path);
    }
    expect(adapter.requests.map((r) => r.headers['Authorization']), [
      'long',
      'long',
      'long',
      'long',
      'long',
      'short',
    ]);
    api.dio.close();
  });
  test(
    'parallel 401 responses share refresh and replay with updated token',
    () async {
      var refreshes = 0;
      final api = ApiClient('http://test.invalid')
        ..accessToken = 'old'
        ..refreshToken = 'long'
        ..userId = '100';
      api.dio.httpClientAdapter = FakeAdapter((options) async {
        if (options.path.startsWith('/user/refreshToken/')) {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(options.headers['Authorization'], 'long');
          return jsonResponse(
            {'code': 1},
            headers: {
              'authorization': ['Bearer new'],
              'refreshtoken': ['new-long'],
            },
          );
        }
        return options.headers['Authorization'] == 'old'
            ? jsonResponse({}, status: 401)
            : success('ok');
      });
      expect(
        await Future.wait([
          api.get('/wallet/info'),
          api.get('/favorites/list'),
        ]),
        ['ok', 'ok'],
      );
      expect(refreshes, 1);
      expect(api.accessToken, 'new');
      expect(api.refreshToken, 'new-long');
      api.dio.close();
    },
  );
  test('expired refresh token ends session once and does not loop', () async {
    var expired = 0;
    final api = ApiClient('http://test.invalid')
      ..accessToken = 'old'
      ..refreshToken = 'bad'
      ..userId = '100';
    api.onExpired = () async {
      expired++;
    };
    api.dio.httpClientAdapter = FakeAdapter(
      (o) => jsonResponse({}, status: o.path.startsWith('/user/') ? 400 : 401),
    );
    await expectLater(api.get('/wallet/info'), throwsA(isA<ApiException>()));
    expect(expired, 1);
    api.dio.close();
  });
  test('old account response cannot overwrite a new account token', () async {
    final gate = Completer<ResponseBody>();
    final api = ApiClient('http://test.invalid')
      ..accessToken = 'old'
      ..userId = '100';
    api.dio.httpClientAdapter = FakeAdapter((o) => gate.future);
    final response = api.get('/wallet/info');
    await Future<void>.delayed(Duration.zero);
    api.userId = '200';
    api.accessToken = 'new';
    gate.complete(
      jsonResponse(
        {'code': 1},
        headers: {
          'authorization': ['Bearer stale'],
        },
      ),
    );
    await expectLater(response, throwsA(isA<ApiException>()));
    expect(api.accessToken, 'new');
    api.dio.close();
  });
}
