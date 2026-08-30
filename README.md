# ghostWriter Markdown

ghostWriter Markdown is a lightweight, accessibility-first Markdown editor for
iPhone and iPad. It is designed as a blind-first writing environment while
remaining straightforward and comfortable for every writer.

The app keeps documents as ordinary Markdown files, uses native iOS controls,
and provides structured HTML rendering without requiring an account, analytics,
or a developer-operated online service.

## Accessibility

Accessibility is a core part of ghostWriter's interface rather than an optional
mode. The app is developed toward WCAG 2.2 Level AA and tested with VoiceOver as
a primary interaction method.

Accessibility features include:

- A predictable, linear VoiceOver reading order
- Native controls with their expected roles and interactions
- Outline navigation that moves the insertion point and VoiceOver focus to a
  selected heading
- A configurable editor Status Bar for line, column, document, heading, and
  selection information
- Dynamic Type support, including accessibility text sizes
- System, monospaced, rounded, and serif editor font choices
- Light, dark, and system appearance options
- Native text editing, selection, dictation, braille input, and Find and Replace
- Voice Control, Switch Control, and hardware keyboard compatibility through
  standard iOS components
- Accessible rendered HTML with semantic headings, lists, tables, links, and
  landmarks
- Reduced-motion support and visible keyboard focus in rendered documents
- Logical focus restoration after sheets, menus, alerts, and file operations

The app interface is responsible for providing an accessible editing and file
management experience. The author of a document remains responsible for the
accessibility of the content they create, including heading structure, link
wording, image alternative text, and table design.

Accessibility testing is an ongoing process. Reports from VoiceOver and other
assistive technology users are especially welcome.

## Features

- Create, open, rename, duplicate, import, share, and recover Markdown documents
- Restore deleted documents or remove them permanently through Recently Deleted
- Store documents as ordinary files that are visible in the Files app
- Automatically save changes while protecting against external file conflicts
- Search document names and contents
- Pin important documents at the beginning of the Library
- Sort documents by name, creation date, modification date, or last opened date
- Continue bulleted, numbered, and task lists automatically
- Indent and outdent using tabs, two spaces, or four spaces
- Navigate long documents through a heading-based Outline
- Jump directly to a numbered line from File Actions
- Render Markdown as structured HTML inside the app
- Export to Markdown, plain text, HTML, Word, PowerPoint, PDF, EPUB, eBraille,
  and Braille Ready Format
- Produce contracted or uncontracted braille editions translated with liblouis
- Insert links, external images, formatting, headings, quotes, code, and lists
  through a dedicated Insert Actions workflow
- Attach images from Files or the Photo Library with alternative text or a
  decorative designation
- Customize the information presented in the editor Status Bar
- Choose an editor typeface without losing Dynamic Type support
- Use optional hardware-keyboard shortcuts for common Library and editor actions

## Export formats

Documents are shared through File Actions > Share.

| Format | Extension | Notes |
| --- | --- | --- |
| Markdown | `.md` | The original syntax, unchanged |
| Plain Text | `.txt` | Markdown syntax removed |
| HTML | `.html` | Complete standalone document with managed local images embedded |
| Word Document | `.docx` | Word heading styles, lists, and tables |
| PowerPoint | `.pptx` | Widescreen slides, presentation themes, speaker notes, and embedded images |
| PDF | `.pdf` | Tagged PDF, US Letter, one-inch margins |
| EPUB | `.epub` | Reflowable ebook with a table of contents |
| eBraille | `.ebrl` | Reflowable Unicode braille targeting eBraille 1.0 |
| Braille Ready Format | `.brf` | Fixed-page braille for displays and embossers |

Content handling varies by export format. PowerPoint's supported content and
conversion limits are described below. HTML embeds images from the app-managed
asset directory in the standalone file. EPUB and eBraille package those images
inside their publications. In these HTML-based exports, unsafe, missing, or
unsupported local image references fall back to readable alternative text
instead of becoming broken references.

### PowerPoint presentations

Choose File Actions > Share > PowerPoint, then select a theme. Warm paper,
Midnight, High contrast light, and High contrast dark apply to the whole
presentation. The app remembers the selected theme. Theme text and background
pairings have automated contrast checks of at least 7:1; themes do not recolor
images or guarantee the accessibility of their contents.

A level 1 heading before the first slide supplies the presentation title;
otherwise, the document name is used. Content before the first level 2 heading
appears on the title slide. Each level 2 heading starts and titles a new slide.
Put `***` on a line by itself to start speaker notes, which continue until the
next level 2 heading. Deeper headings do not end speaker notes.

| Markdown content | PowerPoint output |
| --- | --- |
| Deeper headings and paragraphs | Slide text with supported inline emphasis and formatting |
| Bulleted and numbered lists | Native list paragraphs with nested levels and starting numbers |
| Task lists | List items with Completed or Not completed labels, not interactive checkboxes |
| Links outside tables | Clickable text |
| Tables | Column headings followed by labeled text rows, not native PowerPoint tables |
| Block quotes | Paragraphs introduced by Quote |
| Code blocks | Monospaced text without syntax highlighting |
| Images | Embedded pictures with alternative text or a decorative designation |

Tables do not retain their grid, column alignment, cell formatting, or
cell-by-cell table navigation. Links within table cells become plain text.

Use Insert Actions > Image from Files or Image from Photo Library to attach an
image. The app stores it with the document and inserts its relative Markdown
reference. PowerPoint also downloads PNG, JPEG, and SVG images referenced by
HTTPS URLs. SVGs become high-resolution PNG pictures with their colors and
transparency preserved; the original Markdown reference is unchanged.
Unavailable, invalid, or oversized images are skipped without preventing the
rest of the presentation from exporting.

Each slide supports up to four included images. Slides with too much text or
too many images produce an error asking for another level 2 heading. Content is
not automatically split across slides. Image loading is bounded to 32 unique
references, 10 MiB per image, and a 40 MiB total image-data budget, including SVG
conversions.

Automated tests check exported content, package structure, and theme contrast.
They do not establish PowerPoint or VoiceOver behavior on a user's device.

### Braille exports

Both braille formats translate through [liblouis](https://liblouis.io/) into
Unified English Braille, in contracted (grade 2) or uncontracted (grade 1)
form. The app remembers the grade, transcriber, and BRF page dimensions.
Metadata about a particular work is not reused automatically for another
document.

**eBraille** produces a `.ebrl` file targeting [eBraille
1.0](https://daisy.github.io/ebraille/published/1.0/). Content is Unicode
braille that reflows to the line length of the display it is read on, with a
navigation document, embedded images, and the metadata the standard requires.
The export requires an author, transcriber, copyright date, braille grade, and
completeness declaration rather than inventing those facts. Ordinary embedded
pictures are not declared to be tactile graphics.

**Braille Ready Format** produces a `.brf` file of ASCII braille, wrapped and
paginated to a fixed page. The export asks for the braille grade and the page
size; the default is the standard braille page of 40 cells by 25 lines.

Two scripts in `Scripts/` help when working on braille output:

```sh
# Run local structural checks and read the braille back in English
python3 Scripts/validate-ebraille.py FILE.ebrl

# Show the cell layout of each block
python3 Scripts/preview-ebraille-layout.py FILE.ebrl

# Unpack an eBraille file and open it in a browser
Scripts/open-ebraille.sh FILE.ebrl
```

The validation and preview scripts need liblouis installed locally
(`brew install liblouis`). The validator checks the package rules implemented
by the script; it does not replace testing in an independent eBraille reading
system or review by a qualified braille transcriber.

## Supported Markdown

The renderer supports common Markdown structures, including:

- ATX and Setext headings
- Paragraphs and line breaks
- Emphasis, strong emphasis, and strikethrough
- Inline and fenced code
- Ordered, unordered, nested, and task lists
- Block quotations
- Links, reference links, and images
- Tables with column headings and alignment
- Horizontal rules

Rendered and shared HTML documents include a complete `head` section, a
document title, responsive viewport information, and a semantic `main` region.
JavaScript is not used in rendered documents.

## Requirements

- iOS or iPadOS 17.6 or later
- Xcode with support for the project's iOS deployment target
- ZIPFoundation is resolved as a Swift package dependency. liblouis is vendored
  in `Vendor/liblouis` as a prebuilt XCFramework under the LGPL v2.1 or later;
  its licence and source location are recorded in the app under Settings >
  Acknowledgements. Anyone distributing a statically linked build should review
  the LGPL relinking and source-delivery obligations for that distribution.

## Building

1. Clone the repository:

   ```sh
   git clone https://github.com/Marconiusiii/ghostWriter-Markdown-iOS.git
   cd ghostWriter-Markdown-iOS
   ```

2. Open `ghostWriter.xcodeproj` in Xcode.
3. Select the `ghostWriter` scheme and an iPhone or iPad simulator.
4. Build and run the app with Command-R.

To run the test suite in Xcode, use Command-U. Tests can also be run from the
command line after substituting an installed simulator name:

```sh
xcodebuild \
  -project ghostWriter.xcodeproj \
  -scheme ghostWriter \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

Available simulator destinations can be listed with:

```sh
xcodebuild -project ghostWriter.xcodeproj -scheme ghostWriter -showdestinations
```

## Files and privacy

Documents are stored locally as Markdown files in the app's `ghostWriter`
Documents folder. The folder is available through the Files app so writers can
copy, move, back up, or manage their work outside ghostWriter.

Deleted documents move into the `Recently Deleted` folder and remain there
until restored or permanently deleted by the user.

ghostWriter has no accounts, advertising, or analytics and does not collect
user data. A rendered document can request an externally hosted image when its
Markdown contains an external image address. Sharing sends the selected file to
the standard iOS share sheet, after which the receiving app's privacy policy
applies.

Read the complete
[ghostWriter Privacy Policy](https://marconius.com/gwPrivacy/).

## Contributing and feedback

Bug reports, accessibility findings, and focused improvements are welcome
through [GitHub Issues](https://github.com/Marconiusiii/ghostWriter-Markdown-iOS/issues).
Please include the device, OS version, app version, assistive technology, and
clear reproduction steps when reporting an accessibility problem.

The app also includes a Send Feedback button in Settings. It opens an in-app
mail composer and automatically includes the app and OS versions.

Before contributing code, preserve the native SwiftUI control structure,
logical reading order, Dynamic Type behavior, and existing VoiceOver focus
contracts. In particular, Outline navigation has specialized focus management
that keeps a writer's place in long documents.

## Project links

- [ghostWriter Markdown for iOS](https://marconius.com/ghostWriter/)
- [ghostWriter on the web](https://marconius.com/fun/ghostWriter/)
- [Privacy Policy](https://marconius.com/gwPrivacy/)
- [GitHub repository](https://github.com/Marconiusiii/ghostWriter-Markdown-iOS/)

## License

ghostWriter Markdown is available under the
[MIT License](LICENSE).

Copyright © 2026 Marco Salsiccia.
