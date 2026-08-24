// Pages project visibility probe (operator: "cannot see normal is boring?").
// Prints project facts + deployment count via the account token. No secrets.
//   dart run tool/cf_pages_probe.dart
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/credential_cli.dart';

const acc = '997e3edfd319cbbac9797d1c53ad61d5';

Future<void> main() async {
  final store =
      await defaultCredentialStore(Platform.environment['HOME']! + '/.appbox');
  final token = await store.read('CLOUDFLARE_API_TOKEN');
  if (token == null) {
    stdout.writeln('vault: CLOUDFLARE_API_TOKEN NOT SET');
    exit(1);
  }
  final client = HttpClient();
  Future<Map<String, dynamic>> get(String path) async {
    final req = await client.getUrl(
        Uri.parse('https://api.cloudflare.com/client/v4' + path));
    req.headers.set('Authorization', 'Bearer ' + token);
    final res = await req.close();
    return jsonDecode(await res.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  }

  final projects = await get('/accounts/' + acc + '/pages/projects');
  stdout.writeln('pages projects visible to this token: ' +
      ((projects['result'] as List)
          .map((p) => (p as Map)['name'] as String)
          .join(', ')));
  final p = (projects['result'] as List)
      .cast<Map>()
      .firstWhere((m) => m['name'] == 'architect-gallore');
  stdout.writeln('architect-gallore:');
  stdout.writeln('  created_on:       ' + (p['created_on'] as String));
  stdout.writeln('  subdomain:        ' + (p['subdomain'] as String));
  stdout.writeln('  production_branch: ' + (p['production_branch'] as String? ?? '(default)'));
  final deps = await get('/accounts/' + acc +
      '/pages/projects/architect-gallore/deployments');
  final list = deps['result'] as List? ?? [];
  stdout.writeln('  deployments:      ' + list.length.toString() +
      (list.isEmpty ? '  (inert — nothing published, by design)' : ''));
  client.close();
}
