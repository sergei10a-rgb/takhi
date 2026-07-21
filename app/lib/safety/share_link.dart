// SPDX-License-Identifier: AGPL-3.0-or-later

/// Builds the shareable "watch this trip live" URL (spec §10
/// "Аялал-хуваалцах вэб"): a link to a static, server-less HTML page
/// (`docs/share/index.html`, Task 8 Step 6) that reads straight from the
/// public Nostr relay network with no author infrastructure in the loop.
/// [shareKeyHex] is a throwaway keypair's *private* key
/// (`ShareSession.shareKeyPair.privateHex`) -- see this task's own doc
/// comment for exactly why putting a private key in a URL fragment is
/// safe here (it never leaves the browser that opens the link).
String buildShareUrl({
  required String baseUrl,
  required String shareKeyHex,
  required String tripId,
  required List<String> relayUrls,
}) {
  final relaysParam = relayUrls.map(Uri.encodeComponent).join(',');
  final fragment =
      'k=${Uri.encodeComponent(shareKeyHex)}&trip=${Uri.encodeComponent(tripId)}&relays=$relaysParam';
  final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  return '$normalizedBase#$fragment';
}

/// Reverses [buildShareUrl]'s fragment encoding. `docs/share/index.html`
/// mirrors this same three-field parse independently in plain JS (it
/// cannot depend on this Dart function) -- kept here for the app's own
/// "does my link actually round-trip" tests and any future in-app
/// "preview my share link" feature.
({String shareKeyHex, String tripId, List<String> relayUrls})
parseShareFragment(String fragment) {
  final clean = fragment.startsWith('#') ? fragment.substring(1) : fragment;
  final params = Uri.splitQueryString(clean);
  final k = params['k'];
  final trip = params['trip'];
  final relays = params['relays'];
  if (k == null || trip == null || relays == null || relays.isEmpty) {
    throw const FormatException('share fragment missing k/trip/relays');
  }
  return (shareKeyHex: k, tripId: trip, relayUrls: relays.split(','));
}

/// Where the static share page is mirrored (spec §10: GitHub Pages or any
/// mirror). `docs/share/` is deliberately placed under `docs/` so
/// "serve Pages from /docs on main" needs zero extra CI/build config --
/// see FORKING.md (Task 10) for pointing this at a fork's own mirror. Open
/// protocol question (see plan Self-Review), same honesty pattern as Plan
/// 4's `kTakhiAppDownloadUrl`.
const String kShareBaseUrl = 'https://takhi-app.github.io/takhi/share/';
