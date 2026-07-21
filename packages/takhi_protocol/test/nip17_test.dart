// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

void main() {
  final sender = generateKeyPair(List<int>.filled(32, 41));
  final recipient = generateKeyPair(List<int>.filled(32, 42));
  final ephemeral = generateKeyPair(List<int>.filled(32, 43));
  final eve = generateKeyPair(List<int>.filled(32, 44));

  NostrEvent wrapForRecipient() => nip17Wrap(
        senderPrivHex: sender.privateHex,
        recipientPubHex: recipient.publicHex,
        rumorKind: 14,
        content: 'Санал: 5000₮, 4 минутад ирнэ',
        now: 1700000000,
        ephemeralKeyPair: ephemeral,
        wrapCreatedAt: 1699950000,
        sealNonce32: List<int>.filled(32, 1),
        sealAuxRand: List<int>.filled(32, 2),
        wrapNonce32: List<int>.filled(32, 3),
        wrapAuxRand: List<int>.filled(32, 4),
      );

  test('wrap hides the real sender and content behind an ephemeral key', () {
    final wrap = wrapForRecipient();
    expect(wrap.kind, kKindGiftWrap);
    expect(wrap.pubkey, ephemeral.publicHex);
    expect(wrap.pubkey, isNot(sender.publicHex));
    expect(wrap.tags, [
      ['p', recipient.publicHex]
    ]);
    expect(wrap.content.contains('5000'), isFalse);
  });

  test('unwrap recovers the rumor and the real sender', () {
    final wrap = wrapForRecipient();
    final unwrapped = nip17Unwrap(wrap, recipient.privateHex);
    expect(unwrapped.senderPubkey, sender.publicHex);
    expect(unwrapped.rumor.kind, 14);
    expect(unwrapped.rumor.content, 'Санал: 5000₮, 4 минутад ирнэ');
    expect(unwrapped.rumor.pubkey, sender.publicHex);
    expect(unwrapped.rumor.sig, isNull);
  });

  test('someone other than the tagged recipient cannot unwrap', () {
    final wrap = wrapForRecipient();
    expect(() => nip17Unwrap(wrap, eve.privateHex), throwsException);
  });

  test(
      'rejects a forged wrap whose inner rumor pubkey does not match the '
      'seal signer (spoofed sender)', () {
    // Mallory seals a rumor that CLAIMS to be from the victim, but signs
    // the seal with her own key -- nip17Unwrap must catch the mismatch
    // rather than trusting the rumor's self-reported pubkey.
    final mallory = generateKeyPair(List<int>.filled(32, 45));
    final victim = generateKeyPair(List<int>.filled(32, 46));
    final forgedRumor = buildRumor(
      pubkey: victim.publicHex,
      createdAt: 1,
      kind: 14,
      content: 'жинхэнэ биш',
    );
    final sealedByMallory = sealRumor(
      forgedRumor,
      mallory.privateHex,
      recipient.publicHex,
      now: 1,
      nonce32: List<int>.filled(32, 5),
      auxRand: List<int>.filled(32, 6),
    );
    final forgedWrap = giftWrap(
      sealedByMallory,
      recipient.publicHex,
      randomizedCreatedAt: 1,
      ephemeralKeyPair: ephemeral,
      nonce32: List<int>.filled(32, 7),
      auxRand: List<int>.filled(32, 8),
    );
    expect(() => nip17Unwrap(forgedWrap, recipient.privateHex),
        throwsFormatException);
  });

  test(
      'wrapCreatedAt defaults to a randomized past timestamp within the '
      'window when omitted', () {
    final wrap = nip17Wrap(
      senderPrivHex: sender.privateHex,
      recipientPubHex: recipient.publicHex,
      rumorKind: 14,
      content: 'x',
      now: 2000000000,
      ephemeralKeyPair: ephemeral,
      sealNonce32: List<int>.filled(32, 1),
      sealAuxRand: List<int>.filled(32, 2),
      wrapNonce32: List<int>.filled(32, 3),
      wrapAuxRand: List<int>.filled(32, 4),
    );
    expect(wrap.createdAt, lessThanOrEqualTo(2000000000));
    expect(wrap.createdAt,
        greaterThanOrEqualTo(2000000000 - kGiftWrapRandomizationWindowSeconds));
  });
}
