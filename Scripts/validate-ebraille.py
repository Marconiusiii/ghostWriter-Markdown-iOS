#!/usr/bin/env python3
"""Run local structural and content checks on an eBraille (.ebrl) file.

Checks the container is a well-formed eBraille package, that required metadata
is present, that every rendered character is legal braille, and — the check
that actually catches translation bugs — back-translates the braille to English
so you can read what the file really says.

This is a focused project validator, not an official certification service and
not a substitute for reading the exported document on target hardware.

Usage:  validate-ebraille.py FILE.ebrl [--table en-ueb-g2.ctb]
"""

import argparse
import re
import subprocess
import sys
import zipfile
from xml.etree import ElementTree as ET
from urllib.parse import unquote, urlsplit

OPF = "{http://www.idpf.org/2007/opf}"
DC = "{http://purl.org/dc/elements/1.1/}"

# Legal in rendered braille text per eBraille 1.0 section 6.2.1: the Braille
# Patterns block, plus the listed whitespace characters. ASCII space is
# permitted — U+2800 is preferable on a real display, since it occupies a cell,
# but a plain space is conformant and is not reported as an error.
BRAILLE = re.compile("^[\u2800-\u28ff\t\n\r \u00a0\u00ad]*$")

# Whitespace that is legal but better expressed as U+2800 in braille text.
SOFT_WHITESPACE = re.compile("[ \u00a0]")

# Core image media types. PDF is permitted for tactile graphics but is a
# foreign resource: the spec requires a core-media-type fallback for it.
CORE_IMAGE_TYPES = {
    "image/jpeg": "JPG",
    "image/png": "PNG",
    "image/svg+xml": "SVG",
}
FOREIGN_IMAGE_TYPES = {"application/pdf": "PDF"}

REQUIRED_META = [
    "a11y:brailleSystem",
    "a11y:brailleCellType",
    "a11y:completeTranscription",
    "a11y:producer",
    "dcterms:dateCopyrighted",
    "dcterms:modified",
    "a11y:tactileGraphics",
]

# Marked RECOMMENDED by the spec rather than required, so their absence is
# reported as advice and does not fail the file. Split by namespace because
# Dublin Core elements are their own tags while dcterms lives in <meta>.
RECOMMENDED_DC = ["source", "publisher", "rights", "subject", "description"]
RECOMMENDED_META = ["dcterms:educationLevel"]

# dcterms:dateCopyrighted MUST be YYYY, YYYY-MM, or YYYY-MM-DD.
COPYRIGHT_DATE = re.compile(r"^\d{4}(-\d{2}(-\d{2})?)?$")

# dcterms:modified MUST be an XML Schema dateTime in UTC.
MODIFIED_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")

problems = []
notes = []
advice = []


def fail(msg):
    problems.append(msg)


def ok(msg):
    notes.append(msg)


def warn(msg):
    """A recommendation, not a conformance failure. Never affects exit status."""
    advice.append(msg)


def check_container(path):
    with open(path, "rb") as handle:
        head = handle.read(58)
    if head[30:38] != b"mimetype":
        fail("mimetype is not the first entry in the archive")
    elif head[38:58] != b"application/epub+zip":
        fail("mimetype content is not application/epub+zip")
    else:
        ok("mimetype is first and correct")

    with zipfile.ZipFile(path) as archive:
        info = archive.infolist()
        if info and info[0].filename == "mimetype":
            if info[0].compress_type != zipfile.ZIP_STORED:
                fail("mimetype is compressed; it must be stored")
            else:
                ok("mimetype is stored uncompressed")
        if "META-INF/container.xml" not in archive.namelist():
            fail("META-INF/container.xml is missing")
        else:
            ok("META-INF/container.xml present")
        return archive.namelist()


def opf_path(archive):
    with archive.open("META-INF/container.xml") as handle:
        tree = ET.parse(handle)
    node = tree.find(".//{urn:oasis:names:tc:opendocument:xmlns:container}rootfile")
    return node.get("full-path")


def check_metadata(archive, opf):
    with archive.open(opf) as handle:
        tree = ET.parse(handle)
    root = tree.getroot()

    for tag in ("identifier", "title", "creator", "language", "format"):
        element = root.find(f".//{DC}{tag}")
        if element is None or not (element.text or "").strip():
            fail(f"dc:{tag} is missing from the package metadata")
    fmt = root.find(f".//{DC}format")
    if fmt is not None and fmt.text != "eBraille 1.0":
        fail(f"dc:format is {fmt.text!r}, expected 'eBraille 1.0'")
    else:
        ok("dc:format declares eBraille 1.0")

    present = {m.get("property") for m in root.findall(f".//{OPF}meta")}
    for prop in REQUIRED_META:
        if prop not in present:
            fail(f"required metadata {prop} is missing")
    if all(p in present for p in REQUIRED_META):
        ok("all required eBraille metadata properties present")

    # a11y:brailleSystem should follow the registry form: "[code] [grade]",
    # where grade is grade0/grade1/grade2/no-grade, optionally followed by a
    # specialization. "UEB grade 2" reads well but is not registry syntax.
    system_re = re.compile(
        r"^\S+ (grade0|grade1|grade2|no-grade)( \S+)?$"
    )
    for meta in root.findall(f".//{OPF}meta"):
        if meta.get("property") != "a11y:brailleSystem":
            continue
        value = " ".join((meta.text or "").split())
        if not system_re.match(value):
            fail(
                f"a11y:brailleSystem {value!r} is not registry form "
                "'[code] [grade]' with grade spelled grade1/grade2/no-grade"
            )
        else:
            ok(f"a11y:brailleSystem {value!r} follows the registry form")

    lang = root.find(f".//{DC}language")
    if lang is not None:
        if "Brai" not in lang.text:
            fail(f"dc:language {lang.text!r} lacks the Brai script subtag")
        else:
            ok(f"dc:language is {lang.text}")

        # The document language and the braille code must describe the same
        # thing. A file translated through a UEB table but declaring itself
        # French misdescribes its own contents.
        code_languages = {"ueb": "en", "ebae": "en", "seb": "en", "cbc": "en"}
        declared = lang.text.split("-")[0].lower()
        for meta in root.findall(f".//{OPF}meta"):
            if meta.get("property") != "a11y:brailleSystem":
                continue
            code = (meta.text or "").strip().split(" ")[0].lower()
            expected = code_languages.get(code)
            if expected and expected != declared:
                fail(
                    f"dc:language is {lang.text!r} but a11y:brailleSystem "
                    f"{code!r} is a {expected!r} braille code"
                )

    # Date formats. Both are REQUIRED and both have a fixed shape; a file that
    # gets these wrong is non-conforming even though the property is present.
    for meta in root.findall(f".//{OPF}meta"):
        value = (meta.text or "").strip()
        if meta.get("property") == "dcterms:dateCopyrighted":
            if not COPYRIGHT_DATE.match(value):
                fail(
                    f"dcterms:dateCopyrighted {value!r} is not ISO 8601; "
                    "it must be YYYY, YYYY-MM, or YYYY-MM-DD"
                )
            else:
                ok(f"dcterms:dateCopyrighted {value!r} is a conformant date")
        elif meta.get("property") == "dcterms:modified":
            if not MODIFIED_DATE.match(value):
                fail(
                    f"dcterms:modified {value!r} is not an XML Schema dateTime "
                    "of the form YYYY-MM-DDThh:mm:ssZ"
                )
            else:
                ok(f"dcterms:modified {value!r} is a conformant dateTime")

    # a11y:producer allows one or more; the transcriber and the producing
    # software are both legitimate values, so this only reports the count.
    producers = [
        (m.text or "").strip()
        for m in root.findall(f".//{OPF}meta")
        if m.get("property") == "a11y:producer"
    ]
    if any(not producer for producer in producers):
        fail("a11y:producer must not be empty")
    elif producers:
        ok(f"a11y:producer names {', '.join(repr(p) for p in producers)}")

    # dc:creator must name the author of the work, not the software that made
    # the file. A creator that matches a producer usually means the two have
    # been conflated, which misdescribes the authorship of the source work.
    creator = root.find(f".//{DC}creator")
    if creator is not None:
        creator_text = (creator.text or "").strip()
        if any(creator_text.lower() == p.lower() for p in producers):
            warn(
                f"dc:creator is {creator_text!r}, which is also an "
                "a11y:producer — dc:creator should name the author of the "
                "original work, not whoever produced the braille"
            )

    # Properties the spec recommends. Absent ones are worth mentioning because
    # they are what makes a transcription traceable to its source.
    for tag in RECOMMENDED_DC:
        if root.find(f".//{DC}{tag}") is None:
            warn(f"recommended metadata dc:{tag} is not present")
    present_meta = {m.get("property") for m in root.findall(f".//{OPF}meta")}
    for prop in RECOMMENDED_META:
        if prop not in present_meta:
            warn(f"recommended metadata {prop} is not present")

    manifest = {i.get("href") for i in root.findall(f".//{OPF}item")}
    names = set(archive.namelist())
    for href in manifest:
        if href not in names:
            fail(f"manifest lists {href}, which is not in the archive")
    ok(f"{len(manifest)} manifest items all present in the archive")
    return manifest


def text_nodes(xhtml):
    """Rendered text and alt attributes, in document order."""
    body = xhtml.split("<body>", 1)[-1]
    alts = re.findall(r'alt="([^"]*)"', body)
    stripped = re.sub(r"<[^>]+>", "\n", body)
    nodes = [n for n in stripped.split("\n") if n.strip()]
    return nodes, alts


def check_braille(archive, manifest, table, show):
    names = set(archive.namelist())
    for href in sorted(manifest):
        if not href.endswith((".xhtml", ".html")) or href not in names:
            continue
        with archive.open(href) as handle:
            xhtml = handle.read().decode("utf-8")
        nodes, alts = text_nodes(xhtml)

        for value in nodes + alts:
            if not BRAILLE.match(value):
                bad = {c for c in value if not ("⠀" <= c <= "⣿")}
                bad -= {"\n"}
                if bad:
                    fail(f"{href}: print characters in rendered text: {sorted(bad)!r}")
                    break
        else:
            ok(f"{href}: all rendered text is braille")

        if show and (nodes or alts):
            print(f"\n--- back-translation of {href} ---")
            for value in nodes + alts:
                english = back_translate(value, table)
                if english:
                    print(f"  {english}")


def back_translate(braille, table):
    try:
        result = subprocess.run(
            ["lou_translate", "-b", f"unicode.dis,{table}"],
            input=braille, capture_output=True, text=True, check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return result.stdout.strip()


def check_entry_page(archive, opf, manifest):
    """Primary entry page rules (eBraille 1.0 section 8).

    index.html must sit in the publication root, be a navigation document,
    point back at the package document, and carry the dpub-aria roles that let
    a web renderer recognise its table of contents and page list.
    """
    names = set(archive.namelist())
    if "index.html" not in names:
        fail("index.html is missing from the publication root")
        return
    ok("index.html present in the publication root")

    if opf != "package.opf":
        fail(f"package document is {opf!r}; it must be package.opf in the root")
    else:
        ok("package document is package.opf in the root")

    with archive.open("index.html") as handle:
        page = handle.read().decode("utf-8")

    link = re.search(r'<link\b[^>]*rel="publication"[^>]*>', page)
    if not link:
        fail('index.html has no <link rel="publication"> pointing at the package document')
    else:
        tag = link.group(0)
        href = re.search(r'href="([^"]*)"', tag)
        media = re.search(r'type="([^"]*)"', tag)
        if not href or href.group(1) != opf:
            fail(f'<link rel="publication"> href must be {opf!r}')
        elif not media or media.group(1) != "application/oebpspackage+xml".replace(
            "oebpspackage", "oebps-package"
        ):
            fail('<link rel="publication"> type must be application/oebps-package+xml')
        else:
            ok('index.html links to the package document')

    if 'role="doc-toc"' not in page:
        fail('the table of contents nav must carry role="doc-toc"')
    else:
        ok("table of contents carries the doc-toc role")

    if 'epub:type="page-list"' in page and 'role="doc-pagelist"' not in page:
        fail('the page list nav must also carry role="doc-pagelist"')

    # A page list entry must name its print page in a title attribute.
    pagelist = re.search(r'<nav[^>]*page-list.*?</nav>', page, re.S)
    if pagelist:
        for anchor in re.findall(r"<a\b[^>]*>", pagelist.group(0)):
            if "title=" not in anchor:
                fail("each page list entry needs a title with the print page number")
                break

    # The entry page should not be in the spine.
    with archive.open(opf) as handle:
        root = ET.parse(handle).getroot()
    nav_ids = {
        item.get("id")
        for item in root.findall(f".//{OPF}item")
        if "nav" in (item.get("properties") or "")
    }
    spine_ids = {ref.get("idref") for ref in root.findall(f".//{OPF}itemref")}
    if nav_ids & spine_ids:
        notes.append("note: the entry page is in the spine; the spec recommends against it")
    else:
        ok("entry page is kept out of the spine")

    try:
        navigation = ET.fromstring(page)
    except ET.ParseError as error:
        fail(f"index.html is not well-formed XML: {error}")
        return

    targets = []
    for anchor in navigation.findall(".//{*}nav//{*}a"):
        href = (anchor.get("href") or "").strip()
        if href:
            targets.append(href)
    if not targets:
        fail("the table of contents has no links")
        return

    parsed_documents = {}
    problem_count = len(problems)
    for href in targets:
        parts = urlsplit(href)
        if parts.scheme or parts.netloc:
            fail(f"table of contents link {href!r} points outside the publication")
            continue
        path = unquote(parts.path) or "index.html"
        if path not in manifest or path not in names:
            fail(f"table of contents link {href!r} targets an unmanifested document")
            continue
        if not parts.fragment:
            continue
        if path not in parsed_documents:
            with archive.open(path) as handle:
                parsed_documents[path] = ET.parse(handle).getroot()
        ids = {
            element.get("id")
            for element in parsed_documents[path].iter()
            if element.get("id")
        }
        if unquote(parts.fragment) not in ids:
            fail(f"table of contents link {href!r} targets a missing identifier")
    if len(problems) == problem_count:
        ok(f"checked {len(targets)} table of contents link target(s)")


def check_forbidden(archive, opf, manifest):
    """Features eBraille forbids (sections 3.4, 5.6, 6.2.3, 6.3, 7)."""
    with archive.open(opf) as handle:
        opf_text = handle.read().decode("utf-8")
        root = ET.fromstring(opf_text)

    # Manifest fallbacks are forbidden outright.
    if re.search(r'<item\b[^>]*\bfallback=', opf_text):
        fail("manifest fallbacks are not allowed in eBraille")

    if "<collection" in opf_text:
        fail("collections are not allowed in the package document")

    for meta in root.findall(f".//{OPF}meta"):
        prop = meta.get("property") or ""
        if prop.startswith("rendition:layout") and (meta.text or "").strip() == "pre-paginated":
            fail("fixed layout (rendition:layout pre-paginated) is not allowed")
        if prop.startswith("rendition:") and prop != "rendition:layout":
            fail(f"fixed-layout property {prop} is not allowed")
    for ref in root.findall(f".//{OPF}itemref"):
        if "rendition:layout-pre-paginated" in (ref.get("properties") or ""):
            fail("spine override rendition:layout-pre-paginated is not allowed")

    # Remote resources and absolute paths are not supported.
    for item in root.findall(f".//{OPF}item"):
        href = item.get("href", "")
        if re.match(r"^[a-z][a-z0-9+.-]*://", href):
            fail(f"remote resource in manifest: {href}")
        elif href.startswith("/"):
            fail(f"path-absolute URL in manifest: {href}")
        elif href.startswith("../"):
            fail(f"resource outside the publication root: {href}")

    names = set(archive.namelist())
    for href in sorted(manifest):
        # A manifest entry that is not in the archive is already reported by
        # check_metadata; skip it here rather than crashing on the open.
        if href not in names:
            continue
        if href.endswith((".xhtml", ".html")):
            with archive.open(href) as handle:
                doc = handle.read().decode("utf-8")
            if re.search(r"<script\b", doc):
                fail(f"{href}: script elements are not allowed")
            if re.search(r"<form\b[^>]*\baction=", doc):
                fail(f"{href}: the form action attribute is not allowed")
            if "-epub-" in doc:
                fail(f"{href}: -epub- prefixed CSS properties are not allowed")

        if href.endswith(".css"):
            with archive.open(href) as handle:
                css = handle.read().decode("utf-8")
            if "-epub-" in css:
                fail(f"{href}: -epub- prefixed properties are not allowed")
            if re.search(r"@media[^{]*\bbraille\b", css):
                fail(f"{href}: the deprecated braille media type must not be used")
            font_props = sorted({
                m.group(1)
                for m in re.finditer(
                    r"\b(font-family|font-size|font-style|font-weight|font-variant"
                    r"|color|text-decoration|text-shadow|text-underline-position)\s*:",
                    css,
                )
            })
            if font_props:
                notes.append(
                    f"note: {href} sets typographic properties the spec advises "
                    f"against: {', '.join(font_props)}"
                )
            # Horizontal positions must be in ch. Reading systems guarantee
            # 1ch is the cell-to-cell distance and 1em the line-to-line
            # distance, so an em margin indents by lines and lands on an
            # arbitrary cell — braille layout standards are written in cells.
            horizontal = re.findall(
                r"\b(margin-left|margin-right|padding-left|padding-right|text-indent)"
                r"\s*:\s*(-?\d+(?:\.\d+)?)(em|rem)\b",
                css,
            )
            if horizontal:
                props = sorted({f"{prop} in {unit}" for prop, _, unit in horizontal})
                fail(
                    f"{href}: horizontal spacing uses line units: "
                    f"{', '.join(props)}; use ch, which is one braille cell"
                )
            elif re.search(r"\b(padding-left|text-indent|margin-left)\s*:\s*-?\d", css):
                ok(f"{href}: horizontal spacing is in cell units")

            if re.search(r"\b\d+(\.\d+)?(px|pt|cm|mm|in|pc)\b", css):
                notes.append(
                    f"note: {href} uses absolute lengths; the spec asks for "
                    "font-relative units (em, ch, rem)"
                )
            ok(f"{href}: no forbidden CSS features")

        if href.endswith(".svg"):
            with archive.open(href) as handle:
                svg = handle.read().decode("utf-8")
            lowered = svg.lower()
            forbidden_elements = (
                "script", "foreignobject", "iframe", "object", "embed",
                "audio", "video", "form", "input", "button", "animate",
                "animatemotion", "animatetransform", "set",
            )
            for element in forbidden_elements:
                if re.search(rf"<{element}\b", lowered):
                    fail(f"{href}: <{element}> is not allowed in a shared tactile SVG")
            if re.search(r"\son[a-z0-9_-]+\s*=", lowered):
                fail(f"{href}: event-handler attributes are not allowed in a tactile SVG")
            if re.search(r"\b(?:href|xlink:href|src)\s*=\s*['\"](?!#|['\"])", lowered):
                fail(f"{href}: external resource references are not allowed in a tactile SVG")
            if "@import" in lowered or "url(" in lowered:
                fail(f"{href}: external CSS references are not allowed in a tactile SVG")
            if "<!entity" in lowered:
                fail(f"{href}: external entity declarations are not allowed in a tactile SVG")


def check_graphics(archive, opf, manifest):
    """Validate images and the tactile graphics declaration.

    ghostWriter identifies tactile images with the tactile-graphic class in
    XHTML. This lets the validator compare the declaration with the resources
    actually presented as tactile, without misclassifying ordinary images.
    """
    with archive.open(opf) as handle:
        root = ET.parse(handle).getroot()

    image_formats = {}
    manifest_items = {}
    foreign = []
    for item in root.findall(f".//{OPF}item"):
        media = item.get("media-type", "")
        href = item.get("href", "")
        manifest_items[href] = item
        if media in CORE_IMAGE_TYPES:
            image_formats[href] = CORE_IMAGE_TYPES[media]
        elif media in FOREIGN_IMAGE_TYPES:
            counts[FOREIGN_IMAGE_TYPES[media]] = counts.get(FOREIGN_IMAGE_TYPES[media], 0) + 1
            if item.get("fallback") is None:
                foreign.append(href)
        elif media.startswith("image/"):
            fail(f"{href}: {media} is not a core eBraille image type")

    declared = None
    for meta in root.findall(f".//{OPF}meta"):
        if meta.get("property") == "a11y:tactileGraphics":
            declared = (meta.text or "").strip()

    for href in foreign:
        fail(f"{href} is a foreign resource (PDF) with no fallback declared")

    tactile_sources = []
    referenced_images = []
    names = set(archive.namelist())
    for href in sorted(manifest):
        if not href.endswith((".xhtml", ".html")) or href not in names:
            continue
        with archive.open(href) as handle:
            xhtml = handle.read().decode("utf-8")
        for tag in re.findall(r"<img\b[^>]*/?>", xhtml):
            src = re.search(r'src="([^"]*)"', tag)
            if src:
                referenced_images.append(unquote(src.group(1)))
            classes = re.search(r'class="([^"]*)"', tag)
            class_names = (classes.group(1).split() if classes else [])
            if "tactile-graphic" not in class_names:
                continue
            if not src:
                fail(f"{href}: tactile graphic has no src")
                continue
            tactile_sources.append(unquote(src.group(1)))

    tactile_formats = [image_formats.get(source) for source in tactile_sources]
    for source, image_format in zip(tactile_sources, tactile_formats):
        if image_format is None:
            fail(f"tactile graphic {source!r} is not a supported manifested image")

    if any(image_formats.get(source) == "SVG" for source in referenced_images):
        for href in sorted(manifest):
            if not href.endswith((".xhtml", ".html")) or href not in names:
                continue
            with archive.open(href) as handle:
                xhtml = handle.read().decode("utf-8")
            references_svg = any(
                source in xhtml
                for source in referenced_images
                if image_formats.get(source) == "SVG"
            )
            properties = (manifest_items.get(href).get("properties", "")
                          if manifest_items.get(href) is not None else "")
            if references_svg and "svg" not in properties.split():
                fail(f"{href}: manifest item must declare the svg property")

    if declared is None:
        fail("a11y:tactileGraphics is missing")
        return

    if declared == "none":
        if tactile_sources:
            fail("a11y:tactileGraphics declares none but tactile graphics are present")
        else:
            ok("a11y:tactileGraphics declares that no tactile graphics are present")
        return

    if not tactile_sources:
        fail(f"a11y:tactileGraphics says {declared!r} but no tactile graphics are marked in the content")
        return

    listed = [part.strip() for part in declared.split(",") if part.strip()]
    actual = {value for value in tactile_formats if value is not None}
    if set(listed) != actual:
        fail(
            f"a11y:tactileGraphics lists {declared!r}, but tactile content "
            f"uses {', '.join(sorted(actual)) or 'no supported format'}"
        )
    else:
        ok(f"a11y:tactileGraphics matches tactile content formats: {declared}")


def check_image_alt(archive, manifest, table, show):
    """Every non-decorative image needs braille alt text.

    An image with no description is inert to a reader who cannot see it, and
    alt text in print rather than braille would be unreadable on a display.
    """
    described = 0
    decorative = 0
    names = set(archive.namelist())

    for href in sorted(manifest):
        if not href.endswith((".xhtml", ".html")) or href not in names:
            continue
        with archive.open(href) as handle:
            xhtml = handle.read().decode("utf-8")

        for tag in re.findall(r"<img\b[^>]*/?>", xhtml):
            src = re.search(r'src="([^"]*)"', tag)
            src = src.group(1) if src else "(no src)"
            alt = re.search(r'alt="([^"]*)"', tag)

            if alt is None:
                fail(f"{href}: <img src={src!r}> has no alt attribute")
                continue

            value = alt.group(1)
            if value == "":
                # Native HTML defines alt="" as decorative. Redundant ARIA is
                # neither required nor desirable here.
                decorative += 1
                continue

            presentation = 'role="presentation"' in tag or 'aria-hidden="true"' in tag
            if presentation:
                fail(f"{href}: <img src={src!r}> is decorative but has alt text")
                continue

            if not BRAILLE.match(value):
                bad = sorted({c for c in value if not ("\u2800" <= c <= "\u28ff")})
                fail(f"{href}: alt text for {src!r} is not braille: {bad!r}")
                continue

            described += 1
            if show:
                english = back_translate(value, table)
                if english:
                    print(f"  [image] {src}: {english}")

            if src not in manifest:
                fail(f"{href}: <img> references {src!r}, which is not in the manifest")

    if described or decorative:
        ok(f"{described} described image(s), {decorative} decorative")


def check_roundtrip(archive, manifest, table):
    """Catch word boundaries dropped at an inline-markup edge.

    Guessing from the English does not work: "isbold" looks like an ordinary
    word, while legitimate names such as ghostWriter and iCloud carry an
    internal capital and look like two words fused. So this compares the file
    against the source instead. Each side of an inline boundary is translated
    on its own and the results concatenated; if the file's braille is shorter
    than that, a separating space was swallowed on the way in.
    """
    names = set(archive.namelist())
    for href in sorted(manifest):
        if not href.endswith((".xhtml", ".html")) or href not in names:
            continue
        with archive.open(href) as handle:
            xhtml = handle.read().decode("utf-8")

        for tag, markup in re.findall(r"<(p|h[1-6]|li|td|th)>(.*?)</\1>", xhtml, re.S):
            # Split into the runs the markup separates, keeping their order.
            runs = [r for r in re.split(r"<[^>]+>", markup)]
            if len(runs) < 2:
                continue
            if not any(r.strip() for r in runs[1:]):
                continue

            for before, after in zip(runs, runs[1:]):
                if not before.strip() or not after.strip():
                    continue
                # A boundary is intact if the two runs stay separated: either
                # the file already carries a braille space between them, or
                # the words genuinely abut in the source.
                if before.endswith("\u2800") or after.startswith("\u2800"):
                    continue

                english_before = back_translate(before, table) or ""
                english_after = back_translate(after, table) or ""
                if not english_before or not english_after:
                    continue
                # Two word characters meeting with no space between them is
                # the signature of a lost boundary.
                if english_before[-1].isalnum() and english_after[0].isalnum():
                    fail(
                        f"{href}: no space between {english_before!r} and "
                        f"{english_after!r} across an inline boundary"
                    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("file")
    parser.add_argument("--table", default="en-ueb-g2.ctb")
    parser.add_argument("--quiet", action="store_true",
                        help="skip the back-translation dump")
    args = parser.parse_args()

    try:
        check_container(args.file)
        with zipfile.ZipFile(args.file) as archive:
            opf = opf_path(archive)
            manifest = check_metadata(archive, opf)
            check_braille(archive, manifest, args.table, not args.quiet)
            check_entry_page(archive, opf, manifest)
            check_forbidden(archive, opf, manifest)
            check_graphics(archive, opf, manifest)
            check_image_alt(archive, manifest, args.table, not args.quiet)
            check_roundtrip(archive, manifest, args.table)
    except Exception as error:
        # Report rather than exit silently: a crash part-way through must not
        # look like a clean run, and whatever was found before it still counts.
        fail(f"validator error while reading the file: {error!r}")

    print("\n=== checks passed ===")
    for note in notes:
        print(f"  ok    {note}")
    if advice:
        print("\n=== recommendations ===")
        for item in advice:
            print(f"  note  {item}")
    if problems:
        print("\n=== problems ===")
        for problem in problems:
            print(f"  FAIL  {problem}")
        print(f"\n{len(problems)} problem(s) found.")
        return 1
    print("\nNo problems found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
