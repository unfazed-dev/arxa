import 'package:flutter_test/flutter_test.dart';
import 'package:app_box/app/app.locator.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('ShowcaseUnknownViewModel Tests -', () {
    setUp(() => registerServices());
    tearDown(() => locator.reset());
  });
}
