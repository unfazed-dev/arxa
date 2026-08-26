# Stub inventory — stacked_kit, the FSM pipeline, flutter-crew

Surveyed 2026-07-27. What is genuinely wired versus what throws.

## 🔴 The finding that changes a plan

**`stacked_kit_payments` has no working card processor.** Both providers are
stubs:

```dart
throw UnimplementedError('StripePaymentsProvider is a stub (phase-later)');
throw UnimplementedError('PayPalPaymentsProvider is a stub (phase-later)');
```

The registry lists `payments | native-first | Apple Pay` — **Apple Pay is the
only wired path**. So the arxa **payment gate cannot be built on the
payments kit as it stands**. Either Stripe gets implemented (the kit's own TODO
says *"implement with `flutter_stripe`"*), or arxa's licensing runs through
something outside the kit entirely.

This is worth stating plainly because §17 placed the payment gate at
`arxa-builder` on the assumption the machinery existed. The *placement* is
still right; the *implementation* has no foundation yet.

## 🟠 Auth — the other one arxa needs itself

| symbol | state |
|---|---|
| `AppleSignInProvider.signIn` | `UnimplementedError` (phase-later) |
| `GoogleSignInProvider.signIn` | `UnimplementedError` (phase-later) |
| `SeedAuthBackend` | stub (phase-4) |

arxa's desktop app wants auth. `SeedAuthBackend` being a stub also means the
seeded/fake-data story the product promises is thinner than it reads.

## 🟡 Other stubs

| kit | stub | note |
|---|---|---|
| `maps` | `OpenStreetMapProvider`, `MapboxProvider` | TODOs name `flutter_map ^8.x` and `mapbox_maps_flutter ^2.x` |
| `deploy` | `VercelTarget` | throws; fastlane/shorebird/CF Pages are **wired** |

## Kit registry — 23 kits by phase

| phase | count | meaning |
|---|---:|---|
| `stable` | 14 | wired |
| `native-first` | 3 | permissions, media, payments |
| `native-first-partial` | 5 | documents, notifications, maps, bluetooth, security |
| `n/a` | 1 | `showcase_app` (integration surface) |

**`hasSkill: false` on all 23.** No kit has a phase skill today, so every
`arxa-*` skill is the first of its kind — there is no prior art to copy
inside the kit, only the flutter-crew stage contract.

## flutter-crew

54 Python files, **26,841 lines** (up from the 22,738 measured earlier in the
spine research — it is moving). Tests present.

**Smell: a `test.bak/` directory duplicating five test files** verbatim
(`test_self_tests.py`, `test_signin_parity_primitives.py`,
`test_stamp_native_names.py`, `test_app_name.py`,
`test_backend_auth_resolver.py`). Dead copies beside live ones are how a suite
starts lying about what it covers — delete or revive before vendoring anything
from here.

## `TODO(prose)` is a feature, not debt

`tools/gen_playbook.py` emits `<!-- TODO(prose): … -->` for any narrative
section with no source, and `tools/test_memory.sh` **asserts the count is
zero** for a rich README. That is a deliberate, tested "unwritten prose"
marker. Do not confuse it with abandoned work — and copy the pattern: a
generator that marks its own gaps and a test that counts them is exactly the
discipline missing elsewhere.

## What this means for build order

1. Nothing blocks the **design → freeze → scaffold** path; that is all wired.
2. **Deploy is wired** for the targets that matter (fastlane, shorebird, CF
   Pages). Do not advertise vercel.
3. **Payments and auth are the two real holes**, and arxa needs both for
   itself. They are product work, not pipeline work — sequence them
   accordingly rather than discovering it at the payment gate.
