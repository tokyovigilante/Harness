import Foundation

public extension String {

  /*
    Truncates the string to the specified length number of characters and appends an optional trailing string if longer.
    - Parameter length: Desired maximum lengths of a string
    - Parameter trailing: A 'String' that will be appended after the truncation.

    - Returns: 'String' object.
    */
    func truncate (_ length: Int, trailing: String = "…") -> String {
        return (self.count > length) ? self.prefix(length-1) + trailing : self
    }

    func appendLine(to url: URL) throws {
         try (self + "\n").append(to: url)
     }

     func append(to url: URL) throws {
         let data = self.data(using: .utf8)!
         try data.append(to: url)
     }

}
