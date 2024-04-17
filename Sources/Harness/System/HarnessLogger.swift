/**
 * Modified from log.c - https://github.com/rxi/log.c
 *
 * Copyright (c) 2020 rxi
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 * of the Software, and to permit persons to whom the Software is furnished to do
 * so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
import Foundation

enum ANSIColor: String {
    case black = "30"
    case red = "31"
    case green = "32"
    case yellow = "33"
    case blue = "34"
    case agenta = "35"
    case cyan = "36"
    case white = "37"
    case brightBlack = "90"
    case brightRed = "91"
    case brightGreen = "92"
    case brightYellow = "93"
    case brightBlue = "94"
    case brightMagenta = "95"
    case brightCyan = "96"
    case brightWhite = "97"
    case `default` = "0"

    var controlCode: String {
        return "\u{1B}[0;\(self.rawValue)m"
    }

    var boldControlCode: String {
        return "\u{1B}[\(self.rawValue);1m"
    }
}

public class HarnessLogger {

    public static let shared = HarnessLogger(stderr: true)

    public enum Level: Comparable, Codable {
        case trace
        case debug
        case info
        case warn
        case error
        case critical

        var colourCode: ANSIColor {
            switch self {
            case .trace:
                return .blue
            case .debug:
                return .cyan
            case .info:
                return .green
            case .warn:
                return .yellow
            case .error:
                return .brightRed
            case .critical:
                return .brightMagenta
            }
        }
    }

    private let _stream: StdioOutputStream

    private var _dateFormatter = DateFormatter()

    public var level: HarnessLogger.Level = .info

    public var colour: Bool = true

    private init (stderr: Bool) {
        _stream = stderr ? StdioOutputStream.stderr : StdioOutputStream.stdout
        _dateFormatter.dateFormat = "MMM dd HH:mm:ss.SSS"
    }

    @inlinable
    public func trace (_ message: String, file: String = #fileID,
            function: String = #function, line: UInt = #line) {
        log(level: .trace, message: message, file: file, function: function, line: line)
    }

    @inlinable
    public func debug (_ message: String, file: String = #fileID,
            function: String = #function, line: UInt = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }

    @inlinable
    public func info (_ message: String, file: String = #fileID,
            function: String = #function, line: UInt = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }

    @inlinable
    public func warn (_ message: String, file: String = #fileID,
            function: String = #function, line: UInt = #line) {
        log(level: .warn, message: message, file: file, function: function, line: line)
    }

    @inlinable
    public func error (_ message: String, file: String = #fileID,
            function: String = #function, line: UInt = #line) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }

    @inlinable
    public func critical (_ message: String, file: String = #fileID,
            function: String = #function, line: UInt = #line) {
        log(level: .critical, message: message, file: file, function: function, line: line)
    }

    private func timestamp() -> String {

        let date = Date(timeIntervalSince1970: PrecisionTimer.wallTime())
        return _dateFormatter.string(from: date)
    }

    public func log (level: HarnessLogger.Level, message: String, file: String = #fileID,
            function: String = #function, line: UInt = #line) {

        if level < self.level { return }
        let formattedLog = format(level: level, message: message, file: file, function: function, line: line)

        _stream.write(formattedLog)
    }

    fileprivate let _fragmentResetCount = 40

    fileprivate var _longestFileLineFragment = 0
    fileprivate var _logsBeforeFragmentReset = 0

    private func format (level: HarnessLogger.Level, message: String, file: String,
            function: String, line: UInt) -> String {
        var log = timestamp() + " "
        if self.colour {
            log += level >= .warn ? level.colourCode.boldControlCode : level.colourCode.controlCode
        }

        log += "\(level)".uppercased().padding(toLength: 5, withPad: " ", startingAt: 0)
        if self.colour && level < .warn {
            log += ANSIColor.default.controlCode
        }

        var fileLineFragment = " (\(file):\(line)) "
        let fileLineFragmentCount = fileLineFragment.count

        if fileLineFragmentCount > _longestFileLineFragment {
            _longestFileLineFragment = fileLineFragment.count
        } else {
            fileLineFragment = fileLineFragment.padding(toLength: _longestFileLineFragment, withPad: " ", startingAt: 0)
        }
        log += fileLineFragment
        _logsBeforeFragmentReset += 1
        if _logsBeforeFragmentReset >= _fragmentResetCount {
            _logsBeforeFragmentReset = 0
            _longestFileLineFragment = 0
        }

        if colour {
            if level < .warn && level > .trace {
                log += ANSIColor.default.boldControlCode
            } else if level == .trace {
                log += ANSIColor.default.controlCode
            }
        }
        log += "\(message)"

        if colour {
            log += "\(ANSIColor.default.controlCode)"
        }
        log += "\n"
        return log
    }

}

/*

#if os(Linux)
    public static func redirectGLibLogging (for domains: [String]) {
        let flags = GLogLevelFlags(rawValue:
                G_LOG_LEVEL_MASK.rawValue |
                G_LOG_FLAG_FATAL.rawValue |
                G_LOG_FLAG_RECURSION.rawValue
        )
        for domain in domains {
            _ = g_log_set_handler(domain, flags, glibLogHandler, nil)
        }
    }
#endif
}

#if os(Linux)

private extension HarnessLogger.Level {

    init? (gLevel level: GLogLevelFlags) {
        switch level {
        case G_LOG_LEVEL_DEBUG:
            self = .debug
        case G_LOG_LEVEL_INFO:
            self = .verbose
        case G_LOG_LEVEL_INFO:
            self = .info
        case G_LOG_LEVEL_WARNING:
            self = .warning
        case G_LOG_LEVEL_CRITICAL, G_LOG_LEVEL_ERROR, G_LOG_FLAG_RECURSION, G_LOG_FLAG_FATAL:
            self = .error
        default:
            return nil
        }
    }

}

fileprivate var glibLogHandler: @convention(c) (UnsafePointer<Int8>?,
        GLogLevelFlags, UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void = { (log_domain, log_level, message, user_data) in

    var level = LoggerMessageType(gLevel: log_level)
    if level == nil {
        Log.warning("Unknown GLib log level \(log_level)")
    }
    guard let message = message, var messageString = String(cString: message, encoding: .utf8) else {
        Log.debug("Invalid Glib log message")
        return
    }
    Log.logger?.log(level ?? .warning, msg: messageString, functionName: #function, lineNum: #line, fileName: #file)
}
#endif
*/
