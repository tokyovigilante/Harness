import Foundation

// Baased on https://gist.github.com/antfarm/695fa78e0730b67eb094c77d53942216

fileprivate var table: [UInt32] = {
    (0...255).map { i -> UInt32 in
        (0..<8).reduce(UInt32(i), { c, _ in
            (c % 2 == 0) ? (c >> 1) : (0xEDB88320 ^ (c >> 1))
        })
    }
}()

public extension Array where Element == UInt8 {

    var crc32: UInt32 {
        return ~(self.reduce(~UInt32(0), { crc, byte in
            (crc >> 8) ^ table[(Int(crc) ^ Int(byte)) & 0xFF]
        }))
    }
}
