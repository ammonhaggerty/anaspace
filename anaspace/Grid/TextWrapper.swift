import Foundation

enum TextWrapper {

    /// Wraps `text` (uppercased) into lines of at most `maxWidth` characters.
    /// Breaks at word boundaries. Hyphenates words that don't fit a line.
    /// Returns at most `maxLines` lines; truncates last line with U+22F0 if needed.
    static func wrap(_ text: String, maxWidth: Int, maxLines: Int = .max) -> [String] {
        guard maxWidth > 0 else { return [] }
        let text = text.uppercased()
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return [] }

        var lines: [String] = []
        var currentLine = ""

        for word in words {
            if currentLine.isEmpty {
                // Start a new line with this word
                if word.count <= maxWidth {
                    currentLine = word
                } else {
                    // Hyphenate oversized word
                    let fragments = hyphenate(word, maxWidth: maxWidth)
                    for (i, fragment) in fragments.enumerated() {
                        if i < fragments.count - 1 {
                            lines.append(fragment)
                        } else {
                            currentLine = fragment
                        }
                    }
                }
            } else if currentLine.count + 1 + word.count <= maxWidth {
                // Fits on current line with a space
                currentLine += " " + word
            } else {
                // Doesn't fit — flush current line and start new
                lines.append(currentLine)
                if word.count <= maxWidth {
                    currentLine = word
                } else {
                    currentLine = ""
                    let fragments = hyphenate(word, maxWidth: maxWidth)
                    for (i, fragment) in fragments.enumerated() {
                        if i < fragments.count - 1 {
                            lines.append(fragment)
                        } else {
                            currentLine = fragment
                        }
                    }
                }
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        // Apply maxLines truncation
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
            // Truncate last line with U+22F0
            var lastLine = lines[maxLines - 1]
            if lastLine.count >= maxWidth {
                lastLine = String(lastLine.prefix(maxWidth - 1)) + "\u{22F0}"
            } else {
                lastLine = lastLine + "\u{22F0}"
                if lastLine.count > maxWidth {
                    lastLine = String(lastLine.prefix(maxWidth - 1)) + "\u{22F0}"
                }
            }
            lines[maxLines - 1] = lastLine
        }

        return lines
    }

    /// Breaks a single word into fragments that fit within `maxWidth`,
    /// adding hyphens at break points.
    private static func hyphenate(_ word: String, maxWidth: Int) -> [String] {
        guard word.count > maxWidth, maxWidth > 1 else { return [word] }

        var fragments: [String] = []
        var remaining = word

        while remaining.count > maxWidth {
            // Take maxWidth - 1 chars + hyphen
            let breakAt = remaining.index(remaining.startIndex, offsetBy: maxWidth - 1)
            let fragment = String(remaining[..<breakAt]) + "-"
            fragments.append(fragment)
            remaining = String(remaining[breakAt...])
        }

        if !remaining.isEmpty {
            fragments.append(remaining)
        }

        return fragments
    }
}
