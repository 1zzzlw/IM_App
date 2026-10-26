import 'package:flutter_test/flutter_test.dart';
import 'package:im_app/core/api_client.dart';
import 'package:im_app/core/models.dart';

import 'support.dart';

void main() {
  test(
    'unwrap Result once and read Java PageResult.data without losing records',
    () async {
      final api = ApiClient('http://test.invalid');
      api.dio.httpClientAdapter = FakeAdapter(
        (request) => success({
          'total': 1,
          'data': [
            {'id': '1792113130553123456', 'content': '热门动态'},
          ],
        }),
      );
      final page = await api.get(
        '/moments/list/hot',
        query: {'page': 1, 'pageSize': 20},
      );
      expect(asList(page).single['content'], '热门动态');
      expect(asList(page).single['id'], '1792113130553123456');
      expect(asJson(page)['total'], 1);
      api.dio.close();
    },
  );
  test('list parser retains raw lists, other page formats and empty pages', () {
    for (final value in <dynamic>[
      [
        {'id': '1'},
      ],
      {
        'data': [
          {'id': '1'},
        ],
      },
      {
        'records': [
          {'id': '1'},
        ],
      },
      {
        'list': [
          {'id': '1'},
        ],
      },
      {
        'items': [
          {'id': '1'},
        ],
      },
    ]) {
      expect(asList(value).single['id'], '1');
    }
    expect(asList({'total': 0, 'data': []}), isEmpty);
    expect(asList(null), isEmpty);
  });
}
