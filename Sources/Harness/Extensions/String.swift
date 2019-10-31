import Foundation

public extension String {

    var paragraphs: [String] {
        var result: [String] = []
        self.enumerateLines { line, stop in
            result.append(line)
        }
        return result
    }

    var firstParagraph: String {
        return self.paragraphs.first ?? self
    }

    // From https://useyourloaf.com/blog/empty-strings-in-swift/
    var isBlank: Bool {
         return allSatisfy { $0.isWhitespace }
    }

    /*
    Truncates the string to the specified length number of characters and appends an optional trailing string if longer.
    - Parameter length: Desired maximum lengths of a string
    - Parameter trailing: A 'String' that will be appended after the truncation.
    - Parameter trimWhitespace: 'Bool' whether to strip trailing whitespace before appending truncation character

    - Returns: 'String' object.
    */
    func truncate (_ length: Int, trailing: String = "…", trimmingWhitespace trim: Bool = true) -> String {
        if self.count > length {
            let truncatedSelf = self.prefix(length-1)
            return trim
                    ? truncatedSelf.trimmingCharacters(in: .whitespacesAndNewlines) + trailing
                    : truncatedSelf + trailing
        }
        return self
        //return (self.count > length && self.count > 1) ? self.prefix(length-1) + trailing : self
    }

    func stripEmoji() -> String {
        return String(self.filter { !$0.isEmoji })
    }

    func appendLine(to url: URL) throws {
        try (self + "\n").append(to: url)
    }

    func append(to url: URL) throws {
        let data = self.data(using: .utf8)!
        try data.append(to: url)
    }

    /*
    Applies the Knuth-Plass line-breaking algorithm using the shortest-path method
    (https://xxyxyz.org/line-breaking/) to a paragraph of text with the specified width
    and returns an array of lines. Behaviour is undefined if line breaks are present,
    so the use of the output of String.paragraphs is suggested.
    - Parameter width: Desired maximum line length.

    - Returns: '[String]' array.
    */
    func lines (width: Int) -> [String] {
        let paragraphs = self.paragraphs
        var lines: [String] = []
        for paragraph in paragraphs {
            lines.append(contentsOf: paragraph.shortestPathLineBreak(width: width))
        }
        return lines
    }

    func words (clampTo width: Int? = nil) -> [String] {
        var words = self.components(separatedBy: .whitespaces)
        guard let width = width else {
            return words
        }
        var i = 0
        while i < words.count {
            let word = words[i]
            let wordLength = word.count
            if wordLength > width {
                let splitWord = stride(from: 0, to: wordLength, by: width).map { (position: Int) -> String in
                    let start = word.index(word.startIndex, offsetBy: position)
                    let end = word.index(word.startIndex, offsetBy: min(position + width, count))
                    return String(word[start..<end])
                }
                words.replaceSubrange(i...i, with: splitWord)
                i += splitWord.count
                continue
            }
            i += 1
        }
        return words
    }

    private func shortestPathLineBreak (width: Int) -> [String] {
        let words = self.words(clampTo: width)
        let count = words.count
        var offsets: [Int] = [0]

        for word in words {
            offsets.append(offsets.last! + word.count)
        }

        var minima: [Int] = [Int](repeating: Int.max, count: count + 1)
        minima[0] = 0
        var breaks: [Int] = [Int](repeating: 0, count: count + 1)

        var w, j, cost: Int
        for i in 0..<count {
            j = i + 1
            while j <= count {
                w = offsets[j] - offsets[i] + j - i - 1
                if w > width {
                    break
                }
                cost = minima[i] + (width - w) * (width - w)
                if cost < minima[j] {
                    minima[j] = cost
                    breaks[j] = i
                }
                j += 1
            }
        }
        var i: Int
        var lines: [String] = []
        j = count
        while j > 0 {
            i = breaks[j]
            lines.append(words[i..<j].joined(separator: " "))
            j = i
        }
        lines.reverse()
        return lines
    }
}

// Also from https://useyourloaf.com/blog/empty-strings-in-swift/
extension Optional where Wrapped == String {
    var isBlank: Bool {
        return self?.isBlank ?? true
    }
}

extension Character {

    fileprivate var isEmoji: Bool {
        return
            Character(UnicodeScalar(UInt32(0x1d000))!) <= self && self <= Character(UnicodeScalar(UInt32(0x1f77f))!) ||
            Character(UnicodeScalar(UInt32(0x2100))!) <= self && self <= Character(UnicodeScalar(UInt32(0x26ff))!)
    }
}
