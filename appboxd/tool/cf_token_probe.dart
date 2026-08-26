// Cloudflare token identity probe (operator ask, 2026-08-25).
//
// The operator asked: "show me the token name you have — this is the only
// one in my account, resolve this once and for all." The vault stores only
// the VALUE (never a name), so the identity must come from Cloudflare's own
// API: verify the vault token against both verify routes (user + account)
// and attempt the token listings. The token value never appears in output.
//
//   dart run tool/cf_token_probe.dart
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/credential_cli.dart';

const acc = '997e3edfd319cbbac9797d1c53ad61d5';

Future<void> main() async {
  final store =
      await defaultCredentialStore('${Platform.environment['HOME']!}/.appbox');
  final token = await store.read('CLOUDFLARE_API_TOKEN');
  if (token == null) {
    stdout.writeln('vault: CLOUDFLARE_API_TOKEN NOT SET');
    return;
  }
  stdout.writeln('vault token present · length ${token.length} · value never printed');
  final client = HttpClient();
  Future<void> probe(String label, String path) async {
    try {
      final req = await client
          .getUrl(Uri.parse('https://api.cloudflare.com/client/v4$path'));
      req.headers.set('Authorization', 'Bearer $token');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      stdout.writeln('--- $label [HTTP ${res.statusCode}]');
      stdout.writeln(body.length > 700 ? '${body.substring(0, 700)}…' : body);
    } catch (e) {
      stdout.writeln('--- $label THREW $e');
    }
  }

  await probe('/user/tokens/verify', '/user/tokens/verify');
  await probe('/accounts/<acc>/tokens/verify', '/accounts/$acc/tokens/verify');
  await probe('/accounts/<acc>/pages/projects (auth proof)',
      '/accounts/$acc/pages/projects');
  await probe('/accounts/<acc>/tokens (list)', '/accounts/$acc/tokens');
  client.close();
}
