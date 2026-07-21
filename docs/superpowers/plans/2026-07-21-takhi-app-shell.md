# Тахь апп — каркас, Nostr relay pool, identity onboarding — Implementation Plan (Plan 2/5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement task-by-task. Steps use checkbox (`- [ ]`).

**Goal:** Stand up the Flutter app "Тахь" — a two-mode (passenger/driver) shell with brand theme, Mongolian+English i18n, a Nostr relay pool (connect to public relays, publish signed events, subscribe by filter), and identity onboarding (generate keypair, 12-word seed backup + restore, secure storage), reaching the first usable screen in < 60 seconds.

**Architecture:** Flutter app under `app/`, depending on the local `takhi_protocol` package (Plan 1) for all crypto/event logic. UI is thin over a set of services (`RelayPool`, `IdentityService`). State via `flutter_riverpod`. The app never talks to any authored server — only public Nostr relays over WebSocket.

**Tech Stack:** Flutter 3.44 / Dart 3.12, `flutter_riverpod`, `web_socket_channel` (relay WS), `flutter_secure_storage` (keys), `go_router` (nav), `flutter_localizations` + ARB (i18n), `takhi_protocol` (path dep). Test: `flutter test` (unit + widget), `integration_test`.

## Global Constraints

- **Depends on `takhi_protocol`** (Plan 1) via path dependency. Public API consumed (exact names): `generateKeyPair()`, `generateMnemonic()`, `privateKeyFromMnemonic(mnemonic, {account})`, `pubkeyFromPrivate(hex)`, `hexToNpub(hex)`, `NostrEvent`, `signEvent(unsigned, privHex, {auxRand})`, `verifyEvent(e)`, `computeEventId(e)`, `nip44Encrypt/Decrypt`, `buildRideRequest(...)`, kind constants `kKindProfile/kKindRideRequest/...`. **Before coding, run `dart pub get` in `app/` and confirm these symbols resolve; if Plan 1 renamed any, adapt imports and note it.**
- **License:** every Dart file starts `// SPDX-License-Identifier: AGPL-3.0-or-later`.
- **No authored server:** relay URLs are public and user-editable. Ship a default list (working values, verified reachable at plan time): `wss://relay.damus.io`, `wss://nos.lol`, `wss://relay.primal.net`, `wss://relay.nostr.band`. App connects to ≥3 concurrently.
- **Brand (from `brand/BRAND.md`):** `--takhi-gold #C99A3C`, `--gold-deep #A67C28`, `--ink #1C1A16`, `--steppe #2E6E5E`, `--paper #F4F1E9`, `--sand #E7DEC9`. App icon = `brand/out/icon_gold_1024.png`. Light + dark themes both first-class.
- **i18n:** Mongolian (`mn`, default) + English (`en`). ALL user-facing strings via ARB — no hardcoded literals in widgets. Mongolian Cyrillic is the primary voice.
- **Identity is a keypair;** no phone number, no account, no server registration. Seed = 12-word BIP-39 (NIP-06).
- **Onboarding budget:** cold start → first interactive screen < 60s (spec §10). No blocking network on first paint.
- **State:** immutable models; Riverpod providers; no global mutable singletons.

---

### Task 1: App scaffold + brand theme + launcher icon

**Files:**
- Create: `app/` via `flutter create` (org `mn.takhi`, project `takhi`, platforms: android, web, windows)
- Create: `app/pubspec.yaml` (deps + assets + path dep on `../packages/takhi_protocol`)
- Create: `app/lib/theme/takhi_theme.dart`
- Create: `app/lib/main.dart`
- Test: `app/test/theme_test.dart`

**Interfaces:**
- Produces: `ThemeData takhiTheme(Brightness b)` with brand ColorScheme; `class TakhiColors` const tokens; `runApp` boots a `MaterialApp` showing a placeholder home.

- [ ] **Step 1: Scaffold**

Run (in repo root):
```bash
export PATH="$PATH:/c/src/flutter/bin"
flutter create --org mn.takhi --project-name takhi --platforms=android,web,windows app
```

- [ ] **Step 2: Write failing theme test**

```dart
// app/test/theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/theme/takhi_theme.dart';

void main() {
  test('light + dark themes expose brand gold as primary', () {
    expect(takhiTheme(Brightness.light).colorScheme.primary,
        const Color(0xFFC99A3C));
    expect(takhiTheme(Brightness.dark).colorScheme.primary,
        const Color(0xFFC99A3C));
    expect(TakhiColors.ink, const Color(0xFF1C1A16));
  });
}
```

- [ ] **Step 3: Run — fails** (`flutter test test/theme_test.dart` → theme undefined).

- [ ] **Step 4: Implement theme + main**

```dart
// app/lib/theme/takhi_theme.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

class TakhiColors {
  static const gold = Color(0xFFC99A3C);
  static const goldDeep = Color(0xFFA67C28);
  static const ink = Color(0xFF1C1A16);
  static const steppe = Color(0xFF2E6E5E);
  static const paper = Color(0xFFF4F1E9);
  static const sand = Color(0xFFE7DEC9);
}

ThemeData takhiTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme(
    brightness: b,
    primary: TakhiColors.gold,
    onPrimary: TakhiColors.ink,
    secondary: TakhiColors.steppe,
    onSecondary: Colors.white,
    surface: dark ? const Color(0xFF211E19) : TakhiColors.paper,
    onSurface: dark ? TakhiColors.paper : TakhiColors.ink,
    error: const Color(0xFF9E3327),
    onError: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'NotoSans', // bundled in Task later; fallback ok now
  );
}
```

```dart
// app/lib/main.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/takhi_theme.dart';

void main() => runApp(const ProviderScope(child: TakhiApp()));

class TakhiApp extends StatelessWidget {
  const TakhiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Тахь',
        theme: takhiTheme(Brightness.light),
        darkTheme: takhiTheme(Brightness.dark),
        home: const Scaffold(body: Center(child: Text('Тахь'))),
      );
}
```

Add to `app/pubspec.yaml` dependencies: `flutter_riverpod: ^2.5.1`, `web_socket_channel: ^3.0.1`, `flutter_secure_storage: ^9.2.2`, `go_router: ^14.2.0`, and:
```yaml
  takhi_protocol:
    path: ../packages/takhi_protocol
```
Under `flutter:` add `assets: [ ../brand/out/icon_gold_1024.png ]` (or copy icon into `app/assets/` — copying is cleaner; do that and reference `assets/icon.png`).

- [ ] **Step 5: Run — passes.** `flutter test test/theme_test.dart` → PASS. Then `flutter analyze` clean.

- [ ] **Step 6: Commit**
```bash
git add app
git commit -m "feat(app): Flutter scaffold + brand theme"
```

---

### Task 2: i18n (mn + en) with ARB

**Files:**
- Create: `app/l10n.yaml`, `app/lib/l10n/app_mn.arb`, `app/lib/l10n/app_en.arb`
- Modify: `app/pubspec.yaml` (flutter_localizations, generate: true)
- Modify: `app/lib/main.dart` (localizationsDelegates, supportedLocales, locale default mn)
- Test: `app/test/l10n_test.dart`

**Interfaces:**
- Produces: generated `AppLocalizations` with keys: `appName`, `passengerMode`, `driverMode`, `createIdentity`, `restoreIdentity`, `seedBackupTitle`, `seedBackupWarning`, `iSavedIt`, `connecting`, `connected`. Mongolian is the default.

- [ ] **Step 1: Failing test**

```dart
// app/test/l10n_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:takhi/l10n/app_localizations.dart';

void main() {
  testWidgets('mn is default and appName is Тахь', (t) async {
    late AppLocalizations l;
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (c) { l = AppLocalizations.of(c)!; return const SizedBox(); }),
    ));
    expect(l.appName, 'Тахь');
    expect(l.localeName, 'mn');
  });
}
```

- [ ] **Step 2: Run — fails** (AppLocalizations not generated).

- [ ] **Step 3: Create ARB + config**

```yaml
# app/l10n.yaml
arb-dir: lib/l10n
template-arb-file: app_mn.arb
output-localization-file: app_localizations.dart
```

```json
// app/lib/l10n/app_mn.arb
{
  "@@locale": "mn",
  "appName": "Тахь",
  "passengerMode": "Зорчигч",
  "driverMode": "Жолооч",
  "createIdentity": "Шинээр эхлэх",
  "restoreIdentity": "Сэргээх",
  "seedBackupTitle": "Нөөц үгсээ хадгал",
  "seedBackupWarning": "Энэ 12 үгийг бичиж хадгал. Утсаа гээвэл зөвхөн эдгээрээр сэргээнэ. Хэнд ч бүү харуул.",
  "iSavedIt": "Хадгаллаа",
  "connecting": "Холбогдож байна…",
  "connected": "Холбогдлоо"
}
```

```json
// app/lib/l10n/app_en.arb
{
  "@@locale": "en",
  "appName": "Тахь",
  "passengerMode": "Passenger",
  "driverMode": "Driver",
  "createIdentity": "Start fresh",
  "restoreIdentity": "Restore",
  "seedBackupTitle": "Back up your recovery words",
  "seedBackupWarning": "Write down these 12 words. If you lose your phone, only these restore you. Never show anyone.",
  "iSavedIt": "I saved it",
  "connecting": "Connecting…",
  "connected": "Connected"
}
```

In `pubspec.yaml` under `flutter:` add `generate: true` and add `flutter_localizations: { sdk: flutter }` to dependencies. Wire delegates in `main.dart` with `locale: const Locale('mn')` default.

- [ ] **Step 4: Generate + run** — `flutter gen-l10n && flutter test test/l10n_test.dart` → PASS.

- [ ] **Step 5: Commit** — `git add app && git commit -m "feat(app): mn/en localization"`

---

### Task 3: IdentityService — create / restore / secure store

**Files:**
- Create: `app/lib/identity/identity_service.dart`
- Create: `app/lib/identity/identity_state.dart` (Riverpod)
- Test: `app/test/identity_service_test.dart`

**Interfaces:**
- Consumes: `takhi_protocol` — `generateMnemonic`, `privateKeyFromMnemonic`, `pubkeyFromPrivate`, `hexToNpub`.
- Produces:
  - `class Identity { final String privHex; final String pubHex; String get npub; }`
  - `abstract class KeyStore { Future<void> write(String privHex); Future<String?> read(); Future<void> clear(); }` — with `SecureKeyStore` (flutter_secure_storage) and `InMemoryKeyStore` (tests).
  - `class IdentityService { IdentityService(this._store); Future<Identity> createNew(); Future<Identity> restore(String mnemonic); Future<Identity?> load(); Future<void> signOut(); (String mnemonic, Identity) createNewWithMnemonic(); }`

- [ ] **Step 1: Failing test**

```dart
// app/test/identity_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/identity/identity_service.dart';

void main() {
  test('createNew persists and load returns same identity', () async {
    final store = InMemoryKeyStore();
    final svc = IdentityService(store);
    final id = await svc.createNew();
    expect(id.pubHex.length, 64);
    expect(id.npub.startsWith('npub1'), isTrue);
    final loaded = await svc.load();
    expect(loaded!.pubHex, id.pubHex);
  });

  test('restore from known mnemonic yields NIP-06 pubkey', () async {
    final svc = IdentityService(InMemoryKeyStore());
    final id = await svc.restore(
        'leader monkey parrot ring guide accuse powder nine wheel kick hobby suspect');
    expect(id.privHex,
        '7f7ff03d123792d6ac594bfa67bf6d0c0ab55b6b1fdb6249303fe861f1ccba9a');
  });

  test('signOut clears store', () async {
    final store = InMemoryKeyStore();
    final svc = IdentityService(store);
    await svc.createNew();
    await svc.signOut();
    expect(await svc.load(), isNull);
  });
}
```

- [ ] **Step 2: Run — fails.**

- [ ] **Step 3: Implement**

```dart
// app/lib/identity/identity_service.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

class Identity {
  final String privHex;
  final String pubHex;
  const Identity(this.privHex, this.pubHex);
  String get npub => hexToNpub(pubHex);
}

abstract class KeyStore {
  Future<void> write(String privHex);
  Future<String?> read();
  Future<void> clear();
}

class InMemoryKeyStore implements KeyStore {
  String? _v;
  @override Future<void> write(String p) async => _v = p;
  @override Future<String?> read() async => _v;
  @override Future<void> clear() async => _v = null;
}

class SecureKeyStore implements KeyStore {
  static const _k = 'takhi_priv';
  final _s = const FlutterSecureStorage();
  @override Future<void> write(String p) => _s.write(key: _k, value: p);
  @override Future<String?> read() => _s.read(key: _k);
  @override Future<void> clear() => _s.delete(key: _k);
}

class IdentityService {
  final KeyStore _store;
  IdentityService(this._store);

  Future<Identity> createNew() async {
    final (_, id) = await createNewWithMnemonic();
    return id;
  }

  Future<(String, Identity)> createNewWithMnemonic() async {
    final mnemonic = generateMnemonic();
    final id = _fromMnemonic(mnemonic);
    await _store.write(id.privHex);
    return (mnemonic, id);
  }

  Future<Identity> restore(String mnemonic) async {
    final id = _fromMnemonic(mnemonic.trim());
    await _store.write(id.privHex);
    return id;
  }

  Future<Identity?> load() async {
    final priv = await _store.read();
    if (priv == null) return null;
    return Identity(priv, pubkeyFromPrivate(priv));
  }

  Future<void> signOut() => _store.clear();

  Identity _fromMnemonic(String m) {
    final priv = privateKeyFromMnemonic(m);
    return Identity(priv, pubkeyFromPrivate(priv));
  }
}
```

```dart
// app/lib/identity/identity_state.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'identity_service.dart';

final keyStoreProvider = Provider<KeyStore>((_) => SecureKeyStore());
final identityServiceProvider =
    Provider<IdentityService>((ref) => IdentityService(ref.read(keyStoreProvider)));
final currentIdentityProvider = FutureProvider<Identity?>(
    (ref) => ref.read(identityServiceProvider).load());
```

- [ ] **Step 4: Run — passes** (`flutter test test/identity_service_test.dart`).

- [ ] **Step 5: Commit** — `git add app && git commit -m "feat(app): identity service (create/restore/secure store)"`

---

### Task 4: RelayPool — connect, publish, subscribe

**Files:**
- Create: `app/lib/nostr/relay_pool.dart`
- Create: `app/lib/nostr/relay_filter.dart`
- Test: `app/test/relay_pool_test.dart`

**Interfaces:**
- Consumes: `NostrEvent`, `computeEventId`, `verifyEvent`, `signEvent`.
- Produces:
  - `class RelayFilter { final List<int>? kinds; final List<String>? authors; final Map<String,List<String>> tagFilters; final int? since; final int? limit; Map<String,dynamic> toJson(); }`
  - `abstract class RelaySocket { Stream<String> get messages; void send(String data); Future<void> close(); }` (real = `WsRelaySocket`; test = `FakeRelaySocket`).
  - `class RelayPool { RelayPool(this.urls, {RelaySocket Function(String)? connect}); Future<void> connectAll(); Future<void> publish(NostrEvent e); Stream<NostrEvent> subscribe(RelayFilter f); Set<String> get connectedUrls; void dispose(); }`
  - Dedupe events by id across relays; drop events failing `verifyEvent`.

- [ ] **Step 1: Failing test (with fake socket, no network)**

```dart
// app/test/relay_pool_test.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/nostr/relay_pool.dart';
import 'package:takhi_protocol/takhi_protocol.dart';

class FakeRelaySocket implements RelaySocket {
  final _c = StreamController<String>.broadcast();
  final sent = <String>[];
  @override Stream<String> get messages => _c.stream;
  @override void send(String d) => sent.add(d);
  @override Future<void> close() async => _c.close();
  void emit(String s) => _c.add(s);
}

void main() {
  test('publish sends EVENT frame to all relays', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a', 'wss://b'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final kp = generateKeyPair(List<int>.filled(32, 9));
    final e = signEvent(
        NostrEvent(pubkey: kp.publicHex, createdAt: 1, kind: 1, tags: [], content: 'hi'),
        kp.privateHex, auxRand: List<int>.filled(32, 0));
    await pool.publish(e);
    expect(sockets['wss://a']!.sent.first.contains('"EVENT"'), isTrue);
    expect(sockets['wss://b']!.sent.length, 1);
  });

  test('subscribe yields verified events, deduped across relays', () async {
    final sockets = <String, FakeRelaySocket>{};
    final pool = RelayPool(['wss://a', 'wss://b'],
        connect: (u) => sockets[u] = FakeRelaySocket());
    await pool.connectAll();
    final kp = generateKeyPair(List<int>.filled(32, 5));
    final e = signEvent(
        NostrEvent(pubkey: kp.publicHex, createdAt: 2, kind: 1, tags: [], content: 'x'),
        kp.privateHex, auxRand: List<int>.filled(32, 0));
    final got = <NostrEvent>[];
    final sub = pool.subscribe(RelayFilter(kinds: [1])).listen(got.add);
    final frame = jsonEncode(['EVENT', 'sub', e.toJson()]);
    sockets['wss://a']!.emit(frame);
    sockets['wss://b']!.emit(frame); // same event from 2nd relay
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(got.length, 1); // deduped
    expect(got.first.content, 'x');
    await sub.cancel();
  });
}
```

- [ ] **Step 2: Run — fails.**

- [ ] **Step 3: Implement** (WebSocket real impl + pool logic)

```dart
// app/lib/nostr/relay_filter.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
class RelayFilter {
  final List<int>? kinds;
  final List<String>? authors;
  final Map<String, List<String>> tagFilters; // e.g. {'#g': ['u9huf6']}
  final int? since;
  final int? limit;
  const RelayFilter({this.kinds, this.authors, this.tagFilters = const {}, this.since, this.limit});
  Map<String, dynamic> toJson() => {
        if (kinds != null) 'kinds': kinds,
        if (authors != null) 'authors': authors,
        for (final e in tagFilters.entries) e.key: e.value,
        if (since != null) 'since': since,
        if (limit != null) 'limit': limit,
      };
}
```

```dart
// app/lib/nostr/relay_pool.dart
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:takhi_protocol/takhi_protocol.dart';
import 'relay_filter.dart';
export 'relay_filter.dart';

abstract class RelaySocket {
  Stream<String> get messages;
  void send(String data);
  Future<void> close();
}

class WsRelaySocket implements RelaySocket {
  final WebSocketChannel _ch;
  WsRelaySocket(String url) : _ch = WebSocketChannel.connect(Uri.parse(url));
  @override Stream<String> get messages => _ch.stream.map((e) => e as String);
  @override void send(String data) => _ch.sink.add(data);
  @override Future<void> close() => _ch.sink.close();
}

int _subCounter = 0;

class RelayPool {
  final List<String> urls;
  final RelaySocket Function(String) _connect;
  final Map<String, RelaySocket> _sockets = {};
  final Set<String> _seenEventIds = {};

  RelayPool(this.urls, {RelaySocket Function(String)? connect})
      : _connect = connect ?? ((u) => WsRelaySocket(u));

  Set<String> get connectedUrls => _sockets.keys.toSet();

  Future<void> connectAll() async {
    for (final u in urls) {
      try {
        _sockets[u] = _connect(u);
      } catch (_) {/* skip unreachable relay */}
    }
  }

  Future<void> publish(NostrEvent e) async {
    final frame = jsonEncode(['EVENT', e.toJson()]);
    for (final s in _sockets.values) {
      s.send(frame);
    }
  }

  Stream<NostrEvent> subscribe(RelayFilter f) {
    final subId = 'takhi-${_subCounter++}';
    final controller = StreamController<NostrEvent>.broadcast();
    final subs = <StreamSubscription>[];
    final reqFrame = jsonEncode(['REQ', subId, f.toJson()]);

    for (final s in _sockets.values) {
      s.send(reqFrame);
      subs.add(s.messages.listen((raw) {
        try {
          final decoded = jsonDecode(raw) as List;
          if (decoded.isEmpty || decoded[0] != 'EVENT') return;
          if (decoded.length < 3 || decoded[1] != subId) return;
          final m = decoded[2] as Map<String, dynamic>;
          final ev = NostrEvent(
            id: m['id'] as String?,
            pubkey: m['pubkey'] as String,
            createdAt: m['created_at'] as int,
            kind: m['kind'] as int,
            tags: (m['tags'] as List)
                .map((t) => (t as List).map((x) => x as String).toList())
                .toList(),
            content: m['content'] as String,
            sig: m['sig'] as String?,
          );
          if (ev.id == null || _seenEventIds.contains(ev.id)) return;
          if (!verifyEvent(ev)) return;
          _seenEventIds.add(ev.id!);
          controller.add(ev);
        } catch (_) {/* malformed frame, ignore */}
      }));
    }
    controller.onCancel = () async {
      for (final s in _sockets.values) {
        s.send(jsonEncode(['CLOSE', subId]));
      }
      for (final sub in subs) {
        await sub.cancel();
      }
    };
    return controller.stream;
  }

  void dispose() {
    for (final s in _sockets.values) {
      s.close();
    }
    _sockets.clear();
  }
}
```

> `NostrEvent.toJson()` (Plan 1 Task 4) omits null `id`/`sig` only if defined so; confirm it includes `id`,`pubkey`,`created_at`,`kind`,`tags`,`content`,`sig`. If Plan 1's `toJson` differs, adapt the publish frame to emit the NIP-01 shape.

- [ ] **Step 4: Run — passes** (`flutter test test/relay_pool_test.dart`).

- [ ] **Step 5: Commit** — `git add app && git commit -m "feat(app): Nostr relay pool (publish/subscribe/dedupe/verify)"`

---

### Task 5: Onboarding UI — mode pick, create/restore, seed backup

**Files:**
- Create: `app/lib/onboarding/onboarding_page.dart`
- Create: `app/lib/onboarding/seed_backup_page.dart`
- Create: `app/lib/onboarding/restore_page.dart`
- Create: `app/lib/router.dart`
- Modify: `app/lib/main.dart` (use router, wire providers)
- Test: `app/test/onboarding_widget_test.dart`

**Interfaces:**
- Consumes: `identityServiceProvider`, `AppLocalizations`, `takhiTheme`.
- Produces: a `GoRouter` with routes `/` (onboarding: gold brand screen with mode toggle + Start/Restore), `/seed` (shows 12 words + warning + "I saved it"), `/restore` (paste mnemonic), `/home` (placeholder two-mode home). Creating identity routes to `/seed` then `/home`.

- [ ] **Step 1: Failing widget test**

```dart
// app/test/onboarding_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:takhi/onboarding/onboarding_page.dart';
import 'package:takhi/identity/identity_state.dart';
import 'package:takhi/identity/identity_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:takhi/l10n/app_localizations.dart';

void main() {
  testWidgets('onboarding shows brand name and create button', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [keyStoreProvider.overrideWithValue(InMemoryKeyStore())],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('mn'),
        home: const OnboardingPage(),
      ),
    ));
    expect(find.text('Тахь'), findsWidgets);
    expect(find.text('Шинээр эхлэх'), findsOneWidget);
    expect(find.text('Зорчигч'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — fails.**

- [ ] **Step 3: Implement** onboarding page (brand gold background, horse icon asset, mode toggle passenger/driver, "Start fresh" + "Restore" buttons), seed backup page (numbered 12-word grid, red warning text from `seedBackupWarning`, "I saved it" → `/home`), restore page (multiline field → `identityService.restore`), and `router.dart` wiring these with `go_router`. Wire `main.dart` to use `MaterialApp.router` with the router and both themes + localization delegates. Full widget code for each page (brand-styled, using `TakhiColors` and `AppLocalizations.of(context)!`), no hardcoded strings.

> Keep each page a focused widget file. Home is a placeholder `Scaffold` with a passenger/driver `SegmentedButton` — the real ride flow is Plan 3.

- [ ] **Step 4: Run — passes** (`flutter test test/onboarding_widget_test.dart`), then `flutter analyze` clean.

- [ ] **Step 5: Commit** — `git add app && git commit -m "feat(app): onboarding + seed backup + restore UI"`

---

### Task 6: Launcher icon + smoke run + coverage

**Files:**
- Modify: `app/pubspec.yaml` (flutter_launcher_icons config)
- Create: `app/assets/icon.png` (copy of `brand/out/icon_gold_1024.png`)
- Test: `app/integration_test/boot_test.dart`

- [ ] **Step 1: Configure launcher icons**

Add dev_dep `flutter_launcher_icons: ^0.14.1` and config pointing `image_path: assets/icon.png`, then run `dart run flutter_launcher_icons`.

- [ ] **Step 2: Boot integration test**

```dart
// app/integration_test/boot_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:takhi/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('app boots to onboarding without crashing', (t) async {
    app.main();
    await t.pumpAndSettle();
    expect(find.text('Тахь'), findsWidgets);
  });
}
```

- [ ] **Step 3: Run smoke** — `flutter test integration_test/boot_test.dart` (or `flutter run -d chrome` and confirm onboarding paints). Capture that first paint works.

- [ ] **Step 4: Coverage** — `flutter test --coverage`; ensure service/logic files (identity, relay_pool, theme) ≥ 80%. Add tests for any gap.

- [ ] **Step 5: Commit** — `git add app && git commit -m "feat(app): launcher icon + boot smoke test"`

---

## Self-Review

**Spec coverage:** §5 relay pool → Task 4 ✓ · §3/§4 identity=key + seed backup → Tasks 3,5 ✓ · §10 <60s onboarding (no blocking net on first paint; identity is local) → Tasks 3,5 ✓ · §4 mn+en i18n → Task 2 ✓ · §10 brand/dark+light → Task 1 ✓ · app icon → Task 6 ✓. Ride flow, map, taximeter, calling, safety → Plans 3-5 (out of scope here).

**Placeholder scan:** Task 5's page bodies are described rather than fully transcribed — the implementer must write complete widget code (no literal placeholders in output); every string comes from ARB keys defined in Task 2. Flag: this is the one task requiring real design work, not transcription — dispatch it to a standard (not cheapest) model.

**Type consistency:** `Identity`, `KeyStore`, `IdentityService`, `RelayPool`, `RelayFilter`, `RelaySocket`, `takhiTheme`, `TakhiColors`, provider names are consistent across tasks. `takhi_protocol` symbols match Plan 1's Produces blocks.

**Open items:** verify `NostrEvent.toJson()` shape from Plan 1 (Task 4 note); NotoSans font bundling deferred (system fallback acceptable until a font task in Plan 3 UI polish).
