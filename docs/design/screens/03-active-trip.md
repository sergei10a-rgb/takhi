# 03 — Идэвхтэй аялал (S10–S13) · Тахь

> Хэв маяг: `docs/design/screens/00-style.md` (§2 STYLE PREAMBLE) — доорх prompt бүр түүгээр эхэлнэ.
> Эх код: `app/lib/ride/active_trip_view.dart` (бүтнээр), `app/lib/ride/trip_phase.dart`,
> `app/lib/ride/trip_role.dart`, `app/lib/ride/live_location_channel.dart`,
> `app/lib/payment/driver_qr_display.dart`, `app/lib/safety/sos_button.dart`,
> `app/lib/l10n/app_mn.arb`.
> Хостууд: `app/lib/ride/passenger_ride_page.dart`, `app/lib/ride/driver_inbox_page.dart`.
>
> **Монгол текст бүр `app_mn.arb`-аас авсан.** arb-д байхгүйг «(шинэ)» гэж тэмдэглэв.

---

## 0. Энэ бүлгийн бүтцийн үндэс (кодоос нотлогдсон)

`ActiveTripView` бол **route биш, шигтгэгдсэн харагдац**: өөрийн `go_router` зам, өөрийн AppBar
байхгүй (`active_trip_view.dart:44-47`). AppBar/Scaffold-ыг хост хуудас өгдөг:

| Хост | AppBar гарчиг | AppBar-ийн үйлдэл | Файл |
|---|---|---|---|
| Зорчигч | «Тахь» (`appName`) | байхгүй | `passenger_ride_page.dart:290` |
| Жолооч | «Тахь» (`appName`) | QR тохиргоо (tooltip `qrCaptureTitle` = «Банкны QR зураг») | `driver_inbox_page.dart:235-241` |

Дотоод дөрвөн алхам = `enum _ActiveTripStep { tracking, fareConfirm, rating, done }`
(`active_trip_view.dart:41`), сонголт нь `build`-ийн `switch (_step)` (мөр 488-542).

**Хоёр үүрэг (`TripRole`)** нэг л виджетэд шигтгэгддэг тул алхам бүрт ялгаа гарна:

| Алхам | Зорчигч | Жолооч |
|---|---|---|
| S10 tracking | доод товч **байхгүй**; фазыг DM-ээр хүлээж авна (`_startTracking`, мөр 215-234) | доод товч фазаас хамаарч солигдоно; фазыг **өөрөө** илгээнэ (`_markPassengerBoarded`, `_endTrip`) |
| S11 fareConfirm | **зөвхөн энэ тал** харна, тэр ч байтугай зөвхөн таксиметртэй үед | **хэзээ ч харахгүй** — шууд S12 руу (мөр 416-427) |
| S12 rating | ижил UI | ижил UI (үүргийн салаа байхгүй, мөр 682-748) |
| S13 done | «QR уншуулах эсвэл бэлнээр» текст | өөрийн банкны QR зураг (`DriverQrDisplay`) |

**Хоёр үнийн горим** (кодын нотолгоо): `ActiveTripView.kmTariffMnt == null` бол **урьдчилан
тохирсон тогтмол үнэ** — `_finalFareMnt` мөнх `null` тул `_stopTrackingAndMoveToRating` шууд
`rating` руу үсэрч, баримтад `widget.agreedPriceMnt` бичигдэнэ (мөр 421-427, 464).
`kmTariffMnt != null` бол **GPS-таксиметр**: жолооч «Аялал дууслаа» дарахад `_endTrip`
`computeFareMnt(mntPerKm:, distanceMeters: _track.distanceMeters)`-оор дүнг **нэг удаа** бодож
(мөр 346-353) статус DM-ийн `finalFareMnt`-аар зорчигч руу явуулна; зорчигч тал түүнийг
`ReceivedTripStatus.finalFareMnt`-аас хуулж (мөр 227-232) **S11 гарц**-аар дамжина.

**Навигаци (одоогийн байдал):** буцах хамгаалалт **аль хэдийн нэмэгдсэн** —
`ConfirmLeaveScope` (`app/lib/widgets/confirm_leave_scope.dart`) хоёр хостод хоёуланд нь
идэвхтэй: жолооч `_activeTrip && _tripInFlight` (мөр 222-228), зорчигч `_isRequestLive`
(мөр 368-380). Диалог: гарчиг «Аялалаас гарах уу?» (`leaveTripTitle`), тайлбар
`leaveTripMessage`, товчнууд «Үлдэх» (`stayAction`) / «Гарах» (`leaveAction`).
`onTripSettled` (баримт нийтлэгдсэн эсвэл татгалзсан) дуудагдмагц хамгаалалт унтарч,
S13-аас буцахад диалог гарахаа болино. **Зорилтот төлөв**: AppBar-т буцах сум ил харагдана
(48dp), S10/S11/S12-оос буцахад диалог, S13-аас чөлөөтэй.

---

## S10. Аялал явж байна

**Файл:** `app/lib/ride/active_trip_view.dart` (546-680 `_TrackingView`; сонголт 488-523; SOS 626)
**Зорилго:** аялал үргэлжлэх бүх хугацаанд эсрэг талын байршил, аяллын фаз, холбоо барих ба яаралтай тусламжийг нэг дэлгэцээс алдалгүй барих.
**Хаанаас ирнэ:** зорчигч — `PassengerRidePage._DoneStep`-ийн «Аялал руу очих» (`startTripAction`) товчоор; жолооч — `DriverInboxPage`-ийн handoff дэлгэц дээрх «Аялал эхлүүлэх» (`viewActiveTripAction`) товчоор.
**Агуулга:** (дээрээс доош)

1. **Хостын AppBar** — гарчиг «Тахь» (`appName`), буцах сум; жолоочид QR тохиргооны үйлдэл.
2. **Фазын мөр** (Padding 12, Row): зүүн талд фазын шошго (одоо gold, w600), баруун талд дараалан — хуваалцах, дуудлага, SOS гурван icon-товч.
3. **Таксиметрийн дүн** — зөвхөн `liveFareMnt != null` үед: «Одоогийн дүн: {mnt}₮» (зүүн зэрэгцүүлсэн, 20sp, bold).
4. **Дуут зурвасын тууз** — зөвхөн зурвас ирсэн бол: `Wrap` доторх `ActionChip`-ууд, gold дэвсгэр, ink play/stop дүрс, шошго «Тоглуулах» + `(Ns)` үргэлжлэх хугацаа.
5. **Газрын зураг** (`RideMap`, `Expanded` — дэлгэцийн үлдсэн бүх талбай): өөрийн байршил = `my_location` gold, эсрэг тал = `directions_car` ink. Байршил мэдэгдэхгүй бол зураг хотын төв дээр (`defaultCityConfig`) төвлөрнө.
6. **Доод үндсэн товч — ЗӨВХӨН ЖОЛООЧИД** (Padding 16), фазаас хамаарна.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | «Буцах» (`backAction`, tooltip) | icon-товч | `ConfirmLeaveScope` гацаана | Диалог «Аялалаас гарах уу?» → «Гарах» бол хуудаснаас гарч, нөгөө талд `TripPhase.arrived` илгээнэ |
| AppBar QR (жолооч) | «Банкны QR зураг» (`qrCaptureTitle`, tooltip) | icon-товч | QR оруулах хуудас нээнэ | `DriverQrCapturePage` |
| Фазын шошго | «Жолооч ирж байна» / «Аяллын явцад» / «Хүрлээ» (`tripPhaseEnRouteToPickup` / `tripPhaseInProgress` / `tripPhaseArrived`) | текст (үйлдэлгүй) | зөвхөн төлөв харуулна | — |
| Хуваалцах | «Аялал хуваалцах» (`shareTripAction`, tooltip) | icon-товч | `ShareSession` үүсгэж, аяллын холбоосыг OS-ийн share хуудсаар илгээнэ | Системийн share sheet |
| Дуудлага | «Дуудлага хийх» (`startCallAction`, tooltip) | icon-товч | апп доторх дуут дуудлага эхлүүлнэ | `CallScreen` (push) |
| SOS | «SOS» (`sosAction`, tooltip) | icon-товч, улаан | доод хуудас (bottom sheet) нээнэ | ↓ SOS хуудсын мөрүүд |
| SOS → цагдаа | «102 — цагдаа» (`sosCallPoliceAction`) | жагсаалтын мөр | `tel:` URI-г OS-д дамжуулна | Утасны залгагч |
| SOS → түргэн | «103 — түргэн тусламж» (`sosCallAmbulanceAction`) | жагсаалтын мөр | `tel:` URI-г OS-д дамжуулна | Утасны залгагч |
| SOS → SMS | «Яаралтай холбоо барих хүнд SMS» (`sosSendLocationSmsAction`) | жагсаалтын мөр | байршил/Plus Code-той `sms:` URI бэлдэнэ | SMS апп (илгээхийг хэрэглэгч өөрөө дарна) |
| SOS → дугаар алга | «Яаралтай үед холбогдох дугаар хадгалагдаагүй байна» (`sosNoContactHint`) + «Дугаар нэмэх» (`sosAddContactAction`) | мөр + текст-товч | тохиргоо руу шилжинэ | `/settings/emergency-contact` |
| Дуут зурвасын чип | «Тоглуулах» (`playVoiceNoteAction`) | чип | тоглуулна / дахин дарвал зогсооно | Тухайн дэлгэц дээрээ |
| Доод товч (жолооч, фаз=ирж байна) | «Зорчигч сууллаа» (`markPassengerBoardedAction`) | үндсэн товч | фазыг `tripInProgress` болгож зорчигч руу DM илгээнэ | Тухайн дэлгэц (фаз солигдоно) |
| Доод товч (жолооч, фаз=явцад) | «Аялал дууслаа» (`endTripAction`) | үндсэн товч | таксиметртэй бол эцсийн дүнг бодож DM-ээр илгээнэ, GPS/relay-г таслана | Жолооч → **S12**; зорчигч талд → **S11** (таксиметр) эсвэл **S12** (тогтмол үнэ) |
| Газрын зураг | — | хүрэлт/чирэлт | зөвхөн pan/zoom, сонголт байхгүй | — |

**Төлөвүүд:**
- **Ачаалж буй:** эхний GPS fix ирээгүй — өөрийн gold маркер байхгүй, зураг хотын төв дээр; эсрэг талын маркер нь `LiveLocationChannel.watch` эхний ping ирэх хүртэл байхгүй.
- **Зөвшөөрөл татгалзсан:** бүх харагдац `LocationPermissionDeniedView`-ээр солигдоно — «Аялал хянахын тулд байршлын зөвшөөрөл шаардлагатай» (`locationPermissionNeededHint`) + «Зөвшөөрөл өгөх» (`grantLocationPermissionAction`) товч (дахин оролдоно).
- **Хоосон:** тусдаа хоосон төлөв байхгүй — газрын зураг үргэлж дүүрэн.
- **Алдаа:** тусдаа алдааны дэлгэц байхгүй; тайлагдахгүй/гэмтсэн ping чимээгүй хаягдана (`live_location_channel.dart:58-61`).
- **Мэдэгдэл:** дуут зурвас ирэхэд snackbar «Дуут зурвас ирлээ» (`voiceNoteReceivedLabel`).

**⚠ Контрастын засвар:** одоогийн код фазын шошго болон таксиметрийн дүнг **gold текстээр** цаасан дэвсгэр дээр бичдэг (2.28:1 — унана). Prompt-д ink текст, gold зөвхөн дүүргэлт болгосон.

**Stitch prompt — A) ЗОРЧИГЧ:**

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

SCREEN — Android mobile app screen: the live trip, PASSENGER side. The rider must see where
the car is and reach emergency help within one second, with no bottom action button.
Top: a flat app bar on paper ground with a 3px solid ink rule along its bottom edge, a back
arrow inside a 48dp target on the left, and a bold left-aligned title "Тахь".
Under it a status strip with unequal padding — 20px top, 12px bottom: on the left a fully
round steppe-green #2E6E5E pill with white uppercase text "Жолооч ирж байна"; on the right a
row of three 48dp square icon buttons with 1.5px ink borders and 4px radius — a share glyph,
a phone glyph, and then, separated by a deliberate 20px gap so it can never be hit by
accident, an emergency button with a 1.5px red #9E3327 border and a red glyph.
Below that a single ink line reading "Одоогийн дүн: 12 400₮", where the words are small ink
caps and the amount is huge tabular ink numerals at 64sp; it never animates.
The rest of the screen is a warm paper-toned map with ink-drawn roads and a thick gold route
line: a small gold disc marks the rider, a solid ink car block marks the driver, each sitting
on a hard 3px ink offset. No button along the bottom edge.
```

**Stitch prompt — B) ЖОЛООЧ:**

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

SCREEN — Android mobile app screen: the live trip, DRIVER side. The driver is carrying a
passenger and needs the map, emergency access, and exactly one large phase action.
Top: a flat app bar on paper ground with a 3px solid ink rule under it, a back arrow in a
48dp target on the left, a bold left-aligned title "Тахь", and one square QR icon action on
the right.
Beneath it a status strip: on the left a fully round steppe-green #2E6E5E pill with white
uppercase text "Аяллын явцад"; on the right three 48dp square ink-bordered icon buttons —
share, phone, and, after a 20px separating gap, a red-bordered #9E3327 emergency button.
Then one ink line: "Одоогийн дүн: 12 400₮", small ink caps for the words and huge tabular
ink numerals at 64sp for the amount, never animating.
A warm paper-toned map with ink roads and a thick gold route line fills the middle: a gold
disc for the driver, a solid ink block for the passenger's pickup point, each with a hard
3px ink offset.
Pinned to the bottom on paper ground above a 3px ink rule: one full-width solid gold
#C99A3C button, 14px radius, 18px vertical padding, centered bold ink label "Аялал дууслаа".
```

---

## S11. Төлбөр баталгаажуулах

**Файл:** `app/lib/ride/active_trip_view.dart` (818-865 `_FareConfirmView`; гарц 416-427; сонголт 524-528)
**Зорилго:** GPS-таксиметрээр бодогдсон эцсийн дүнг зорчигч өөрөө үзээд батлах — эсвэл татгалзах — хүртэл ямар ч баримт нийтлэгдэхгүй байлгах.
**Хаанаас ирнэ:** зөвхөн **зорчигчид**, зөвхөн **таксиметртэй** аялалд: жолооч S10 дээр «Аялал дууслаа» дарж, `finalFareMnt`-той статус DM ирмэгц (`_stopTrackingAndMoveToRating`, мөр 421-427). Тогтмол үнийн аялалд энэ дэлгэц **огт байхгүй**; жолооч тал **хэзээ ч** үүнийг харахгүй (тэр өөрөө дүнг бодоод S12 руу шууд орно).
**Агуулга:** төвлөрсөн багана — (1) гарчиг «Аяллын эцсийн дүн», (2) 12px зай, (3) дүнгийн мөр «Тохирсон үнэ: {price}₮» (24sp, bold), (4) 24px зай, (5) бүтэн өргөнтэй үндсэн товч «Батлах», (6) 12px зай, (7) хүрээтэй товч «Татгалзах».

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| Гарчиг | «Аяллын эцсийн дүн» (`meteredFareConfirmTitle`) | текст | — | — |
| Дүн | «Тохирсон үнэ: {price}₮» (`agreedPriceLabel`) | том тоо (үйлдэлгүй) | жолоочийн GPS-ээр бодсон дүн | — |
| Үндсэн товч | «Батлах» (`meteredFareConfirmAction`) | үндсэн товч | `_confirmFare()` — алхмыг `rating` болгоно | **S12** |
| Хоёрдогч товч | «Татгалзах» (`meteredFareDeclineAction`) | хүрээтэй товч | `_declineFare()` — `_fareDeclined = true`, **үнэлгээг бүрэн алгасна**, баримт нийтлэгдэхгүй, `onTripSettled` дуудагдаж буцах хамгаалалт унтарна | **S13** (татгалзсан хувилбар) |
| AppBar буцах сум | «Буцах» (`backAction`, tooltip) | icon-товч | хамгаалалт хараахан идэвхтэй | Диалог «Аялалаас гарах уу?» |

**Төлөвүүд:**
- **Ачаалж буй:** байхгүй — дүн аль хэдийн ирсэн үед л энэ алхам үүснэ.
- **Хоосон / алдаа:** байхгүй; `_finalFareMnt` заавал утгатай (мөр 525).
- **Тайлбар:** «Татгалзах» нь алдаа биш, **хүчинтэй төгсгөл** — хос баримт үүсэхгүй тул нэр хүндэд тооцогдохгүй.

**⚠ Тэмдэглэл:** дүнгийн мөр `agreedPriceLabel` («Тохирсон үнэ: …»)-ыг дахин ашиглаж байгаа тул таксиметрийн эцсийн дүнг «тохирсон» гэж нэрлэж байна. arb-д таксиметрийн дүнд зориулсан тусдаа мөр **байхгүй** → шаардвал «(шинэ)».

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

SCREEN — Android mobile app screen: the passenger confirms the metered final fare of a
finished taxi ride. This is a receipt-like page, not a payment form: nothing is charged here,
the rider only accepts or rejects the number the meter produced.
Top: a flat app bar on paper ground with a 3px solid ink rule under it, a back arrow inside a
48dp target on the left, and a bold left-aligned title "Тахь".
Centred in the page, a flat #E7DEC9 surface card with 4px radius sitting on a hard 3px solid
ink offset down and to the right, like a printed ticket. Inside it, generous 32px padding:
a small ink heading "Аяллын эцсийн дүн", then a 3px ink rule, then the amount line
"Тохирсон үнэ: 12 400₮" where "Тохирсон үнэ:" is small ink text and "12 400₮" is enormous
tabular ink numerals at 88sp, tightly tracked, occupying most of the card.
Below the card, separated by 32px: a full-width solid gold #C99A3C button with 14px radius,
18px vertical padding and a centered bold ink label "Батлах". Under it, 12px away, an
outlined button with a 1.5px red #9E3327 border, transparent fill and red label "Татгалзах".
No other controls anywhere on the screen.
```

---

## S12. Үнэлгээ өгөх

**Файл:** `app/lib/ride/active_trip_view.dart` (682-748 `_RatingView`; илгээх 448-473; сонголт 529-535)
**Зорилго:** аялал дууссаны дараа эсрэг талаа од болон сэтгэгдлээр үнэлж, өөрийн талын баримтыг нийтлэх.
**Хаанаас ирнэ:** жолооч — S10-ийн «Аялал дууслаа»-аас шууд; зорчигч — тогтмол үнийн аялалд S10-оос шууд, таксиметртэй бол S11-ийн «Батлах»-аас.
**Агуулга:** (Padding 16, төвлөрсөн багана) — (1) гарчиг «Аяллыг үнэлнэ үү», (2) 12px зай, (3) төвд байрлах 5 одны эгнээ (дүүрсэн/хоосон од), (4) 12px зай, (5) хүрээтэй нэг мөрт текст талбар (**шошго/сануулга байхгүй — arb-д мөр алга → «(шинэ)»**), (6) 16px зай, (7) бүтэн өргөнтэй үндсэн товч «Илгээх».

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| Гарчиг | «Аяллыг үнэлнэ үү» (`rateTripTitle`) | текст | — | — |
| Од 1–5 | шошгогүй (icon) | 5 icon-товч | `_selectedStars = i+1`, түүнээс өмнөх бүх од дүүрнэ | Тухайн дэлгэц |
| Сэтгэгдэл | **«(шинэ)»** — arb-д placeholder байхгүй | текст оролт | `_commentController`, баримтын `comment` талбарт орно | Тухайн дэлгэц |
| Илгээх | «Илгээх» (`submitRatingAction`) | үндсэн товч | `_submitRating()` — баримт нийтэлж (`role`, од, км, хугацаа, үнэ, сэтгэгдэл), `onTripSettled` дуудна | **S13** |
| AppBar буцах сум | «Буцах» (`backAction`, tooltip) | icon-товч | хамгаалалт идэвхтэй хэвээр | Диалог «Аялалаас гарах уу?» |

**Төлөвүүд:**
- **Идэвхгүй:** од сонгоогүй үед «Илгээх» товч **бүдгэрч, дарагдахгүй** (`onPressed: selectedStars > 0 ? … : null`, мөр 742) — 0 од нь протоколын хувьд буруу (1..5 л зөвшөөрөгдөнө).
- **Ачаалж буй:** илгээх үед товчны шошго спиннерээр солигдоно (`PrimaryButton.loading`).
- **Алдаа:** тусдаа алдааны UI **байхгүй** — нийтлэлт амжилтгүй болбол `finally` дотор зөвхөн спиннер унтарч, дэлгэц энэ хэвээр үлдэнэ (дахин дарж болно).
- **Хоосон:** байхгүй.

**Алгасах боломж — кодын нотолгоо:** энэ дэлгэц дээр «алгасах» товч **байхгүй**; S13 руу гарах цорын ганц зам нь `_submitRating` (мөр 468). Өөрөөр хэлбэл **үнэлгээгүйгээр баримт нийтлэгдэхгүй**. Гарах бусад зам нь зөвхөн буцах-баталгаажуулалт (аялалыг орхих) бөгөөд тэр тохиолдолд энэ талын баримт хэзээ ч нийтлэгдэхгүй → хос үүсэхгүй → нэр хүндэд тооцогдохгүй. Хоёр тал тус тусдаа **өөрийн** баримтаа нийтэлдэг (`role: widget.role.wireValue`, мөр 461) тул үнэлгээ хоёр талдаа, тэгш хэмтэй.

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

SCREEN — Android mobile app screen: rating the other party right after a taxi ride ended.
The same screen serves both driver and passenger, so it names no role and shows no avatar.
Top: a flat app bar on paper ground with a 3px solid ink rule under it, a back arrow inside a
48dp target on the left, and a bold left-aligned title "Тахь".
Below, with 32px of breathing room, a wide heavy ink heading "Аяллыг үнэлнэ үү", tightly
tracked, left-aligned, followed by a 3px ink rule.
Under the rule, a centred row of five large star shapes, each in its own 56dp touch target:
the first three are solid gold #C99A3C filled stars with a 2px ink outline, the last two are
empty stars drawn only as 2px ink outlines on paper — gold is the fill that marks a chosen
star, never a text colour.
Beneath the stars, 32px down, a single-line text input on paper ground with a 1.5px ink
border and 4px radius, empty, no placeholder text inside it.
Pinned near the bottom with 32px of space above it: a full-width solid gold #C99A3C button,
14px radius, 18px vertical padding, centered bold ink label "Илгээх".
```

---

## S13. Аялал дууссан

**Файл:** `app/lib/ride/active_trip_view.dart` (750-811 `_DoneView`; сонголт 536-541), `app/lib/payment/driver_qr_display.dart`
**Зорилго:** аяллын үр дүнг (баримт нийтлэгдсэн үү, төлбөрөө яаж төлөх вэ) тод хэлж, дараагийн аялал руу цэвэр гарц өгөх.
**Хаанаас ирнэ:** S12-ийн «Илгээх»-ээс (баримт нийтлэгдсэн), эсвэл S11-ийн «Татгалзах»-аас (баримт нийтлэгдээгүй).
**Агуулга:** төвлөрсөн багана, хоёр хувилбар —

- **Хэвийн (баримт нийтлэгдсэн):** (1) «Баримт нийтлэгдлээ», (2) 8px, (3) «Тохирсон үнэ: {price}₮», (4) 16px, (5) **жолооч** → өөрийн банкны QR зураг 220×220 (эсвэл QR тохируулаагүй бол «Та банкны QR-аа хараахан оруулаагүй байна» + «Зураг сонгох» текст-товч); **зорчигч** → «Жолоочийн QR-ыг уншуулах эсвэл бэлнээр төлнө үү», (6) 24px, (7) «Аяллыг дуусгах» товч.
- **Татгалзсан:** (1) «Та дүнг батлаагүй тул баримт нийтлэгдсэнгүй» — үнэ, QR, төлбөрийн сануулга **бүгд алга**, (2) 24px, (3) «Аяллыг дуусгах» товч.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| Гарчиг (хэвийн) | «Баримт нийтлэгдлээ» (`tripReceiptPublished`) | текст | — | — |
| Гарчиг (татгалзсан) | «Та дүнг батлаагүй тул баримт нийтлэгдсэнгүй» (`meteredFareDeclinedHint`) | текст | — | — |
| Үнэ | «Тохирсон үнэ: {price}₮» (`agreedPriceLabel`) | том тоо | таксиметрийн эцсийн эсвэл тохирсон үнэ | — |
| QR зураг (жолооч) | шошгогүй | зураг 220×220 | зорчигч уншуулна | — |
| QR алга (жолооч) | «Та банкны QR-аа хараахан оруулаагүй байна» (`qrNotSetHint`) + «Зураг сонгох» (`qrCaptureAction`) | сануулга + текст-товч | QR оруулах хуудас | `DriverQrCapturePage` (push) |
| Төлбөрийн сануулга (зорчигч) | «Жолоочийн QR-ыг уншуулах эсвэл бэлнээр төлнө үү» (`payWithQrOrCashHint`) | текст | — | — |
| Дуусгах | «Аяллыг дуусгах» (`finishTripAction`) | үндсэн товч | хостын per-trip төлөвийг цэвэрлэнэ | Зорчигч → дуудлага өгөх эхлэл; жолооч → ойролцоох дуудлагын газрын зураг |
| AppBar буцах сум | «Буцах» (`backAction`, tooltip) | icon-товч | `onTripSettled` аль хэдийн дуудагдсан тул **диалоггүй** шууд гарна | Өмнөх хуудас |

**Төлөвүүд:**
- **Ачаалж буй:** жолоочийн QR зураг ачаалагдтал (`driverQrBytesProvider` шийдэгдтэл) «QR оруулаагүй» сануулга харагдана — flicker-ээс сэргийлэхийн тулд provider ашигласан.
- **Хоосон:** «QR тохируулаагүй» = хоосон төлөв; шийдэл нь тэр даруй дэргэдээ.
- **Алдаа:** тусдаа алдааны төлөв байхгүй.
- **Хязгаар:** `onFinished` дамжуулаагүй хост дээр «Аяллыг дуусгах» товч **огт харагдахгүй** (мухар гарц) — хоёр бодит хост хоёулаа дамжуулдаг.

**Stitch prompt — A) ЗОРЧИГЧ (баримт нийтлэгдсэн):**

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

SCREEN — Android mobile app screen: the finished-trip receipt shown to the PASSENGER. It
reads like a torn printed ticket, closing the ride and telling the rider how to pay.
Top: a flat app bar on paper ground with a 3px solid ink rule under it, a back arrow inside a
48dp target on the left, and a bold left-aligned title "Тахь".
Centred below, a flat #E7DEC9 card with 4px radius on a hard 3px solid ink offset. Inside,
32px padding: a fully round steppe-green #2E6E5E pill with white uppercase text
"Баримт нийтлэгдлээ", then a 3px ink rule, then the line "Тохирсон үнэ: 12 400₮" where the
words are small ink text and "12 400₮" is huge tabular ink numerals at 80sp.
Under the card, on plain paper with 24px of space, a calm two-line ink sentence
"Жолоочийн QR-ыг уншуулах эсвэл бэлнээр төлнө үү", left-aligned, no icon, no card around it.
Pinned to the bottom with 40px above it: a full-width solid gold #C99A3C button, 14px radius,
18px vertical padding, centered bold ink label "Аяллыг дуусгах".
```

**Stitch prompt — B) ЖОЛООЧ (баримт нийтлэгдсэн, QR-тай):**

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

SCREEN — Android mobile app screen: the finished-trip screen shown to the DRIVER, whose own
bank QR code must be big enough for a passenger to scan across the seat.
Top: a flat app bar on paper ground with a 3px solid ink rule under it, a back arrow inside a
48dp target on the left, a bold left-aligned title "Тахь", and one square QR icon action on
the right.
Below, tightly stacked with only 12px between them: a fully round steppe-green #2E6E5E pill
with white uppercase text "Баримт нийтлэгдлээ", and the line "Тохирсон үнэ: 12 400₮" where
the words are small ink text and the amount is huge tabular ink numerals at 72sp.
Then, taking the visual centre of the screen, a square 220x220 QR code drawn in pure ink on
a white block, framed by a 3px solid ink border and dropped on a hard 3px ink offset, with
40px of empty paper around it so nothing competes with it.
Pinned to the bottom above a 3px ink rule: a full-width solid gold #C99A3C button, 14px
radius, 18px vertical padding, centered bold ink label "Аяллыг дуусгах".
```

---

## Нэгтгэлд дамжуулах тэмдэглэл

1. **arb-д дутуу мөрүүд:** S12-ийн сэтгэгдлийн талбарт placeholder/шошго байхгүй → «(шинэ)».
   S11/S13-д таксиметрийн эцсийн дүнг `agreedPriceLabel` («Тохирсон үнэ: …») дахин ашиглаж
   байгаа — утга зүйн хувьд зөрүүтэй → шаардвал «(шинэ)».
2. **Контраст:** энэ бүлгийн бүх gold текст (фазын шошго, таксиметрийн дүн, гарчигууд,
   `_DoneView`-ийн текстүүд) цаасан дэвсгэр дээр **2.28:1** — prompt-уудад ink болгож
   зассан. Кодыг ирээдүйд засах шаардлагатай (энэ workflow-д код засаагүй).
3. **Навигаци:** `ConfirmLeaveScope` аль хэдийн байгаа; шинэ шаардлага нь зөвхөн AppBar-ийн
   буцах сум ил, 48dp байх ба S13 дээр диалог гарахгүй байх (`onTripSettled` унтраадаг).
4. **Таксиметрийн тоо анимац хийхгүй** — 00-style.md-ийн хатуу дүрэм, S10/S11-ийн prompt-д
   тусгайлан бичсэн.
