//
//  ConsoleManagement.swift
//  Spitfire
//
//  Created by Ryan Walklin on 25/2/18.
//

import Foundation
import HeliumLogger
import LoggerAPI

//typealias ConsoleOptions = (path: String, interactive: Bool, args: [String])

public enum LogDestination {
    case console
    case file
}

fileprivate struct LogOutputStream: TextOutputStream {

    let logURL: URL
    var destinations: [LogDestination]

    func write(_ text: String) {
        if destinations.contains(.console) {
            fputs(text, stderr)
        }
        if destinations.contains(.file) {
            do {
                try text.append(to: logURL)
            } catch let error {
                Log.warning("Logging to \(logURL) failed: \(error.localizedDescription)")
            }
        }
    }
}

public class ConsoleManager {

    public static func configureLogging (_ mode: LoggerMessageType = .verbose,
            detailed: Bool = false, destinations: [LogDestination] = [.console]) throws {

        if destinations.isEmpty {
            return
        }

        let logURL = LocalStorage.logURL
        let outputStream = LogOutputStream(logURL: logURL, destinations: destinations)
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
/*
    static func processCommandLine () throws -> ConsoleOptions {
        let parser = ArgumentParser(commandName: LocalStorage.executableName, usage: "[interactive]", overview: "Context-sensitive Automation for macOS")
        let interactive: OptionArgument<Bool> = parser.add(option: "--consoleInteractive", kind: Bool.self, usage: "Show console UI in foreground"/*, completion: .values(["--consoleInteractive"])*/)
        guard let path = CommandLine.arguments.first else {
            exit(0)
        }
        let args = Array(CommandLine.arguments.dropFirst())
        let result = try parser.parse(args)

        return (path, result.get(interactive) == true, args)
    }
*/

}

