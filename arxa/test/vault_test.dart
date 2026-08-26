import 'package:arxa/process.dart';
import 'package:arxa/vault.dart';
import 'package:test/test.dart';

/// Records invocations and answers from a scripted table keyed on argv.
class FakeProcessRunner implements ProcessRunner {
  final calls = <List<String>>[];
  RunnerResult Function(String executable, List<String> args)? handler;

  @override
  Future<RunnerResult> run(
    String executable,
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    calls.add([executable, ...args]);
    return handler?.call(executable, args) ?? const RunnerResult(0, '', '');
  }
}

void main() {
  group('InMemoryVault', () {
    test('round-trips write/read/delete and enumerates keys', () async {
      final vault = InMemoryVault();
      expect(await vault.read('k'), isNull);
      await vault.write('k', 'v');
      await vault.write('other', 'x');
      expect(await vault.read('k'), 'v');
      expect(await vault.readAllKeys(), containsAll(['k', 'other']));
      await vault.delete('k');
      expect(await vault.read('k'), isNull);
    });
  });

  group('KeychainVault', () {
    late FakeProcessRunner runner;
    late KeychainVault vault;
    setUp(() {
      runner = FakeProcessRunner();
      vault = KeychainVault(service: 'arxa', runner: runner);
    });

    test('write shells add-generic-password -U with service/account/secret', () async {
      await vault.write('arxa.key.anthropic', 'sk-secret');
      expect(runner.calls.single, [
        KeychainVault.binary,
        'add-generic-password',
        '-U',
        '-s', 'arxa',
        '-a', 'arxa.key.anthropic',
        '-w', 'sk-secret',
      ]);
    });

    test('read returns the password without the trailing newline', () async {
      runner.handler = (_, _) => const RunnerResult(0, 'sk-secret\n', '');
      expect(await vault.read('arxa.key.anthropic'), 'sk-secret');
      expect(runner.calls.single, containsAllInOrder([
        'find-generic-password', '-s', 'arxa', '-a', 'arxa.key.anthropic', '-w',
      ]));
    });

    test('read maps errSecItemNotFound (44) to null', () async {
      runner.handler = (_, _) => const RunnerResult(44, '', 'not found');
      expect(await vault.read('absent'), isNull);
    });

    test('read throws on an unexpected keychain failure', () async {
      runner.handler = (_, _) => const RunnerResult(1, '', 'denied');
      expect(() => vault.read('k'), throwsStateError);
    });

    test('delete tolerates a missing entry', () async {
      runner.handler = (_, _) => const RunnerResult(44, '', '');
      await vault.delete('absent'); // must not throw
    });

    test('readAllKeys parses dump-keychain output for our service only', () async {
      runner.handler = (_, _) => const RunnerResult(0, '''
keychain: "/keychains-fixture/login.keychain-db"
class: "genp"
attributes:
    "acct"<blob>="arxa.key.anthropic"
    "svce"<blob>="arxa"
class: "genp"
attributes:
    "acct"<blob>="arxa.licence"
    "svce"<blob>="arxa"
class: "genp"
attributes:
    "acct"<blob>="someone.else"
    "svce"<blob>="other-service"
class: "inet"
attributes:
    "acct"<blob>="ignored-internet-password"
    "svce"<blob>="arxa"
''', '');
      expect(await vault.readAllKeys(),
          ['arxa.key.anthropic', 'arxa.licence']);
    });
  });
}
