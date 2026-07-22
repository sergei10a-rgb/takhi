// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

/// Connection-state values `RTCPeerConnection.onConnectionState`
/// (flutter_webrtc) actually delivers, renamed to plain,
/// package-independent identifiers -- nothing above [CallEngine] imports
/// `package:flutter_webrtc` directly. `newConnection` is the
/// pre-negotiation state (`new` is a reserved word in Dart).
enum CallConnectionState {
  newConnection,
  connecting,
  connected,
  failed,
  disconnected,
  closed,
}

/// A local SDP description ready to hand to `CallSignalService` -- the
/// wire shape `CallOfferPayload`/`CallAnswerPayload`'s `sdp` field carries
/// (`ride_dm_payload.dart`, Task 2).
class LocalSessionDescription {
  final String sdp;
  final String type; // 'offer' | 'answer'
  const LocalSessionDescription(this.sdp, this.type);
}

/// A single ICE candidate in the exact three fields
/// `CallIceCandidatePayload` (Task 2) and `RTCIceCandidate`
/// (flutter_webrtc) both carry.
class IceCandidateData {
  final String candidate;
  final String sdpMid;
  final int sdpMLineIndex;
  const IceCandidateData(this.candidate, this.sdpMid, this.sdpMLineIndex);
}

/// Abstracts a single audio-only WebRTC peer connection so `CallService`
/// (Task 7) and its tests never talk to `package:flutter_webrtc` directly
/// -- mirrors `LocationSource`'s role for GPS (Plan 4 Task 1) exactly.
/// Everything above this interface is testable with `FakeCallEngine`
/// (`test/support/fake_call_engine.dart`); only `FlutterWebrtcCallEngine`
/// itself has no dedicated unit test, for the same documented reason
/// `GeolocatorLocationSource` and `WsRelaySocket` don't -- a thin wrapper
/// around a platform plugin that cannot run meaningfully without a real
/// device/microphone.
///
/// One [CallEngine] instance is exactly one call attempt: audio-only by
/// construction (no video track is ever requested -- spec §7.3 is "дуут
/// яриа", voice, not video), and disposed at the end of every attempt.
/// Callers never reuse an instance across two calls.
abstract interface class CallEngine {
  Stream<CallConnectionState> get connectionState;
  Stream<IceCandidateData> get localIceCandidates;

  /// Starts as the caller: creates the local audio track, generates an
  /// SDP offer, and sets it as the local description.
  Future<LocalSessionDescription> createOffer();

  /// Starts as the callee: creates the local audio track, sets
  /// [remoteOfferSdp] as the remote description, and generates an SDP
  /// answer.
  Future<LocalSessionDescription> createAnswer(String remoteOfferSdp);

  /// Caller-side: completes the offer/answer exchange once the callee's
  /// answer arrives.
  Future<void> acceptAnswer(String remoteAnswerSdp);

  Future<void> addRemoteIceCandidate(IceCandidateData candidate);

  /// Mutes/unmutes the local microphone track without renegotiating.
  Future<void> setMuted(bool muted);

  /// Closes the peer connection and releases the local audio track.
  Future<void> dispose();
}

/// Real [CallEngine] backed by `package:flutter_webrtc`. Configured with
/// [iceServers] (`buildIceServers`'s output, Task 3) at construction --
/// STUN and any currently-known helper TURN entries are both already
/// merged into that one list by the time it reaches here, so this class
/// has no separate "try direct, then try relay" logic of its own (see
/// Task 3's `buildIceServers` doc comment for why that's correct).
class FlutterWebrtcCallEngine implements CallEngine {
  final List<Map<String, dynamic>> iceServers;
  webrtc.RTCPeerConnection? _pc;
  webrtc.MediaStream? _localStream;
  Future<webrtc.RTCPeerConnection>? _pcFuture;
  final _connectionStateController =
      StreamController<CallConnectionState>.broadcast();
  final _iceCandidateController =
      StreamController<IceCandidateData>.broadcast();

  FlutterWebrtcCallEngine({required this.iceServers});

  @override
  Stream<CallConnectionState> get connectionState =>
      _connectionStateController.stream;
  @override
  Stream<IceCandidateData> get localIceCandidates =>
      _iceCandidateController.stream;

  /// Returns the single `RTCPeerConnection` for this call attempt,
  /// creating it (once) on first call. Every caller -- `createOffer`/
  /// `createAnswer`, and every `addRemoteIceCandidate` for a trickled
  /// candidate that happens to arrive over signaling while one of those is
  /// still mid-flight -- must await the exact same in-flight creation
  /// rather than each independently seeing `_pc == null` and racing to
  /// create a *second* `RTCPeerConnection` plus a second `getUserMedia`
  /// microphone capture (Plan 5 review IMPORTANT-1 fix). Caching the
  /// `Future` itself, not just its eventual result in [_pc], is what
  /// closes that window: every reentrant call between the first call and
  /// its completion is handed the exact same pending `Future` instead of
  /// re-running the body below.
  Future<webrtc.RTCPeerConnection> _ensurePeerConnection() =>
      _pcFuture ??= _createPeerConnection();

  Future<webrtc.RTCPeerConnection> _createPeerConnection() async {
    final pc = await webrtc.createPeerConnection({'iceServers': iceServers});
    pc.onConnectionState = (state) =>
        _connectionStateController.add(_mapConnectionState(state));
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return; // end-of-candidates marker
      _iceCandidateController.add(
        IceCandidateData(c.candidate!, c.sdpMid ?? '', c.sdpMLineIndex ?? 0),
      );
    };
    _localStream = await webrtc.navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    for (final track in _localStream!.getAudioTracks()) {
      await pc.addTrack(track, _localStream!);
    }
    _pc = pc;
    return pc;
  }

  @override
  Future<LocalSessionDescription> createOffer() async {
    final pc = await _ensurePeerConnection();
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    return LocalSessionDescription(offer.sdp ?? '', 'offer');
  }

  @override
  Future<LocalSessionDescription> createAnswer(String remoteOfferSdp) async {
    final pc = await _ensurePeerConnection();
    await pc.setRemoteDescription(
      webrtc.RTCSessionDescription(remoteOfferSdp, 'offer'),
    );
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return LocalSessionDescription(answer.sdp ?? '', 'answer');
  }

  @override
  Future<void> acceptAnswer(String remoteAnswerSdp) async {
    final pc = await _ensurePeerConnection();
    await pc.setRemoteDescription(
      webrtc.RTCSessionDescription(remoteAnswerSdp, 'answer'),
    );
  }

  @override
  Future<void> addRemoteIceCandidate(IceCandidateData candidate) async {
    final pc = await _ensurePeerConnection();
    await pc.addCandidate(
      webrtc.RTCIceCandidate(
        candidate.candidate,
        candidate.sdpMid,
        candidate.sdpMLineIndex,
      ),
    );
  }

  @override
  Future<void> setMuted(bool muted) async {
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> dispose() async {
    await _localStream?.dispose();
    await _pc?.close();
    await _connectionStateController.close();
    await _iceCandidateController.close();
  }

  CallConnectionState _mapConnectionState(
    webrtc.RTCPeerConnectionState state,
  ) => switch (state) {
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateNew =>
      CallConnectionState.newConnection,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
      CallConnectionState.connecting,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
      CallConnectionState.connected,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
      CallConnectionState.failed,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
      CallConnectionState.disconnected,
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
      CallConnectionState.closed,
  };
}
