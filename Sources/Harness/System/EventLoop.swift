/** Linux GMainLoop integration based on
  *	https://gitlab.gnome.org/GNOME/gtk/blob/master/gdk/quartz/gdkeventloop-quartz.c
  *
  * This file implementations integration between the GLib main loop and
  * the native system of the Core Foundation run loop and Cocoa event
  * handling.
  * We integrate in GLib main loop handling by adding a "run loop observer"
  * that gives us notification at various points in the run loop cycle. We map
  * these points onto the corresponding stages of the GLib main loop
  * (prepare, check, dispatch), and make the appropriate calls into GLib.
  *
  * the OS X APIs don’t allow us to wait simultaneously for file descriptors
  * and for events. So when we need to do a blocking wait that includes file
  * descriptor activity, we push the actual work of calling select() to a
  * helper thread (the "select thread") and wait for native events in
  * the main thread.
  *
  * The main known limitation of this code is that if a callback is triggered
  * via the OS X run loop while we are "polling" (in either case described
  * above), iteration of the GLib main loop is not possible from within
  * that callback. If the programmer tries to do so explicitly, then they
  * will get a warning from GLib "main loop already active in another thread".
  */

#if os(Linux)
import CGLib
import Glibc
#endif
import CoreFoundation
import Foundation
import LoggerAPI

public func eventLoopRun () {
	EventLoop.shared.run()
}

fileprivate class EventLoop {

	fileprivate static var shared = EventLoop()

#if os(Linux)
	/******* State for run loop iteration *******/

	/* Count of number of times we've gotten an "Entry" notification for
	 * our run loop observer.
	 */
	private var _currentLoopLevel = 0

	/* Run loop level at which we acquired ownership of the GLib main
	 * loop. See note in run_loop_entry(). -1 means that we don’t have
	 * ownership
	 */
	private var _acquiredLoopLevel = -1

	/* Between run_loop_before_waiting() and run_loop_after_waiting();
	 * whether we we need to call select_thread_collect_poll()
	 */
	private var _runLoopPollingAsync = false

	/* Between run_loop_before_waiting() and run_loop_after_waiting();
	 * max_prioritiy to pass to g_main_loop_check()
	 */
	private var _runLoopMaxPriority: Int32 = 0

	/* Timer that we've added to wake up the run loop when a GLib timeout
	 */
	private var _runLoopTimer: CFRunLoopTimer! = nil

	/* These are the file descriptors that are we are polling out of
	 * the run loop. (We keep the array around and reuse it to avoid
	 * constant allocations.)
	 */
    var _pollFDCapacity: UInt32 = 16
    var _pollFDs = UnsafeMutablePointer<GPollFD>.allocate(capacity: 16)
    var _pollFDCount: UInt32 = 0

    /* The default poll function for GLib; we replace this with our own
     * Cocoa-aware version and then call the old version to do actual
     * file descriptor polling. There’s no actual need to chain to the
     * old one; we could reimplement the same functionality from scratch,
     * but since the default implementation does the right thing, why
     * bother.
     */
    private let _oldPollFunc: GPollFunc

	/* Reference to the run loop of the main thread. (There is a unique
	 * CFRunLoop per thread.)
	 */
	private let _mainRunLoop: RunLoop

	/* Flag when we've called nextEventMatchingMask ourself; this triggers
	 * a run loop iteration, so we need to detect that and avoid triggering
	 * our "run the GLib main looop while the run loop is active machinery.
	 */
	private var _gettingEvents: Int32 = 0

    /************************************************************
     *********              Select Thread               *********
     ************************************************************/

    /* The states in our state machine, see comments in select_thread_func()
     * for descriptiions of each state
     */
    private enum SelectThreadState {
        case beforeStart
        case waiting
        case pollingQueued
        case pollingRestart
        case pollingDescriptors
    }

    private var _selectThreadState: SelectThreadState = .beforeStart

    private var _selectThread =
            UnsafeMutablePointer<pthread_t>.allocate(capacity: 1)
    private var _selectThreadMutex = pthread_mutex_t()
    private var _selectThreadCond = pthread_cond_t()

    /* These are the file descriptors that the select thread is currently
     * polling.
     */
     private var _currentPollFDs: UnsafeMutablePointer<GPollFD>! = nil
     private var _currentPollFDCount: UInt32 = 0

    /* These are the file descriptors that the select thread should pick
     * up and start polling when it has a chance.
     */
    private var _nextPollFDs: UnsafeMutablePointer<GPollFD>! = nil
    private var _nextPollFDCount: UInt32 = 0

    /* Pipe used to wake up the select thread */
    private var _selectThreadWakeupPipe: [Int32] = [0, 0]

    /* Run loop source used to wake up the main thread */
    private var _selectMainThreadSource: CFRunLoopSource! = nil
#endif

	private init () {
        assert(Thread.isMainThread, "EventLoop must be created on main thread")
        _mainRunLoop = RunLoop.main
#if os(Linux)
        _oldPollFunc = g_main_context_get_poll_func(nil)
        //g_main_context_set_poll_func(nil, pollFunc)
        pthread_mutex_init(&_selectThreadMutex, nil)
        pthread_cond_init(&_selectThreadCond, nil)

        let unsafeSelf = Unmanaged.passUnretained(self).toOpaque()
        var observerContext =
                CFRunLoopObserverContext(version: 0, info: unsafeSelf,
                retain: nil, release: nil, copyDescription: nil)
        let observer =
                CFRunLoopObserverCreate(nil, UInt(kCFRunLoopAllActivities),
                true, 0, runLoopObserverCallback, &observerContext)
	    CFRunLoopAddObserver(_mainRunLoop.getCFRunLoop(), observer,
                kCFRunLoopCommonModes)
#endif
	}

	fileprivate func run() {
        assert(Thread.isMainThread, "EventLoop must be run on main thread")
		_mainRunLoop.run()
	}

#if os(Linux)
 	fileprivate var runLoopObserverCallback: @convention(c)
            (CFRunLoopObserver?, CFRunLoopActivity, UnsafeMutableRawPointer?)
            -> Void = { observer, activity, data in
        guard let data = data else {
            Log.error("invalid EventLoop object")
            return
        }
        let eventLoop = Unmanaged<EventLoop>.fromOpaque(data)
                .takeUnretainedValue()
        eventLoop.runLoopCallback(activity: activity)
	}

    private func runLoopCallback (activity: CFRunLoopActivity) {
        switch Int(activity) {
        case kCFRunLoopEntry:
            _currentLoopLevel += 1
        case kCFRunLoopExit:
            assert(_currentLoopLevel > 0,
                   "Invalid _currentLoopLevel on kCFRunLoopExit")
            _currentLoopLevel -= 1;
        default:
            break;
        }
        if _gettingEvents > 0 { /* Activity we triggered */
            return
        }
        switch Int(activity) {
        case kCFRunLoopEntry:
            runLoopEntry()
        case kCFRunLoopBeforeTimers:
            runLoopBeforeTimers()
        case kCFRunLoopBeforeSources:
            runLoopBeforeSources()
        case kCFRunLoopBeforeWaiting:
            runLoopBeforeWaiting()
        case kCFRunLoopAfterWaiting:
            runLoopAfterWaiting()
        case kCFRunLoopExit:
            runLoopExit()
        default:
            break
        }
    }

	private func runLoopEntry () {
  		if _acquiredLoopLevel == -1 {
      		if g_main_context_acquire(nil) == 1 {
	  			Log.verbose("EventLoop: Beginning tracking run loop activity")
	  			_acquiredLoopLevel = _currentLoopLevel
			} else {
            	/* If we fail to acquire the main context, that means someone is iterating
            	 * the main context in a different thread; we simply wait until this loop
            	 * exits and then try again at next entry. In general, iterating the loop
            	 * from a different thread is rare: it is only possible when GDK threading
            	 * is initialized and is not frequently used even then. So, we hope that
            	 * having GLib main loop iteration blocked in the combination of that and
            	 * a native modal operation is a minimal problem. We could imagine using a
            	 * thread that does g_main_context_wait() and then wakes us back up, but
            	 * the gain doesn't seem worth the complexity.
            	 */
			  	Log.warning("EventLoop: Can't acquire main loop")
			}
    	}
	}

	fileprivate func runLoopBeforeTimers () {
		// no-op
	}

	fileprivate func runLoopBeforeSources () {

		let context = g_main_context_default()
		var maxPriority: Int32 = 0

		/* Before we let the CFRunLoop process sources, we want to check if there
		 * are any pending GLib main loop sources more urgent than
		 * G_PRIORITY_DEFAULT that need to be dispatched. (We consider all activity
		 * from the CFRunLoop to have a priority of G_PRIORITY_DEFAULT.) If no
		 * sources are processed by the CFRunLoop, then processing will continue
		 * on to the BeforeWaiting stage where we check for lower priority sources.
		 */
  		g_main_context_prepare(context, &maxPriority)
  		maxPriority = min(maxPriority, G_PRIORITY_DEFAULT)

		/* We ignore the timeout that query_main_context () returns since we'll
		 * always query again before waiting.
		 */
        var timeout: Int32 = 0
		let fdCount = queryMainContext(context: context,
                maxPriority: maxPriority, timeout: &timeout)

		if fdCount > 0 {
			_ = _oldPollFunc(_pollFDs, fdCount, 0)
		}

		if g_main_context_check(context, maxPriority,
                _pollFDs, Int32(fdCount)) != 0   {
		    //Log.debug("EventLoop: Dispatching high priority sources")
		    g_main_context_dispatch(context)
	    }
	}

	/* Wrapper around g_main_context_query() that handles reallocating
	 * run_loop_pollfds up to the proper size
	 */
    fileprivate func queryMainContext(context: OpaquePointer?,
            maxPriority: Int32,
            timeout: UnsafeMutablePointer<Int32>?) -> UInt32 {

        let fdCount = UInt32(g_main_context_query(context, maxPriority, timeout,
                        _pollFDs, Int32(_pollFDCapacity)))
	    while fdCount > _pollFDCapacity {
	        _pollFDs.deallocate()
	        _pollFDCapacity = fdCount
	        _pollFDs = UnsafeMutablePointer<GPollFD>
                    .allocate(capacity: Int(_pollFDCapacity))
            return queryMainContext(context: context, maxPriority: maxPriority,
                    timeout: timeout)
	    }
	    return fdCount
	}

    fileprivate func runLoopBeforeWaiting() {

        let context = g_main_context_default()

        /* At this point, the CFRunLoop is ready to wait. We start a GMain loop
        * iteration by calling the check() and query() stages. We start a
        * poll, and if it doesn't complete immediately we let the run loop
        * go ahead and sleep. Before doing that, if there was a timeout from
        * GLib, we set up a CFRunLoopTimer to wake us up.
        */
        g_main_context_prepare(context, &_runLoopMaxPriority)

        var timeout: Int32 = 0
        _pollFDCount = queryMainContext(context: context,
                maxPriority: _runLoopMaxPriority, timeout: &timeout)

        let readyCount = selectThreadStartPoll(pollFDs: _pollFDs, count: _pollFDCount, timeout: timeout)

        if readyCount > 0 || timeout == 0 {
            /* We have stuff to do, no sleeping allowed! */
            CFRunLoopWakeUp(_mainRunLoop.getCFRunLoop())
        } else if (timeout > 0) {
            /* We need to get the run loop to break out of its wait when our
             * timeout expires. We do this by adding a dummy timer that we'll
             * remove immediately after the wait wakes up.
             */
            /*Log.debug("""
                    EventLoop: Adding timer to wake us up in \(timeout) ms
                    """)*/
            _runLoopTimer = CFRunLoopTimerCreate(nil, /* allocator */
					     CFAbsoluteTimeGetCurrent() + Double(timeout) / 1000,
					     0, /* interval (0=does not repeat) */
					     0, /* flags */
					     0, /* order (priority) */
					     runLoopDummyTimerCallback,
					     nil)
            CFRunLoopAddTimer(_mainRunLoop.getCFRunLoop(), _runLoopTimer,
                kCFRunLoopCommonModes)
        }
        _runLoopPollingAsync = readyCount < 0
    }

    private var runLoopDummyTimerCallback: @convention(c) (CFRunLoopTimer?,
            UnsafeMutableRawPointer?) -> Void = { timer, data in
        // no-op
    }

    fileprivate func runLoopAfterWaiting () {

        let context = g_main_context_default()
        /* After sleeping, we finish off the GMain loop iteration started in
         * before_waiting() by doing the check() and dispatch() stages.
         */
        if _runLoopTimer != nil {
            CFRunLoopRemoveTimer(_mainRunLoop.getCFRunLoop(), _runLoopTimer,
                    kCFRunLoopCommonModes)
            _runLoopTimer = nil
        }

        if _runLoopPollingAsync {
          _ = selectThreadCollectPoll(pollFDs: _pollFDs, count: _pollFDCount)
          _runLoopPollingAsync = false
        }

        if g_main_context_check(context, _runLoopMaxPriority, _pollFDs,
                Int32(_pollFDCount)) == 1 {
            //Log.debug("EventLoop: Dispatching after waiting")
            g_main_context_dispatch(context)
        }
    }

    fileprivate func runLoopExit () {
    /* + 1 because we decrement current_loop_level separately in observer_callback() */
        if (_currentLoopLevel + 1) == _acquiredLoopLevel {
            g_main_context_release(nil)
            _acquiredLoopLevel = -1
            Log.debug("EventLoop: Ended tracking run loop activity")
        }
    }

    // PRAGMA: Select Thread

    private func selectThreadStart () {
        assert(_selectThreadState == .beforeStart)

        pipe(&_selectThreadWakeupPipe)
        _ = fcntl(_selectThreadWakeupPipe[0], F_SETFL, O_NONBLOCK)

        var sourceContext = CFRunLoopSourceContext(version: 0, info: nil,
                retain: nil, release: nil, copyDescription: nil,
                equal: nil, hash: nil, schedule: nil, cancel: nil,
                perform: gotFDActivity)
        let selectMainThreadSource =
                CFRunLoopSourceCreate(nil, 0, &sourceContext)

        CFRunLoopAddSource(_mainRunLoop.getCFRunLoop(), selectMainThreadSource,
                kCFRunLoopCommonModes)

        _selectThreadState = .waiting
        let unsafeSelf = Unmanaged.passUnretained(self).toOpaque()
        while true {
            if pthread_create(_selectThread, nil, selectThreadCallback, unsafeSelf)
                    == 0 {
                break
            }
            Log.warning("Failed to create select thread, sleeping and trying again")
            sleep(1)
        }
    }
    /*
    #ifdef G_ENABLE_DEBUG
    static void
    dump_poll_result (GPollFD *ufds,
              guint    nfds)
    {
      GString *s;
      gint i;

      s = g_string_new ("");
      for (i = 0; i < nfds; i++)
        {
          if (ufds[i].fd >= 0 && ufds[i].revents)
        {
              g_string_append_printf (s, " %d:", ufds[i].fd);
          if (ufds[i].revents & G_IO_IN)
                g_string_append (s, " in");
          if (ufds[i].revents & G_IO_OUT)
            g_string_append (s, " out");
          if (ufds[i].revents & G_IO_PRI)
            g_string_append (s, " pri");
          g_string_append (s, "\n");
        }
        }
      g_message ("%s", s->str);
      g_string_free (s, TRUE);
    }
    #endif
    */

    private func pollFDsEqual (oldPollFDs: UnsafeMutablePointer<GPollFD>,
            oldPollFDCount: UInt32, newPollFDs: UnsafeMutablePointer<GPollFD>,
            newPollFDCount: UInt32) -> Bool {
        if oldPollFDCount != newPollFDCount {
            return false
        }

        for i in 0..<Int(oldPollFDCount) {
            if oldPollFDs[i].fd != newPollFDs[i].fd ||
                    oldPollFDs[i].events != newPollFDs[i].events {
                return false
            }
        }

        return true
    }

    /* Begins a polling operation with the specified GPollFD array; the
     * timeout is used only to tell if the polling operation is blocking
     * or non-blocking.
     *
     * Returns:
     *  -1: No file descriptors ready, began asynchronous poll
     *   0: No file descriptors ready, asynchronous poll not needed
     * > 0: Number of file descriptors ready
     */
    fileprivate func selectThreadStartPoll (pollFDs: UnsafeMutablePointer<GPollFD>,
            count: UInt32, timeout: Int32) -> Int32 {
        var readyCount: Int32
        var haveNewPollFDs = false
        var pollFDIndex: Int32 = -1

        for i in 0..<Int(count) {
            if pollFDs[i].fd == -1 {
                pollFDIndex = Int32(i)
                break
            }
        }

        if count == 0 || (count == 1 && pollFDIndex >= 0) {
            Log.debug("EventLoop: Nothing to poll")
            return 0
        }

        /* If we went immediately to an async poll, then we might decide to
        * dispatch idle functions when higher priority file descriptor sources
        * are ready to be dispatched. So we always need to first check
        * check synchronously with a timeout of zero, and only when no
        * sources are immediately ready, go to the asynchronous poll.
        *
        * Of course, if the timeout passed in is 0, then the synchronous
        * check is sufficient and we never need to do the asynchronous poll.
        */
        readyCount = _oldPollFunc(pollFDs, count, 0)
        if readyCount > 0 || timeout == 0 {
            /*#ifdef G_ENABLE_DEBUG
                  if ((_gdk_debug_flags & GDK_DEBUG_EVENTLOOP) && n_ready > 0)
                {
                  g_message ("EventLoop: Found ready file descriptors before waiting");
                  dump_poll_result (ufds, nfds);
                }
            #endif*/
            return readyCount
        }

        pthread_mutex_lock(&_selectThreadMutex)

        if _selectThreadState == .beforeStart {
            selectThreadStart()
        }

        if _selectThreadState == .pollingQueued {
            /* If the select thread hasn't picked up the set of file descriptors yet
            * then we can simply replace an old stale set with a new set.
            */
            if !pollFDsEqual(oldPollFDs: pollFDs, oldPollFDCount: count,
                    newPollFDs: _nextPollFDs,
                    newPollFDCount: _nextPollFDCount - 1) {
                _nextPollFDs.deallocate()
                _nextPollFDs = nil
                _nextPollFDCount = 0
                haveNewPollFDs = true
           }
        }
        else if (_selectThreadState == .pollingRestart ||
                _selectThreadState == .pollingDescriptors) {
            /* If we are already in the process of polling the right set of file descriptors,
            * there's no need for us to immediately force the select thread to stop polling
            * and then restart again. And avoiding doing so increases the efficiency considerably
            * in the common case where we have a set of basically inactive file descriptors that
            * stay unchanged present as we process many events.
            *
            * However, we have to be careful that we don't hit the following race condition
            *  Select Thread              Main Thread
            *  -----------------          ---------------
            *  Polling Completes
            *                             Reads data or otherwise changes file descriptor state
            *                             Checks if polling is current
            *                             Does nothing (*)
            *                             Releases lock
            *  Acquires lock
            *  Marks polling as complete
            *  Wakes main thread
            *                             Receives old stale file descriptor state
            *
            * To avoid this, when the new set of poll descriptors is the same as the current
            * one, we transition to the POLLING_RESTART stage at the point marked (*). When
            * the select thread wakes up from the poll because a file descriptor is active, if
            * the state is POLLING_RESTART it immediately begins polling same the file descriptor
            * set again. This normally will just return the same set of active file descriptors
            * as the first time, but in sequence described above will properly update the
            * file descriptor state.
            *
            * Special case: this RESTART logic is not needed if the only FD is the internal GLib
            * "wakeup pipe" that is presented when threads are initialized.
            *
            * P.S.: The harm in the above sequence is mostly that sources can be signalled
            *   as ready when they are no longer ready. This may prompt a blocking read
            *   from a file descriptor that hangs.
            */
            if !pollFDsEqual(oldPollFDs: pollFDs, oldPollFDCount: count,
                    newPollFDs: _currentPollFDs,
                    newPollFDCount: _currentPollFDCount - 1) {
                haveNewPollFDs = true
            } else {
                if !(count == 1 && pollFDIndex < 0) ||
                        (count == 2 && pollFDIndex >= 0) {
                    selectThreadSet(state: .pollingRestart)
                }
            }
        } else {
            haveNewPollFDs = true
        }

        if haveNewPollFDs {
            /*Log.debug("""
                    EventLoop: Submitting a new set of file descriptors to the select thread
            """)*/
            assert(_nextPollFDs == nil)

            _nextPollFDCount = count + 1
            _nextPollFDs = UnsafeMutablePointer<GPollFD>
                    .allocate(capacity: Int(_nextPollFDCount))
            memcpy(_nextPollFDs, pollFDs,
                    Int(count) * MemoryLayout<GPollFD>.size)

            _nextPollFDs[Int(count)].fd = _selectThreadWakeupPipe[0]
            _nextPollFDs[Int(count)].events = UInt16(G_IO_IN.rawValue)

            if _selectThreadState != .pollingQueued && _selectThreadState != .waiting {
                if _selectThreadWakeupPipe[1] != 0 {
                    var c: Character = "A"
                    write(_selectThreadWakeupPipe[1], &c, 1)
                }
            }
            selectThreadSet(state: .pollingQueued)
        }
        pthread_mutex_unlock(&_selectThreadMutex)

        return -1
    }

    private func selectThreadSet (state newState: SelectThreadState) {
        if _selectThreadState == newState {
            return
        }
        let oldState = _selectThreadState
        _selectThreadState = newState
        //og.debug("EventLoop: Select thread state: \(oldState) => \(newState)")

        if oldState == .waiting && newState != .waiting {
            pthread_cond_signal(&_selectThreadCond)
        }
    }

    /* End an asynchronous polling operation started with
     * select_thread_collestart_pollct_poll(). This must be called if and only if
     * select_thread_start_poll() return -1. The GPollFD array passed
     * in must be identical to the one passed to select_thread_start_poll().
     *
     * The results of the poll are written into the GPollFD array passed in.
     *
     * Returns: number of file descriptors ready
     */
    fileprivate func selectThreadCollectPoll (
            pollFDs: UnsafeMutablePointer<GPollFD>,
            count: UInt32) -> Int32 {

        pthread_mutex_lock(&_selectThreadMutex)

        var readyCount: Int32 = 0

        if _selectThreadState == .waiting { /* The poll completed */
            for i in 0..<Int(count) {
                if pollFDs[i].fd == -1 {
                    continue
                }
                assert(pollFDs[i].fd == _currentPollFDs[i].fd)
                assert(pollFDs[i].events == _currentPollFDs[i].events)
                if _currentPollFDs[i].revents != 0 {
                    pollFDs[i].revents = _currentPollFDs[i].revents
                    readyCount += 1
                }
            }
        }
/*
    #ifdef G_ENABLE_DEBUG
          if (_gdk_debug_flags & GDK_DEBUG_EVENTLOOP)
        {
          g_message ("EventLoop: Found ready file descriptors after waiting");
          dump_poll_result (ufds, nfds);
        }
    #endif
        }*/

        pthread_mutex_unlock(&_selectThreadMutex)
        return readyCount
    }

    /* called from _selectThread only */
    fileprivate func selectThreadFunc () {

        //char c;

        pthread_mutex_lock(&_selectThreadMutex)

        while true {
            switch _selectThreadState {
            case .beforeStart:
                /* The select thread has not been started yet
                */
                assertionFailure("Not reached")
            case .waiting:
                /* Waiting for a set of file descriptors to be
                * submitted by the main thread
                *
                *  => POLLING_QUEUED: main thread thread submits a set of file descriptors
                */
                pthread_cond_wait(&_selectThreadCond, &_selectThreadMutex)
            case .pollingQueued:
                /* Waiting for a set of file descriptors to be submitted by the main thread
                *
                *  => POLLING_DESCRIPTORS: select thread picks up the file descriptors to begin polling
                */
                if _currentPollFDs != nil {
                    _currentPollFDs.deallocate()
                }
                _currentPollFDs = _nextPollFDs
                _currentPollFDCount = _nextPollFDCount

                _nextPollFDs = nil
                _nextPollFDCount = 0

                selectThreadSet(state: .pollingDescriptors)
            case .pollingRestart:
                /* Select thread is currently polling a set of file descriptors, main thread has
                * began a new iteration with the same set of file descriptors. We don't want to
                * wake the select thread up and wait for it to restart immediately, but to avoid
                * a race (described below in select_thread_start_polling()) we need to recheck after
                * polling completes.
                *
                * => POLLING_DESCRIPTORS: select completes, main thread rechecks by polling again
                * => POLLING_QUEUED: main thread submits a new set of file descriptors to be polled
                */
                selectThreadSet(state: .pollingDescriptors)
            case .pollingDescriptors:
                /* In the process of polling the file descriptors
                *
                *  => WAITING: polling completes when a file descriptor becomes active
                *  => POLLING_QUEUED: main thread submits a new set of file descriptors to be polled
                *  => POLLING_RESTART: main thread begins a new iteration with the same set file descriptors
                */
                pthread_mutex_unlock(&_selectThreadMutex)
                _ = _oldPollFunc(_currentPollFDs, _currentPollFDCount, -1)
                pthread_mutex_lock(&_selectThreadMutex)

                var c: Character = "A"
                read(_selectThreadWakeupPipe[0], &c, 1)

                if _selectThreadState == .pollingDescriptors {
                  signalMainThread()
                  selectThreadSet(state: .waiting)
                }
            }
        }
    }

    func signalMainThread () {
        //Log.debug("EventLoop: Waking up main thread")

        /* If we are in nextEventMatchingMask, then we need to make sure an
        * event gets queued, otherwise it's enough to simply wake up the
        * main thread run loop
        */
        if !_runLoopPollingAsync {
            //CFRunLoopSourceSignal(_selectMainThreadSource)
        }

        /* Don't check for CFRunLoopIsWaiting() here because it causes a
        * race condition (the loop could go into waiting state right after
        * we checked).
        */
        CFRunLoopWakeUp(_mainRunLoop.getCFRunLoop())
    }


    deinit {
        _selectThread.deallocate()
    }
#endif
}

fileprivate func selectThreadCallback (arg: UnsafeMutableRawPointer?) ->
        UnsafeMutableRawPointer? {

    guard let arg = arg else {
        Log.error("Invalid selectThreadFunc argument")
        return nil
    }
    let eventLoop = Unmanaged<EventLoop>.fromOpaque(arg).takeUnretainedValue()
    eventLoop.selectThreadFunc()
    return nil
}

fileprivate func gotFDActivity (info: UnsafeMutableRawPointer?) {
    Log.debug("Got FD activity")
  /*NSEvent *event;

  // Post a message so we'll break out of the message loop
  event = [NSEvent otherEventWithType: NSApplicationDefined
	                     location: NSZeroPoint
	                modifierFlags: 0
	                    timestamp: 0
	                 windowNumber: 0
	                      context: nil
                              subtype: GDK_QUARTZ_EVENT_SUBTYPE_EVENTLOOP
	                        data1: 0
	                        data2: 0];

  [NSApp postEvent:event atStart:YES];*/
}




