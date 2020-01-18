//
//  ConsoleManagement.swift
//  Spitfire
//
//  Created by Ryan Walklin on 25/2/18.
//

import Foundation
import HeliumLogger
import LoggerAPI
#if os(Linux)
import CGLib
#endif

//typealias ConsoleOptions = (path: String, interactive: Bool, args: [String])

public enum LogDestination {
    case console
    case file
}

fileprivate struct LogOutputStream: TextOutputStream {

    let logURL: URL
    var destinations: [LogDestination]
    var async: Bool

    func write(_ text: String) {
        if async {
            asyncWrite(text)
        } else {
            syncWrite(text)
        }
    }

    private func syncWrite (_ text: String) {
        if self.destinations.contains(.console) {
            fputs(text, stderr)
        }
        if self.destinations.contains(.file) {
            do {
                try text.append(to: self.logURL)
            } catch let error {
                Log.warning("Logging to \(self.logURL) failed: \(error.localizedDescription)")
            }
        }
    }

    private func asyncWrite (_ text: String) {
        DispatchQueue.main.async {
            syncWrite(text)
        }
    }

}

public class ConsoleManager {

    public static func configureLogging (_ mode: LoggerMessageType = .verbose,
            detailed: Bool = false, destinations: [LogDestination] = [.console], async: Bool = true) throws {

        if destinations.isEmpty {
            return
        }

        let logURL = LocalStorage.logURL
        let outputStream = LogOutputStream(logURL: logURL, destinations: destinations, async: async)
        let logger = HeliumStreamLogger(mode, outputStream: outputStream)

        if destinations.contains(.file) {

            Log.debug("Logging to \(logURL)")
            do {
                try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try "".write(to: logURL, atomically: false, encoding: .utf8)
            } catch let error {
                Log.warning("Log rotation failed: \(error.localizedDescription)")
            }
        }

        logger.colored = true
        if detailed {
            logger.format = "[(%date)] [(%type)] [(%file):(%line) (%func)] (%msg)"
            logger.dateFormat = "dd/MMM/yyyy:HH:mm:ss Z"
        } else {
            logger.format = "[(%type)] (%msg)"
        }

        Log.logger = logger
    }

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

/*
    static func processCommandLine () throws -> ConsoleOptions {
        let parser = ArgumentParser(commandName: LocalStorage.executableName, usage: "[interactive]", overview: "Context-sensitive Automation for macOS")
        let interactive: OptionArgument<Bool> = parser.add(option: "--consoleInteractive", kind: Bool.self, usage: "Show console UI in foreground", completion: .values(["--consoleInteractive"]))
        guard let path = CommandLine.arguments.first else {
            exit(0)
        }
        let args = Array(CommandLine.arguments.dropFirst())
        let result = try parser.parse(args)

        return (path, result.get(interactive) == true, args)
    }
*/

#if os(Linux)

private extension LoggerMessageType {

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
