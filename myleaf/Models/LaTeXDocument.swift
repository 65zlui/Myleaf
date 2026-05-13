import Foundation

struct LaTeXDocument {
    var sourceText: String
    var fileURL: URL?

    init(sourceText: String = LaTeXDocument.defaultTemplate, fileURL: URL? = nil) {
        self.sourceText = sourceText
        self.fileURL = fileURL
    }

    static let defaultTemplate = """
    \\documentclass{article}
    \\usepackage[utf8]{inputenc}

    \\title{Untitled Document}
    \\author{}
    \\date{\\today}

    \\begin{document}

    \\maketitle

    \\section{Introduction}
    Hello, LaTeX!

    \\end{document}
    """
}
