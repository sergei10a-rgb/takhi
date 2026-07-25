# 04 — Жолоочийн тал (S14–S18) · Тахь

> Хэв маяг: `docs/design/screens/00-style.md` (STYLE PREAMBLE) — доорх prompt бүр түүгээр эхэлнэ.
> Эх код (бүтнээр уншиж нотолсон): `app/lib/ride/driver_inbox_page.dart`,
> `app/lib/map/nearby_requests_layer.dart`, `app/lib/ride/driver_inbox_service.dart`,
> `app/lib/ride/offer_service.dart`, `app/lib/ride/handoff_service.dart`,
> `app/lib/ride/ride_dm_payload.dart`, `app/lib/profile/driver_profile_page.dart`,
> `app/lib/profile/driver_profile_service.dart`, `app/lib/payment/driver_qr_capture_page.dart`,
> `app/lib/payment/driver_qr_store.dart`, `app/lib/payment/payment_providers.dart`,
> `app/lib/payment/driver_qr_display.dart`, `app/lib/map/ride_map.dart`,
> `app/lib/widgets/confirm_leave_scope.dart`, `app/lib/router.dart`, `app/lib/l10n/app_mn.arb`.
>
> **Монгол текст бүр `app_mn.arb`-аас авсан.** arb-д байхгүйг «(шинэ)» гэж тэмдэглэв —
> тийм газарт prompt нь **байрлал/хэмжээ л зааж**, бодит үг зохиогүй (`———` орлуулагч).

---

## 0. Энэ бүлгийн бүтцийн үндэс (кодоос нотлогдсон)

### 0.1. Нэг route, гурван дэлгэц

`/ride/driver` бол **ганц go_router зам** (`router.dart:80-83`) бөгөөд `DriverInboxPage`
дотроосоо **гурван өөр Scaffold**-ыг өөрийн төлөвөөр сольж үзүүлдэг (`_buildScaffold`,
`driver_inbox_page.dart:231-299`). Дэлгэц хооронд шилжилт нь `setState`, push биш:

| Нөхцөл (код) | Дэлгэц | Мөр |
|---|---|---|
| `_activeTrip && _awardedHandoff != null` | **S16** идэвхтэй аялал | 233-254 |
| `_awardedHandoff != null` (`_activeTrip == false`) | **S15** аялал өгөгдсөн | 255-287 |
| бусад тохиолдолд | **S14** ойролцоох захиалгын зураг | 288-298 |

Гурвуулангийнх нь AppBar **яг ижил**: гарчиг «Тахь» (`appName`) + баруун талд QR тохиргооны
icon-товч (`_QrSettingsAction`, tooltip `qrCaptureTitle` = «Банкны QR зураг»).

Төлөвийн талбарууд: `_listings` (ирж буй захиалгууд), `_awardedHandoff` (сонгогдсон),
`_activeTrip`, `_tripInFlight`, `_lastOfferedPriceMnt`, `_lastOfferedKmTariffMnt`.
`_finishTrip()` (166-172) бүгдийг цэвэрлээд **S14 руу буцаана** — нэг ээлжинд олон аялал
хийх боломж энэ функцээр л бий.

⚠ **MVP-ийн хязгаар (кодын тайлбар, мөр 30-35):** энэ дэлгэц нэг зэрэг **ганц** идэвхтэй
харилцан үйлдлийг л хөтөлдөг — хэдэн ч санал явуулсан, **хамгийн эхний** ирсэн handoff нь
«өгөгдсөн» болж харагдана. «Явуулсан саналуудын жагсаалт» гэсэн самбар байхгүй.

### 0.2. Push-аар нээгддэг хоёр дэлгэц

| Дэлгэц | Хэрхэн нээгддэг | Route |
|---|---|---|
| **S17** Жолоочийн профайл | «Тохиргоо» → «Жолоочийн профайл» (`settings_page.dart:31-35`) | `context.push('/settings/driver-profile')` |
| **S18** Төлбөрийн QR бүртгэх | S14/S15/S16-ийн AppBar-ийн QR товч (`driver_inbox_page.dart:430-436`) **эсвэл** S13-ийн «QR тавиагүй» блокийн «Зураг сонгох» (`driver_qr_display.dart:30-35`) | `Navigator.push(MaterialPageRoute)` |

Хоёулаа push тул AppBar-т **системийн буцах сум автоматаар** гарна. **Зорилтот төлөв:**
буцах сум ил, 48dp хүрэлтийн талбайтай, tooltip «Буцах» (`backAction`).

### 0.3. Навигацийн одоогийн байдал vs зорилтот төлөв

**Аль хэдийн нэмэгдсэн** (кодоос нотлогдсон):

- `ConfirmLeaveScope` бүх хуудсыг ороосон боловч **зөвхөн** `_activeTrip && _tripInFlight`
  үед идэвхтэй (`driver_inbox_page.dart:222-228`). Өөрөөр хэлбэл **S16-оос гарахад л**
  диалог гарна; S14/S15-аас чөлөөтэй буцна.
- Диалог: гарчиг «Аялалаас гарах уу?» (`leaveTripTitle`), тайлбар `leaveTripMessage`,
  товчнууд «Үлдэх» (`stayAction`) / «Гарах» (`leaveAction`).
- «Гарах» дарвал `_abandonTrip()` (189-207) зорчигч руу `TripPhase.arrived` статус илгээж,
  тэднийг мөнх хүлээх байдалд орхихгүй.
- `onTripSettled` (баримт нийтлэгдсэн/татгалзсан) ирмэгц `_tripInFlight = false` болж
  хамгаалалт унтарна — дууссан дэлгэцээс гарахад диалог **гарахгүй**.
- S17 (`driver_profile_page.dart:18-21`) ба S18 (`driver_qr_capture_page.dart:21-23`)
  дээр `ConfirmLeaveScope` **зориудаар байхгүй**: буруу буцахад дахин бөглөх/дахин зураг
  сонгохоос өөр алдагдал байхгүй, хадгалсан хуучин утга хэвээр үлдэнэ.
- S14-ийн саналын диалогт «Цуцлах» (`cancelAction`) товч **байгаа** (403-406), publish
  явагдаж байх үед идэвхгүйждэг.

**Зорилтот төлөв (дизайнд заавал тусгах):**

1. S14/S15/S16 гурвуулангийн AppBar-т буцах сум **ил харагдана** (48dp).
2. S15 → S14 руу **алхам-буцалт** байх ёстой: одоо код зөвхөн урагшаа явдаг
   (`viewActiveTripAction` → S16), «өгөгдсөн аялал»-аас захиалгын зураг руу буцах
   дотоод алхам байхгүй. Буцах сум дарахад бүтэн хуудаснаас гарах биш, **S14 руу нэг алхам
   ухрах** нь зөв зан төлөв. (Диалог шаардлагагүй — S15 дээр алдагдах зүйл байхгүй.)
3. S16-оос буцахад заавал баталгаажуулах диалог (аль хэдийн бий).
4. S17/S18-ийн буцах сум чөлөөтэй.

### 0.4. Байршил-нууцлалын гол дүрэм (S14-ийн дизайны цөм)

`DriverInboxService.nearbyRequests` нь өөрийн **geohash-6 нүд + 8 хөрш** = 9 нүдээр
subscribe хийдэг (`driver_inbox_service.dart:37-47`). Нийтийн захиалгын эвентэд
зорчигчийн **яг координат огт байдаггүй** — зөвхөн `pickupGeohash`.
`NearbyRequestsLayer` тэр geohash-ийг `geohashDecodeCenter`-ээр задалж **нүдний ТӨВД**
маркер тавьдаг (`nearby_requests_layer.dart:29-31`).

Тоон утга: стандарт geohash-6 нүд ≈ **610 м (хойд-урд) × 820 м (зүүн-баруун)**
(УБ-ын өргөрөгт). Тэгэхээр төв цэг ба бодит цэгийн хоорондох зөрүү ердийн үед
**±300–400 м**, хамгийн муугаар **~±500 м** — бүдүүвчээр «≈ ±600 м».

⚠ **Дизайны сорилт:** одоогийн код 36×36 `person_pin_circle` **нарийн зүү** зурдаг —
энэ нь **хуурамч нарийвчлал** (жолооч тэр яг байшин дээр очиж болно гэж ойлгоно).
Зорилтот дизайн: **цэг биш ТАЛБАЙ** — тасархай захтай нүд + төв дэх жижиг цэг.
Яг координат зөвхөн S15-д (сонгогдсоны дараа, DM-ээр) ирнэ.

### 0.5. Хэв маягийн онцгой анхаарал (энэ бүлэгт хамаарах)

- Энэ бүлгийн кодод **gold текст цаасан дэвсгэр дээр байхгүй** — сайн. Prompt-уудад ч
  gold-ыг зөвхөн **дүүргэлт** болгосон (`gold on paper = 2.28:1`, хориотой).
- `TakhiColors.steppe` (#2E6E5E) цаасан газрын зураг дээр **дүүргэлт/маркер** болж
  ажиллана (5.3:1 текст ч болно). **Харанхуй горимд** энэ унана (2.77:1) —
  `steppeLight #4E9E88` хэрэгтэй (**одоо theme-д байхгүй шинэ токен**).
- ₮-ийн дүн, км-тариф, минут, захиалгын тоо — бүгд `FontFeature.tabularFigures()`.
- Жолооч машин жолоодож байхад хардаг тул: хүрэлт ≥48dp, S16-ийн үндсэн товч ≥64dp.

---

### S14. Жолоочийн inbox — ойролцоох захиалгын газрын зураг

**Файл:** `app/lib/ride/driver_inbox_page.dart` (288-298; давхарга `app/lib/map/nearby_requests_layer.dart` 27-44; урсгал `app/lib/ride/driver_inbox_service.dart` 32-48)
**Зорилго:** ээлж эхлүүлсэн жолооч ойролцоохон хэн дуудлага өгснийг газрын зураг дээр хараад аль нэгийг сонгож үнийн санал явуулна.
**Хаанаас ирнэ:** Нүүр хуудас (S3) — «Жолооч» горим сонгоод «Дуудлага сонсох» (`startAsDriverAction`) товч дарж `/ride/driver` руу push хийгдэнэ.
**Агуулга:** (дээрээс доош)

1. **AppBar** — зүүн талд буцах сум, гарчиг «Тахь» (`appName`), баруун талд QR тохиргооны icon-товч.
2. **Газрын зураг** — дэлгэцийн үлдсэн **бүх** талбай (`RideMap`, OSM tile, төв нь `_myLocation`, эхлэх zoom 15). Зураг чирэхэд `onCenterChanged` ажиллаж `_myLocation` шинэчлэгдэнэ.
3. **Захиалгын маркерууд** — `_listings` бүрд нэг. Одоо: steppe өнгийн 36×36 `person_pin_circle` зүү, нүдний төвд. **Зорилтот:** тасархай захтай ойролцоо талбай + төв цэг (§0.4).
4. **OSM эзэмшигчийн бичиг** — `RichAttributionWidget` (доод буланд, өөрчлөх боломжгүй).
5. **(шинэ) Доод статусын блок** — «хүлээж байна» гэдгийг мэдрүүлэх ганц элемент: хүлээгдэж буй захиалгын **тоо** (том tabular тоо) + амьд төлөвийн pill. arb-д тохирох мөр байхгүй тул шошгыг зохиогоогүй.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | «Буцах» (`backAction`, tooltip) | icon-товч | `ConfirmLeaveScope` идэвхгүй тул шууд поп хийнэ | Нүүр хуудас (S3) |
| AppBar QR товч | «Банкны QR зураг» (`qrCaptureTitle`, tooltip) | icon-товч | QR оруулах хуудсыг push хийнэ | **S18** |
| Захиалгын маркер (талбай) | шошгогүй (зөвхөн дүрс) | газрын зураг дээрх хүрэлт | `_sendOffer(listing)` — эхлээд өөрийн профайлын км-тарифыг локалаас уншаад дараа нь саналын диалог нээнэ | **S14a** давхарга |
| Газрын зураг | — | чирэлт/pinch | pan/zoom; төв өөрчлөгдөнө (шинэ subscribe **автоматаар үүсэхгүй** — урсгал `initState`-д нэг л удаа холбогдоно) | — |
| (шинэ) статусын блок | «(шинэ)» | текст/тоо, үйлдэлгүй | хүлээгдэж буй захиалгын тоо | — |

**Төлөвүүд:**

- **Ачаалж буй:** тусдаа ачаалалтын дэлгэц **байхгүй** — газрын зураг шууд гарч, эвентүүд нэг нэгээрээ дуслаад маркер нэмэгдэнэ. (Хэрэв индикатор нэмэх бол: spinner биш, **3px gold indeterminate bar** AppBar-ийн доор.)
- **Хоосон:** хамгийн түгээмэл төлөв — маркергүй зураг. arb-д тайлбар мөр **байхгүй** → «(шинэ)». Prompt-д зөвхөн байрлал/хэмжээ заасан.
- **Алдаа:** тусдаа алдааны дэлгэц байхгүй. Задалж чадаагүй эвент (`FormatException`) болон хугацаа нь дууссан захиалга (`isExpired`) **чимээгүй** шүүгдэнэ (`driver_inbox_service.dart:46,50-56`).
- **Зөвшөөрөл:** энэ дэлгэц GPS зөвшөөрөл **шаарддаггүй** — байршил нь газрын зургийн төвөөс (`defaultCityConfig` = УБ-ын төв) авагдана, тиймээс зөвшөөрлийн дэлгэц энд гарахгүй.
- **Бүртгэл алга:** `currentIdentityProvider` хоосон бол урсгал огт холбогдохгүй — зураг гарна, маркер хэзээ ч гарахгүй (чимээгүй).

**Stitch prompt:**

```
STYLE — Тахь (Takhi), a Mongolian open-source taxi app. Direction: steppe-print — warm
brutalist, printed-field-manual, never corporate. Ground is warm paper #F4F1E9 (dark mode
#211E19), raised surfaces #E7DEC9, all text and structure near-black ink #1C1A16. Gold
#C99A3C (deep #A67C28) is a structural FILL, never a small accent — gold blocks carry ink
text on them. Steppe green #2E6E5E means live/confirmed; red #9E3327 means danger only.
Depth comes from flat overlapping blocks, 1px hairline and 3px heavy ink rules, and hard
3px solid ink offsets — no blur, no soft shadow, no gradient, no glassmorphism. Typography
is Cyrillic-complete and every visible label is Mongolian Cyrillic: wide heavy display
headings with tight tracking, calm readable body sans, and huge tabular numerals for money,
distance and time. Radius is deliberately mixed: 14px action buttons, 4px cards, fully
round status pills. Spacing is generous and unequal; touch targets are large.

SCREEN — Android mobile app screen: a taxi driver's waiting inbox, a full-bleed map of
nearby ride calls. This is the screen a driver stares at longest in a shift, so it must
read like a field instrument, not an empty page.
Top: a flat app bar on paper ground with no shadow and a 3px solid ink rule along its
bottom edge; a back arrow inside a 48dp touch target on the left, a bold left-aligned
title "Тахь", and a single 48dp icon button on the right showing a QR-code glyph.
Body: a warm paper-toned map with thin ink-drawn roads, no photography, no satellite
imagery. Four waiting ride calls are drawn as AREAS, never as precise pins: each is a
rounded 4px rectangle about one fifth of the screen wide, filled steppe green #2E6E5E at
18% opacity, outlined with a 1.5px DASHED ink #1C1A16 border, with one small solid
steppe-green dot at its exact center. The dashed edge must read as "somewhere inside
here". Two of the areas overlap flatly, with no shadow between them.
Bottom: a floating block over the map, #E7DEC9 fill, 4px radius, hard 3px solid ink
offset down-right, 20px side margins, 20px top padding and 12px bottom padding. On its
left a huge tabular numeral "4" at 72sp ink with a small blank uppercase micro-label slot
above it rendered as "———". On its right a fully round steppe-green #2E6E5E pill sized
for one short uppercase word, its label also rendered as "———".
Do not invent any other text. No blur, no gradient, no drop shadow anywhere.
```

---

### S14a. Үнийн санал илгээх цонх *(S14-ийн дээр гарах давхарга — тусдаа route биш)*

**Файл:** `app/lib/ride/driver_inbox_page.dart` (302-419 `_OfferDialog`; нээх нь 118-158 `_sendOffer`)
**Зорилго:** тухайн захиалгад ямар үнэ, хэдэн минутад хүрэх, ямар машинтайгаа санал болгохоо жолооч бөглөж илгээнэ.
**Хаанаас ирнэ:** S14-ийн газрын зураг дээрх захиалгын талбайд хүрэхэд.
**Агуулга:** дээрээс доош — үнэ, хүрэх хугацаа, машины мэдээлэл гэсэн гурван оролт; дараа нь **зөвхөн** энэ жолооч профайлдаа км-тариф хадгалсан үед (`driverKmTariffMnt != null`) таксиметрийн тэмдэглэгээ; доод талд «Цуцлах» ба «Санал илгээх».

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| Үнийн талбар | «Үнэ (₮)» (`offerPriceFieldLabel`) | тоон оролт | `int.tryParse`; хоосон/буруу бол илгээх **огт ажиллахгүй** (чимээгүй no-op, мөр 338-343) | — |
| Хугацааны талбар | «Хүрэх хугацаа (мин)» (`offerEtaFieldLabel`) | тоон оролт | мөн адил заавал | — |
| Машины талбар | «Машины мэдээлэл» (`offerVehicleFieldLabel`) | текст оролт | шалгалтгүй, хоосон ч болно | — |
| Таксиметрийн тэмдэглэгээ | «Таксиметрээр (миний км-тариф)» (`meteredOfferToggleLabel`) | checkbox | асаавал саналд `kmTariffMnt` хавсаргана → сонгогдвол аялал бүхэлдээ **GPS-таксиметр** горимд орно | — |
| Цуцлах | «Цуцлах» (`cancelAction`) | текст-товч | цонхыг хаана; илгээх явцад **идэвхгүй** | **S14** |
| Санал илгээх | «Санал илгээх» (`sendOfferAction`) | үндсэн товч + ачаалалт | `OfferService.sendOffer` — NIP-17 шифрлэсэн DM-ээр зөвхөн тэр зорчигч руу; амжилттай бол цонх өөрөө хаагдана | **S14** (хүлээх төлөв рүү) |

**Төлөвүүд:** **Ачаалж буй** — «Санал илгээх» товч ачаалалтын байдалд, «Цуцлах» идэвхгүй. **Алдаа** — тусдаа алдааны мессеж **байхгүй** (илгээлт бүтэлгүйтвэл чимээгүй). **Км-тарифгүй жолооч** — checkbox мөр огт харагдахгүй (arb-д `meteredOfferNoTariffHint` «Эхлээд профайлдаа км-тарифаа тохируулна уу» гэсэн мөр байгаа ч энэ цонх түүнийг **ашигладаггүй**).

**Stitch prompt:**

```
STYLE — Тахь (Takhi), a Mongolian open-source taxi app. Direction: steppe-print — warm
brutalist, printed-field-manual, never corporate. Ground is warm paper #F4F1E9 (dark mode
#211E19), raised surfaces #E7DEC9, all text and structure near-black ink #1C1A16. Gold
#C99A3C (deep #A67C28) is a structural FILL, never a small accent — gold blocks carry ink
text on them. Steppe green #2E6E5E means live/confirmed; red #9E3327 means danger only.
Depth comes from flat overlapping blocks, 1px hairline and 3px heavy ink rules, and hard
3px solid ink offsets — no blur, no soft shadow, no gradient, no glassmorphism. Typography
is Cyrillic-complete and every visible label is Mongolian Cyrillic: wide heavy display
headings with tight tracking, calm readable body sans, and huge tabular numerals for money,
distance and time. Radius is deliberately mixed: 14px action buttons, 4px cards, fully
round status pills. Spacing is generous and unequal; touch targets are large.

SCREEN — Android mobile app screen: a modal dialog in which a taxi driver bids on one
waiting ride call. The dialog sits on a dimmed ink scrim over a paper-toned map.
The dialog itself is a paper #F4F1E9 block, 4px radius, no shadow, offset 3px down-right
by a solid ink #1C1A16 shape behind it, with 20px inner padding.
Top of the dialog: a 3px solid ink rule across its full width.
Then three stacked text inputs on paper ground, each with a 1.5px ink border, 4px radius,
and 12px vertical gaps: the first labelled "Үнэ (₮)" holding a large tabular numeral
"12000"; the second labelled "Хүрэх хугацаа (мин)" holding the tabular numeral "7"; the
third labelled "Машины мэдээлэл" holding the text "Prius 30, цагаан". Show the first
input in the focused state with a 3px gold #C99A3C border instead of the ink one.
Below the inputs a full-width 1px ink hairline at 20% opacity, then a checkbox row with a
square 24dp ink-outlined checkbox, checked with a solid gold #C99A3C fill and an ink tick,
labelled "Таксиметрээр (миний км-тариф)" — the label wraps to two lines.
Bottom, after a 20px gap: a right-aligned row with a plain text button reading "Цуцлах"
in ink, then a solid gold #C99A3C button with 14px radius, 18px vertical padding and a
bold ink label "Санал илгээх".
No blur, no gradient, no drop shadow anywhere.
```

---

### S15. Аялал өгөгдсөн — зорчигчийн яг байршил ирлээ

**Файл:** `app/lib/ride/driver_inbox_page.dart` (255-287; өгөгдөл `app/lib/ride/handoff_service.dart` 59-69, `RideHandoffPayload` `ride_dm_payload.dart:179-227`)
**Зорилго:** зорчигч энэ жолоочийг сонгосныг мэдэгдэж, урьд нь зөвхөн ойролцоо талбайгаар харагдаж байсан **яг** очих цэгийг анх удаа үзүүлж, аялал руу орох ганц товч өгнө.
**Хаанаас ирнэ:** S14-ээс — санал илгээсний дараа зорчигч тэр саналыг сонгоход handoff DM ирж, хуудас автоматаар энэ дэлгэц рүү сэлгэнэ (`_handoffSubscription`, мөр 98-104). Хэрэглэгчийн товч дарах шаардлагагүй.
**Агуулга:** (дээрээс доош, бүгд дэлгэцийн голд төвлөрсөн, 24px padding)

1. **AppBar** — буцах сум, «Тахь» (`appName`), QR icon-товч.
2. **Гарчиг** — «Зорчигчийн яг байршил» (`handoffReceivedTitle`), w600.
3. **Plus Code** — `handoff.payload.plusCode` (жишээ `RPXQ+FQ`), богино техникийн код.
4. **Тэмдэглэл** — `handoff.payload.landmarkText`, зорчигчийн чөлөөт текст (жишээ «цагаан хаалга»), голлуулсан.
5. **Үндсэн товч** — «Аялал эхлүүлэх» (`viewActiveTripAction`).

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | «Буцах» (`backAction`, tooltip) | icon-товч | **зорилтот:** нэг алхам ухарч захиалгын зураг руу (одоо код бүтэн хуудаснаас гаргадаг) | **S14** |
| AppBar QR товч | «Банкны QR зураг» (`qrCaptureTitle`, tooltip) | icon-товч | QR хуудсыг push хийнэ | **S18** |
| Plus Code | — (динамик утга) | текст | сонгож хуулах боломж **байхгүй** | — |
| Тэмдэглэлийн текст | — (динамик утга) | текст | үйлдэлгүй | — |
| «Аялал эхлүүлэх» | «Аялал эхлүүлэх» (`viewActiveTripAction`) | үндсэн товч | `_activeTrip = true`, `_tripInFlight = true` — GPS хяналт, амьд байршил, дуудлага, SOS бүхий аялал эхэлнэ | **S16** |
| (санал) Тохирсон үнийн мөр | «Тохирсон үнэ: {price}₮» (`agreedPriceLabel`) | текст | **одоо кодод байхгүй.** Түлхүүр нь arb-д аль хэдийн бий; жолооч ямар үнээр тохирснаа энд эргэж харах ёстой | — |

**Төлөвүүд:**

- **Ачаалж буй:** байхгүй — энэ дэлгэц зөвхөн өгөгдөл бүрэн ирсэн үед л оршино.
- **Хоосон/алдаа:** байхгүй. Тэмдэглэлийн текст хоосон байж болно (зорчигч бөглөөгүй) → тэр мөр хоосон зайгаар үлдэнэ.
- **Утасны дугаар:** payload-д байж болох ч (`phone`, зөвхөн зорчигч хуваалцахаар тохируулсан бол) **энэ дэлгэц дээр огт харагддаггүй** — цаашаа S16-д дуудлагын нөөц суваг болж дамждаг.
- **Олон handoff:** хоёр дахь handoff ирвэл эхнийхийг **дарж бичнэ** (§0.1-ийн MVP хязгаар).

**Stitch prompt:**

```
STYLE — Тахь (Takhi), a Mongolian open-source taxi app. Direction: steppe-print — warm
brutalist, printed-field-manual, never corporate. Ground is warm paper #F4F1E9 (dark mode
#211E19), raised surfaces #E7DEC9, all text and structure near-black ink #1C1A16. Gold
#C99A3C (deep #A67C28) is a structural FILL, never a small accent — gold blocks carry ink
text on them. Steppe green #2E6E5E means live/confirmed; red #9E3327 means danger only.
Depth comes from flat overlapping blocks, 1px hairline and 3px heavy ink rules, and hard
3px solid ink offsets — no blur, no soft shadow, no gradient, no glassmorphism. Typography
is Cyrillic-complete and every visible label is Mongolian Cyrillic: wide heavy display
headings with tight tracking, calm readable body sans, and huge tabular numerals for money,
distance and time. Radius is deliberately mixed: 14px action buttons, 4px cards, fully
round status pills. Spacing is generous and unequal; touch targets are large.

SCREEN — Android mobile app screen: the moment a passenger has picked THIS driver and
their exact pickup point has arrived. It should feel like a printed dispatch ticket, not
a notification.
Top: a flat app bar on paper ground with a 3px solid ink rule along its bottom edge, a
back arrow in a 48dp touch target on the left, bold left-aligned title "Тахь", and one
48dp QR-code icon button on the right.
Centre of the screen, one vertically centred ticket block on #E7DEC9 with 4px radius,
28px inner padding, no shadow, offset 3px down-right by a solid ink #1C1A16 shape:
— a heavy wide heading in ink with tight tracking reading "Зорчигчийн яг байршил";
— a 3px solid ink rule under it, full block width;
— the Plus Code "RPXQ+FQ" set very large in tabular monospaced ink figures with wide
  letter spacing, the single loudest element on the screen;
— under it the passenger's landmark note "цагаан хаалга" in calm body sans, centred, in
  ink at 80% opacity;
— a 1px ink hairline at 20% opacity, then a single line reading "Тохирсон үнэ: 12000₮"
  with the amount in tabular figures.
Bottom of the screen, pinned with 20px side margins and 32px above it: a full-width solid
gold #C99A3C button, 14px radius, 18px vertical padding, centred bold ink label
"Аялал эхлүүлэх".
No blur, no gradient, no drop shadow anywhere.
```

---

### S16. Жолоочийн идэвхтэй аялал (бүрхүүл)

**Файл:** `app/lib/ride/driver_inbox_page.dart` (233-254 — бүрхүүл; хамгаалалт 209-229; дотоод агуулга `app/lib/ride/active_trip_view.dart`)
**Зорилго:** аялал үргэлжлэх бүх хугацаанд жолооч ганц дэлгэцээс байршил, фаз, холбоо барих, төлбөрийн QR-аа бариад, төгсгөлд нь баримтаа нийтэлнэ.
**Хаанаас ирнэ:** S15-ийн «Аялал эхлүүлэх» товчоор.
**Агуулга:** (дээрээс доош)

1. **AppBar** — буцах сум (**хамгаалалттай**), гарчиг «Тахь» (`appName`), баруун талд QR icon-товч. ⚠ Энэ QR товч аяллын **дунд ч зориудаар үлддэг** (кодын тайлбар, мөр 237-240): зорчигч төгсгөлд яг үүнийг уншуулах тул алга болбол хамгийн хэрэгтэй мөчид олдохгүй болно.
2. **Бүх бие** — `ActiveTripView(role: TripRole.driver, …)`. Дотоод дөрвөн алхам (аялал явж байна → үнэ батлах → үнэлгээ → дууссан) **`docs/design/screens/03-active-trip.md` (S10–S13)**-д бүрэн тайлбарлагдсан. Энэ хэсэг зөвхөн **бүрхүүлийг** тодорхойлно.

Бүрхүүлээс `ActiveTripView` руу дамжих утгууд (мөр 243-252): `tripId` = handoff-ийн trip id; `counterpartyPubHex` = handoff илгээгчийн түлхүүр; `agreedPriceMnt` = `_lastOfferedPriceMnt ?? 0`; `counterpartyPhone` = handoff-ийн утас (байвал); `kmTariffMnt` = `_lastOfferedKmTariffMnt` (S14a-д таксиметр сонгосон бол). **`kmTariffMnt` нь null эсэх нь** аяллыг тогтмол үнэтэй эсвэл GPS-таксиметртэй болгодог — тусдаа «горим» тохиргоо байхгүй.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум (аялал явж байхад) | «Буцах» (`backAction`, tooltip) | icon-товч | `ConfirmLeaveScope` таслаж баталгаажуулах диалог гаргана | ↓ диалогийн мөрүүд |
| Диалог — гарчиг/тайлбар | «Аялалаас гарах уу?» (`leaveTripTitle`) / `leaveTripMessage` | диалог | алдагдах зүйлийг тодорхой хэлнэ | — |
| Диалог — үлдэх | «Үлдэх» (`stayAction`) | текст-товч | юу ч болохгүй, аялал үргэлжилнэ | **S16** |
| Диалог — гарах | «Гарах» (`leaveAction`) | текст-товч | `_abandonTrip()` зорчигч руу «хүрлээ» статус илгээж тэднийг чөлөөлнө; энэ тал баримт нийтлэхгүй | Нүүр хуудас (S3) |
| AppBar буцах сум (аялал дууссаны дараа) | «Буцах» (`backAction`, tooltip) | icon-товч | `onTripSettled` ажилласан тул хамгаалалт **унтарсан** — диалоггүй шууд гарна | Нүүр хуудас (S3) |
| AppBar QR товч | «Банкны QR зураг» (`qrCaptureTitle`, tooltip) | icon-товч | QR хуудсыг push хийнэ (аяллын дунд ч ажиллана) | **S18** |
| Доод үндсэн товч (фаз = ирж байна) | «Зорчигч сууллаа» (`markPassengerBoardedAction`) | үндсэн товч | фазыг «явцад» болгож зорчигч руу DM илгээнэ | **S16** (фаз солигдоно) |
| Доод үндсэн товч (фаз = явцад) | «Аялал дууслаа» (`endTripAction`) | үндсэн товч | таксиметртэй бол эцсийн дүнг бодож илгээнэ, GPS/relay-г таслана | **S16** → үнэлгээний алхам |
| Дууссан дэлгэцийн товч | «Аяллыг дуусгах» (`finishTripAction`) | үндсэн товч | `_finishTrip()` — бүх аяллын төлөв цэвэрлэгдэж дараагийн дуудлага сонсох байдалд эргэнэ | **S14** |

**Төлөвүүд:**

- **Ачаалж буй:** эхний GPS fix ирэх хүртэл өөрийн маркер зурагт байхгүй (03-д дэлгэрэнгүй).
- **Зөвшөөрөл татгалзсан:** бүх бие `LocationPermissionDeniedView` болж солигдоно — «Аялал хянахын тулд байршлын зөвшөөрөл шаардлагатай» (`locationPermissionNeededHint`) + «Зөвшөөрөл өгөх» (`grantLocationPermissionAction`). **AppBar (буцах сум, QR товч) хэвээр үлдэнэ** — энэ бол бүрхүүлийн үүрэг.
- **Хоосон/алдаа:** бүрхүүлийн түвшинд байхгүй.
- **Хамгаалалт унтрах цэг:** `onTripSettled` (баримт нийтлэгдсэн **эсвэл** зорчигч дүнг татгалзсан) → тэр мөчөөс буцах чөлөөтэй.

**Stitch prompt:**

```
STYLE — Тахь (Takhi), a Mongolian open-source taxi app. Direction: steppe-print — warm
brutalist, printed-field-manual, never corporate. Ground is warm paper #F4F1E9 (dark mode
#211E19), raised surfaces #E7DEC9, all text and structure near-black ink #1C1A16. Gold
#C99A3C (deep #A67C28) is a structural FILL, never a small accent — gold blocks carry ink
text on them. Steppe green #2E6E5E means live/confirmed; red #9E3327 means danger only.
Depth comes from flat overlapping blocks, 1px hairline and 3px heavy ink rules, and hard
3px solid ink offsets — no blur, no soft shadow, no gradient, no glassmorphism. Typography
is Cyrillic-complete and every visible label is Mongolian Cyrillic: wide heavy display
headings with tight tracking, calm readable body sans, and huge tabular numerals for money,
distance and time. Radius is deliberately mixed: 14px action buttons, 4px cards, fully
round status pills. Spacing is generous and unequal; touch targets are large.

SCREEN — Android mobile app screen: the live trip as the DRIVER sees it, shown together
with the confirmation dialog that appears when the driver tries to leave mid-trip.
Behind the dialog: a flat app bar on paper ground with a 3px solid ink rule along its
bottom edge, a back arrow in a 48dp target on the left, a bold left-aligned title "Тахь",
and one 48dp QR-code icon button on the right. Under it a status strip with 20px top and
12px bottom padding: on the left a fully round steppe-green #2E6E5E pill with white
uppercase text "Аяллын явцад"; on the right three 48dp square icon buttons with 1.5px ink
borders and 4px radius — share, phone, and, after a deliberate 20px gap, an emergency
button with a 1.5px red #9E3327 border and red glyph. Below that a warm paper-toned map
with ink-drawn roads filling the rest, and pinned at the bottom a full-width solid gold
#C99A3C button with 14px radius, 20px vertical padding and a bold ink label
"Аялал дууслаа", at least 64dp tall.
In front: an ink scrim at 55% and a centred paper #F4F1E9 dialog, 4px radius, 3px solid
ink offset down-right, 24px padding — a heavy ink heading "Аялалаас гарах уу?", a 3px ink
rule, three lines of calm body text, then a right-aligned row with a plain ink text button
"Үлдэх" and a text button "Гарах" in red #9E3327.
No blur, no gradient, no drop shadow anywhere.
```

---

### S17. Жолоочийн профайл

**Файл:** `app/lib/profile/driver_profile_page.dart` (бүтнээр; хадгалалт `app/lib/profile/driver_profile_service.dart` 16-46)
**Зорилго:** жолооч машин, өнгө, улсын дугаар, км-тарифаа нэг удаа бөглөж, нийтийн kind-0 Nostr профайл болгон нийтлэн, км-тарифаа саналын урсгалд бэлэн болгоно.
**Хаанаас ирнэ:** Нүүр хуудасны тохиргооны араа → «Тохиргоо» → «Жолоочийн профайл» (`settingsDriverProfileMenuLabel`), `/settings/driver-profile` руу push.
**Агуулга:** (дээрээс доош, 16px padding, гүйлгэдэг)

1. **AppBar** — буцах сум, гарчиг «Жолоочийн профайл» (`driverProfileTitle`), elevation 0, surface өнгө, баруун талд үйлдэл **байхгүй**.
2. **«Нэр»** оролт (`driverProfileNameFieldLabel`), OutlineInputBorder.
3. **«Машины загвар»** оролт (`driverProfileCarFieldLabel`).
4. **«Өнгө»** оролт (`driverProfileColorFieldLabel`).
5. **«Улсын дугаар»** оролт (`driverProfilePlateFieldLabel`).
6. **«Км-тариф (₮/км)»** оролт (`driverProfileKmTariffFieldLabel`), тоон гар.
7. **«Хадгалах»** үндсэн товч (`saveDriverProfileAction`).

Хуудас нээгдмэгц өмнө хадгалсан профайл локалаас уншигдаж талбарууд **урьдчилан бөглөгдөнө** (`initState`, мөр 38-48).

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | «Буцах» (`backAction`, tooltip) | icon-товч | хамгаалалтгүй — шууд гарна, хагас бөглөсөн маягт устана (хадгалсан хуучин утга хэвээр) | Тохиргоо (S4) |
| Нэрийн талбар | «Нэр» (`driverProfileNameFieldLabel`) | текст оролт | хоосон биш байх шаардлагатай | — |
| Машины загвар | «Машины загвар» (`driverProfileCarFieldLabel`) | текст оролт | хоосон биш байх шаардлагатай | — |
| Өнгө | «Өнгө» (`driverProfileColorFieldLabel`) | текст оролт | хоосон биш байх шаардлагатай | — |
| Улсын дугаар | «Улсын дугаар» (`driverProfilePlateFieldLabel`) | текст оролт | хоосон биш байх шаардлагатай | — |
| Км-тариф | «Км-тариф (₮/км)» (`driverProfileKmTariffFieldLabel`) | тоон оролт | бүхэл тоо болж задрах ёстой; **энэ утга л** S14a-ийн таксиметрийн сонголтыг нээдэг | — |
| Хадгалах | «Хадгалах» (`saveDriverProfileAction`) | үндсэн товч | 5 талбар бүгд зөв бол л идэвхтэй; kind-0 эвент гарын үсэг зурж бүх relay руу нийтлээд локалд хуулбарлана | Тохиргоо (S4) руу поп + snackbar |
| Баталгаажуулалт | «Профайл хадгалагдлаа» (`driverProfileSavedConfirmation`) | snackbar | амжилтыг мэдэгдэнэ | — |

**Төлөвүүд:**

- **Ачаалж буй:** хадгалах явцад товч ачаалалтын байдалд (`_saving`). Хуудас нээгдэх үеийн локал уншилтад индикатор **байхгүй** — талбарууд эхлээд хоосон, дараа нь дүүрнэ.
- **Хоосон:** анх удаа орж буй жолоочид бүх талбар хоосон, «Хадгалах» **идэвхгүй**.
- **Алдаа:** тусдаа алдааны заалт **байхгүй** — relay-д нийтлэх бүтэлгүйтвэл хэрэглэгчид харагдахгүй. (Одоогийн зан төлөв; сайжруулах бол шинэ arb мөр хэрэгтэй.)
- **Зөвшөөрөл:** шаардлагагүй.

**Stitch prompt:**

```
STYLE — Тахь (Takhi), a Mongolian open-source taxi app. Direction: steppe-print — warm
brutalist, printed-field-manual, never corporate. Ground is warm paper #F4F1E9 (dark mode
#211E19), raised surfaces #E7DEC9, all text and structure near-black ink #1C1A16. Gold
#C99A3C (deep #A67C28) is a structural FILL, never a small accent — gold blocks carry ink
text on them. Steppe green #2E6E5E means live/confirmed; red #9E3327 means danger only.
Depth comes from flat overlapping blocks, 1px hairline and 3px heavy ink rules, and hard
3px solid ink offsets — no blur, no soft shadow, no gradient, no glassmorphism. Typography
is Cyrillic-complete and every visible label is Mongolian Cyrillic: wide heavy display
headings with tight tracking, calm readable body sans, and huge tabular numerals for money,
distance and time. Radius is deliberately mixed: 14px action buttons, 4px cards, fully
round status pills. Spacing is generous and unequal; touch targets are large.

SCREEN — Android mobile app screen: a taxi driver's own public profile form — the card a
passenger will judge them by, so it should read like a filled-in vehicle registration
slip rather than a settings page.
Top: a flat app bar on paper ground, no shadow, a 3px solid ink rule along its bottom
edge, a back arrow inside a 48dp touch target on the left, and a bold left-aligned title
"Жолоочийн профайл".
Body on paper ground with 20px side padding. Four text inputs stacked with 20px gaps,
each on paper with a 1.5px ink #1C1A16 border, 4px radius, its label sitting above the
box in small uppercase ink with wide letter spacing: "Нэр" filled with "Батбаяр",
"Машины загвар" filled with "Toyota Prius 30", "Өнгө" filled with "Цагаан",
"Улсын дугаар" filled with "1234 УБА" set in wide tabular figures.
Then a 3px solid ink section rule across the width, with 32px of space above it.
Below the rule the tariff field is treated differently and louder: label
"Км-тариф (₮/км)" in small uppercase ink, and the value "1200" as a huge tabular numeral
at 64sp sitting inside a #E7DEC9 block with 4px radius and a hard 3px solid ink offset.
Bottom: a full-width solid gold #C99A3C button, 14px radius, 18px vertical padding,
centred bold ink label "Хадгалах".
No blur, no gradient, no drop shadow anywhere.
```

---

### S18. Төлбөрийн QR бүртгэх

**Файл:** `app/lib/payment/driver_qr_capture_page.dart` (бүтнээр; хадгалалт `app/lib/payment/driver_qr_store.dart`, кэш `app/lib/payment/payment_providers.dart`)
**Зорилго:** жолооч банкны QR зургаа галерейгаас сонгож утсандаа **зөвхөн локал** хадгалж, аяллын төгсгөлд зорчигчид үзүүлэх бэлтгэл хийнэ.
**Хаанаас ирнэ:** (а) S14/S15/S16-ийн AppBar-ийн QR icon-товчоор; (б) аялал дууссаны дараах дэлгэцээс (S13) QR тавиагүй үед гарах «Зураг сонгох» текст-товчоор.
**Агуулга:** (дээрээс доош, 24px padding)

1. **AppBar** — буцах сум, гарчиг «Банкны QR зураг» (`qrCaptureTitle`), баруун талд үйлдэл байхгүй.
2. **Урьдчилан харах талбай** — дэлгэцийн үлдсэн ихэнхийг эзэлнэ (`Expanded` + `Center`): зураг сонгоогүй бол «Та банкны QR-аа хараахан оруулаагүй байна» (`qrNotSetHint`) гэсэн голлуулсан текст; сонгосон бол 240×240 зураг.
3. **«Зураг сонгох»** — тойрог-зурвастай (outlined) товч (`qrCaptureAction`), галерей нээнэ.
4. **«Хадгалах»** — үндсэн товч (`qrSaveAction`), зураг сонгох хүртэл **идэвхгүй**.

⚠ **Нууцлал:** QR зураг файл болж зөвхөн аппын хувийн лавлахад (`driver_qr.bin`) бичигдэнэ — **relay руу хэзээ ч нийтлэгддэггүй** (spec §8). Камерын зөвшөөрөл огт шаардахгүй, зөвхөн галерей.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | «Буцах» (`backAction`, tooltip) | icon-товч | хамгаалалтгүй — сонгосон боловч хадгалаагүй зураг л алдагдана | өмнөх дэлгэц (S14/S15/S16 эсвэл S13) |
| Урьдчилан харах талбай | «Та банкны QR-аа хараахан оруулаагүй байна» (`qrNotSetHint`) — зөвхөн хоосон үед | текст / зураг | үйлдэлгүй (хүрэхэд зураг сонгогддоггүй) | — |
| «Зураг сонгох» | «Зураг сонгох» (`qrCaptureAction`) | outlined товч | OS-ийн галерей нээж, сонгосон зургийн байтыг санах ойд авна | Системийн зураг сонгогч → буцаад **S18** |
| «Хадгалах» | «Хадгалах» (`qrSaveAction`) | үндсэн товч + ачаалалт | файлд бичээд кэшийг хүчингүй болгож (доорх дэлгэц шинэ QR-аа шууд харна) буцна | өмнөх дэлгэц + snackbar |
| Амжилтын мэдэгдэл | «QR хадгалагдлаа» (`qrSavedConfirmation`) | snackbar | — | — |
| Алдааны мэдэгдэл | «QR хадгалж чадсангүй. Дахин оролдоно уу.» (`qrSaveError`) | snackbar | диск дүүрсэн/эрх хүрэхгүй зэрэг тохиолдолд; хуудас **хаагдахгүй**, дахин оролдож болно | **S18** |

**Төлөвүүд:**

- **Ачаалж буй:** «Хадгалах» товч ачаалалтын байдалд. Галерейгаас байт унших хугацаанд тусдаа индикатор байхгүй.
- **Хоосон (анхны):** том хоосон талбай + «Та банкны QR-аа хараахан оруулаагүй байна», «Хадгалах» идэвхгүй.
- **Алдаа:** зөвхөн хадгалалтын алдаа (`qrSaveError` snackbar). Зураг сонгохыг цуцлавал юу ч болохгүй.
- **Зөвшөөрөл:** камерын зөвшөөрөл **шаардахгүй**; галерейн зөвшөөрлийг систем өөрөө асууна, апп дотор тусгай дэлгэц байхгүй.

**Stitch prompt:**

```
STYLE — Тахь (Takhi), a Mongolian open-source taxi app. Direction: steppe-print — warm
brutalist, printed-field-manual, never corporate. Ground is warm paper #F4F1E9 (dark mode
#211E19), raised surfaces #E7DEC9, all text and structure near-black ink #1C1A16. Gold
#C99A3C (deep #A67C28) is a structural FILL, never a small accent — gold blocks carry ink
text on them. Steppe green #2E6E5E means live/confirmed; red #9E3327 means danger only.
Depth comes from flat overlapping blocks, 1px hairline and 3px heavy ink rules, and hard
3px solid ink offsets — no blur, no soft shadow, no gradient, no glassmorphism. Typography
is Cyrillic-complete and every visible label is Mongolian Cyrillic: wide heavy display
headings with tight tracking, calm readable body sans, and huge tabular numerals for money,
distance and time. Radius is deliberately mixed: 14px action buttons, 4px cards, fully
round status pills. Spacing is generous and unequal; touch targets are large.

SCREEN — Android mobile app screen: a taxi driver registering their own bank payment QR
image, which is stored only on the phone. Show the EMPTY state, before any image has been
picked.
Top: a flat app bar on paper ground, no shadow, a 3px solid ink rule along its bottom
edge, a back arrow inside a 48dp touch target on the left, and a bold left-aligned title
"Банкны QR зураг".
Centre, filling most of the screen: a large square placeholder about 260dp wide, centred,
drawn on #E7DEC9 with 4px radius and a 1.5px DASHED ink #1C1A16 border, no shadow and no
offset — it is a hole, not a card. Inside it a simple ink outline of a QR frame at low
contrast, and below that, centred on paper ground outside the square, two lines of calm
body sans in ink at 80% opacity reading
"Та банкны QR-аа хараахан оруулаагүй байна".
Bottom, stacked with 20px side margins: first an outlined button with a 1.5px ink border,
transparent fill, 14px radius, 18px vertical padding and a centred bold ink label
"Зураг сонгох"; 20px under it a full-width button with 14px radius and 18px vertical
padding in its DISABLED state — a flat #E7DEC9 fill with a 1.5px ink border at 30%
opacity and the label "Хадгалах" in ink at 35% opacity, clearly not tappable yet.
No blur, no gradient, no drop shadow anywhere.
```

---

## 5. Нэгтгэлд дамжуулах тэмдэглэл

1. **S14 бол ганцхан жинхэнэ «уйтгартай» дэлгэц** — ээлжийн ихэнх цаг энд өнгөрнө. Дизайны
   гол шийдэл: хуурамч нарийвчлал үзүүлэхгүйгээр (**талбай, зүү биш**) хүлээлтийг мэдээлэл
   болгож харуулах (тоо + амьд pill).
2. **S14-ийн хоосон төлөв ба статусын шошгонд arb мөр байхгүй** — «(шинэ)». Хэрэв нэмэх бол
   `app_mn.arb`-д шинэ түлхүүр шаардлагатай; энэ баримт бичиг үг зохиогүй.
3. **S15-д «Тохирсон үнэ: {price}₮» (`agreedPriceLabel`) мөр нэмэхийг санал болгов** —
   түлхүүр аль хэдийн arb-д байгаа; жолооч ямар үнээр тохирсноо handoff дэлгэцээс харах ёстой.
4. **S15 → S14 руу алхам-буцалт хийх шаардлагатай** (одоо байхгүй) — навигацийн ажилтай
   шууд холбогдоно.
5. **Харанхуй горим:** S14-ийн steppe маркер/pill, S16-ийн steppe фазын pill нь харанхуйд
   унана → `steppeLight #4E9E88` шинэ токен хэрэгтэй; өргөгдсөн гадаргуу `#2C2822`.
6. **S16-ийн дотоод агуулгыг давхардуулж бүү бич** — S10–S13 нь `03-active-trip.md`-д бий.
   Энэ бүлэг зөвхөн жолоочийн бүрхүүл (AppBar + QR үйлдэл + гарах хамгаалалт)-ийг эзэмшинэ.
