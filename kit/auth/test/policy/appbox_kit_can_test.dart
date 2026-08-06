import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_auth/src/models/appbox_kit_auth_user.dart';
import 'package:appbox_kit_auth/src/policy/appbox_kit_access_policy.dart';
import 'package:appbox_kit_auth/src/policy/appbox_kit_can.dart';

const _policy = AppBoxKitAccessPolicy(
  roles: {'customer', 'admin'},
  defaultRole: 'customer',
  actions: {'product.update': {'admin'}},
);

AppBoxKitAuthUser _user(String role) =>
    AppBoxKitAuthUser(id: role, email: '$role@x', metadata: {'role': role});

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders child when allowed', (t) async {
    await t.pumpWidget(_host(
      AppBoxKitCan(
        action: 'product.update',
        policy: _policy,
        user: _user('admin'),
        child: const Text('EDIT'),
      ),
    ));
    expect(find.text('EDIT'), findsOneWidget);
  });

  testWidgets('renders nothing (shrink) when denied — C14', (t) async {
    await t.pumpWidget(_host(
      AppBoxKitCan(
        action: 'product.update',
        policy: _policy,
        user: _user('customer'),
        child: const Text('EDIT'),
      ),
    ));
    expect(find.text('EDIT'), findsNothing);
  });

  testWidgets('renders nothing when signed out', (t) async {
    await t.pumpWidget(_host(
      AppBoxKitCan(
        action: 'product.update',
        policy: _policy,
        user: null,
        child: const Text('EDIT'),
      ),
    ));
    expect(find.text('EDIT'), findsNothing);
  });

  testWidgets('renders fallback when provided and denied', (t) async {
    await t.pumpWidget(_host(
      AppBoxKitCan(
        action: 'product.update',
        policy: _policy,
        user: _user('customer'),
        fallback: const Text('READ-ONLY'),
        child: const Text('EDIT'),
      ),
    ));
    expect(find.text('EDIT'), findsNothing);
    expect(find.text('READ-ONLY'), findsOneWidget);
  });
}
