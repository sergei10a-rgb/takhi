// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:takhi/call/call_engine.dart';

/// Deterministic [CallEngine] test double -- scripted SDP strings and
/// manually-triggerable state via [emitConnectionState]/
/// [emitLocalIceCandidate], mirroring [FakeLocationSource]'s `emit()` role
/// for GPS (Plan 4) exactly. `FlutterWebrtcCallEngine` itself is
/// intentionally left without a dedicated unit test (see its doc comment).
class FakeCallEngine implements CallEngine {
  String nextOfferSdp = 'fake-offer-sdp';
  String nextAnswerSdp = 'fake-answer-sdp';
  final List<String> acceptedAnswers = [];
  final List<IceCandidateData> addedRemoteCandidates = [];
  bool? lastMuted;
  bool disposed = false;

  final _connectionStateController =
      StreamController<CallConnectionState>.broadcast();
  final _iceCandidateController =
      StreamController<IceCandidateData>.broadcast();

  @override
  Stream<CallConnectionState> get connectionState =>
      _connectionStateController.stream;
  @override
  Stream<IceCandidateData> get localIceCandidates =>
      _iceCandidateController.stream;

  void emitConnectionState(CallConnectionState s) =>
      _connectionStateController.add(s);
  void emitLocalIceCandidate(IceCandidateData c) =>
      _iceCandidateController.add(c);

  @override
  Future<LocalSessionDescription> createOffer() async =>
      LocalSessionDescription(nextOfferSdp, 'offer');

  @override
  Future<LocalSessionDescription> createAnswer(String remoteOfferSdp) async =>
      LocalSessionDescription(nextAnswerSdp, 'answer');

  @override
  Future<void> acceptAnswer(String remoteAnswerSdp) async =>
      acceptedAnswers.add(remoteAnswerSdp);

  @override
  Future<void> addRemoteIceCandidate(IceCandidateData candidate) async =>
      addedRemoteCandidates.add(candidate);

  @override
  Future<void> setMuted(bool muted) async => lastMuted = muted;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _connectionStateController.close();
    await _iceCandidateController.close();
  }
}
