// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

/// Roadmap #12 — the badge half, done the ownerless way.
///
/// A formal NIP-58 badge is minted by an *awarding issuer*, which is the same
/// central authority the whole design does without. So the badge a passenger
/// sees is not awarded to a driver by anyone — it is *derived* from the paired
/// trip receipts the network already carries, by the same [computeReputation]
/// that ranks offers. [reputationTier] turns that computed reputation into the
/// one word a screen can show, and these tests pin what that word is.
void main() {
  Reputation rep({
    int paired = 0,
    double avg = 0,
    double weight = 0,
    int distinct = 0,
  }) =>
      Reputation(paired, avg, weight, distinctCounterpartyCount: distinct);

  test('no paired receipts reads as none', () {
    expect(reputationTier(rep()), ReputationTier.none);
  });

  test('a little paired history from few riders reads as newcomer', () {
    expect(
      reputationTier(rep(paired: 2, avg: 5, distinct: 2)),
      ReputationTier.newcomer,
    );
  });

  test('history from enough distinct riders reads as established', () {
    expect(
      reputationTier(rep(
        paired: 40,
        avg: 4.8,
        distinct: kEstablishedDistinctCounterparties,
      )),
      ReputationTier.established,
    );
  });

  test('the count that matters is distinct riders, not raw trips', () {
    // Many trips, but all with the same one rider — cheap to fake, so it must
    // NOT reach established on trip count alone.
    expect(
      reputationTier(rep(paired: 99, avg: 5, distinct: 1)),
      ReputationTier.newcomer,
    );
  });

  test('a viewer who personally trusts the subject sees trusted', () {
    expect(
      reputationTier(rep(paired: 40, avg: 4.8, distinct: 9),
          viewerTrusts: true),
      ReputationTier.trusted,
    );
  });

  test('explicit trust outranks a thin computed history', () {
    // The viewer ticked "I trust this driver": a deliberate human judgment
    // outranks whatever the receipts do or do not yet show.
    expect(
      reputationTier(rep(paired: 1, avg: 5, distinct: 1), viewerTrusts: true),
      ReputationTier.trusted,
    );
  });
}
