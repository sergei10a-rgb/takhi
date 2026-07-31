// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'dialog_action_bar.dart';

/// Guards a screen whose in-flight work would be silently destroyed by a
/// back gesture -- a running taximeter session that has not been written
/// to the journal yet, an active trip whose state lives only in memory,
/// a published ride request the other side is still waiting on.
///
/// While [enabled] is true every pop attempt (the `AppBar` arrow,
/// Android's hardware back, iOS' back swipe -- they all funnel through
/// `Navigator.maybePop`) is intercepted and turned into a confirmation
/// dialog instead. Only if the user picks "leave" does
/// [onConfirmedLeave] run -- the place to publish a cancellation, write
/// the journal entry, or tear down subscriptions -- and the route then
/// actually pops. While [enabled] is false the widget is inert and pops
/// behave exactly as they would without it, so callers can express
/// "nothing to lose on this step" by flipping a single flag rather than
/// conditionally wrapping their subtree. Prefer that flag over swapping
/// this widget in and out of the tree: a changing ancestor remounts
/// everything below it, which on a screen like `ActiveTripView` would
/// silently restart the very trip the guard exists to protect.
///
/// Wrap the `Scaffold`, not the whole page: `PopScope` only needs to sit
/// under the route, and keeping the `Scaffold` inside means the dialog
/// still finds a `MaterialLocalizations` ancestor.
class ConfirmLeaveScope extends StatefulWidget {
  /// Whether leaving currently needs confirming. `false` makes this
  /// widget a no-op pass-through.
  final bool enabled;

  /// Dialog headline, e.g. `l.leaveMeterTitle`.
  final String title;

  /// Dialog body spelling out what is lost by leaving, e.g.
  /// `l.leaveMeterMessage`.
  final String message;

  /// Runs once the user has confirmed, *before* the route pops -- so it
  /// can still read the state it is about to tear down. Must not itself
  /// pop the route.
  final VoidCallback? onConfirmedLeave;

  final Widget child;

  const ConfirmLeaveScope({
    super.key,
    required this.enabled,
    required this.title,
    required this.message,
    this.onConfirmedLeave,
    required this.child,
  });

  @override
  State<ConfirmLeaveScope> createState() => _ConfirmLeaveScopeState();
}

class _ConfirmLeaveScopeState extends State<ConfirmLeaveScope> {
  /// Guards against a second back press (or a back press racing the
  /// dialog's own entry animation) stacking a second identical dialog on
  /// top of the first -- which would then need dismissing twice.
  bool _asking = false;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.enabled,
    onPopInvokedWithResult: (didPop, result) {
      // The `enabled` check is not redundant with `canPop` above: a
      // *nested* `PopScope` (a wizard's "one step back", say) can refuse
      // a pop this widget was happy to allow, and the navigator then
      // notifies every registered entry -- including this inert one --
      // with `didPop: false`. Without it, a disabled guard would raise
      // its dialog over somebody else's refusal, which is exactly what
      // "while [enabled] is false the widget is inert" promises it will
      // not do.
      if (didPop || !widget.enabled || _asking) return;
      unawaited(_confirmThenLeave());
    },
    child: widget.child,
  );

  Future<void> _confirmThenLeave() async {
    final l = AppLocalizations.of(context)!;
    // Captured before the await: `context` may be defunct afterwards, but
    // the navigator this route belongs to is what has to do the popping.
    final navigator = Navigator.of(context);

    _asking = true;
    final bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(widget.title),
          content: Text(widget.message),
          actions: [
            // Emphasis on staying, not on leaving: this dialog was not
            // sought out, it was raised by a back gesture, so the loud
            // button has to be the one that undoes that reflex.
            DialogActionBar(
              dismiss: DialogAction(
                label: l.stayAction,
                tone: DialogActionTone.primary,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              proceed: DialogAction(
                label: l.leaveAction,
                tone: DialogActionTone.caution,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ),
          ],
        ),
      );
    } finally {
      _asking = false;
    }

    // `null` is a barrier tap or a back press on the dialog itself --
    // treated as "stay", the safe answer for every screen this guards.
    if (confirmed != true || !mounted) return;

    widget.onConfirmedLeave?.call();

    // `pop`, not `maybePop`: this route's own `PopScope` still reports
    // `canPop: false` (the caller may not have rebuilt yet), and
    // `maybePop` would bounce straight back into this dialog.
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    // Root route: `pop` is a no-op, so confirming "leave" would leave the
    // user exactly where they were -- and their next back press reopens
    // this dialog, forever. That is a misuse, not a state to recover from
    // at runtime: this widget's contract is that it only ever guards a
    // *pushed* route. A root-route screen that needs the same guard must
    // drive its own `PopScope` and navigate explicitly (see
    // `SeedBackupPage`, which `go`es to `/home` on confirm).
    assert(
      false,
      'ConfirmLeaveScope guards a root route ("${widget.title}"): '
      'Navigator.pop() cannot leave it, so the confirm dialog would '
      'reopen on every back press. Drive PopScope + an explicit '
      'go()/replace() from the screen itself instead.',
    );
  }
}
