# DOM Scheduler for read/write tasks

## API

### Scheduler

The scheduler algorithm is quite simple and looks like this:

```dart
while (writeTasks.isNotEmpty) {
  while (writeTasks.isNotEmpty) {
     writeTasks.removeFirst().start();
     runMicrotasks();
  }
  while (readTasks.isNotEmpty) {
    readTasks.removeFirst().start();
    runMicrotasks();
  }
}
while (afterTasks.isNotEmpty) {
  afterTasks.removeFirst().start();
  runMicrotasks();
}
```

It will perform write and read tasks in batches until there are no
write or read tasks left.

Write tasks sorted by their priority, and the tasks with the lowest
value in the priority property are executed first. It is implemented
this way because most of the time tasks priority will be its depth in
the DOM.

Scheduler runs in its own `Zone` and intercepts all microtasks, this
way it is possible to use `Future`s to track dependencies between
tasks.

#### `Frame get nextFrame`

Returns `Frame` that contains tasks for the next animation frame.

#### `Frame get currentFrame`

Returns `Frame` that contains tasks for the current animation frame.

#### `Zone get zone`

Returns Scheduler `Zone`.

### Frame

#### `Future write([int priority = maxPriority])`

Returns `Future` that will be completed when Scheduler starts
executing write tasks with this priority.

#### `Future read()`

Returns `Future` that will be completed when Scheduler starts
executing read tasks.

#### `Future after()`

Returns `Future` that will be completed when Scheduler finishes
executing all write and read tasks.

## Notes

If you are planning to use something else for the write priority and
not depth of the node in the DOM tree, please let me know. Right now
it is implemented in a way that is better suited for depth, and will
behave badly for sparse values.