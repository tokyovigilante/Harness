
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif os(Windows)
import CRT
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("Unsupported runtime")
#endif

#if canImport(WASILibc) || os(Android)
internal typealias CFilePointer = OpaquePointer
#else
internal typealias CFilePointer = UnsafeMutablePointer<FILE>
#endif

// Prevent name clashes
#if os(macOS) || os(tvOS) || os(iOS) || os(watchOS)
let systemStderr = Darwin.stderr
let systemStdout = Darwin.stdout
#elseif os(Windows)
let systemStderr = CRT.stderr
let systemStdout = CRT.stdout
#elseif canImport(Glibc)
let systemStderr = Glibc.stderr!
let systemStdout = Glibc.stdout!
#elseif canImport(WASILibc)
let systemStderr = WASILibc.stderr!
let systemStdout = WASILibc.stdout!
#else
#error("Unsupported runtime")
#endif

/// A wrapper to facilitate `print`-ing to stderr and stdio that
/// ensures access to the underlying `FILE` is locked to prevent
/// cross-thread interleaving of output.
internal struct StdioOutputStream: TextOutputStream {
    internal let file: CFilePointer
    internal let flushMode: FlushMode

    internal func write(_ string: String) {
        self.contiguousUTF8(string).withContiguousStorageIfAvailable { utf8Bytes in
            #if os(Windows)
            _lock_file(self.file)
            #elseif canImport(WASILibc)
            // no file locking on WASI
            #else
            flockfile(self.file)
            #endif
            defer {
                #if os(Windows)
                _unlock_file(self.file)
                #elseif canImport(WASILibc)
                // no file locking on WASI
                #else
                funlockfile(self.file)
                #endif
            }
            _ = fwrite(utf8Bytes.baseAddress!, 1, utf8Bytes.count, self.file)
            if case .always = self.flushMode {
                self.flush()
            }
        }!
    }

    /// Flush the underlying stream.
    /// This has no effect when using the `.always` flush mode, which is the default
    internal func flush() {
        _ = fflush(self.file)
    }

    internal func contiguousUTF8(_ string: String) -> String.UTF8View {
        var contiguousString = string
        #if compiler(>=5.1)
        contiguousString.makeContiguousUTF8()
        #else
        contiguousString = string + ""
        #endif
        return contiguousString.utf8
    }

    internal static let stderr = StdioOutputStream(file: systemStderr, flushMode: .always)
    internal static let stdout = StdioOutputStream(file: systemStdout, flushMode: .always)

    /// Defines the flushing strategy for the underlying stream.
    internal enum FlushMode {
        case undefined
        case always
    }
}
