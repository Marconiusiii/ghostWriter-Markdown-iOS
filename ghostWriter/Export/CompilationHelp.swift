import Foundation

nonisolated enum CompilationHelp {
    static let paragraphs = [
        "To combine a folder’s documents, choose Export Compilation… from its context menu or VoiceOver Actions. Inside an open folder, use its heading actions. Enter Document name and choose Export format.",
        "Use the switches in Files and folders to select what to include. Expand a folder to choose individual items inside it. Turning off a folder excludes all of its contents; turning it back on restores the individual selections.",
        "The initial order comes from saved Manual order, regardless of the Library’s current sort or pinned documents. Choose Edit to rearrange files and folders, then Done Editing to return to selection. Moving a folder moves its contents together. These changes apply only to this export.",
        "To save an inclusion preference for future exports, use Exclude from Compilations or Include in Compilations in a file or folder’s Library actions, an open folder’s heading actions, or the editor’s File Actions. These saved exclusions also apply to folder word, sentence, and character totals. Exporting a folder directly always uses that folder as the scope, even if it is excluded from compilations of its parent.",
        "Each document uses its opening Heading 1 as its title, or its filename if it has no opening Heading 1. Document name names the output file; it does not create a title page.",
        "Word and PDF offer Start each document on a new page. Turn it off to let the documents flow together. In Word, an empty paragraph separates documents, as if you pressed Return twice between them.",
        "Preserve individual document heading structure keeps each document’s heading levels. Turn it off to keep only the first document’s title at Heading 1 and move the remaining headings down one level. Heading 6 stays at Heading 6, so original Heading 5 and Heading 6 headings can end up at the same level. This option is available for Word, PDF, HTML, Markdown, EPUB, and eBraille.",
        "Choose the options for your format, then Export and share…. Preparation progress identifies the current document and how many documents have been prepared, including any needed iCloud downloads. The app then creates the output and opens the Share Sheet. Cancel stops the export. If a document or linked file cannot be read, the app reports an error.",
        "If the output arrives as a ZIP, extract it before opening the document and keep the extracted files together so linked images and attachments remain available. Format-specific topics explain Word styles, presentation structure, ebook output, and braille settings."
    ]

    static let smartPunctuation = [
        "Turn on Settings > Export > Use smart punctuation to convert straight quotes and apostrophes to curly marks and three periods to an ellipsis (…). It applies to individual and compilation exports in every format. Your saved documents and punctuation in the editor are unchanged.",
        "Code, link destinations, and image paths are left unchanged. Existing curly punctuation and ellipses are kept. Dashes and runs of four or more periods are not converted. For braille output, punctuation is converted before translation.",
        "Review the result before publication. The conversion uses surrounding text to interpret punctuation and can mistake unusual quotations, leading apostrophes, abbreviations, or measurement marks. It does not apply language-specific quotation styles or spacing, or correct existing curly punctuation.",
        "For Markdown export, enabling this option can also change the spelling and spacing of Markdown syntax. Leave it off when you need an unchanged copy of a single document’s Markdown."
    ]

}
