import Foundation

public extension Data {
    func append (to url: URL) throws {
        do {
            let fileHandle = try FileHandle(forWritingTo: url)
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } catch {
            try write(to: url, options: .atomic)
        }
    }
}
