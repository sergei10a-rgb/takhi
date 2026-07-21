// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

TripReceipt _receipt({
  required String tripId,
  required String author,
  required String counterparty,
}) =>
    TripReceipt(
      tripId: tripId,
      counterpartyPubkey: counterparty,
      role: 'passenger',
      ratingStars: 5,
      distanceMeters: 1000,
      durationSeconds: 300,
      priceMnt: 5000,
      comment: '',
      authorPubkey: author,
      createdAt: 1,
    );

void main() {
  test('isTripReceiptPaired is true when the reciprocal receipt is '
      'present', () {
    final mine = _receipt(tripId: 't1', author: 'A', counterparty: 'B');
    final theirs = _receipt(tripId: 't1', author: 'B', counterparty: 'A');
    expect(isTripReceiptPaired(mine: mine, candidates: [theirs]), isTrue);
  });

  test('isTripReceiptPaired is false when trip ids differ', () {
    final mine = _receipt(tripId: 't1', author: 'A', counterparty: 'B');
    final theirs = _receipt(tripId: 't2', author: 'B', counterparty: 'A');
    expect(isTripReceiptPaired(mine: mine, candidates: [theirs]), isFalse);
  });

  test('isTripReceiptPaired is false when the candidate points at someone '
      'else', () {
    final mine = _receipt(tripId: 't1', author: 'A', counterparty: 'B');
    final unrelated = _receipt(tripId: 't1', author: 'B', counterparty: 'C');
    expect(isTripReceiptPaired(mine: mine, candidates: [unrelated]), isFalse);
  });

  test('isTripReceiptPaired is false for an empty candidate list', () {
    final mine = _receipt(tripId: 't1', author: 'A', counterparty: 'B');
    expect(isTripReceiptPaired(mine: mine, candidates: []), isFalse);
  });

  test('isTripReceiptPaired finds the match among unrelated candidates',
      () {
    final mine = _receipt(tripId: 't1', author: 'A', counterparty: 'B');
    final theirs = _receipt(tripId: 't1', author: 'B', counterparty: 'A');
    final noise = _receipt(tripId: 't9', author: 'X', counterparty: 'Y');
    expect(
      isTripReceiptPaired(mine: mine, candidates: [noise, theirs]),
      isTrue,
    );
  });
}
