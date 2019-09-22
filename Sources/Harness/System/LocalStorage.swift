//
//  LocalStorage.swift
//  Spitfire
//
//  Created by Ryan Walklin on 25/2/18.
//  Copyright © 2016 Test Toast. All rights reserved.
//

import Foundation
import LoggerAPI

/// Functions to store support files on device
public class LocalStorage {

    public class var homeFolderURL: URL {
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public class var appSupportFolderURL: URL {
#if os(OSX)
            return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Utilities.executableName)
#elseif os(iOS)
            return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
#elseif os(Linux)
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config")
                .appendingPathComponent(Harness.Utilities.executableName)

#endif
    }

    public class var logURL: URL {
        let logFolderURL: URL
#if os(OSX)
            logFolderURL = FileManager.default.urls (for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs")
#elseif os(iOS)
            logFolderURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
#elseif os(Linux)
            logFolderURL = appSupportFolderURL
#endif
        return logFolderURL.appendingPathComponent(Harness.Utilities.executableName).appendingPathExtension("log")
    }

    public class var configURL: URL {
        return appSupportFolderURL.appendingPathComponent(Harness.Utilities.executableName + ".json")
    }

    public class func createContainingFolder(for url: URL) throws {
        let folderURL = url.deletingLastPathComponent()
        Log.debug("Creating folder \(folderURL.path) for \(url.lastPathComponent)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
    }
}
