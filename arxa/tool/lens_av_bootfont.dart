// Boot-path probe: fresh page load with arxa.editorFont ALREADY = 'fira'.
// Reads boot state only (no clicks): did apply() at plugin load set the
// body inline var? Does a mounted .cm-content compute to Fira?
// Usage: dart run tool/lens_av_bootfont.dart <url> <outDir>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln('usage: dart run tool/lens_av_bootfont.dart <url> <outDir>');
    exit(2);
  }
  final url = argv[0];
  Directory(argv[1])..createSync(recursive: true);
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 800);
    await tab.navigateAndSettle(url, settleMs: 4000);
    final r = await tab.evaluate('''(async () => {
      const cm = document.querySelector('.aXa_av_editorWrap .cm-content');
      const tags = [...document.querySelectorAll('style[data-plugin-css]')].map(t => t.dataset.pluginCss);
      const panel = document.querySelector('style[data-plugin-css="arxa-artifact-viewer/panel.css"]');
      let ruleCount = -1;
      if (panel && panel.sheet) {
        ruleCount = 0;
        const walk = (rls) => { for (const r of rls) { if (r.selectorText !== undefined) ruleCount++; if (r.cssRules) walk(r.cssRules); } };
        walk(panel.sheet.cssRules);
      }
      return JSON.stringify({
        stored: localStorage.getItem('arxa.editorFont'),
        bodyVar: document.body.style.getPropertyValue('--arxa-editor-font') || '(unset)',
        hasCM: !!cm,
        cmFam: cm ? getComputedStyle(cm).fontFamily.slice(0, 90) : null,
        panelTag: !!panel,
        ruleCount,
        pluginCssTags: tags.length
      })
    })()''');
    print('BOOT -> ' + jsonEncode(r));
  } finally {
    await client.close();
  }
}
