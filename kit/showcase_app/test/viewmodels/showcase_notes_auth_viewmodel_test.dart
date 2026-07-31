import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('ShowcaseNotesAuthViewModel Tests -', () {
    setUp(() => registerServices());
    tearDown(() => locator.reset());
  });
}
