
#if os(Linux)
import Glibc
#elseif os(OSX) || os(iOS)
import QuartzCore
#endif
import Foundation
import LoggerAPI

public struct PrecisionTimer {
    public let startTime: TimeInterval

    public init () {
        startTime = currentTime()
    }

    public var elapsed: TimeInterval {
        return currentTime() - startTime
    }

}

fileprivate func convertToSeconds (time: timespec) -> TimeInterval {
    return (TimeInterval(time.tv_sec) * 1e9 + Double(time.tv_nsec))/1e9
}

fileprivate func currentTime () -> TimeInterval {
    let currentTime: TimeInterval
#if os(OSX)
    currentTime = CACurrentMediaTime()
#elseif os(Linux)
    var timeSpec = timespec()
    if clock_gettime(CLOCK_MONOTONIC_RAW, &timeSpec) == 0 {
        currentTime = convertToSeconds(time: timeSpec)
    } else {
        Log.error("CLOCK_MONOTONIC_RAW access failed: \(errno)")
        currentTime = 0
    }
#endif
    return currentTime
}

@discardableResult public func measure<A>(name: String = "", _ block: () -> A) -> A {
    let startTime = PrecisionTimer()
    let result = block()
    print("\(name) - elapsed: " + String(format: "%.2f", startTime.elapsed) + "s")
    return result
}
