#!/usr/bin/env python3
"""Build the bundled Markdown manual from the same content as native Help."""
from pathlib import Path
import subprocess
import json
import tempfile

root = Path(__file__).resolve().parents[1]
view = (root / 'ghostWriter/Views/HelpView.swift').read_text()
model = view[view.index('struct HelpTopic:'):]
source = 'import Foundation\n' + model
for path in ['ghostWriter/Word/WordExportHelpContent.swift', 'ghostWriter/Export/CompilationHelp.swift']:
    source += '\n' + (root / path).read_text()
source += r'''
var manual = "# ghostWriter Markdown Help\n\n"
manual += "Open Help Manual in the library or use the Help Manual button at the top of Help. The included manual is read-only and stays current with app updates. Choose Make a Copy to create an editable document for your notes. Your copy is separate from this manual.\n\n"
func appendTopic(_ topic: HelpTopic, level: Int) {
    manual += String(repeating: "#", count: level) + " " + topic.title + "\n\n"
    manual += topic.paragraphs.joined(separator: "\n\n") + "\n\n"
    if topic.offersStylesheetCopy {
        manual += "Default stylesheet example:\n\n```json\n" + WordExportHelp.example + "\n```\n\n"
    }
    for child in topic.subtopics { appendTopic(child, level: level + 1) }
}
for category in HelpCategory.all {
    manual += "## " + category.title + "\n\n"
    for topic in category.topics { appendTopic(topic, level: 3) }
}
let word = "# Word export\n\n" + WordExportHelp.workflow.joined(separator: "\n\n")
    + "\n\n## Named stylesheets\n\n" + WordExportHelp.theme.joined(separator: "\n\n")
    + "\n\n## JSON specification\n\n" + WordExportHelp.reference.joined(separator: "\n\n")
    + "\n\n### Additional paragraph and document settings\n\n" + WordExportHelp.advanced.joined(separator: "\n\n")
    + "\n\n## Default stylesheet example\n\n```json\n" + WordExportHelp.example + "\n```\n"
let output = ["manual": manual.trimmingCharacters(in: .whitespacesAndNewlines) + "\n", "word": word]
let encoded = try JSONEncoder().encode(output)
print(String(decoding: encoded, as: UTF8.self))
'''
with tempfile.TemporaryDirectory(prefix='ghostwriter-manual-') as temporary:
    swift = Path(temporary) / 'main.swift'
    swift.write_text(source)
    output = json.loads(subprocess.check_output(['swift', '-module-cache-path', str(Path(temporary) / 'cache'), str(swift)], text=True))
for path in ['Documentation/Help.md', 'ghostWriter/Resources/ghostWriter Help.md']:
    (root / path).write_text(output['manual'])
(root / 'Documentation/Word export.md').write_text(output['word'])
