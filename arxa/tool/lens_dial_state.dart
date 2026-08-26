import 'dart:io';
import 'package:arxa/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/', settleMs: 3500);
  stdout.writeln('host: ${await js(tab,
      'String(!!document.getElementById("arxa-dial-host"))')}');
  stdout.writeln('island tag: ${await js(tab,
      'String(!!document.querySelector("script[src*=dial_island]"))')}');
  stdout.writeln('config: ${await js(tab,
      'document.getElementById("arxa-dial-config")?.textContent ?? "none"')}');
  stdout.writeln('errors: ${tab.consoleErrors.length} ${tab.consoleErrors.take(3)}');
  await client.close();
}
