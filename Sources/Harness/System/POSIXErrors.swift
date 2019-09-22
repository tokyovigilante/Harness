#if os(OSX)
import Darwin
#elseif os(Linux)
import Glibc
#endif

public class PosixErrors {

    public static func errorString (_ errnum: Int32) -> String {
        var stringBuf = [Int8](repeating: 0, count: 1024)
        strerror_r(errnum, &stringBuf, stringBuf.count)
        if let errorString = String(validatingUTF8: stringBuf) {
            return errorString
        }
        return "Unknown error"
    }

}

