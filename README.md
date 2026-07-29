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
- Share complete standalone HTML, Markdown, or plain-text files
- Insert links, external images, formatting, headings, quotes, code, and lists
  through a dedicated Insert Actions workflow
- Customize the information presented in the editor Status Bar
- Choose an editor typeface without losing Dynamic Type support
- Use optional hardware-keyboard shortcuts for common Library and editor actions

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
- No third-party packages or external dependencies

## Building

1. Clone the repository:

   ```sh
   git clone https://github.com/Marconiusiii/ghostWriter.git
   cd ghostWriter
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
through [GitHub Issues](https://github.com/Marconiusiii/ghostWriter/issues).
Please include the device, OS version, app version, assistive technology, and
clear reproduction steps when reporting an accessibility problem.

The app also includes a Send Feedback button in Settings. It opens an in-app
mail composer and automatically includes the app and OS versions.

Before contributing code, preserve the native SwiftUI control structure,
logical reading order, Dynamic Type behavior, and existing VoiceOver focus
contracts. In particular, Outline navigation has specialized focus management
that keeps a writer's place in long documents.

## Project links

- [ghostWriter on the web](https://marconius.com/fun/ghostWriter/)
- [Privacy Policy](https://marconius.com/gwPrivacy/)
- [GitHub repository](https://github.com/Marconiusiii/ghostWriter/)

## License

ghostWriter Markdown is available under the
[MIT License](LICENSE).

Copyright © 2026 Marco Salsiccia.
