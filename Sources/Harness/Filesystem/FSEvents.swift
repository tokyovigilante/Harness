//
//  FSEvents.swift
//  Merlin
//
//  Created by Ryan Walklin on 2018-11-18.
//  Copyright © 2018 Test Toast. All rights reserved.
//

import Foundation

public struct FSEvent {
    public let uuid: UUID
    public let descriptor: Int
    public let path: URL
    public let newPath: URL?
    public let type: FSEventType
}

public enum FSEventType: String, CaseIterable {
    /* Supported events suitable for MASK parameter of INOTIFY_ADD_WATCH.  */
    case access // IN_ACCESS    0x00000001 /* File was accessed.  */
    case modify // IN_MODIFY    0x00000002 /* File was modified.  */
    case attrib // IN_ATTRIB    0x00000004 /* Metadata changed.  */
    case writableClose // IN_CLOSE_WRITE   0x00000008 /* Writtable file was closed.  */
    case unwritableClose // IN_CLOSE_NOWRITE 0x00000010 /* Unwrittable file closed.  */
    case close // IN_CLOSE     (IN_CLOSE_WRITE | IN_CLOSE_NOWRITE) /* Close.  */
    case open // IN_OPEN      0x00000020 /* File was opened.  */
    case moveFrom // IN_MOVED_FROM    0x00000040 /* File was moved from X.  */
    case moveTo // IN_MOVED_TO      0x00000080 /* File was moved to Y.  */
    case move // IN_MOVE      (IN_MOVED_FROM | IN_MOVED_TO) /* Moves.  */
    case create// IN_CREATE    0x00000100 /* Subfile was created.  */
    case delete // IN_DELETE    0x00000200 /* Subfile was deleted.  */
    case deleteSelf // IN_DELETE_SELF   0x00000400 /* Self was deleted.  */
    case moveSelf // IN_MOVE_SELF     0x00000800 /* Self was moved.  */

    /* Events sent by the kernel.  */
    case unmount // IN_UNMOUNT   0x00002000 /* Backing fs was unmounted.  */
    case overflow // IN_Q_OVERFLOW    0x00004000 /* Event queued overflowed.  */
    case ignored // IN_IGNORED   0x00008000 /* File was ignored.  */
}

public enum FSEventsError: Error {
    case startupFailure(_ posixMessage: String)
    case watchFailure(_ posixMessage: String)
    case usage(_ message: String)
}

public enum FSEventsState {
    case stopped
    case running
    case error(message: String)
}

extension FSEventsState: Equatable {}

extension FSEventsState: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch(self) {
        case .stopped: return "stopped"
        case .running: return "running"
        case let .error(message): return "FSEvents error: \(message)"
        }
    }
}

public protocol FSEventsProtocol: AnyObject {

    var watchList: [UUID: (FSEventsProtocol, FSEvent) -> ()] { get }

    func startWatching () throws

    @discardableResult func watch<T: AnyObject> (
        item: URL,
        types: [FSEventType],
        watcher: T,
        closure: @escaping (T, FSEventsProtocol, FSEvent) -> Void
    ) throws -> ObservationToken

    func stopWatching () throws
    //func removeWatches (folder: URL)
    //func removeAll ()
}
