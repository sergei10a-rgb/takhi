# Тахь протокол — PROTOCOL.md

version: 0.1.0

Энэ баримт бичиг нь [`packages/takhi_protocol`](packages/takhi_protocol/) — цэвэр Dart,
UI-гүй, сүлжээгүй лавлагаа хэрэгжүүлэлт — дээр бодитоор хэрэгжсэн зан төлөвийг
тодорхойлно. `takhi` бол стандарт [Nostr](https://github.com/nostr-protocol/nostr)
протокол дээр баригдсан такси/аялалын өргөтгөл: төв сервер, custody, дансны мэдээлэл
байхгүй. Кодыг нэг ч мөр уншаагүй хөгжүүлэгч энэ баримт бичгээс өөрийн клиент бичиж
чадах ёстой.

## 1. Нэвтэрхий (identity)

- Хэрэглэгч тус бүр **secp256k1 түлхүүрийн хос** — Nostr стандарт: 32 байт хувийн
  түлхүүр, BIP-340 x-only (32 байт / 64 hex тэмдэгт) нийтийн түлхүүр (`pubkey`).
- **NIP-06**: хувийн түлхүүр BIP-39 12 үгийн mnemonic-аас BIP-32 зам
  `m/44'/1237'/0'/0/0`-оор гарна. Апп seed-ийг үгээр харуулж хэрэглэгч бичиж авна —
  бүртгэл, серверийн нөөцлөлт байхгүй.
- **NIP-19**: түлхүүрүүд хэрэглэгчид харуулахдаа bech32 `npub1…` (нийтийн),
  `nsec1…` (хувийн) хэлбэрт хөрвүүлэгдэнэ. Дотооддоо event-ийн `pubkey` талбар
  үргэлж 64 hex тэмдэгт хэлбэртэй.

## 2. Event загвар (NIP-01)

Бүх зурвас нь стандарт Nostr event:

```json
{
  "id": "<sha256 hex>",
  "pubkey": "<64 hex>",
  "created_at": <unix seconds>,
  "kind": <int>,
  "tags": [["<key>", "<value>", ...], ...],
  "content": "<string>",
  "sig": "<128 hex BIP-340 Schnorr>"
}
```

- `id` = `sha256(json([0, pubkey, created_at, kind, tags, content]))` — JSON нь
  зай/шинэ мөргүй, `jsonEncode`-ийн стандарт дараалалтай compact массив
  (`computeEventId`).
- `sig` = event id-г BIP-340 Schnorr гарын үсэгээр баталгаажуулна (`signEvent` /
  `verifyEvent`).
- **NIP-40**: хугацаа хязгаартай event-үүд `["expiration", "<unix seconds>"]`
  tag ашиглана.

## 3. Event kind-ууд (§6-ийн эцсийн утга)

| Kind | Нэр | Тогтвортой байдал | Хэрэгжилт |
|---:|---|---|---|
| `0` | Профайл | replaceable | `takhi_protocol`-д тусгайлан хэрэгжээгүй (стандарт NIP-01 kind 0 JSON content); апп давхаргад |
| `20177` | Дуудлага (ride request) | ephemeral + NIP-40 expiry | `buildRideRequest` / `parseRideRequest` |
| `20178` | Аяллын амьд байршил | ephemeral, NIP-44 шифртэй | kind тогтмол (`kKindLiveLocation`) тодорхойлогдсон; builder Plan 3 (ride state machine)-д |
| `30177` | Аяллын баримт (trip receipt) | addressable, `d`=trip_id | `buildTripReceipt` / `parseTripReceipt` |
| `30178` | Туслагч-зарлал (helper announcement) | addressable | kind тогтмол (`kKindHelper`) тодорхойлогдсон; builder Plan 5 (P2P дуудлага)-д |

Kind тогтмолууд: `kKindProfile`, `kKindRideRequest`, `kKindLiveLocation`,
`kKindTripReceipt`, `kKindHelper` (`lib/src/takhi_events.dart`).

## 4. Tag схем

### 4.1 Дуудлага — kind `20177`

| Tag | Утга | Заавал |
|---|---|---|
| `["g", "<geohash-6>"]` | Суух орчмын бүдүүвч байршил, geohash нарийвчлал 6 (~±0.61км) | тийм |
| `["dest", "<geohash-6>"]` | Очих орчмын бүдүүвч байршил, geohash-6 | тийм |
| `["expiration", "<unix seconds>"]` | NIP-40: `created_at + expirySeconds` (`buildRideRequest` default 240с) | тийм |
| `["price", "<int mnt>"]` | Зорчигчийн санал үнэ, төгрөгөөр | сонголттой |
| `["nonce", "<counter>", "<difficulty>"]` | NIP-13 PoW (§5) | сонголттой, relay-ийн шаардлагаас хамаарна |

`content` = чөлөөт текст тэмдэглэл. `parseRideRequest` `g`/`dest`/`expiration`
байхгүй бол `FormatException` шиднэ; `price` байхгүй бол `null`.

### 4.2 Аяллын баримт — kind `30177`

| Tag | Утга |
|---|---|
| `["d", "<trip_id>"]` | Аяллын давтагдашгүй ID — хос баримт хос tag-аар (§4.3) холбогдоно |
| `["p", "<counterparty pubkey hex>"]` | Нөгөө талын нийтийн түлхүүр |
| `["role", "driver"\|"passenger"]` | Энэ баримтыг бичсэн талын үүрэг |
| `["rating", "1".."5"]` | Үнэлгээ (1–5 од); `buildTripReceipt` мужаас гарвал `ArgumentError` |
| `["dist", "<int meters>"]` | Хэмжсэн зай, метрээр |
| `["dur", "<int seconds>"]` | Аяллын үргэлжлэх хугацаа, секундээр |
| `["price", "<int mnt>"]` | Эцсийн үнэ, төгрөгөөр |

`content` = сонголттой сэтгэгдэл текст. `parseTripReceipt` дутуу tag бүрт
`FormatException` шиднэ; `authorPubkey`/`createdAt` нь event-ийн `pubkey`/
`created_at`-аас шууд авагдана (tag биш).

### 4.3 Хос баримтын дүрэм (§9)

- Аялал бүрийн төгсгөлд **хоёр тал тус бүр** өөрийн `30177` баримт нийтэлнэ:
  ижил `trip_id` (`d` tag), нөгөө талын pubkey (`p` tag).
- Баримт зөвхөн **хосоороо** — driver ба passenger аль аль нь ижил `trip_id`
  дээр бие биеийг `p`-ээр зааж баримт нийтэлсэн үед л — жинтэй тооцогдоно.
  Ганц талын баримт (нөгөө тал нийтлээгүй) `computeReputation`-д жингүй.
  Энэ нь `packages/takhi_protocol/lib/src/reputation.dart`-д хэрэгжсэн бөгөөд
  `test/reputation_test.dart`-д Sybil (self-praise ring) сценариудаар
  баталгаажсан.
- Клиент талын жинлэлт (web-of-trust): олон **өөр, өөрсдөө түүхтэй**
  counterparty-аас ирсэн баримт өндөр жинтэй; ижил жижиг бүлэг дотроо л
  магтсан баримтын нийлбэр жин хязгаарлагдмал өснө (Sybil ring-ийн өсөлт
  чиглэлээр хязгаарлагдсан — доор §5-г үзнэ үү).

### 4.4 Туслагч-зарлал — kind `30178` (спекийн түвшин, builder дараагийн төлөвлөгөөнд)

Спекийн §6/§7.3-①-ээс: сайн дурын blind-relay (TURN) зангилааны хаяг/
credential-ийг хэн ч зарлаж, хэн ч ашиглаж болно. `kKindHelper` тогтмол энэ
багцад тодорхойлогдсон боловч typed builder/parser энэ багцад ХЭРЭГЖЭЭГҮЙ
(deviation — доор Тэмдэглэл хэсгийг үзнэ үү); санал болгож буй tag схем:

| Tag | Утга |
|---|---|
| `["d", "<helper node id>"]` | addressable identity |
| `["host", "<ip-or-domain>"]` | TURN серверийн хаяг |
| `["port", "<int>"]` | TURN порт |
| `["expiration", "<unix seconds>"]` | NIP-40, зарлалын хугацаа |

`content` = сонголттой TURN credential (шифрлэгдсэн эсвэл нийтэд нээлттэй,
зохион байгуулагчаас хамаарна). Энэ schema Plan 5-д (P2P дуудлага) баталгаажна.

## 5. Proof-of-Work (NIP-13)

- `minePow(base, difficulty, {maxIterations})` — `["nonce", "<counter>",
  "<difficulty>"]` tag нэмж, `computeEventId`-ийн үр дүнгийн эхний
  `difficulty` бит 0 болтол `nonce`-г нэмэгдүүлнэ.
- Тоолуур: `countLeadingZeroBits(hexId)` — hex мөрийг nibble бүрээр bit
  тоолно.
- Хайлт `maxIterations` (default 2²²) хүрч олдохгүй бол `PowExhausted`
  шидэгдэнэ — сервер/UI давхарга дахин оролдох эсвэл хэрэглэгчид мэдэгдэх
  ёстой.
- Хэрэглээ: `20177` дуудлагад PoW нэмж spam-ыг зардалтай болгоно (§7.1:
  «PoW бодогдоно, 4 мин expiry»); тодорхой хатуу difficulty энэ багцад
  тогтоогдоогүй — relay бодлого, апп тохиргооноос хамаарна (§16.3).

## 6. Geohash (байршлын нууцлал)

- `geohashEncode(lat, lon, {precision = 6})` — стандарт base32 geohash
  (`0123456789bcdefghjkmnpqrstuvwxyz`).
- **Нарийвчлал 6** = ~±0.61 км (~1.2×0.6 км нүд) — **дуудлагад ашиглагдах цорын
  ганц нийтэд харагдах нарийвчлал** (§6: "geohash-6 (~±600м)"). Яг цэг
  (координат/Plus Code) хэзээ ч нийтэд kind `20177`-д ил гарахгүй.
- `geohashDecode` / `geohashNeighbors` — decode ба 8 хөрш нүдийг тооцоолно
  (ойролцоох дуудлага хайхад).
- **Нууцлалын шаталсан задаргаа (§6):**

  | Түвшин | Нарийвчлал | Хэн харна |
  |---|---|---|
  | Нийтэд (kind `20177`) | geohash-6 (~±600м) | Бүх сонсож буй жолооч |
  | Сонгосон жолоочид (NIP-17 DM) | яг цэг: координат + Plus Code + landmark текст | Зөвхөн зорчигчийн сонгосон нэг жолооч |
  | Аяллын явцад (kind `20178`, NIP-44 шифртэй) | амьд координат, 5-10с тутам | Зөвхөн тухайн хос |

  Зорчигчийн яг байршил ХЭЗЭЭ Ч нийтэд ил гарахгүй.

## 7. Plus Code (`lib/src/pluscode.dart`)

- `open_location_code` багцын нимгэн wrapper: координатыг Google Plus
  Code (Open Location Code) мөр рүү/-ээс хөрвүүлнэ.
- Зорилго: сонгосон жолоочид дамжуулах "яг цэг"-ийг богино, хүн уншиж
  болохуйц, координатаас илүү алдаа тэвчих кодоор илэрхийлэх (§7.4/§8).
  Энэ утга зөвхөн шифрлэгдсэн NIP-17 DM дотор дамжина — Nostr event tag-д
  нийтэд ил гарахгүй.

## 8. NIP-44 v2 шифрлэлт

- `lib/src/nip44.dart` нь албан ёсны NIP-44 v2 (`nip44.encrypt`/`decrypt`)
  хэрэгжилт: ECDH (secp256k1, sender priv × recipient pub) → HKDF-extract →
  conversation key → per-message HKDF-expand (nonce-той) → ChaCha20 →
  HMAC-SHA256 auth (`pointycastle`).
- `test/nip44_vectors.dart` нь албан ёсны nostr NIP-44 test vector-уудаас
  хуулсан утгууд агуулж, `nip44_test.dart` тэдгээрийг шалгана + сөрөг
  (tamper/adversarial) тестүүд.
- Хэрэглээ: аяллын амьд байршил (`20178`), санал/тохироо/чат/дуудлагын
  signaling бүх NIP-17 DM (§6-ийн хүснэгт) энэ шифрлэлт дээр суурилна.

## 9. Хоёр талын нэр хүнд (§9, `lib/src/reputation.dart`)

- `computeReputation(receipts, forPubkey)` — kind `30177` баримтуудын
  жагсаалт хүлээн авч, зөвхөн **хос** (§4.3) баталгаажсан баримтуудыг
  тооцоолол ашиглана.
- Web-of-trust жинлэлт: counterparty бүрийн жин тухайн counterparty-гийн
  ӨӨРИЙН баримтын тоо/олон талт байдлаас хамаарна — цөөн тооны, бие
  биенээ л магтсан identity бүлэг (Sybil ring) өсөх тусам нэмэлт жингийн
  ургалт хязгаарлагдана (log-хэлбэрийн саатал; `test/reputation_test.dart`
  дэх Sybil-ring тестүүдээр баталгаажсан).
- Гаралт: аяллын тоо, дундаж үнэлгээ, жинлэгдсэн нэр хүндийн оноо.
  Сервер, төв шүүгч байхгүй — тооцоолол бүрэн клиент талд.

## 10. NIP-стандартын нийцэл

| NIP | Зорилго | Хэрэгжилт |
|---|---|---|
| NIP-01 | Event, id, sig | `event.dart`, `sign.dart` |
| NIP-06 | Mnemonic → түлхүүр | `nip06.dart` (албан ёсны тест vector-ээр баталгаажсан) |
| NIP-13 | Proof-of-Work | `pow.dart` |
| NIP-19 | bech32 npub/nsec | `nip19.dart` |
| NIP-40 | Expiration tag | `takhi_events.dart` (`expiration` tag) |
| NIP-44 v2 | Шифрлэлт | `nip44.dart` (албан ёсны vector-ээр баталгаажсан) |

## 11. Тэмдэглэл ба хязгаарлалт (v0.1)

- Энэ багц (`packages/takhi_protocol`) нь **UI-гүй, сүлжээгүй** — relay
  холболт, WebSocket, HTTP энд байхгүй. Дараагийн төлөвлөгөөнүүд
  (`docs/superpowers/plans/`) relay pool, ride state machine, taximeter,
  P2P дуудлага, аюулгүй байдлын давхаргыг нэмнэ.
- **Deviation:** `20178` (аяллын амьд байршил) ба `30178` (туслагч-зарлал)
  kind тогтмол Task 10-д тодорхойлогдсон боловч typed builder/parser энэ
  багцад бичигдээгүй — эдгээр нь тус тус Plan 3 (ride state machine) ба
  Plan 5 (P2P дуудлага)-д хэрэгжинэ гэж Execution Handoff-д (энэ
  төлөвлөгөөний төгсгөл) тодорхой заасан. §4.4-т санал болгож буй tag
  схем баримтжуулсан ч баталгаажаагүй.
- PoW хатуу `difficulty` утга, default relay жагсаалт зэрэг v0.1-ийн
  нээлттэй асуудлууд (`docs/superpowers/specs/2026-07-21-takhi-design.md`
  §16) хожим PROTOCOL.md-ийн дараагийн хувилбарт тогтооно.

## 12. Тестийн хамрал

`dart test --coverage=coverage` (packages/takhi_protocol/): бүх тест ногоон,
`lib/`-ийн мөрийн хамрал ≥ 80% (файл бүрээр). CI (`.github/workflows/protocol.yml`)
`dart test` + coverage тайлан үүсгэлтийг push/PR бүрт ажиллуулна.
