#!/usr/bin/env python3
"""Reconcile the returned review workbook without changing the workbook.

Requires openpyxl. Defaults to a read-only report; --apply imports reviewed
current strings and the reviewed Welcome document, and writes an audit report.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

import openpyxl

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("workbook", type=Path)
parser.add_argument("--apply", action="store_true")
args = parser.parse_args()
digest = hashlib.sha256(args.workbook.read_bytes()).hexdigest()
book = openpyxl.load_workbook(args.workbook, read_only=True, data_only=True)
catalog_path = ROOT / "ghostWriter/Localizable.xcstrings"
catalog = json.loads(catalog_path.read_text())
strings = catalog["strings"]
source = "\n".join(p.read_text() for p in (ROOT / "ghostWriter").rglob("*.swift"))
source += "\n" + (ROOT / "ghostWriter/Resources/ghostWriter Help Manual.md").read_text()
printf = re.compile(r"%(?:\d+\$)?(?:[-+ #0]*\d*(?:\.\d+)?)?(?:ll|l|z)?[@diuoxXfFeEgGcCsSp%]")
accepted, retired, pending = [], [], []
seen = set()
counts = Counter()
for sheet_name in ["Interface", "Accessibility", "Help and onboarding", "Exports"]:
    rows = list(book[sheet_name].values)
    assert rows[1][0] == "Stable ID" and rows[1][3] == "English source"
    for row in rows[2:]:
        identifier, area, usage, english, draft, correction, status, notes, *_ = row
        if not identifier:
            continue
        assert identifier not in seen, f"Duplicate ID: {identifier}"
        seen.add(identifier)
        counts[status] += 1
        if status not in ("Approved", "Changed"):
            pending.append((identifier, status, english, notes or ""))
            continue
        translation = correction or draft
        assert isinstance(translation, str) and translation.strip(), identifier
        assert Counter(printf.findall(english)) == Counter(printf.findall(translation)), f"Placeholder mismatch: {identifier}"
        existing = strings.get(english)
        if english not in source and (existing is None or existing.get("extractionState") == "stale"):
            retired.append((identifier, english))
            continue
        entry = strings.setdefault(english, {"extractionState": "manual"})
        entry.setdefault("localizations", {})["es"] = {
            "stringUnit": {"state": "translated", "value": translation}
        }
        # Dynamic Help text is looked up at runtime, so preserve its manual key.
        if sheet_name == "Help and onboarding":
            entry["extractionState"] = "manual"
        if entry.get("extractionState") == "manual":
            entry["generatesSymbol"] = False
        accepted.append(identifier)

welcome_rows = list(book["Welcome document"].values)[2:]
english_welcome = "\n".join(row[2] or "" for row in welcome_rows).rstrip() + "\n"
current_welcome = (ROOT / "ghostWriter/Resources/Welcome to ghostWriter Markdown.md").read_text()
assert english_welcome == current_welcome.rstrip() + "\n", "Welcome source changed; reconcile before import."
translated_lines = []
for identifier, kind, english, draft, correction, status, notes in welcome_rows:
    counts[status] += 1
    if english:
        assert status in ("Approved", "Changed"), f"Unreviewed Welcome content: {identifier}"
        translated = correction or draft
        assert isinstance(translated, str) and translated.strip(), identifier
        # Preserve heading levels and list/code markers used by Markdown.
        marker = re.match(r"^(#{1,6} |[-*] |\d+\. |```)", english)
        if marker:
            assert translated.startswith(marker.group()), f"Markdown marker changed: {identifier}"
        translated_lines.append(translated)
    else:
        translated_lines.append("")
spanish_welcome = "\n".join(translated_lines).rstrip() + "\n"
book.close()

report = [
    "# Spanish localization review for 1.6.0", "",
    f"Returned workbook: {args.workbook.name}", "",
    f"Workbook SHA-256: `{digest}`", "",
    "The returned workbook is preserved unchanged. Corrections take precedence over drafts; the translators entered their changes in the Spanish draft column in this return.", "",
    f"Imported {len(accepted)} reviewed current catalog strings and the reviewed Welcome document. {len(retired)} reviewed entries no longer match current source and were not imported. {len(pending)} catalog entries remain pending.", "",
    "The Spanish interface release hold remains in place. New stylesheet documentation needs a Spanish draft and review in the next workbook. Existing unreviewed translations are retained as drafts, not newly approved. The English and bundled Help documents remain English until a complete Spanish manual is prepared.", "",
    "Spanish Grade 1 remains the default. Grade 2 has not received a full translator braille test; it must not be described as validated.", "",
    "## Questions to resolve", "",
]
for identifier, status, english, notes in pending:
    if status == "Question":
        report += [f"- {identifier}: {english}. Translator note: {notes}"]
report += ["", "## Reviewed entries whose source changed or was removed", ""]
report += [f"- {identifier}: {english}" for identifier, english in retired]
report += ["", "## Pending export and interface entries", "", ", ".join(item[0] for item in pending), "",
           "## Imported catalog IDs", "", ", ".join(accepted), "",
           "## Workbook status totals", ""]
report += [f"- {status}: {count}" for status, count in sorted(counts.items())]
report_text = "\n".join(report) + "\n"
if args.apply:
    # Match Xcode's formatting, including empty object spacing.
    encoded = json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : "))
    encoded = re.sub(r"^(\s*)\"(.*)\" : \{\}", lambda m: m[1] + '"' + m[2] + '" : {\n\n' + m[1] + '}', encoded, flags=re.M)
    catalog_path.write_text(encoded + "\n")
    (ROOT / "ghostWriter/es.lproj/Welcome to ghostWriter Markdown.md").write_text(spanish_welcome)
    (ROOT / "Documentation/Spanish localization review.md").write_text(report_text)
assert hashlib.sha256(args.workbook.read_bytes()).hexdigest() == digest
print(f"{'Imported' if args.apply else 'Ready to import'}: {len(accepted)} catalog strings and Welcome; {len(retired)} changed/removed sources; {len(pending)} pending entries.")
