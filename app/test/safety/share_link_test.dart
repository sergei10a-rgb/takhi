// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/safety/share_link.dart';

void main() {
  test('buildShareUrl embeds k/trip/relays in the fragment, not the path', () {
    final url = buildShareUrl(
      baseUrl: 'https://example.org/share/',
      shareKeyHex: 'ab' * 32,
      tripId: 'trip-1',
      relayUrls: ['wss://a', 'wss://b'],
    );
    expect(url, startsWith('https://example.org/share/#'));
    // The path portion (before '#') must not contain the key or trip id.
    final path = url.split('#').first;
    expect(path.contains('ab' * 32), isFalse);
    expect(path.contains('trip-1'), isFalse);
  });

  test('buildShareUrl normalizes a baseUrl missing a trailing slash', () {
    final url = buildShareUrl(
      baseUrl: 'https://example.org/share',
      shareKeyHex: 'cd' * 32,
      tripId: 'trip-1',
      relayUrls: ['wss://a'],
    );
    expect(url, startsWith('https://example.org/share/#'));
  });

  test('parseShareFragment reverses buildShareUrl exactly', () {
    final url = buildShareUrl(
      baseUrl: 'https://example.org/share/',
      shareKeyHex: 'ef' * 32,
      tripId: 'trip-with spaces',
      relayUrls: ['wss://relay.one', 'wss://relay.two'],
    );
    final fragment = url.split('#')[1];
    final parsed = parseShareFragment(fragment);
    expect(parsed.shareKeyHex, 'ef' * 32);
    expect(parsed.tripId, 'trip-with spaces');
    expect(parsed.relayUrls, ['wss://relay.one', 'wss://relay.two']);
  });

  test('parseShareFragment throws on a fragment missing a required part', () {
    expect(
      () => parseShareFragment('k=abc&trip=t1'), // no relays
      throwsFormatException,
    );
  });
}
