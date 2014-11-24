// Copyright (c) 2014, the dom_scheduler project authors. Please see the
// AUTHORS file for details. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// DOM Tasks Scheduler.
library dom_scheduler;

import 'dart:async';
import 'dart:collection';
import 'dart:html' as html;
import 'package:collection/priority_queue.dart';

/// Write groups sorted by their priority to prevent unnecessary writes when the
/// parent removes its children.
class _WriteGroup implements Comparable {
  final int priority;

  Completer completer;

  _WriteGroup(this.priority);

  int compareTo(_WriteGroup other) => priority.compareTo(other.priority);
}

/// Frame tasks
class Frame {
  /// Write groups indexed by priority
  List<_WriteGroup> writeGroups = [];
  HeapPriorityQueue<_WriteGroup> writeQueue = new HeapPriorityQueue<_WriteGroup>();
  Completer readCompleter;
  Completer afterCompleter;

  /// Returns [Future] that completes when [Scheduler] launches write
  /// tasks for that [Frame]
  Future write(int priority) {
    if (priority >= writeGroups.length) {
      var i = writeGroups.length;
      while (i <= priority) {
        writeGroups.add(new _WriteGroup(i++));
      }
    }
    final g = writeGroups[priority];
    if (g.completer == null) {
      g.completer = new Completer();
      writeQueue.add(g);
    }
    return g.completer.future;
  }

  /// Returns [Future] that completes when [Scheduler] launches read
  /// tasks for that [Frame]
  Future read() {
    if (readCompleter == null) {
      readCompleter = new Completer();
    }
    return readCompleter.future;
  }

  /// Returns [Future] that completes when [Scheduler] finishes all
  /// read and write tasks for that [Frame]
  Future after() {
    if (afterCompleter == null) {
      afterCompleter = new Completer();
    }
    return afterCompleter.future;
  }
}

/// [Scheduler] runs [Frame]'s write/read tasks.
///
/// Whenever you add any task to the [nextFrame], Scheduler starts waiting
/// for the next frame with the requestAnimationFrame call and then runs all
/// tasks inside the Scheduler's [zone].
///
/// [Scheduler] runs all write tasks and microtasks that were registered
/// in its [zone], when all this tasks are finished, it starts running
/// reading tasks and microtasks, then it checks if there any write tasks
/// were added after read batch, if anything is added, it performs the loop
/// again, otherwise it runs all `after` tasks and finishes.
///
/// ```dart
/// while (writeTasks.isNotEmpty) {
///   while (writeTasks.isNotEmpty) {
///     writeTasks.removeFirst().start();
///     runMicrotasks();
///   }
///   while (readTasks.isNotEmpty) {
///     readTasks.removeFirst().start();
///     runMicrotasks();
///   }
/// }
/// while (afterTasks.isNotEmpty) {
///   afterTasks.removeFirst().start();
///   runMicrotasks();
/// }
/// ```
///
/// By executing tasks this way we can guarantee almost optimal read/write
/// batching.
///
/// TODO: add (intrusive) lists for animation tasks
class Scheduler {
  bool _running = false;
  Queue<Function> _currentTasks = new Queue<Function>();

  ZoneSpecification _zoneSpec;
  Zone _zone;

  int _rafId = 0;
  Frame _currentFrame;
  Frame _nextFrame;

  Scheduler() {
    _zoneSpec = new ZoneSpecification(scheduleMicrotask: _scheduleMicrotask);
    _zone = Zone.current.fork(specification: _zoneSpec);
  }

  /// Scheduler [Zone]
  Zone get zone => _zone;

  /// Current [Frame]
  Frame get currentFrame {
    assert(_currentFrame != null);
    return _currentFrame;
  }

  /// Next [Frame]
  Frame get nextFrame {
    if (_nextFrame == null) {
      _nextFrame = new Frame();
      _requestAnimationFrame();
    }
    return _nextFrame;
  }

  void _scheduleMicrotask(Zone self, ZoneDelegate parent, Zone zone, void f()) {
    if (_running) {
      _currentTasks.add(f);
    } else {
      parent.scheduleMicrotask(zone, f);
    }
  }

  void _runTasks() {
    while (_currentTasks.isNotEmpty) {
      _currentTasks.removeFirst()();
    }
  }

  void _requestAnimationFrame() {
    if (_rafId == 0) {
      _rafId = html.window.requestAnimationFrame(_handleAnimationFrame);
    }
  }

  void _handleAnimationFrame(num t) {
    _rafId = 0;

    _zone.run(() {
      _running = true;
      _currentFrame = _nextFrame;
      _nextFrame = null;
      final wq = _currentFrame.writeQueue;

      do {
        while (wq.isNotEmpty) {
          final writeGroup = wq.removeFirst();
          writeGroup.completer.complete();
          _runTasks();
          writeGroup.completer = null;
        }

        if (_currentFrame.readCompleter != null) {
          _currentFrame.readCompleter.complete();
          _runTasks();
          _currentFrame.readCompleter = null;
        }
      } while (wq.isNotEmpty);

      if (_currentFrame.afterCompleter != null) {
        _currentFrame.afterCompleter.complete();
        _runTasks();
        _currentFrame.afterCompleter = null;
      }
      _running = false;
    });

  }

  /// Force [Scheduler] to run tasks for the [nextFrame].
  void forceNextFrame() {
    if (_rafId != 0) {
      html.window.cancelAnimationFrame(_rafId);
      _rafId = 0;
      _handleAnimationFrame(html.window.performance.now());
    }
  }
}
