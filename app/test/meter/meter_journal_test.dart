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
}
