// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../nostr/relay_pool_provider.dart';
import '../ride/ride_providers.dart';
import 'call_engine.dart';
import 'call_signal_service.dart';
import 'helper_directory_service.dart';
import 'phone_share_settings.dart';
import 'voice_note_player.dart';
import 'voice_note_recorder.dart';
import 'voice_note_service.dart';

final callSignalServiceProvider = Provider<CallSignalService>(
  (ref) => CallSignalService(ref.watch(rideDmChannelProvider)),
);

final voiceNoteServiceProvider = Provider<VoiceNoteService>(
  (ref) => VoiceNoteService(ref.watch(rideDmChannelProvider)),
);

final voiceNoteRecorderProvider = Provider<VoiceNoteRecorder>(
  (ref) => RecordPackageVoiceNoteRecorder(),
);

final voiceNotePlayerProvider = Provider<VoiceNotePlayer>(
  (ref) => AudioPlayersVoiceNotePlayer(),
);

final helperDirectoryServiceProvider = Provider<HelperDirectoryService>(
  (ref) => HelperDirectoryService(ref.watch(relayPoolProvider)),
);

/// The live, app-session-long [HelperDirectory] accumulator: subscribes to
/// every kind-30178 helper announcement (`HelperDirectoryService
/// .watchHelpers`) the moment this provider is first read, and keeps
/// folding them in for as long as the provider stays alive -- a plain
/// `Provider`, not `.autoDispose`, precisely so that subscription keeps
/// running for the whole app session rather than restarting every time
/// some particular screen happens to (re)mount. `CallScreen` reads
/// [HelperDirectory.current] off this provider's instance right before
/// every call attempt to build `buildIceServers`'s `helpers:` argument
/// (Plan 5 Task 3/7's fallback-chain fix); `ActiveTripView` warms this
/// provider up as soon as a trip goes active so real announcements have
/// time to arrive over the network before the user ever taps the call
/// button, rather than only starting to listen at the moment a call
/// begins.
final helperDirectoryProvider = Provider<HelperDirectory>((ref) {
  final dir = HelperDirectory();
  final sub = ref
      .watch(helperDirectoryServiceProvider)
      .watchHelpers()
      .listen(dir.add);
  ref.onDispose(sub.cancel);
  return dir;
});

final phoneShareSettingsStoreProvider = Provider<PhoneShareSettingsStore>(
  (ref) =>
      SharedPreferencesPhoneShareSettingsStore(SharedPreferences.getInstance),
);

/// A *factory*, not a shared instance -- every call attempt needs its own
/// fresh `RTCPeerConnection` (`CallEngine.dispose()` tears one down
/// completely). `CallScreen` calls this once per `initState`, passing the
/// currently-known helper list (`HelperDirectoryService`) merged with
/// `kDefaultStunServers` via `buildIceServers`.
final callEngineFactoryProvider =
    Provider<CallEngine Function(List<Map<String, dynamic>> iceServers)>(
      (ref) =>
          (iceServers) => FlutterWebrtcCallEngine(iceServers: iceServers),
    );
