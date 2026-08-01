// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:takhi/meter/meter_journal.dart';

void main() {
  test(
    'InMemoryMeterJournalStore appends and lists entries in order',
    () async {
      final store = InMemoryMeterJournalStore();
      expect(await store.loadAll(), isEmpty);
      await store.append(
        const MeterTripEntry(
          startedAt: 1,
          endedAt: 100,
          distanceMeters: 2000,
          fareMnt: 3000,
        ),
      );
      await store.append(
        const MeterTripEntry(
          startedAt: 200,
          endedAt: 260,
          distanceMeters: 500,
          fareMnt: 800,
        ),
      );
      final all = await store.loadAll();
      expect(all.length, 2);
      expect(all.first.fareMnt, 3000);
      expect(all.last.fareMnt, 800);
    },
  );

  test(
    'SharedPreferencesMeterJournalStore persists JSON-encoded entries',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesMeterJournalStore(
        SharedPreferences.getInstance,
      );
      await store.append(
        const MeterTripEntry(
          startedAt: 1,
          endedAt: 90,
          distanceMeters: 1500,
          fareMnt: 2200,
        ),
      );
      final all = await store.loadAll();
      expect(all.length, 1);
      expect(all.first.distanceMeters, 1500);
      expect(all.first.fareMnt, 2200);
    },
  );

  test(
    'deleting takes out the run it was asked for and leaves the rest',
    () async {
      final store = InMemoryMeterJournalStore();
      await store.append(
        const MeterTripEntry(
          startedAt: 100,
          endedAt: 400,
          distanceMeters: 2000,
          fareMnt: 3000,
        ),
      );
      await store.append(
        const MeterTripEntry(
          startedAt: 900,
          endedAt: 1200,
          distanceMeters: 500,
          fareMnt: 800,
        ),
      );

      await store.delete(100);

      final left = await store.loadAll();
      expect(left, hasLength(1));
      expect(left.single.startedAt, 900);
      expect(left.single.fareMnt, 800);
    },
  );

  test(
    'deleting a run that is not there changes nothing and does not '
    'throw -- a journal already deleted from twice is not an error',
    () async {
      final store = InMemoryMeterJournalStore();
      await store.append(
        const MeterTripEntry(
          startedAt: 100,
          endedAt: 400,
          distanceMeters: 2000,
          fareMnt: 3000,
        ),
      );

      await store.delete(999);
      await store.delete(100);
      await store.delete(100);

      expect(await store.loadAll(), isEmpty);
    },
  );

  test('a deletion survives the shared_preferences round trip', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesMeterJournalStore(
      SharedPreferences.getInstance,
    );
    await store.append(
      const MeterTripEntry(
        startedAt: 100,
        endedAt: 400,
        distanceMeters: 2000,
        fareMnt: 3000,
      ),
    );
    await store.append(
      const MeterTripEntry(
        startedAt: 900,
        endedAt: 1200,
        distanceMeters: 500,
        fareMnt: 800,
      ),
    );

    await store.delete(100);

    // Re-read through a *new* store over the same preferences, so this is
    // the encoded journal answering rather than anything held in memory.
    final reopened = SharedPreferencesMeterJournalStore(
      SharedPreferences.getInstance,
    );
    final left = await reopened.loadAll();
    expect(left, hasLength(1));
    expect(left.single.startedAt, 900);
  });

  test('a journal entry records the fare breakdown, not just the total', () {
    const entry = MeterTripEntry(
      startedAt: 1,
      endedAt: 900,
      distanceMeters: 4000,
      fareMnt: 4600,
      waitingFareMnt: 600,
      waitingSeconds: 120,
      pausedSeconds: 45,
    );
    final round = MeterTripEntry.fromJson(entry.toJson());
    expect(round.fareMnt, 4600);
    expect(round.waitingFareMnt, 600);
    expect(round.waitingSeconds, 120);
    expect(round.pausedSeconds, 45);
    // Never stored: derived, so the two rows can never disagree with the
    // total a driver was paid.
    expect(round.distanceFareMnt, 4000);
  });

  test('a journal entry written before waiting fares existed still loads, '
      'and reads as a trip that was all distance and no waiting', () {
    final legacy = MeterTripEntry.fromJson(const {
      'startedAt': 1,
      'endedAt': 90,
      'distanceMeters': 1500,
      'fareMnt': 2200,
    });
    expect(legacy.fareMnt, 2200);
    expect(legacy.waitingFareMnt, 0);
    expect(legacy.waitingSeconds, 0);
    expect(legacy.pausedSeconds, 0);
    expect(legacy.distanceFareMnt, 2200);
  });

  test('a journal entry records the trip-duration fare as its own row', () {
    const entry = MeterTripEntry(
      startedAt: 1,
      endedAt: 901,
      distanceMeters: 4000,
      // 4000 distance + 600 stopped-time + 900 duration.
      fareMnt: 5500,
      waitingFareMnt: 600,
      waitingSeconds: 120,
      durationFareMnt: 900,
      pausedSeconds: 45,
    );
    final round = MeterTripEntry.fromJson(entry.toJson());
    expect(round.durationFareMnt, 900);
    expect(round.waitingFareMnt, 600);
    expect(round.fareMnt, 5500);
  });

  // The regression this file exists to catch from now on. `distanceFareMnt`
  // is what is left of the total once every time-based charge is taken off
  // it; a duration fare that is not subtracted lands in the distance row,
  // where it reads as kilometres the car never drove.
  test('distanceFareMnt subtracts the duration fare as well as the waiting '
      'fare, so the three rows still add up to the total', () {
    const entry = MeterTripEntry(
      startedAt: 1,
      endedAt: 901,
      distanceMeters: 4000,
      fareMnt: 5500,
      waitingFareMnt: 600,
      waitingSeconds: 120,
      durationFareMnt: 900,
    );
    expect(entry.distanceFareMnt, 4000);
    expect(
      entry.distanceFareMnt + entry.waitingFareMnt + entry.durationFareMnt,
      entry.fareMnt,
    );
  });

  // A driver who charges both the jam rate and the duration rate bills
  // stopped time twice on purpose (see `computeDurationFareMnt`). The
  // journal records that as it happened rather than netting it off: the
  // history has to match the money, and the overlap is the driver's own
  // pricing decision, not a bookkeeping error for this class to correct.
  test('an entry whose driver charged both time rates keeps both figures, '
      'overlap and all', () {
    const entry = MeterTripEntry(
      startedAt: 1,
      endedAt: 601,
      distanceMeters: 2000,
      // 2000 distance + 500 stopped-time + 600 duration; the 100 stopped
      // seconds are inside the 600-second duration and are billed twice.
      fareMnt: 3100,
      waitingFareMnt: 500,
      waitingSeconds: 100,
      durationFareMnt: 600,
    );
    expect(entry.waitingFareMnt, 500);
    expect(entry.durationFareMnt, 600);
    expect(entry.distanceFareMnt, 2000);
  });

  test('a journal entry written before duration fares existed still loads, '
      'and reads as a trip whose duration was never charged for', () {
    final legacy = MeterTripEntry.fromJson(const {
      'startedAt': 1,
      'endedAt': 900,
      'distanceMeters': 3000,
      'fareMnt': 4000,
      'waitingFareMnt': 400,
      'waitingSeconds': 80,
      'pausedSeconds': 10,
    });
    expect(legacy.durationFareMnt, 0);
    // The breakdown an older entry already carried is untouched by the
    // migration of the field it does not have.
    expect(legacy.waitingFareMnt, 400);
    expect(legacy.distanceFareMnt, 3600);
  });
}
