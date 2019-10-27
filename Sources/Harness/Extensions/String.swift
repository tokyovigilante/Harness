import Foundation

public extension String {

  /*
    Truncates the string to the specified length number of characters and appends an optional trailing string if longer.
    - Parameter length: Desired maximum lengths of a string
    - Parameter trailing: A 'String' that will be appended after the truncation.

    - Returns: 'String' object.
    */
    func truncate (_ length: Int, trailing: String = "…") -> String {
        return (self.count > length && self.count > 1) ? self.prefix(length-1) + trailing : self
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

     var firstParagraph: String {
        if self.isEmpty {
            return self
        }
        return self.components(separatedBy: CharacterSet.newlines).first ?? self
     }

     // From https://useyourloaf.com/blog/empty-strings-in-swift/
     var isBlank: Bool {
         return allSatisfy { $0.isWhitespace }
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
