import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/focus/back_key_release.dart';

// Issue #1680: the player popped on Back's key down, and the remote's key up
// then landed on the detail page and closed it as well. The simulator can't
// send Android's Go Back, so these hold Escape, which counts as Back too.

void main() {
  testWidgets('runs right away when no Back is held', (tester) async {
    var ran = 0;
    runAfterBackKeyUp(() => ran++);

    expect(ran, 1);
  });

  testWidgets('waits for a held Back to come up and keeps that key up', (
    tester,
  ) async {
    var ran = 0;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    runAfterBackKeyUp(() => ran++);
    expect(ran, 0);

    final handled = await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);

    expect(ran, 1);
    expect(handled, isTrue);
  });

  testWidgets('other keys coming up leave the wait alone', (tester) async {
    var ran = 0;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    runAfterBackKeyUp(() => ran++);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    expect(ran, 0);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    expect(ran, 1);
  });

  testWidgets('a cancelled wait never runs or keeps the key up', (
    tester,
  ) async {
    var ran = 0;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    runAfterBackKeyUp(() => ran++)();

    final handled = await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);

    expect(ran, 0);
    expect(handled, isFalse);
  });

  // macOS can keep Escape in the pressed set after the system consumed its
  // key up, so a finished episode's exit waited forever.
  testWidgets('a timeout runs the action when the key up never comes', (
    tester,
  ) async {
    var ran = 0;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    runAfterBackKeyUp(
      () => ran++,
      timeout: const Duration(milliseconds: 600),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(ran, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(ran, 1);

    // The late key up neither runs it again nor gets swallowed.
    final handled = await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    expect(ran, 1);
    expect(handled, isFalse);
  });

  testWidgets('a key up before the timeout runs it once', (tester) async {
    var ran = 0;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    runAfterBackKeyUp(
      () => ran++,
      timeout: const Duration(milliseconds: 600),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 1));
    expect(ran, 1);
  });
}
