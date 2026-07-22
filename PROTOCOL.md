# Тахь протокол — PROTOCOL.md

version: 0.2.0

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
| `20178` | Аяллын амьд байршил | ephemeral, NIP-44 шифртэй | `buildLiveLocationEvent` / `parseLiveLocationEvent` (Plan 4) |
| `30177` | Аяллын баримт (trip receipt) | addressable, `d`=trip_id | `buildTripReceipt` / `parseTripReceipt` |
| `30178` | Туслагч-зарлал (helper announcement) | addressable | `buildHelperAnnouncement` / `parseHelperAnnouncement` (Plan 5) |

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

### 4.4 Туслагч-зарлал — kind `30178`

Спекийн §6/§7.3-①-ээс: сайн дурын blind-relay (TURN) зангилааны хаяг/
credential-ийг хэн ч зарлаж, хэн ч ашиглаж болно. `kKindHelper` тогтмол,
`buildHelperAnnouncement`/`parseHelperAnnouncement` typed builder/parser
хоёулаа энэ багцад хэрэгжсэн (Plan 5, `lib/src/helper_announcement.dart`):

| Tag | Утга |
|---|---|
| `["d", "<helper node id>"]` | addressable identity |
| `["host", "<ip-or-domain>"]` | TURN серверийн хаяг |
| `["port", "<int>"]` | TURN порт |
| `["expiration", "<unix seconds>"]` | NIP-40, зарлалын хугацаа |

`content` = сонголттой TURN credential (шифрлэгдсэн эсвэл нийтэд нээлттэй,
зохион байгуулагчаас хамаарна) — санаатайгаар NIP-44-ээр шифрлэгдээгүй,
учир нь kind-30178 зарлалын гол зорилго нь **хэн ч харж, ашиглаж болохуйц**
байх явдал юм (spec §7.3-①). `host` талбар нь хэн ч нийтлэх боломжтой
итгэлгүй гадаад өгөгдөл тул `isValidTurnHost` (`app/lib/call/ice_servers.dart`)
дамжуулагч (host эсвэл port биш, зөвхөн зохион байгуулалт) баталгаажуулна —
доор §13-г үзнэ үү.

### 4.5 Дуудлага-сигналинг ба дуут-зурвас — NIP-17 gift-wrap дундуур

Дуудлагын сигналинг (`call_offer`/`call_answer`/`call_ice`/`call_hangup`) ба
дуут-зурвасын нөөц сувгийн (`voice_note`, §7.3-③) аль аль нь **шинэ Nostr
kind огтхон ч шаардаагүй** — §4.3-т дурдсан хос-баримтын dm сувагтай ижил,
одоо байгаа kind-1059 gift-wrap DM сувгаар (§8-ийн `nip17Wrap`/`nip17Unwrap`,
`app/lib/ride/ride_dm_payload.dart`-ийн `RideDmPayload`) дамждаг: эдгээр
таван зурвас тус бүр gift-wrap-ласан rumor-ын JSON `content`-д зөвхөн нэмэлт
`"type"` дискриминатор утга хэлбэрээр илэрхийлэгдэнэ (`"call_offer"`,
`"call_answer"`, `"call_ice"`, `"call_hangup"`, `"voice_note"`) — §3-ийн kind
хүснэгтийг зөвхөн уншсан уншигч эндээс "дуудлагад шинэ kind хэрэгтэй байсан"
гэж буруу дүгнэж болзошгүй тул энд тодорхой тэмдэглэв.

`voice_note` payload нь ≤10 секунд, ~30КБ хэмжээгээр хатуу хязгаарлагдсан
audio blob-ыг base64-аар `content`-д зөөнө (`validateVoiceNoteAudio`,
`app/lib/call/voice_note_service.dart`) — хүлээн авагч тал илгээгчийн
мэдэгдсэн үргэлжлэх хугацаа/хэмжээнд итгэхгүй, зөвхөн бодитоор хүлээн авсан
байт тоог дахин шалгана (Global Constraints).

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
  | Сонгосон жолоочид (NIP-17 DM)* | яг цэг: координат + Plus Code + landmark текст | Зөвхөн зорчигчийн сонгосон нэг жолооч |
  | Аяллын явцад (kind `20178`, NIP-44 шифртэй) | амьд координат, 5-10с тутам | Зөвхөн тухайн хос |

  Зорчигчийн яг байршил ХЭЗЭЭ Ч нийтэд ил гарахгүй.

  \* **Хэрэгжилтийн статус:** NIP-17 (seal + gift-wrap, kind 13/1059)
  энэ хүснэгтэд заасан дамжуулагч бодитоор хэрэгжсэн (`nip17.dart`,
  Plan 5) — дэлгэрэнгүй: §8.5.

## 7. Plus Code (`lib/src/pluscode.dart`)

- `open_location_code` багцын нимгэн wrapper: координатыг Google Plus
  Code (Open Location Code) мөр рүү/-ээс хөрвүүлнэ.
- Зорилго: сонгосон жолоочид дамжуулах "яг цэг"-ийг богино, хүн уншиж
  болохуйц, координатаас илүү алдаа тэвчих кодоор илэрхийлэх (§7.4/§8).
  Энэ утга зөвхөн шифрлэгдсэн NIP-17 DM дотор дамжина ёстой — Nostr event
  tag-д нийтэд ил гарахгүй (NIP-17: §8.5). `pluscode.dart`-ын гаралт нь
  ямар ч тохиолдолд зөвхөн gift-wrap-ласан rumor-ын `content`-д л орно,
  plaintext tag-д хэзээ ч тавигдахгүй.

## 8. NIP-44 v2 шифрлэлт

- `lib/src/nip44.dart` нь албан ёсны NIP-44 v2 (`nip44.encrypt`/`decrypt`)
  хэрэгжилт: ECDH (secp256k1, sender priv × recipient pub) → HKDF-extract →
  conversation key → per-message HKDF-expand (nonce-той) → ChaCha20 →
  HMAC-SHA256 auth (`pointycastle`).
- `test/nip44_vectors.dart` нь албан ёсны nostr NIP-44 test vector-уудаас
  хуулсан утгууд агуулж, `nip44_test.dart` тэдгээрийг шалгана + сөрөг
  (tamper/adversarial) тестүүд.
- Хэрэглээ: аяллын амьд байршил (`20178`) шууд NIP-44-ээр шифрлэгдэнэ;
  санал/тохироо/чат/дуудлагын signaling/дуут-зурвасын бүх NIP-17 DM
  (§6-ийн хүснэгт, §4.5) `nip44Encrypt`/`Decrypt`-г **давхар давхаргаар**
  ашиглана (доор §8.5) — seal-ийг нэг удаа, gift-wrap-ыг дахин.

### 8.5 NIP-17 seal + gift-wrap (`lib/src/nip17.dart`)

`packages/takhi_protocol`-д бодитоор хэрэгжсэн (Plan 5) — рюмор → seal →
gift-wrap гурван давхаргат бүтэц (NIP-59):

- **Rumor** (`buildRumor`) — жинхэнэ зурвас, гарын үсэггүй, `id` тооцоологдсон
  боловч `sig` алга. Зөвхөн seal-ийн доторх шифрлэгдсэн `content`-д л
  оршино — өөрөө хэзээ ч relay рүү нийтлэгдэхгүй. `RideDmPayload`-ийн
  бүх зурвас (offer/handoff/cancel/trip_status/call_*/voice_note, §4.5)
  rumor-ын kind тогтмол `kRumorKindRideDm = 20179`-ийг ашиглана
  (`app/lib/ride/ride_dm_channel.dart`).
- **Seal** — kind `13` (`kKindSeal`), rumor-ыг жинхэнэ илгээгчийн
  (sender, recipient) хосоор NIP-44-ээр шифэрлээд жинхэнэ илгээгчийн
  түлхүүрээр гарын үсэг зурна (`sealRumor`).
- **Gift wrap** — kind `1059` (`kKindGiftWrap`), seal-ыг **нэг удаагийн
  ephemeral түлхүүр**-ээр дахин NIP-44 шифрлээд тэр ephemeral түлхүүрээрээ
  гарын үсэг зурна (`giftWrap`) — цорын ганц нийтэд харагдах tag нь
  `["p", "<recipient>"]`; жинхэнэ илгээгчийн pubkey, зурвасын агуулга
  хэн нэгэнд ил гарахгүй. `created_at` NIP-59-ийн зөвлөмжийн дагуу 2
  хоногийн цонхонд санамсаргүй байдлаар өнгөрсөн рүү шилжинэ
  (`randomTimestamp`) — wrap-уудын цаг хугацааны корреляциас сэргийлнэ.
- `nip17Wrap` (rumor→seal→gift-wrap нэг дор) / `nip17Unwrap`
  (`UnwrappedDm(rumor, senderPubkey)` буцаана, seal-ийн гарын үсэг болон
  rumor.pubkey == seal-ийн гарын үсэг зурагчтай таарч байгааг шалгана —
  эс тэгвэл spoofed-sender халдлага) энэ давхаргын нийтлэг орох цэг.
  `RelayPool`-д зөвхөн kind `1059` (gift wrap) л хэзээ ч нийтлэгдэнэ.

## 9. Хоёр талын нэр хүнд (§9, `lib/src/reputation.dart`)

- `computeReputation({required String subjectPubkey, required
  List<TripReceipt> allReceipts, Set<String> viewerTrusted = const {}})` —
  kind `30177` баримтуудын жагсаалт хүлээн авч, зөвхөн **хос** (§4.3)
  баталгаажсан баримтуудыг тооцоолол ашиглана.
- **`viewerTrusted` — жинхэнэ web-of-trust оролт:** энэ бол үзэгчийн
  (viewer) өөрийн итгэдэг counterparty pubkey-үүдийн олонлог. Заавал биш
  (`const {}` default), гэхдээ энэ параметрийг дамжуулах нь section-ийн
  гарчигт заасан "web-of-trust"-ыг бодитоор идэвхжүүлдэг цорын ганц зам:
  `viewerTrusted`-д орсон counterparty-гийн жин **3x** нэмэгдэж, доор
  дурдсан log/sqrt дарангуйллаас **чөлөөлөгдөнө** (учир нь үзэгч тухайн
  identity-г аль хэдийн шалгаж баталгаажуулсан гэж үзнэ). `viewerTrusted`
  дамжуулаагүй бол бүх counterparty итгэлгүй pool-д унана.
- **Sybil-эсэргүүцэх дарангуйлал (итгэлгүй pool-д л хамаарна):**
  counterparty бүрийн ӨӨРИЙН баримтын тоо/олон талт байдлаас хамаарсан жин
  `log(1 + n)`-ээр тооцоологдож, дараа нь итгэлгүй pool-ын нийлбэрийг
  гадна талаас `sqrt()`-ээр дахин дарангуйлна — цөөн тооны, бие биенээ л
  магтсан identity бүлэг (Sybil ring) өсөх тусам нэмэлт жингийн ургалт
  хязгаарлагдана (`test/reputation_test.dart` дэх Sybil-ring тестүүдээр
  баталгаажсан). Энэ дарангуйлал зөвхөн шинэ, `viewerTrusted`-д ороогүй
  identity-д хамаарна — N ширхэг нэг удаагийн pubkey минтлэх халдлагыг
  өртгөөр (хос identity + PoW + хугацаа) болон үзэгчийн өөрийн
  итгэлцлээр (`viewerTrusted`) хязгаарлах зорилготой; баримт дата дангаараа
  ийм халдлагыг бүрэн эсэргүүцэж чадахгүй.
- Гаралт: аяллын тоо, дундаж үнэлгээ, жинлэгдсэн нэр хүндийн оноо
  (`Reputation(pairedTripCount, averageRating, trustWeight)`). Сервер, төв
  шүүгч байхгүй — тооцоолол бүрэн клиент талд; `viewerTrusted`-г тухайн
  клиент өөрөө (жишээ нь өөрийн дагадаг/итгэдэг жолооч-зорчигчдын
  жагсаалтаас) бүрдүүлнэ.

## 10. NIP-стандартын нийцэл

| NIP | Зорилго | Хэрэгжилт |
|---|---|---|
| NIP-01 | Event, id, sig | `event.dart`, `sign.dart` |
| NIP-06 | Mnemonic → түлхүүр | `nip06.dart` (албан ёсны тест vector-ээр баталгаажсан) |
| NIP-13 | Proof-of-Work | `pow.dart` |
| NIP-19 | bech32 npub/nsec | `nip19.dart` |
| NIP-40 | Expiration tag | `takhi_events.dart` (`expiration` tag) |
| NIP-44 v2 | Шифрлэлт | `nip44.dart` (албан ёсны vector-ээр баталгаажсан) |
| NIP-59/NIP-17 | Seal + gift-wrap DM (kind 13/1059) | `nip17.dart` (§8.5) |

## 11. Тэмдэглэл ба хязгаарлалт

- Энэ багц (`packages/takhi_protocol`) нь **UI-гүй, сүлжээгүй** — relay
  холболт, WebSocket, HTTP энд байхгүй; тэдгээр нь `app/` (Flutter каркас,
  Plan 2-5) давхаргад амьдардаг.
- Спекийн (`docs/superpowers/specs/2026-07-21-takhi-design.md`) MVP-д
  ОРОХ бүх онцлог энэ хувилбарын (`0.2.0`) байдлаар бүрэн хэрэгжсэн:
  identity/NIP-06/19, event/sign/verify, PoW, geohash/Plus Code,
  NIP-44 v2, NIP-17 seal+gift-wrap, хос-баримт нэр хүнд, дуудлагын
  сигналинг + туслагч-зарлал (kind 30178) бүгд `packages/takhi_protocol`
  болон `app/lib/`-д бодитоор код болсон. (Хуучин "Plan 5-д хэрэгжинэ" гэж
  заасан хоёр deviation — 30178 builder, NIP-17 давхарга — Plan 5-ийн
  хэрэгжилтээр аль аль нь хаагдсан тул устгав.)
- PoW хатуу `difficulty` утга, default relay/STUN жагсаалт зэрэг
  (`docs/superpowers/specs/2026-07-21-takhi-design.md` §16) нээлттэй
  асуудлууд хэвээр — жинхэнэ сүлжээ (Мобиком/Юнител/Скайтел зэрэг
  Монголын ISP)-д баталгаажаагүй, PoC-ийн талбарын тестээр шийдэгдэнэ.

## 12. Тестийн хамрал

`dart test --coverage=coverage` (packages/takhi_protocol/): бүх тест ногоон,
`lib/`-ийн мөрийн хамрал ≥ 80% (файл бүрээр). CI (`.github/workflows/protocol.yml`)
`dart test` + coverage тайлан үүсгэлтийг push/PR бүрт ажиллуулна.

## 13. ICE тохиргоо ба туслагч-зангилаа (`app/lib/call/ice_servers.dart`)

WebRTC P2P дуудлагын NAT-дамжуулах бүх логик энд, нэг файлд төвлөрнө.
Тодорхой тэмдэглэх нь чухал: **STUN нь зөвхөн хаяг-олох stateless
үйлчилгээ** — media, signaling ХЭЗЭЭ Ч STUN-ээр дамжихгүй (spec §7.3-①,
RFC 5389). Author ямар ч STUN/TURN сервер өөрөө ажиллуулахгүй (Global
Constraints) — доорх бүх зүйл нийтийн дэд бүтэц эсвэл сайн дурынхны
зарлалаас бүрдэнэ.

- **`kDefaultStunServers`** — нийтийн, өргөн ашиглагддаг STUN
  серверүүдийн editable жагсаалт (Google, Cloudflare) — энэ төслийн
  ажиллуулдаг дэд бүтэц ЕР БИШ, зөвхөн хаягаа олоход л ашиглагдана.
  Монголын жинхэнэ ISP (Мобиком/Юнител/Скайтел)-д баталгаажаагүй нээлттэй
  асуудал (§11).
- **`buildIceServers({stunServers, helpers})`** — `flutter_webrtc`-ийн
  `RTCConfiguration`-д шууд өгөх `iceServers` жагсаалт угсарна: эхлээд
  STUN, дараа нь `helpers`-ийн (kind `30178` зарлалуудын, §4.4)
  тус бүрээс нэг `turn:` бичлэг. P2P-шууд ба TURN-релей хоёр тусдаа
  app-түвшний оролдлого биш — жагсаалт бэлдэгдсэний дараах бүх зүйл
  стандарт ICE agent (RFC 8445)-ийн ажил: host/server-reflexive/relay
  candidate бүгдийг зэрэг цуглуулж, аль нь холбогдвол түүнийг сонгоно,
  шууд замыг автоматаар илүүд үзнэ. Цэвэр, синхрон функц тул сүлжээ/WebRTC
  хамааралгүйгээр unit-тестлэгдэнэ.
- **`isValidTurnHost(host)`** — kind-30178 зарлалын `host` талбар хэн ч
  нийтлэх боломжтой итгэлгүй гадаад өгөгдөл (§4.4) тул `turn:` URI-д
  шигтгэхийн өмнө энд шалгагдана (зөвшөөрөгдсөн хэлбэрээс гарсан
  зарлалыг чимээгүй хаяна, бусад хүчинтэй helper-үүдийг гээхгүй).
- **Туслагч-олох урсгал (эцсээс эцэс хүртэл):** хэн нэгэн `coturn`
  ажиллуулаад kind `30178` зарлал нийтэлнэ (§4.4) → `RelayPool` (app
  давхарга) энэ kind-ийг сонсоод `parseHelperAnnouncement`-аар задална →
  `HelperDirectoryService.watchHelpers` (`app/lib/call/
  helper_directory_service.dart`) энэ урсгалыг гаргана → `app/lib/call/
  call_providers.dart`-ийн **`helperDirectoryProvider`** app-сессийн
  туршид амьд ажиллах `HelperDirectory` accumulator-т идэвхтэй (хугацаа
  дуусаагүй) зарлалуудыг цуглуулна (`ActiveTripView` аялал идэвхжих
  дарааг нь урьдчилж "дулаацуулна", жинхэнэ зарлал сүлжээгээр ирэх цаг
  олгохын тулд) → **`CallScreen._startCall`** дуудлага бүрийн эхэнд, өөрөө
  `CallEngine` үүсгэхээсээ (тэгэхээр `CallService`-ээсээ ч) өмнө, тэр
  accumulator-ын тухайн мөчийн `.current()` снэпшотыг `buildIceServers`-д
  дамжуулна. `CallService`-ийн дотор ямар ч `HelperDirectoryService`/TURN
  хамаарал байхгүй — `CallEngine` үүсгэгдсэний дараа шинэчлэгдэх "амьд"
  TURN жагсаалт гэж байхгүй тул хэрэггүй (`ice_servers.dart`-ийн doc
  comment). Бүртгэл, зөвшөөрөл шаардахгүй — хэн ч зарлаж, хэн ч ашиглана
  (spec §7.3-①). Дэлгэрэнгүй, туслагч зангилаа өөрөө хэрхэн асаах заавар:
  [`HELPER.md`](HELPER.md).
