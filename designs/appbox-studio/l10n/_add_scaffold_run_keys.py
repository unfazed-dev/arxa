#!/usr/bin/env python3
"""Append scaffold.run l10n keys to all three ARBs, key-for-key.

Same contract as _add_scaffold_picker_keys.py: en is the SSOT, pl is
hand-translated, qps-ploc is generated with the identical pseudolocalizer
([!! accented ~̷~ !!], ~30% expansion) so the receipt gets a real overflow
stress test. Idempotent: re-running rewrites only these keys.

Copy tone note: this screen is a RECEIPT for a synchronous, deterministic
transform (D24), so no string here mentions waiting, progress, elapsed time or
stages. Verbs are past tense ("landed", "written"), never continuous.
"""
import json
import math
import re
from collections import OrderedDict

EN = {
    "screen.label.scaffold.run": "Scaffold",

    "scaffold.run.pageTitle": "Scaffold receipt",
    "scaffold.run.eyebrow": "Scaffold",

    # Shared kit display names (no scaffold.kit.* existed before this file).
    "scaffold.kit.core": "Core",
    "scaffold.kit.router": "Routing",
    "scaffold.kit.l10n": "Localization",
    "scaffold.kit.auth": "Accounts",
    "scaffold.kit.payments": "Payments",
    "scaffold.kit.push": "Push notifications",

    # Shell chrome
    "scaffold.run.chip.structure": "structure {revision}",
    "scaffold.run.chip.kits": "{count} kits",
    "scaffold.run.thread.frozen": "Your design was frozen at {screens} screens. Nothing below changed it.",
    "scaffold.run.thread.pre": "Everything needed is in place. Scaffolding writes the files — it takes a moment, not a coffee break.",
    "scaffold.run.thread.completed": "Files are on disk. Nothing needs you.",
    "scaffold.run.thread.warning": "Files are on disk. Two kits still need keys before you can ship them.",
    "scaffold.run.thread.failed": "A file could not be written, so nothing was left half-done.",
    "scaffold.run.thread.blocked": "Your design is not frozen yet, so there is nothing to scaffold from.",
    "scaffold.run.thread.toBuild": "Go to build",
    "scaffold.run.activity.label": "Kits",
    "scaffold.run.activity.ready": "ready",
    "scaffold.run.activity.needsKeys": "needs keys",

    # State banner
    "scaffold.run.state.pre.title": "Ready to scaffold",
    "scaffold.run.state.pre.note": "Nothing has been written yet.",
    "scaffold.run.state.completed.title": "Scaffold written",
    "scaffold.run.state.completed.note": "Every file landed. No conflicts, nothing skipped by surprise.",
    "scaffold.run.state.warning.title": "Scaffold written, with notes",
    "scaffold.run.state.warning.note": "All files landed. Some kits still need keys before you can deploy them.",
    "scaffold.run.state.failed.title": "Scaffold stopped",
    "scaffold.run.state.failed.note": "A write was refused. What had landed was undone.",
    "scaffold.run.state.blocked.title": "Nothing to scaffold yet",
    "scaffold.run.state.blocked.note": "Freeze your design first.",

    # Input summary
    "scaffold.run.input.heading": "What this was built from",
    "scaffold.run.input.structure": "Design",
    "scaffold.run.input.frozen": "frozen at {revision}",
    "scaffold.run.input.scope": "Scope",
    "scaffold.run.input.scopeValue": "{screens} screens across {shells} shells",
    "scaffold.run.input.kits": "Kits",
    "scaffold.run.input.kitsValue": "{count} selected",
    "scaffold.run.kit.auto": "added for you",
    "scaffold.run.kit.needsKeys": "needs keys",

    # Gate
    "scaffold.run.gate.note": "This writes files into your project. It reads your frozen design and nothing else, so the same design always produces the same files.",
    "scaffold.run.gate.action": "Write the scaffold",
    "scaffold.run.gate.back": "Back to kits",

    # Writes
    "scaffold.run.writes.heading": "What landed",
    "scaffold.run.writes.counts": "{created} created · {updated} updated · {skipped} skipped",
    "scaffold.run.writes.kind.created": "new",
    "scaffold.run.writes.kind.updated": "updated",
    "scaffold.run.writes.kind.skipped": "left alone",

    # Manifest sidecar (D8)
    "scaffold.run.manifest.heading": "Kit manifest",
    "scaffold.run.manifest.beside": "written beside {path}, which was not modified",
    "scaffold.run.manifest.section.wishlist": "Wishlist — what you asked for",
    "scaffold.run.manifest.section.resolved": "Resolved — what was actually wired in",
    "scaffold.run.delta.untouched": "unchanged",
    "scaffold.run.delta.counts": "{added} added · {changed} changed",

    # Readiness warnings (D6 — inform only)
    "scaffold.run.warn.heading": "Before you deploy",
    "scaffold.run.warn.note": "These never stopped the scaffold. They only matter when you ship.",
    "scaffold.run.warn.readinessUnmet": "{kit} has no keys yet, so it will not work in a deployed build.",
    "scaffold.run.warn.fix": "Add keys",

    # Failure
    "scaffold.run.fail.heading": "Why it stopped",
    "scaffold.run.fail.writeDenied": "This file could not be written. Usually that means it is read-only or open in another program.",
    "scaffold.run.fail.rolledBack": "The {count} files written before the stop were removed, so your project is exactly as it was.",
    "scaffold.run.fail.retry": "Try again",

    # Blocked
    "scaffold.run.blocked.structureNotFrozen": "Scaffolding copies a frozen design into code. Yours is still being edited, so there is no fixed thing to copy.",
    "scaffold.run.blocked.action": "Freeze the design",

    "scaffold.run.next.build": "Continue to build",
}

PL = {
    "screen.label.scaffold.run": "Rusztowanie",

    "scaffold.run.pageTitle": "Potwierdzenie rusztowania",
    "scaffold.run.eyebrow": "Rusztowanie",

    "scaffold.kit.core": "Rdzeń",
    "scaffold.kit.router": "Nawigacja",
    "scaffold.kit.l10n": "Tłumaczenia",
    "scaffold.kit.auth": "Konta",
    "scaffold.kit.payments": "Płatności",
    "scaffold.kit.push": "Powiadomienia push",

    "scaffold.run.chip.structure": "projekt {revision}",
    "scaffold.run.chip.kits": "zestawy: {count}",
    "scaffold.run.thread.frozen": "Twój projekt zamrożono na {screens} ekranach. Nic poniżej tego nie zmieniło.",
    "scaffold.run.thread.pre": "Wszystko jest gotowe. Zapis plików trwa chwilę, nie kwadrans.",
    "scaffold.run.thread.completed": "Pliki są na dysku. Nic nie wymaga Twojej uwagi.",
    "scaffold.run.thread.warning": "Pliki są na dysku. Dwa zestawy wymagają jeszcze kluczy, zanim je wdrożysz.",
    "scaffold.run.thread.failed": "Jednego pliku nie dało się zapisać, więc nic nie zostało w połowie.",
    "scaffold.run.thread.blocked": "Twój projekt nie jest jeszcze zamrożony, więc nie ma z czego budować.",
    "scaffold.run.thread.toBuild": "Przejdź do budowania",
    "scaffold.run.activity.label": "Zestawy",
    "scaffold.run.activity.ready": "gotowy",
    "scaffold.run.activity.needsKeys": "wymaga kluczy",

    "scaffold.run.state.pre.title": "Gotowe do rusztowania",
    "scaffold.run.state.pre.note": "Nic jeszcze nie zostało zapisane.",
    "scaffold.run.state.completed.title": "Rusztowanie zapisane",
    "scaffold.run.state.completed.note": "Wszystkie pliki trafiły na miejsce. Bez konfliktów i bez niespodzianek.",
    "scaffold.run.state.warning.title": "Rusztowanie zapisane, z uwagami",
    "scaffold.run.state.warning.note": "Wszystkie pliki trafiły na miejsce. Część zestawów wymaga kluczy przed wdrożeniem.",
    "scaffold.run.state.failed.title": "Rusztowanie zatrzymane",
    "scaffold.run.state.failed.note": "Zapis został odrzucony. To, co już powstało, zostało cofnięte.",
    "scaffold.run.state.blocked.title": "Nie ma jeszcze czego budować",
    "scaffold.run.state.blocked.note": "Najpierw zamroź swój projekt.",

    "scaffold.run.input.heading": "Na czym to powstało",
    "scaffold.run.input.structure": "Projekt",
    "scaffold.run.input.frozen": "zamrożony na {revision}",
    "scaffold.run.input.scope": "Zakres",
    "scaffold.run.input.scopeValue": "{screens} ekranów w {shells} powłokach",
    "scaffold.run.input.kits": "Zestawy",
    "scaffold.run.input.kitsValue": "wybrano: {count}",
    "scaffold.run.kit.auto": "dodany za Ciebie",
    "scaffold.run.kit.needsKeys": "wymaga kluczy",

    "scaffold.run.gate.note": "To zapisze pliki w Twoim projekcie. Czyta wyłącznie zamrożony projekt, więc ten sam projekt zawsze daje te same pliki.",
    "scaffold.run.gate.action": "Zapisz rusztowanie",
    "scaffold.run.gate.back": "Wróć do zestawów",

    "scaffold.run.writes.heading": "Co powstało",
    "scaffold.run.writes.counts": "{created} nowych · {updated} zaktualizowanych · {skipped} pominiętych",
    "scaffold.run.writes.kind.created": "nowy",
    "scaffold.run.writes.kind.updated": "zaktualizowany",
    "scaffold.run.writes.kind.skipped": "nietknięty",

    "scaffold.run.manifest.heading": "Manifest zestawów",
    "scaffold.run.manifest.beside": "zapisany obok {path}, który nie został zmieniony",
    "scaffold.run.manifest.section.wishlist": "Lista życzeń — o co prosiłeś",
    "scaffold.run.manifest.section.resolved": "Rozstrzygnięte — co faktycznie podłączono",
    "scaffold.run.delta.untouched": "bez zmian",
    "scaffold.run.delta.counts": "{added} dodanych · {changed} zmienionych",

    "scaffold.run.warn.heading": "Zanim wdrożysz",
    "scaffold.run.warn.note": "To nigdy nie zatrzymało rusztowania. Ma znaczenie dopiero przy wdrożeniu.",
    "scaffold.run.warn.readinessUnmet": "{kit} nie ma jeszcze kluczy, więc nie zadziała we wdrożonej aplikacji.",
    "scaffold.run.warn.fix": "Dodaj klucze",

    "scaffold.run.fail.heading": "Dlaczego się zatrzymało",
    "scaffold.run.fail.writeDenied": "Tego pliku nie dało się zapisać. Zwykle znaczy to, że jest tylko do odczytu albo otwarty w innym programie.",
    "scaffold.run.fail.rolledBack": "Pliki zapisane przed zatrzymaniem ({count}) zostały usunięte, więc projekt jest dokładnie taki jak wcześniej.",
    "scaffold.run.fail.retry": "Spróbuj ponownie",

    "scaffold.run.blocked.structureNotFrozen": "Rusztowanie przepisuje zamrożony projekt na kod. Twój wciąż jest edytowany, więc nie ma stałego punktu odniesienia.",
    "scaffold.run.blocked.action": "Zamroź projekt",

    "scaffold.run.next.build": "Przejdź do budowania",
}

ACCENT = str.maketrans({
    "a": "ä", "b": "ƀ", "c": "ç", "d": "ð", "e": "ë", "f": "ƒ", "g": "ğ", "h": "ĥ",
    "i": "ï", "j": "ĵ", "k": "ķ", "l": "ł", "m": "m", "n": "ñ", "o": "ö", "p": "þ",
    "q": "q", "r": "ř", "s": "š", "t": "ţ", "u": "ü", "v": "v", "w": "ŵ", "x": "x",
    "y": "ÿ", "z": "ž",
    "A": "Å", "B": "Ɓ", "C": "Ç", "D": "Ð", "E": "Ë", "F": "Ƒ", "G": "Ğ", "H": "Ĥ",
    "I": "Ï", "J": "Ĵ", "K": "Ķ", "L": "Ł", "M": "M", "N": "Ñ", "O": "Ö", "P": "Þ",
    "Q": "Q", "R": "Ř", "S": "Š", "T": "Ţ", "U": "Ü", "V": "V", "W": "Ŵ", "X": "X",
    "Y": "Ÿ", "Z": "Ž",
})

PLACEHOLDER = re.compile(r"\{[^}]*\}")


def pseudo(value: str) -> str:
    """Accent every letter outside {placeholders}, then pad ~30% and bracket."""
    out, last = [], 0
    for m in PLACEHOLDER.finditer(value):
        out.append(value[last:m.start()].translate(ACCENT))
        out.append(m.group(0))
        last = m.end()
    out.append(value[last:].translate(ACCENT))
    body = "".join(out)
    pad = "~̷~" * max(2, math.ceil(len(value) * 0.3 / 2))
    return f"[!! {body} {pad} !!]"


def merge(path: str, additions: dict) -> int:
    with open(path, encoding="utf-8") as fh:
        arb = json.load(fh, object_pairs_hook=OrderedDict)
    for key, value in additions.items():
        arb[key] = value
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(arb, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    return len([k for k in arb if not k.startswith("@")])


if __name__ == "__main__":
    assert set(EN) == set(PL), f"en/pl key drift: {set(EN) ^ set(PL)}"
    ploc = {k: pseudo(v) for k, v in EN.items()}
    for path, adds in (("app_en.arb", EN), ("app_pl.arb", PL), ("app_qps-ploc.arb", ploc)):
        print(f"{path}: {merge(path, adds)} keys (+{len(adds)})")
