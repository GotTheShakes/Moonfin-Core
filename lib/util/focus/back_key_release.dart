import 'dart:async';

import 'package:flutter/services.dart';

import 'dpad_keys.dart';

/// Runs [action] now, or once a Back key held right now comes back up.
///
/// Android follows Back's key up with a system back, so a screen that closes
/// itself on the key down has to stay until the key comes up, or that back
/// lands on the page below and closes it as well. The key up is marked handled
/// so it can't raise another back, and the returned callback drops a wait that
/// hasn't finished.
///
/// With [timeout], [action] runs anyway once that long has passed without the
/// key up. On macOS the pressed-key state can be stale (an Escape whose key up
/// the system consumed, for example on leaving full screen), and a wait
/// without a timeout would then never end.
VoidCallback runAfterBackKeyUp(VoidCallback action, {Duration? timeout}) {
  if (!HardwareKeyboard.instance.logicalKeysPressed.any((k) => k.isBackKey)) {
    action();
    return () {};
  }
  Timer? timer;
  bool onKey(KeyEvent event) {
    if (event is! KeyUpEvent || !event.logicalKey.isBackKey) return false;
    HardwareKeyboard.instance.removeHandler(onKey);
    timer?.cancel();
    action();
    return true;
  }

  HardwareKeyboard.instance.addHandler(onKey);
  if (timeout != null) {
    timer = Timer(timeout, () {
      HardwareKeyboard.instance.removeHandler(onKey);
      action();
    });
  }
  return () {
    timer?.cancel();
    HardwareKeyboard.instance.removeHandler(onKey);
  };
}
