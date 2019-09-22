//
//  Utilities.swift
//  Airframe
//
//  Created by Ryan Walklin on 24/12/18.
//

import Foundation

public class Utilities {

    public class var executableName: String {
        let processName = ProcessInfo.processInfo.processName
        if let splitName = processName.lowercased().split(separator: "-").first {
            return String(splitName)
        }
        return processName
    }

}

// From https://github.com/apple/swift/blob/master/stdlib/private/SwiftPrivate/SwiftPrivate.swift,
// Also see https://oleb.net/blog/2016/10/swift-array-of-c-strings/

/// Compute the prefix sum of `seq`.
public func scan<S : Sequence, U>(_ seq: S, _ initial: U, _ combine: (U, S.Iterator.Element) -> U) -> [U] {
    var result: [U] = []
    result.reserveCapacity(seq.underestimatedCount)
    var runningResult = initial
    for element in seq {
        runningResult = combine(runningResult, element)
        result.append(runningResult)
    }
    return result
}

public func withArrayOfCStrings<R>(_ args: [String],
                                   _ body: ([UnsafePointer<CChar>?]) -> R) -> R {
    let argsCounts = Array(args.map { $0.utf8.count + 1 })
    let argsOffsets = [ 0 ] + scan(argsCounts, 0, +)
    let argsBufferSize = argsOffsets.last!

    var argsBuffer: [UInt8] = []
    argsBuffer.reserveCapacity(argsBufferSize)
    for arg in args {
        argsBuffer.append(contentsOf: arg.utf8)
        argsBuffer.append(0)
    }
    return argsBuffer.withUnsafeBufferPointer { (argsBuffer) in
        let ptr = UnsafeRawPointer(argsBuffer.baseAddress!)
            .bindMemory(to: CChar.self, capacity: argsBuffer.count)
        var cStrings: [UnsafePointer<CChar>?] = argsOffsets.map { ptr + $0 }
        cStrings[cStrings.count - 1] = nil
        return body(cStrings)
    }
}
