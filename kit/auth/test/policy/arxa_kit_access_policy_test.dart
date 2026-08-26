import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_auth/src/models/arxa_kit_auth_user.dart';
import 'package:arxa_kit_auth/src/policy/arxa_kit_access_policy.dart';

const _policy = ArxaKitAccessPolicy(
  roles: {'customer', 'admin'},
  defaultRole: 'customer',
  routes: {
    'adminDashboard': {'admin'},
    'productEditor': {'admin'},
  },
  actions: {
    'product.update': {'admin'},
    'product.create': {'admin'},
    'order.fulfill': {'admin'},
    'cart.checkout': {'customer', 'admin'},
  },
);

ArxaKitAuthUser _user({String? role, String id = 'u1'}) =>
    ArxaKitAuthUser(id: id, email: '$id@x', metadata: role == null ? {} : {'role': role});

void main() {
  group('roleOf', () {
    test('kit.auth.access-policy — signed-out (null) → null', () {
      expect(_policy.roleOf(null), isNull);
    });
    test('kit.auth.access-policy — valid claim → that role', () {
      expect(_policy.roleOf(_user(role: 'admin')), 'admin');
    });
    test('kit.auth.access-policy — absent claim → defaultRole', () {
      expect(_policy.roleOf(_user(role: null)), 'customer');
    });
    test('kit.auth.access-policy — unrecognised claim → defaultRole', () {
      expect(_policy.roleOf(_user(role: 'superuser')), 'customer');
    });
  });

  group('can (deny-by-default)', () {
    test('kit.auth.access-policy — unlisted action → false even for admin', () {
      expect(_policy.can('product.delete', _user(role: 'admin')), isFalse);
    });
    test('kit.auth.access-policy — admin action allowed for admin', () {
      expect(_policy.can('product.update', _user(role: 'admin')), isTrue);
    });
    test('kit.auth.access-policy — admin action denied for customer (the C15 bypass essence)', () {
      expect(_policy.can('product.update', _user(role: 'customer')), isFalse);
    });
    test('kit.auth.access-policy — shared action allowed for both roles', () {
      expect(_policy.can('cart.checkout', _user(role: 'customer')), isTrue);
      expect(_policy.can('cart.checkout', _user(role: 'admin')), isTrue);
    });
    test('kit.auth.access-policy — signed-out → always false, even for a shared action', () {
      expect(_policy.can('cart.checkout', null), isFalse);
    });
  });

  group('canRoute (allow-by-default)', () {
    test('kit.auth.access-policy — unlisted route → open to everyone, incl. signed-out', () {
      expect(_policy.canRoute('productGrid', _user(role: 'customer')), isTrue);
      expect(_policy.canRoute('productGrid', null), isTrue);
    });
    test('kit.auth.access-policy — admin route allowed for admin', () {
      expect(_policy.canRoute('adminDashboard', _user(role: 'admin')), isTrue);
    });
    test('kit.auth.access-policy — admin route denied for customer', () {
      expect(_policy.canRoute('productEditor', _user(role: 'customer')), isFalse);
    });
    test('kit.auth.access-policy — admin route denied for signed-out', () {
      expect(_policy.canRoute('adminDashboard', null), isFalse);
    });
  });

  group('enforce (Authority — C15)', () {
    test('kit.auth.access-policy — throws for customer on admin action, naming role', () {
      expect(
        () => _policy.enforce('product.update', _user(role: 'customer')),
        throwsA(isA<ArxaKitAccessDeniedError>()),
      );
    });
    test('kit.auth.access-policy — throws for signed-out, naming signed-out', () {
      expect(
        () => _policy.enforce('product.update', null),
        throwsA(
          predicate(
            (e) => e is ArxaKitAccessDeniedError && e.role == null,
          ),
        ),
      );
    });
    test('kit.auth.access-policy — does not throw when allowed', () {
      _policy.enforce('product.update', _user(role: 'admin')); // no throw
      _policy.enforce('cart.checkout', _user(role: 'customer'));
    });
    test('kit.auth.access-policy — a direct facade call as customer is still denied (bypass proof)', () {
      // The UI is bypassed — a facade calls enforce() directly as customer.
      // This is the exact scenario C15 asserts must fail.
      expect(
        () => _policy.enforce('order.fulfill', _user(role: 'customer')),
        throwsA(isA<ArxaKitAccessDeniedError>()),
      );
    });
  });

  group('defaults asymmetry', () {
    test('kit.auth.access-policy — custom roleMetadataKey', () {
      const p = ArxaKitAccessPolicy(
        roles: {'a', 'b'},
        defaultRole: 'a',
        roleMetadataKey: 'level',
      );
      expect(p.roleOf(ArxaKitAuthUser(id: 'x', metadata: {'level': 'b'})), 'b');
      expect(p.roleOf(ArxaKitAuthUser(id: 'x', metadata: {'role': 'b'})), 'a');
    });
  });
}
