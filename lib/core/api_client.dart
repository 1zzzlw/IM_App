import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// 复用 Electron 的原始 Authorization 格式，不擅自加 Bearer 前缀。
/// 401 请求共享一次刷新任务，并且每个请求至多重放一次。
class ApiClient {
  ApiClient(String baseUrl, {Dio? dio}) : dio = dio ?? Dio() {
    this.dio.options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 40),
      sendTimeout: const Duration(minutes: 2),
      validateStatus: (status) => status != null && status < 600,
    );
  }
  final Dio dio;
  String accessToken = '';
  String refreshToken = '';
  String userId = '';
  Future<void> Function()? onTokens;
  Future<void> Function()? onExpired;
  Future<void>? _refreshing;

  // 网关 auth.refreshPaths 明确要求 RefreshToken；其余业务接口使用 AccessToken。
  static bool usesRefreshToken(String path) =>
      path.startsWith('/message/verifyUploadToken/') ||
      path.startsWith('/message/init/list/') ||
      path == '/message/merge' ||
      path == '/conversation/init/list' ||
      path == '/friend/init/list';

  Future<void> capture(Response<dynamic> response) async {
    final token = response.headers.value('authorization');
    final refresh = response.headers.value('refreshtoken');
    if (token == null && refresh == null) return;
    if (token != null) {
      accessToken = token.replaceFirst(
        RegExp(r'^Bearer\s+', caseSensitive: false),
        '',
      );
    }
    if (refresh != null) refreshToken = refresh;
    await onTokens?.call();
  }

  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  Future<void> _refresh() async {
    final account = userId;
    final credential = refreshToken;
    if (refreshToken.isEmpty || userId.isEmpty) {
      await onExpired?.call();
      throw ApiException('登录已过期，请重新登录', 401);
    }
    final response = await dio.post<dynamic>(
      '/user/refreshToken/$userId',
      data: {},
      options: Options(headers: {'Authorization': refreshToken}),
    );
    if (account != userId || credential != refreshToken) {
      throw ApiException('登录状态已变化，请重试');
    }
    if (response.statusCode == 400 || response.statusCode == 401) {
      await onExpired?.call();
      throw ApiException('登录已过期，请重新登录', 401);
    }
    unwrap(response);
    await capture(response);
  }

  dynamic unwrap(Response<dynamic> response) {
    if ((response.statusCode ?? 500) >= 400) {
      throw ApiException(
        str(asJson(response.data)['msg']).isNotEmpty
            ? str(asJson(response.data)['msg'])
            : '服务请求失败（${response.statusCode}）',
        response.statusCode,
      );
    }
    final body = response.data;
    if (body is Map && body.containsKey('code')) {
      if (number(body['code']) != 1) {
        throw ApiException(
          str(body['msg']).isEmpty ? '操作未完成' : str(body['msg']),
        );
      }
      return body['data'];
    }
    return body;
  }

  Future<Response<dynamic>> response(
    String method,
    String path, {
    dynamic data,
    Json? query,
    ResponseType? type,
    CancelToken? cancelToken,
    bool authenticated = true,
  }) async {
    final account = userId;
    final server = dio.options.baseUrl;
    try {
      Future<Response<dynamic>> perform() => dio.request<dynamic>(
        path,
        data: data is FormData ? data.clone() : data,
        queryParameters: query,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          responseType: type,
          headers: authenticated && accessToken.isNotEmpty
              ? {
                  'Authorization': usesRefreshToken(path)
                      ? refreshToken
                      : accessToken,
                }
              : {},
        ),
      );
      var result = await perform();
      if (authenticated &&
          (account != userId || server != dio.options.baseUrl)) {
        throw ApiException('请求所属账号已变化');
      }
      if (result.statusCode == 401 && authenticated) {
        await refresh();
        result = await perform();
        if (account != userId || server != dio.options.baseUrl) {
          throw ApiException('请求所属账号已变化');
        }
        if (result.statusCode == 401) {
          await onExpired?.call();
          throw ApiException('登录已过期，请重新登录', 401);
        }
      }
      await capture(result);
      return result;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw ApiException('连接失败，请检查网络和服务器地址');
    }
  }

  Future<dynamic> get(String path, {Json? query}) async =>
      unwrap(await response('GET', path, query: query));
  Future<dynamic> post(String path, {dynamic data, Json? query}) async =>
      unwrap(await response('POST', path, data: data, query: query));
  Future<dynamic> put(String path, {dynamic data, Json? query}) async =>
      unwrap(await response('PUT', path, data: data, query: query));
  Future<dynamic> delete(String path, {Json? query}) async =>
      unwrap(await response('DELETE', path, query: query));
  Future<Uint8List> captcha() async {
    final result = await response(
      'GET',
      '/user/verifyCode',
      type: ResponseType.bytes,
      authenticated: false,
      query: {'t': DateTime.now().millisecondsSinceEpoch},
    );
    unwrap(result);
    final bytes = Uint8List.fromList(List<int>.from(result.data));
    final contentType = result.headers.value('content-type') ?? '';
    if (!contentType.toLowerCase().startsWith('image/') || bytes.isEmpty) {
      throw ApiException('验证码接口未返回图片，请检查 HTTP 服务地址');
    }
    return bytes;
  }

  /// LineSplitter 可处理跨网络分块的 UTF-8 字符及 CRLF，空行才提交完整事件。
  Stream<SseEvent> stream(
    String path,
    Json body,
    CancelToken cancelToken,
  ) async* {
    final result = await response(
      'POST',
      path,
      data: body,
      type: ResponseType.stream,
      cancelToken: cancelToken,
    );
    if (result.statusCode != 200 ||
        !(result.headers.value('content-type') ?? '').contains(
          'text/event-stream',
        )) {
      throw ApiException('AI 服务没有返回事件流（${result.statusCode}）');
    }
    final bytes = (result.data as ResponseBody).stream;
    yield* parseSse(bytes.cast<List<int>>());
  }
}

class SseEvent {
  const SseEvent(this.event, this.data);
  final String event;
  final String data;
}

Stream<SseEvent> parseSse(Stream<List<int>> bytes) async* {
  var event = 'message';
  var parts = <String>[];
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (parts.isNotEmpty) yield SseEvent(event, parts.join('\n'));
      event = 'message';
      parts = [];
    } else if (line.startsWith('event:')) {
      event = line.substring(6).trimLeft();
    } else if (line.startsWith('data:')) {
      var data = line.substring(5);
      if (data.startsWith(' ')) data = data.substring(1);
      parts.add(data);
    }
  }
  // 未被空行结束的事件可能是截断帧，不把它当成成功消息交给页面。
}
