#if os(Linux)
import Glibc
#elseif os(OSX) || os(iOS)
import QuartzCore
#endif
import Foundation

public struct PrecisionTimer {
    private(set) public var startTime: TimeInterval

    public init () {
        startTime = PrecisionTimer.currentTime()
    }

    public var elapsed: TimeInterval {
        return PrecisionTimer.currentTime() - startTime
    }

    mutating public func reset () -> TimeInterval {
        let start = startTime
        startTime = PrecisionTimer.currentTime()
        return startTime - start
    }

    public static func currentTime () -> TimeInterval {
        let currentTime: TimeInterval
    #if os(OSX)
        currentTime = CACurrentMediaTime()
    #elseif os(Linux)
        var timeSpec = timespec()
        if clock_gettime(CLOCK_MONOTONIC_RAW, &timeSpec) == 0 {
            currentTime = convertToSeconds(time: timeSpec)
        } else {
            HarnessLogger.shared.critical("CLOCK_MONOTONIC_RAW access failed: \(errno)")
            currentTime = 0
        }
    #endif
        return currentTime
    }

    public static func wallTime () -> TimeInterval {
        let currentTime: TimeInterval
    #if os(OSX)
        currentTime = CACurrentMediaTime()
    #elseif os(Linux)
        var timeSpec = timespec()
        if clock_gettime(CLOCK_REALTIME, &timeSpec) == 0 {
            currentTime = convertToSeconds(time: timeSpec)
        } else {
            HarnessLogger.shared.critical("CLOCK_REALTIME access failed: \(errno)")
            currentTime = 0
        }
    #endif
        return currentTime
    }

    public static func precision () -> TimeInterval {
        #if os(OSX)
            return 0.0005
        #elseif os(Linux)
            var precision = timespec()
            if clock_getres(CLOCK_MONOTONIC_RAW, &precision) == 0 {
                return convertToSeconds(time: precision)
            } else {
                HarnessLogger.shared.critical("CLOCK_MONOTONIC_RAW access failed: \(errno)")
                return 0.0
            }
        #endif
    }

}

fileprivate func convertToSeconds (time: timespec) -> TimeInterval {
    return (TimeInterval(time.tv_sec) * 1e9 + Double(time.tv_nsec))/1e9
}

@discardableResult public func measure<A>(name: String = "", _ block: () -> A) -> A {
    let startTime = PrecisionTimer()
    let result = block()
    print("\(name) - elapsed: " + String(format: "%.2f", startTime.elapsed) + "s")
    return result
}
