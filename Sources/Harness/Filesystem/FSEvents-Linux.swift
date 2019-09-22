//
//  FSEvents-Linux.swift
//  Merlin
//
//  Created by Ryan Walklin on 2018-11-18.
//  Copyright © 2018 Test Toast. All rights reserved.
//

#if os(Linux)

import CInotify
import Dispatch
import Foundation
import Glibc
import LoggerAPI

private let allEvents = UInt32(IN_ACCESS | IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE |              IN_CLOSE_NOWRITE | IN_OPEN | IN_MOVED_FROM | IN_MOVED_TO | IN_DELETE | IN_CREATE | IN_DELETE_SELF)

public class FSEvents: FSEventsProtocol {

    public static let shared = FSEvents()

    private var inotifyFD: Int32 = -1
    private var eventReadQueue: DispatchQueue

    private (set) public var watchList: [UUID: (FSEventsProtocol, FSEvent) -> ()] = [:]
    private var uuidMap: [Int32: (UUID, URL)] = [:]

    private (set) public var state: FSEventsState = .stopped {
        didSet {
            if case let .error(message) = state {
                Log.error("\(message)")
            }
        }
    }

    private var cancel = false

    private init () {
        eventReadQueue = DispatchQueue(label: "com.testtoast.spitfire.inotifyeventqueue")
    }

    public func startWatching () throws {
        if state == .running {
            throw FSEventsError.startupFailure("called startWatching with active FSEvents watcher: \(inotifyFD)")
        }
        assert(inotifyFD == -1, "invalid non-null inotify fd for state \(state.debugDescription)")
        inotifyFD = inotify_init1(Int32(/*IN_NONBLOCK*/))
        if inotifyFD == -1 {
            let errorMessage = PosixErrors.errorString(errno)
            state = .error(message: errorMessage)
            throw FSEventsError.startupFailure(errorMessage)
        }
        cancel = false
        eventReadQueue.async {
            self.readEvents()
        }
        state = .running
        Log.verbose("Started FSEvents monitoring with inotify")
    }

    private func readEvents () {
        if cancel {
            Log.debug("Stopped watching fs events")
            close(inotifyFD)
            inotifyFD = -1
            cancel = false
            return
        }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 4096, alignment: MemoryLayout<UInt8>.alignment)
        defer {
            buffer.deallocate()
        }
        let readBytes = read(inotifyFD, buffer, 4096)
        if readBytes == -1 && errno != EAGAIN {
            Log.error("inotify socket read failed: \(PosixErrors.errorString(errno))")
            return
        }
        var eventPointer: UnsafeMutablePointer<inotify_event>? = nil
        var offset = 0
        if readBytes > 0 {
            while offset < readBytes {
                eventPointer = buffer.advanced(by: offset).bindMemory(to: inotify_event.self, capacity: 1)
                guard let event = eventPointer?.pointee else {
                    Log.error("inotify socket read failed: invalid inotify_event data recieved, length \(readBytes))")
                    return
                }
                process(event: event)
                offset += MemoryLayout<inotify_event>.size + Int(event.len)
            }

        }

        eventReadQueue.asyncAfter(deadline: .now() + 0.2) {
            self.readEvents()
        }
    }
/*
    struct inotify_event {
                   int      wd;       /* Watch descriptor */
                   uint32_t mask;     /* Mask describing event */
                   uint32_t cookie;   /* Unique cookie associating related
                                         events (for rename(2)) */
                   uint32_t len;      /* Size of name field */
                   char     name[];   /* Optional null-terminated name */
               };
*/
    let allInotifyTypes = FSEventType.allCases.map { $0.inotifyEnum }

    private func process (event: inotify_event) {
        guard let id = uuidMap[event.wd] else {
            Log.error("Unknown \(event.wd)")
            return
        }
        guard let closure = watchList[id.0] else {
            return
        }
        let mask = event.mask
        for type in allInotifyTypes {
            if mask & type == mask, let fsEventType = FSEventType(inotifyEnum: type) {
                /*Log.debug("Got inotify event \(event.wd): type: \(fsEventType), cookie: \(event.cookie), len: \(event.len)")*/
                let fsEvent = FSEvent(
                                uuid: id.0,
                                descriptor: Int(event.wd),
                                path: id.1,
                                newPath: nil,
                                type: fsEventType
                                )
                closure(self, fsEvent)
            }
        }
    }

    @discardableResult public func watch<T: AnyObject> (
        item: URL,
        types: [FSEventType],
        watcher: T,
        closure: @escaping (T, FSEventsProtocol, FSEvent) -> Void
    ) throws -> ObservationToken {
        if case let .error(message) = state {
            throw FSEventsError.watchFailure(message)
        }
        let inotifyMask: UInt32 = types.reduce (0) { $0 | $1.inotifyEnum }
        let wd = inotify_add_watch(inotifyFD, item.path.utf8String, inotifyMask)
        let id = UUID()
        uuidMap[wd] = (id, item)
        watchList[id] = { [weak self, weak watcher] fsevents, event in
            // If the observer has been deallocated, we can
            // automatically remove the observation closure.
            guard let watcher = watcher else {
                self?.watchList.removeValue(forKey: id)
                self?.uuidMap.removeValue(forKey: wd)
                return
            }
            closure(watcher, fsevents, event)
        }
        let token =  ObservationToken { [weak self] in
            self?.watchList.removeValue(forKey: id)
            self?.uuidMap.removeValue(forKey: wd)
        }
        Log.debug("Watching \(item) \(types):\(inotifyMask) (\(wd):\(id))")
        return token
    }

    public func removeWatches (folder: URL) {

    }

    public func removeAll () {

    }

    public func stopWatching () throws {
        if state != .running {
            throw FSEventsError.usage("stopWatching called without running FSEvents watcher")
        }
        let cancelTime = PrecisionTimer()
        cancel = true
        while state == .running {
            if cancelTime.elapsed > 0.2 {
                Log.error("Failed to stop FSEvents watcher in reasonable time")
                break
            }
        }
        Log.debug("FSEvents stopped watching in \(cancelTime.elapsed)s")
    }

    deinit {
        if state == .running {
            do {
                try stopWatching()
            } catch let error {
                Log.error(error.localizedDescription)
            }
        }
    }
}


private extension FSEventType {

    var inotifyEnum: UInt32 {
        switch self {
        case .access:
            return UInt32(IN_ACCESS)
        case .modify:
            return UInt32(IN_MODIFY)
        case .attrib:
            return UInt32(IN_ATTRIB)
        case .writableClose:
            return UInt32(IN_CLOSE_WRITE)
        case .unwritableClose:
            return UInt32(IN_CLOSE_NOWRITE)
        case .close:
            return UInt32(IN_CLOSE)
        case .open:
            return UInt32(IN_OPEN)
        case .moveFrom:
            return UInt32(IN_MOVED_FROM)
        case .moveTo:
            return UInt32(IN_MOVED_TO)
        case .move:
            return UInt32(IN_MOVE)
        case .create:
            return UInt32(IN_CREATE)
        case .delete:
            return UInt32(IN_DELETE)
        case .deleteSelf:
            return UInt32(IN_DELETE_SELF)
        case .moveSelf:
            return UInt32(IN_MOVE_SELF)
        case .unmount:
            return UInt32(IN_UNMOUNT)
        case .overflow:
            return UInt32(IN_Q_OVERFLOW)
        case .ignored:
            return UInt32(IN_IGNORED)
        }
    }

    init? (inotifyEnum: UInt32) {
        switch inotifyEnum {
        case UInt32(IN_ACCESS):
            self = .access
        case UInt32(IN_MODIFY):
            self = .modify
        case UInt32(IN_ATTRIB):
            self = .attrib
        case UInt32(IN_CLOSE_WRITE):
            self = .writableClose
        case UInt32(IN_CLOSE_NOWRITE):
            self = .unwritableClose
        case UInt32(IN_CLOSE):
            self = .close
        case UInt32(IN_OPEN):
            self = .open
        case UInt32(IN_MOVED_FROM):
            self = .moveFrom
        case UInt32(IN_MOVED_TO):
            self = .moveTo
        case UInt32(IN_MOVE):
            self = .move
        case UInt32(IN_CREATE):
            self = .create
        case UInt32(IN_DELETE):
            self = .delete
        case UInt32(IN_DELETE_SELF):
            self = .deleteSelf
        case UInt32(IN_MOVE_SELF):
            self = .moveSelf
        case UInt32(IN_UNMOUNT):
            self = .unmount
        case UInt32(IN_Q_OVERFLOW):
            self = .overflow
        case UInt32(IN_IGNORED):
            self = .ignored
        default:
            return nil
        }
    }
}

#endif
