import 'package:arxa_studio_mobile/services/tap_routing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('task collapse keys route to the studio root', () {
    expect(routeForTap('task:studio-123'), TapRoute.studioRoot);
    expect(routeForTap('task'), TapRoute.studioRoot);
  });

  test('null and approval collapse keys route to approvals', () {
    expect(routeForTap(null), TapRoute.approvals);
    expect(routeForTap('approval:abc'), TapRoute.approvals);
    expect(routeForTap(''), TapRoute.approvals);
  });
}
