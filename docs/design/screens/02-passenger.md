# БҮЛЭГ 2 — Зорчигчийн захиалгын урсгал (S5–S9)

**Хэв маяг:** `00-style.md` (`steppe-print`). Stitch prompt бүр тэндэх STYLE PREAMBLE-ээр эхэлнэ.

**Эх код:** бүх таван дэлгэц `app/lib/ride/passenger_ride_page.dart` доторх нэг `_PassengerStep`
төлөвт машины алхмууд. Тусдаа route байхгүй — go_router-т ганц л зам бүртгэлтэй
(`app/lib/router.dart:76-79`, `/ride/passenger`), тиймээс `Scaffold` → `AppBar` нь Navigator-ын
стекээс болж буцах сумыг **автоматаар** гаргадаг. Тэр сумны утгыг `_guardBack`
(`passenger_ride_page.dart:368-396`) алхам болгонд өөрөөр тодорхойлдог.

**Навигацийн одоогийн байдал (нотлогдсон, аль хэдийн хэрэгжсэн):**

| Юу | Хаана | Төлөв |
|---|---|---|
| AppBar буцах сум | `Scaffold(appBar: AppBar(...))` `:290` — push-аар нээгддэг тул автомат | ✅ байгаа |
| Алхам-буцалт (өгөгдөл хадгалагдана) | `_goBackTo` `:134`, `_pickup`/`_destination`/`_priceController` цэвэрлэгддэггүй | ✅ байгаа |
| Биен дэх «Буцах» товч | `_BackStepButton` `:481-493`, `l.backAction` | ✅ байгаа |
| Хардвэр/свайп буцалтыг алхам болгох | `PopScope(canPop:false)` `:388-395` | ✅ байгаа |
| Идэвхтэй хүсэлт/аяллаас гарах баталгаажуулалт | `ConfirmLeaveScope` `:371-379` + `app/lib/widgets/confirm_leave_scope.dart` | ✅ байгаа |
| Жолоочид цуцлалт мэдэгдэх | `_abandonRequest` `:159-178` → `cancelWithDriver` | ✅ байгаа |

Өөрөөр хэлбэл **буцах логик бүрэн байна** — доорх дизайн үүнийг зөвхөн *харагдуулах* үүрэгтэй:
алхмын дугаар, AppBar-ын гарчиг, «Буцах» ба «Гарах» хоёрын ялгаа.

---

### S5. Авах цэг сонгох

**Файл:** `app/lib/ride/passenger_ride_page.dart` (`_PassengerStep.pickup` арм `:297-303`;
`_LocationStep` `:399-440`) + `app/lib/map/location_picker.dart` (`:32-114`) +
`app/lib/map/ride_map.dart` (`:12-51`)

**Зорилго:** Зорчигч машин ирэх яг цэгээ газрын зураг дээр тогтоож, тэмдэглэлээр тодруулна.

**Хаанаас ирнэ:** Нүүр хуудаснаас «Дуудлага өгөх» (`startAsPassengerAction`) →
`/ride/passenger`. Мөн S9-ийн аялал дууссаны дараа `_finishTrip` (`:185-200`) энэ алхам руу
буцаана.

**Агуулга:**
1. AppBar — одоо зөвхөн `l.appName` = «Тахь» (`:290`). Зорилтот: алхмын гарчиг + «1 / 3» тоолуур.
2. Төв-зүү газрын зураг, өндөр 260 (`location_picker.dart:78`). OSM плита
   (`ride_map.dart:41-44`), зүү нь `Icons.location_pin`, gold, 40px, `IgnorePointer` —
   **зүү хөдөлдөггүй, зураг доогуураа гулсдаг** (`location_picker.dart:90-96`).
3. Байршлын код — `PickedLocation.plusCode` (`location_picker.dart:23`) тооцоологддог **боловч
   дэлгэц дээр огт харуулдаггүй**. Спек §5 шаарддаг тул зорилтот төлөвт нэмнэ.
4. Тэмдэглэлийн текст талбар, hint = `landmarkHint` (`location_picker.dart:101-111`).
5. Үндсэн товч «Үргэлжлүүл».

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | — (icon) | Навигаци | Эхний алхам, эрсдэл алга: `_guardBack` `previous == null` → child хэвээр (`:381-387`) | Нүүр хуудас руу гарна |
| AppBar гарчиг | «Авах цэг» **(шинэ)** | Текст | Одоо «Тахь» гэж бичдэг — алхам ялгагдахгүй | — |
| Алхмын тоолуур | «1 / 3» **(шинэ)** | Текст | Урсгалын урт ил болно | — |
| Газрын зураг чирэх | — | Дохио | `onPositionChanged(hasGesture)` → `_center` шинэчлэгдэж `onChanged` дуудагдана (`ride_map.dart:34-38`, `location_picker.dart:85-88`) | Байрандаа |
| «Миний байршил» товч | «Миний байршил» **(шинэ)** | Товч | Зураг GPS цэг рүү төвлөрнө. **Одоо байхгүй** — гараар л УБ-ын төвөөс (`city_config.dart:31-35`) хайх ёстой | Байрандаа |
| Байршлын код | «Байршлын код» **(шинэ)** | Текст | `plusCodeEncode(lat, lon)` — уншиж, хуулж, дуудлагаар хэлж болно | — |
| Тэмдэглэл талбар | `landmarkHint` | Оролт | `_landmarkText` → `PickedLocation.landmarkText`; S8-д сонголт хийхэд жолоочид дамжина (`:261`) | — |
| «Үргэлжлүүл» | `nextStep` | Үндсэн товч | `onNext` → `_step = destination` (`:302`) | S6 |

**Төлөвүүд:**
- **Ачаалж буй** — OSM плита татагдах хугацаа. Одоо indicator байхгүй; зорилтот: 3px gold
  indeterminate bar газрын зургийн дээд ирмэг дээр.
- **Хоосон** — байхгүй: төв цэг үргэлж УБ-ын Сүхбаатарын талбайгаас эхэлдэг тул «сонголтгүй»
  төлөв гарахгүй, товч ямагт идэвхтэй.
- **Алдаа** — плита татагдахгүй бол `flutter_map` хоосон дэвсгэр үзүүлнэ. Зорилтот: цайвар
  paper дэвсгэр + байршлын код нь газрын зураггүй ч ажиллана гэдгийг харуулах.
- **Зөвшөөрөл татгалзсан** — энэ дэлгэц GPS шаарддаггүй (гараар сонгодог), тиймээс блоклохгүй.
  Зөвхөн «Миний байршил» товч идэвхгүй болно; `locationPermissionNeededHint` бэлэн байна.

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

Android mobile app screen where a taxi passenger sets the exact point the car should come to.
Top: a flat app bar on paper ground, no shadow, 3px solid ink rule along its bottom edge, a
back arrow on the left inside a 48dp touch target, the bold left-aligned title "Авах цэг",
and on the far right the step counter "1 / 3" in tabular numerals at 60% ink.
Below it a full-bleed warm paper-toned map with ink-drawn roads and no labels clutter,
occupying about 52% of the screen height. A single large gold #C99A3C map pin sits dead
centre and never moves — the map slides under it; draw a thin ink crosshair line pair
crossing the exact centre point. Floating over the map's bottom-right corner: a 56dp square
button, #E7DEC9 fill, 4px radius, hard 3px solid ink offset behind it, ink crosshair icon,
with the small caption "Миний байршил" set below it.
Under the map on paper ground: a 3px ink section rule, then a small uppercase Cyrillic micro
label "Байршлын код" with wide letter tracking, and directly beneath it the monospaced code
8Q7XPJ9Q+2V in large tabular ink figures.
Then a text input on paper ground with a 1.5px ink border, 4px radius, and placeholder text
"Тэмдэглэл (жишээ: цагаан хаалга)".
At the very bottom, a full-width solid gold #C99A3C button, 14px radius, 18px vertical
padding, centred bold ink label "Үргэлжлүүл". No second button on this step.
Make the centre pin unmistakably the subject; keep the map calm and low-contrast so the gold
pin and the gold button are the only saturated things on screen.
```

---

### S6. Очих цэг сонгох

**Файл:** `app/lib/ride/passenger_ride_page.dart` (`_PassengerStep.destination` арм `:304-311`;
`_LocationStep` `:399-440`)

**Зорилго:** Зорчигч хаашаа явахаа тогтооно — жолооч үнэ, зайг үүгээр тооцно.

**Хаанаас ирнэ:** S5-ын «Үргэлжлүүл» товчоос. Мөн S7-ын «Буцах» товч эсвэл S7 дээрх хардвэр
буцалтаас (`_guardBack` `:381-386` → `_PassengerStep.destination`) буцаж ирнэ.

**Агуулга:** S5-тай ижил бүтэц. Гурван ялгаа:
1. Гарчиг ба тоолуур «2 / 3».
2. Дээр нь S5-д сонгосон авах цэгийн товч эргэн санамж (зорилтот, `_pickup.landmarkText` /
   `plusCode`-оос) — хоёр цэг хоорондоо андуурагдахгүй байх гол хамгаалалт.
3. Биен дотор «Буцах» товч гарч ирнэ (`onBack != null`, `:432-435`).

**Чухал нотолгоо:** алхам бүр `ValueKey`-тэй (`:298`, `:305`) тул очих цэгийн picker нь авах
цэгийн зүү, тэмдэглэлийг **өвлөж авдаггүй** — цэвэр эхэлнэ. Харин буцаж ирэхэд өмнө сонгосон
утга нь `initialCenter`/`initialLandmarkText`-ээр сэргээгддэг (`:299-301`, `:306-307`).

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | — (icon) | Навигаци | `PopScope(canPop:false)` барьж авч `_goBackTo(pickup)` (`:382`, `:388-395`) | S5 (сонгосон цэг хадгалагдана) |
| AppBar гарчиг | «Очих цэг» **(шинэ)** | Текст | — | — |
| Алхмын тоолуур | «2 / 3» **(шинэ)** | Текст | — | — |
| Авах цэгийн санамж мөр | «Авах цэг» **(шинэ)** | Мөр | S5-д сонгосон тэмдэглэл/код; хүрэхэд S5 руу | S5 |
| Газрын зураг чирэх | — | Дохио | `_destination` шинэчлэгдэнэ (`:308`) | Байрандаа |
| Байршлын код | «Байршлын код» **(шинэ)** | Текст | Очих цэгийн Plus Code | — |
| Тэмдэглэл талбар | `landmarkHint` | Оролт | `_destination.landmarkText` | — |
| «Үргэлжлүүл» | `nextStep` | Үндсэн товч | `_step = price` (`:309`) | S7 |
| «Буцах» | `backAction` | Хоёрдогч товч | `_goBackTo(pickup)` (`:310`) | S5 |

**Төлөвүүд:** S5-тай яг адил (плита ачаалалт, алдаа, GPS шаарддаггүй). Нэмэлт: авах цэг
болон очих цэг **ижил** байвал сануулах (одоо шалгалт байхгүй) — зорилтот, текст **(шинэ)**.

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

Android mobile app screen where a taxi passenger sets where the ride should end. Top: a flat
app bar on paper ground, 3px solid ink rule along its bottom edge, back arrow on the left in
a 48dp touch target, bold left-aligned title "Очих цэг", and the step counter "2 / 3" on the
right in tabular numerals at 60% ink.
Directly under the app bar, a single compact recap row on #E7DEC9 fill with a 1px ink
hairline under it: a small uppercase micro label "Авах цэг" on the left with wide tracking,
the already-chosen place text "цагаан хаалга" beside it in ink, and a small ink chevron on
the right — this row is tappable and returns to the previous step.
Below that, a full-bleed warm paper-toned map with ink-drawn roads taking about 46% of screen
height, one large gold #C99A3C pin fixed dead centre with a thin ink crosshair through the
exact centre point, and a 56dp square #E7DEC9 button with 4px radius and hard 3px ink offset
floating bottom-right, captioned "Миний байршил".
Under the map: a 3px ink section rule, the uppercase micro label "Байршлын код", the
monospaced code 8Q7XQJ4M+9C in large tabular ink figures, then a text input with a 1.5px ink
border, 4px radius and placeholder "Тэмдэглэл (жишээ: цагаан хаалга)".
Bottom: a full-width solid gold button with 14px radius and bold ink label "Үргэлжлүүл", and
directly below it a full-width outlined button with a 1.5px ink border, transparent fill and
ink label "Буцах". The two buttons must read as clearly unequal in weight.
```

---

### S7. Үнэ санал болгох

**Файл:** `app/lib/ride/passenger_ride_page.dart` (`_PassengerStep.price` арм `:312-316`;
`_PriceStep` `:442-475`) + `app/lib/ride/ride_request_service.dart` (`:30-58`)

**Зорилго:** Зорчигч өөрийн санал болгох үнээ (заавал биш) бичээд дуудлагаа сүлжээнд нийтэлнэ.

**Хаанаас ирнэ:** S6-ын «Үргэлжлүүл» товчоос. Мөн S8-аас «Буцах» дарж хүсэлтээ татан авахад
(`_withdrawRequest` `:143-152`) энэ алхам руу буцаж ирнэ.

**Агуулга:**
1. Одоо: ганц `TextField` (`keyboardType: number`, label = `priceLabel`) + «Нийтлэх» + «Буцах».
2. Зорилтот: дээр нь **маршрутын товч хураангуй** (авах → очих цэг), доор нь **том тоон
   оролт** — учир нь энэ бол мөнгө, `00-style.md`-ийн big-number дүрэм хамаарна.
3. Үнэ хоосон байж болно: `int.tryParse` null буцаавал `offeredMnt: null` (`:78, :88`) —
   «үнээ жолооч нар санал болгог» гэсэн утга. Үүнийг ил тайлбарлах шаардлагатай **(шинэ)**.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | — (icon) | Навигаци | `PopScope` → `_goBackTo(destination)` (`:383`) | S6 |
| AppBar гарчиг | «Үнэ» **(шинэ)** | Текст | — | — |
| Алхмын тоолуур | «3 / 3» **(шинэ)** | Текст | — | — |
| Маршрутын хураангуй | «Авах цэг» / «Очих цэг» **(шинэ)** | Карт | Хоёр цэгийг эцсийн байдлаар шалгах; мөр бүр өөрийн алхам руу | S5 / S6 |
| Үнийн оролт | `priceLabel` | Оролт | `_priceController` → `offeredMnt` (`:78`) | — |
| Хурдан үнэ сонгох (5000 / 8000 / 12000) **(шинэ, заавал биш)** | зөвхөн тоо | Чип | Талбарыг бөглөнө | — |
| «Нийтлэх» | `publishRide` | Үндсэн товч | `_publish()` → PoW (difficulty 8, `ride_request_service.dart:14`) → sign → relay-д нийтлэх → `_step = offers` (`:91-94`) | S8 |
| «Буцах» | `backAction` | Хоёрдогч товч | `_goBackTo(destination)` (`:315`) | S6 |

**Төлөвүүд:**
- **Ачаалж буй** — `_publish` нь PoW олборлож (`minePow`), гарын үсэг зурж, релэйд илгээнэ.
  `PrimaryButton`-д `loading` параметр байгаа (`primary_button.dart:22, 37-46`) ч энд
  **дамжуулаагүй** — товч дарсан ч юу ч болоогүй мэт харагдана. Зорилтот: 3px gold
  indeterminate bar + товч түгжигдэх.
- **Хоосон** — үнэ хоосон бол хэвийн (заавал биш талбар); товч идэвхтэй хэвээр.
- **Алдаа** — `publishRequest` throw хийвэл одоо ямар ч catch байхгүй → чимээгүй гацна.
  Зорилтот: улаан `#9E3327` хүрээтэй сануулга + «Дахин оролдох» **(шинэ)**.
- **Зөвшөөрөл** — хамаарахгүй.

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

Android mobile app screen where a taxi passenger names the price they are willing to pay,
then publishes the ride request. No map on this screen. Top: a flat app bar on paper ground
with a 3px solid ink rule along its bottom edge, a back arrow on the left in a 48dp touch
target, bold left-aligned title "Үнэ", and the step counter "3 / 3" on the right in tabular
numerals at 60% ink.
Below it a route recap block: a flat #E7DEC9 card with 4px radius offset 3px down-right by a
solid ink shape behind it, holding two rows separated by a 1px ink hairline. The first row
has the small uppercase micro label "Авах цэг" and the value "цагаан хаалга"; the second row
has "Очих цэг" and "Драгон төв". A vertical ink line with a small filled square at the top
and a hollow square at the bottom links the two rows on the left.
Then a 3px ink section rule, and the price entry as a big-number display: the uppercase micro
label "Санал үнэ (₮, заавал биш)" above, and under it a very large tabular numeral 8000 in
ink at roughly 72sp with a large ₮ sign trailing it, sitting on a 3px ink underline that
turns gold #C99A3C when focused. Under it, a row of three small outlined ink pills reading
5000, 8000 and 12000.
Bottom: a full-width solid gold button, 14px radius, bold ink label "Нийтлэх", and below it a
full-width outlined ink button labelled "Буцах". Show a 3px gold indeterminate progress bar
pinned directly above the gold button.
```

---

### S8. Жолоочдын санал

**Файл:** `app/lib/ride/passenger_ride_page.dart` (`_PassengerStep.offers` арм `:317-322`;
`_OffersStep` `:495-554`; сонголтын диалог `_confirmSelect` `:207-236`) +
`app/lib/ride/offer_ranking.dart` (бүтнээр) +
`packages/takhi_protocol/lib/src/reputation.dart` (`:12-80`)

**Зорилго:** Ирж буй саналуудаас нэгийг сонгох — аппын хамгийн чухал шийдвэрийн мөч.

**Хаанаас ирнэ:** S7-ын «Нийтлэх» товчоос (`:93`). Санал бүр релэйгээс шууд урсгалаар нэмэгдэнэ
(`_publish` доторх `.listen`, `:95-109`).

#### Эрэмбэлэлтийн ЖИНХЭНЭ логик (нотолсон)

`rankRideOffers` (`offer_ranking.dart:21-42`) нь **ганц түлхүүрээр** эрэмбэлдэг:
`b.reputation.trustWeight.compareTo(a.reputation.trustWeight)` — өндөр `trustWeight` дээр.
Үнэ, ETA эрэмбэд **огт нөлөөлдөггүй**, зөвхөн хажууд нь харагдана.

`computeReputation` (`reputation.dart:12-80`) юу тооцдог вэ:
1. **Хос-баримт (paired) шүүлт** (`:18-30`) — жолоочийн тухай бичигдсэн баримт нь зөвхөн
   *хариу баримт нь мөн байгаа* үед л тоологдоно (`hasCounter`). Өөрөөр хэлбэл нэг талын
   магтаал үнэгүй; хоёул баримтаа нийтэлсэн аялал л жинтэй.
2. Хос-баримт байхгүй бол `Reputation(0, 0, 0)` (`:32`) — **шинэ жолооч бүр яг ийм**.
3. `averageRating` = хос-баримтуудын одны дундаж (`:34-35`).
4. `trustWeight` (`:60-77`) = зохиогч бүрийн `log(1+тоо)` — нэг хүнээс олон удаа магтуулах нь
   огцом буурна; итгэсэн хүн (`viewerTrusted`) ×3; итгээгүй бүлгийн нийлбэрт гадуур `sqrt()`
   — олон хуурамч түлхүүр минтлэх ашгийг дэд-шугаман болгодог.

**Дизайны сорилт ба шийдэл:** `trustWeight` бол хийсвэр бутархай тоо — түүнийг **хэзээ ч
тоогоор бүү үзүүл**. Оронд нь түүний *орц*-ыг харуул: (а) хос-баталгаатай аяллын тоо
`pairedTripCount`, (б) одны дундаж `averageRating`, (в) эрэмбийн байрлал өөрөө. Нэгдүгээр
картад л «яагаад дээр байгаа»-г нэг богино тэмдгээр тайлбарла.

**Агуулга:**
1. Гарчиг `offersWaitingTitle` = «Ирж буй саналууд» (одоо биен дотор, `:521`).
2. Дуусах хугацааны тоолуур: хүсэлт **240 секундын дараа хүчингүй болно**
   (`ride_request_service.dart:39`, `expirySeconds: 240`). Одоо огт харуулдаггүй **(шинэ)**.
3. Саналын жагсаалт — одоо `ListTile`: гарчиг `offerSummary` = «{price}₮ · {eta} мин»,
   дэд гарчиг `vehicleDescription` (`:534-541`). **Нэр хүнд огт харагддаггүй** — гэтэл яг
   тэр нь эрэмбийг тодорхойлж байгаа. Энэ бол одоогийн хамгийн том цоорхой.
4. Доор «Буцах» (`:549`).

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | — (icon) | Навигаци | `_isRequestLive == true` → `ConfirmLeaveScope` (`:369-379`) диалог гарна | Баталвал хуудаснаас гарна |
| Гарах диалог гарчиг | `leaveRideRequestTitle` | Диалог | «Дуудлагаа цуцлах уу?» | — |
| Гарах диалог тайлбар | `leaveRideRequestMessage` | Текст | Саналууд алга болно гэдгийг хэлнэ | — |
| Гарах диалог — үлдэх | `stayAction` | Товч | Юу ч болохгүй | S8 |
| Гарах диалог — гарах | `leaveAction` | Товч | `_abandonRequest` (`:159-178`) → subscription хаагдана | Нүүр хуудас |
| Гарчиг | `offersWaitingTitle` | Текст | — | — |
| Дуусах тоолуур | «Дуудлага дуусах: 3:12» **(шинэ)** | Pill | 240с-ээс буурна | — |
| Саналын карт (мөр бүр) | `offerSummary` + `vehicleDescription` | Жагсаалтын мөр | `onTap: () => onSelect(r)` (`:542`) | Батлах диалог |
| Нэр хүндийн блок картад | «N аялал» / «★ 4.8» / «Шинэ жолооч» **(бүгд шинэ)** | Текст | `pairedTripCount`, `averageRating`; 0 бол «Шинэ жолооч» | — |
| Эрэмбийн шалтгаан (зөвхөн 1-р карт) | «Хамгийн найдвартай» **(шинэ)** | Gold тэмдэг | `trustWeight` хамгийн өндөр гэдгийг ойлгомжтой болгоно | — |
| Батлах диалог гарчиг | `confirmSelectOfferTitle` | Диалог | «Энэ жолоочийг сонгох уу?» | — |
| Батлах диалог тайлбар | `confirmSelectOfferMessage` | Текст | Машин · үнэ · ETA + «яг байршил, утас илгээгдэнэ, буцаах боломжгүй» | — |
| Батлах — цуцлах | `cancelAction` | Товч | `false` буцаана (`:223`) | S8 |
| Батлах — илгээх | `confirmSelectOfferAction` | Товч | `_select` → handoff DM (яг lat/lon + тэмдэглэл + утас) (`:253-264`) | S9 |
| «Буцах» (биен доторх) | `backAction` — **тодруулах шаардлагатай (шинэ)** | Хоёрдогч товч | `_withdrawRequest` (`:143-152`): subscription хаагдаж, саналууд арилна | S7 |

> ⚠️ **Хоёр өөр «буцалт» нэг дэлгэц дээр.** AppBar-ын сум = хуудаснаас гарах (диалогтой),
> биен доторх «Буцах» = хүсэлтээ татаж үнийн алхам руу очих (диалоггүй). Хоёулаа «Буцах»
> гэсэн нэг шошготой байх нь эрсдэлтэй — биен доторхыг «Үнээ өөрчлөх» маягаар ялгах санал
> **(шинэ)**.

**Төлөвүүд:**
- **Ачаалж буй / хоосон** — `_offers` эхлээд хоосон; одоо гарчгаас өөр юу ч байхгүй, хэрэглэгч
  апп гацсан эсэхийг мэдэхгүй. Зорилтот: 3px gold indeterminate bar + тайлбар текст **(шинэ)**
  + үлдэх хугацаа.
- **Нэр хүнд хожуу ирэх** — санал шууд харагддаг ч түүний баримтууд `receiptsAbout`-аар
  **3 секундын дараа** ирдэг (`trip_receipt_repository.dart:23, 54`). Тэр үед
  `_receiptsCache` шинэчлэгдэж жагсаалт **дахин эрэмблэгддэг** (`:107` → `rankRideOffers`).
  Хуруун доор карт үсрэх эрсдэлтэй. Зорилтот: нэр хүнд ирэх хүртэл картад «шалгаж байна»
  төлөв **(шинэ)** үзүүлж, эрэмбийг тухайн карт бүрэн болмогц л шилжүүлэх.
- **Шинэ жолооч** — `Reputation(0,0,0)`. Хамгийн түгээмэл тохиолдол (баримт хуримтлагдаагүй
  сүлжээ). Дор эрэмблэгдэнэ; сөрөг биш, төвийг сахисан «Шинэ жолооч» тэмдэг **(шинэ)**.
- **Алдаа** — релэй тасарвал зүгээр л санал ирэхгүй; хоосон төлөвөөс ялгагдахгүй. Зорилтот:
  холболтын төлөвийг тоолуурын хажууд харуулах.
- **Хугацаа дуусах** — 240с өнгөрвөл жолооч нар хүсэлтийг харахаа болино, гэхдээ код нь
  ямар ч UI өөрчлөлт хийдэггүй. Зорилтот: тоолуур 0 болоход «дахин нийтлэх» санал **(шинэ)**.

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

Android mobile app screen listing live offers from taxi drivers so the passenger can compare
and pick one. Top: a flat app bar on paper ground with a 3px solid ink rule along its bottom
edge, a back arrow on the left in a 48dp touch target, and the bold left-aligned title
"Ирж буй саналууд". Directly under it, a right-aligned fully-round pill with #E7DEC9 fill and
ink text reading "Дуудлага дуусах: 3:12", the time in tabular numerals.
Then a vertical list of four offer cards, all built to an identical column skeleton so the eye
can scan straight down. Each card is a flat #E7DEC9 block, 4px radius, offset 3px down-right
by a solid ink shape. Inside each card, left column: a very large tabular price 9500 with a ₮
sign, and under it in smaller ink "12 мин". Right column, right-aligned: the vehicle line
"Toyota Prius, цагаан" in bold ink, under it a 1px ink hairline, and under that a reputation
line combining a star glyph, the tabular number 4.8, a thin ink separator bar, and the text
"27 аялал".
The first card carries a solid gold #C99A3C block bar across its top edge with the bold ink
label "Хамгийн найдвартай" inside it. The last card shows no star line; instead it has a
fully-round #E7DEC9 pill with ink text "Шинэ жолооч".
Bottom, pinned on paper ground above a 3px ink rule: a full-width outlined button with a
1.5px ink border and ink label "Үнээ өөрчлөх".
Prices must be the largest type on screen; reputation must be legible but never louder than
price.
```

---

### S9. Сонгосон / хүлээж байна

**Файл:** `app/lib/ride/passenger_ride_page.dart` (`_PassengerStep.done` арм `:326-330`;
`_DoneStep` `:556-579`) + `_guardBack` (`:368-380`) + `_abandonRequest` (`:159-178`)

**Зорилго:** Жолооч сонгогдож, зорчигчийн яг байршил илгээгдсэнийг батлаад ирэхийг нь хүлээнэ.

**Хаанаас ирнэ:** S8-ын батлах диалогийн «Тийм, илгээх» → `_select` handoff DM илгээгээд
`_step = done` (`:266-270`).

**Агуулга:**
1. Одоо: төвд ганц мөр `driverOnTheWay` = «{vehicle} ирж байна» + «Аялал руу очих» товч.
   Ямар үнээр, хэдэн минутанд, ямар дугаартай машин ирэх нь **алга** — гэтэл энэ мэдээлэл
   `_selected.offer.payload`-д бүрэн бий (`priceMnt`, `etaMinutes`, `vehicleDescription`).
2. Зорилтот: том ETA тоо + тохирсон үнэ + машины мөр + «таны байршил илгээгдсэн» баталгаа.
3. **Энэ алхам буцалтгүй** — биен дотор «Буцах» товч зориудаар байхгүй (`:323-325` тайлбар):
   жолооч аль хэдийн замд гарсан.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | — (icon) | Навигаци | `_isRequestLive == true`, `leavingRequest == false` → `ConfirmLeaveScope` `leaveTripTitle`-аар (`:370-376`) | Баталвал хуудаснаас гарна |
| Гарах диалог гарчиг | `leaveTripTitle` | Диалог | «Аялалаас гарах уу?» — ⚠️ доорх тэмдэглэгээг үз | — |
| Гарах диалог тайлбар | `leaveTripMessage` | Текст | «Идэвхтэй аялал тасарна…» | — |
| Гарах — үлдэх | `stayAction` | Товч | Юу ч болохгүй | S9 |
| Гарах — гарах | `leaveAction` | Товч | `_abandonRequest` → жолоочид `cancelWithDriver` DM явна (`:168-177`) | Нүүр хуудас |
| Гол мессеж | `driverOnTheWay` | Текст | «{vehicle} ирж байна» (`:570`) | — |
| ETA том тоо | `offerSummary`-ийн мин хэсэг эсвэл шинэ түлхүүр **(шинэ)** | Big-number | `etaMinutes` | — |
| Тохирсон үнэ | `agreedPriceLabel` («Тохирсон үнэ: {price}₮») | Текст | Одоо энд ашиглагдаагүй, гэхдээ arb-д бэлэн байгаа | — |
| Байршил илгээгдсэн баталгаа | «Таны байршил илгээгдлээ» **(шинэ)** | Ногоон pill | `_select`-д handoff DM амжилттай явсны дараа | — |
| «Аялал руу очих» | `startTripAction` | Үндсэн товч | `_step = activeTrip` → `ActiveTripView` (`:328-329`) | Идэвхтэй аялал (Бүлэг 4) |

> ⚠️ **Тексттэй зөрчил (кодын олдвор, дизайны биш):** энэ алхам дээр гарах диалог
> `leaveTripTitle`/`leaveTripMessage` — «Идэвхтэй аялал тасарна» гэж бичдэг. Гэтэл аялал
> хараахан эхлээгүй, жолооч зүгээр л ирж явна. Илүү тохирох текст нь `leaveRideRequestTitle`
> биш, харин **шинэ түлхүүр** («Жолоочийг цуцлах уу?» маягийн) байх ёстой. Кодын арм
> `_guardBack:370` дээр `leavingRequest` нь зөвхөн `offers`-ыг л шалгадаг тул `done` нь
> «аялал»-ын текст рүү унадаг. Нэгтгэлийн үед энэ саналыг оруулах.

**Төлөвүүд:**
- **Ачаалж буй** — `_select` доторх `sendHandoff` дуустал (`:253-264`) дэлгэц S8 дээр гацдаг:
  батлах диалог хаагдсан ч юу ч болоогүй мэт харагдана. Зорилтот: диалог хаагдмагц S9-ийг
  «илгээж байна» төлөвөөр нээх (3px gold indeterminate bar).
- **Хоосон** — `selected == null` бол мессеж хоосон мөр болно (`:570` `vehicle == null ? ''`).
  Онолын хувьд хүрэхгүй, гэхдээ хоосон дэлгэц гарахаас сэргийлж fallback текст **(шинэ)**.
- **Алдаа** — `sendHandoff` бүтэлгүйтвэл catch байхгүй; зорилтот: улаан хүрээтэй сануулга +
  дахин илгээх.
- **Зөвшөөрөл** — энд хамаарахгүй; GPS-ийн зөвшөөрөл дараагийн `ActiveTripView`-д асуугдана
  (`locationPermissionNeededHint`, `grantLocationPermissionAction` бэлэн).

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

Android mobile app screen confirming that a taxi driver has been chosen and is now driving to
the passenger. Top: a flat app bar on paper ground with a 3px solid ink rule along its bottom
edge and a back arrow on the left inside a 48dp touch target; no title text.
Directly below, a fully-round pill with steppe green #2E6E5E fill and white text reading
"Таны байршил илгээгдлээ", left-aligned with generous space above and below it.
Then the centrepiece: a huge tabular numeral 7 in ink at roughly 96sp with the word "мин"
set small beneath it, and above the number a small uppercase Cyrillic micro label with wide
tracking reading "ЖОЛООЧ ИРЭХ ХУГАЦАА". The number must not look animated or ticking.
Under a 3px ink section rule, a flat #E7DEC9 card with 4px radius offset 3px down-right by a
solid ink shape, containing two stacked lines: the bold ink headline "Toyota Prius, цагаан
ирж байна", and beneath it, separated by a 1px ink hairline, the line "Тохирсон үнэ: 9500₮"
with the money in large tabular figures.
Bottom of the screen: a single full-width solid gold #C99A3C button, 14px radius, 18px
vertical padding, bold centred ink label "Аялал руу очих". Deliberately no secondary or back
button in the body — the only way out is the app bar arrow.
Keep the layout vertically unequal: tight around the pill, very open around the big number.
```

---

## Нэгтгэлд шаардлагатай тэмдэглэл

### Шинээр нэмэх l10n түлхүүрүүд (`app/lib/l10n/app_mn.arb`-д БАЙХГҮЙ)

| Санал болгож буй түлхүүр | Хаана | Тайлбар |
|---|---|---|
| `pickupStepTitle` | S5 AppBar | «Авах цэг» |
| `destinationStepTitle` | S6 AppBar | «Очих цэг» |
| `priceStepTitle` | S7 AppBar | «Үнэ» |
| `stepCounter(current, total)` | S5–S7 | «{current} / {total}» |
| `plusCodeLabel` | S5, S6 | Байршлын кодын micro-шошго |
| `myLocationAction` | S5, S6 | GPS товч |
| `samePointWarning` | S6 | Авах = очих цэг үед |
| `offersEmptyHint` | S8 | Санал хүлээж буй тайлбар |
| `requestExpiresIn(time)` | S8 | 240с тоолуур |
| `driverTripCountLabel(count)` | S8 | Хос-баталгаатай аяллын тоо |
| `driverNewLabel` | S8 | `Reputation(0,0,0)` тохиолдол |
| `mostTrustedBadge` | S8 | 1-р картын эрэмбийн шалтгаан |
| `reputationLoadingLabel` | S8 | Баримт татагдаж буй 3с |
| `changePriceAction` | S8 | Биен доторх «Буцах»-ыг ялгах |
| `republishRideAction` | S8 | Хугацаа дууссаны дараа |
| `locationSentConfirmation` | S9 | Ногоон pill |
| `driverEtaLabel` | S9 | Том ETA-гийн micro-шошго |
| `leaveChosenDriverTitle` / `...Message` | S9 | `leaveTripTitle` буруу тохирдгийг засах |

### Дизайнаас гарсан кодын олдворууд (нэгтгэлийн жагсаалтад)

1. **S5/S6 — Plus Code тооцоологддог ч харагддаггүй.** `PickedLocation.plusCode`
   (`location_picker.dart:23`) хэрэглэгдэхгүй; спек §5 харуулахыг шаарддаг.
2. **S5/S6 — «Миний байршил» товч байхгүй.** Газрын зураг үргэлж УБ-ын төвөөс эхэлдэг
   (`city_config.dart:31-35`) тул хэрэглэгч гараар чирж хайна.
3. **S7 — `PrimaryButton.loading` дамжуулаагүй.** PoW + релэй нийтлэлт хугацаа авдаг ч
   ямар ч дохио байхгүй (`passenger_ride_page.dart:468`).
4. **S7/S9 — `try/catch` байхгүй.** `publishRequest` / `sendHandoff` алдвал чимээгүй гацна.
5. **S8 — нэр хүнд огт харагддаггүй** атлаа эрэмбийг ганцаараа тодорхойлдог
   (`offer_ranking.dart:38-41`).
6. **S8 — жагсаалт 3 секундын дараа дахин эрэмблэгддэг** (`trip_receipt_repository.dart:23`
   timeout → `:107` setState) — хуруун доор карт үсрэх эрсдэл.
7. **S8 — хоосон төлөв байхгүй**; релэй тасарсан эсэх нь ялгагдахгүй.
8. **S8 — 240с хугацаа дуусахад UI хариу үйлдэл алга** (`ride_request_service.dart:39`).
9. **S9 — гарах диалогийн текст буруу тохирдог**: `leaveTripTitle` «идэвхтэй аялал» гэдэг ч
   аялал хараахан эхлээгүй (`_guardBack:370` `leavingRequest` зөвхөн `offers`-ыг шалгадаг).
10. **S9 — сонгосон саналын үнэ/ETA харагддаггүй** атлаа `_selected.offer.payload`-д бий.

### Контрастын шалгалт (`00-style.md`-ийн хатуу дүрмээр)

- S8-ын 1-р картын «Хамгийн найдвартай» = gold дүүргэлт дээр ink текст (6.8:1) ✅
- S9-ийн ногоон pill дээр цагаан текст — цайван горимд `steppe #2E6E5E` дүүргэлт зөв;
  **харанхуй горимд** `steppeLight #4E9E88` шаардана (theme-д хараахан байхгүй шинэ токен).
- Хаана ч `gold`-ыг цайван paper дээр текст болгож ХЭРЭГЛЭЭГҮЙ. ⚠️ Гэхдээ одоогийн код
  `passenger_ride_page.dart:524` (`offersWaitingTitle`) ба `:571` (`driverOnTheWay`) дээр яг
  тэрийг хийж байна — `TakhiColors.gold` текст өнгөөр. Энэ нь 2.28:1, шинэ хэв маягаар
  **хориотой**; нэгтгэлд ink болгож солих.
