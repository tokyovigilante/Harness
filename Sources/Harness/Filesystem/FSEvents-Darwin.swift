//
//  FSEvents-Darwin.swift
//  Merlin
//
//  Created by Ryan Walklin on 2018-11-18.
//  Copyright © 2018 Test Toast. All rights reserved.
//

#if os(iOS) || os(OSX)

import Foundation
import Dispatch

class FSEvents: FSEventsProtocol {

    public static let shared = FSEvents()

    private (set) var watchList = [FSEventWatcher]()

    private init () {}

    func watch(folder: String, types: FSEventType, onEvent: (FSEventWatcher) -> Void) {

    }

    func watchRecursive(folder: String, types: FSEventType, onEvent: (FSEventWatcher) -> Void) {

    }

    func removeWatches(folder: URL) {

    }

    func removeAll () {

    }

}
#endif
