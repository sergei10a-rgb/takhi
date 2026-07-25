# БҮЛЭГ 5 — Оффлайн таксиметр (S19–S22)

**Хэв маяг:** `00-style.md` (`steppe-print`). Stitch prompt бүр тэндэх STYLE PREAMBLE-ээр эхэлнэ.

**Эх код:** дөрвүүлээ `app/lib/meter/taximeter_page.dart` доторх нэг `_MeterStep` төлөвт машины
алхмууд (`:40`). Тусдаа route байхгүй — go_router-т ганц зам бүртгэлтэй
(`app/lib/router.dart:84-87`, `/meter`), нүүрнээс `context.push('/meter')`-ээр нээгддэг
(`router.dart:209-217`), тиймээс `Scaffold` → `AppBar` (`taximeter_page.dart:309`) буцах сумыг
**автоматаар** гаргадаг. Тэр сумны утга алхам бүрт өөр — доорх хүснэгтүүдэд задалсан.

**Энэ бүлгийн онцлог — Nostr огт байхгүй.** Жолооч зам дээр гар өргөсөн хүнийг авахад аппаа
асаагаад явсан км-ээр төлбөрөө бодуулна: relay, түлхүүр, DM, баримт — юу ч ашиглагдахгүй
(`taximeter_page.dart:42-45`). Интернэт байвал очих цэгийн үнэлгээг жинхэнэ замын зайгаар
(OSRM `router.project-osrm.org`, `routing_client.dart:30-32`), байхгүй/удвал шулуун зай ×1.35-аар
(`fare_estimate.dart:33-59`, `fare_calc.dart:14-18`) — «ойролцоогоор» гэсэн шошготойгоор.
Ажиллаж буй тоолуурын дүн бүхэлдээ оффлайн: GPS цэгүүдийн haversine нийлбэр × тариф
(`gps_track.dart:28-40`, `meter_session.dart:21-22`).

**Навигацийн одоогийн байдал (кодоос нотлогдсон):**

| Юу | Хаана | Төлөв |
|---|---|---|
| AppBar буцах сум | `Scaffold(appBar: AppBar(...))` `:307-311` — push-аар нээгддэг тул автомат | ✅ байгаа |
| Ажиллаж буй тоолуураас гарах баталгаажуулалт | `ConfirmLeaveScope(enabled: _step == running)` `:331-341` + `leaveMeterTitle`/`leaveMeterMessage` | ✅ байгаа |
| Гарахыг баталсан үед цэвэрлэх (журналд БИЧИХГҮЙ) | `_discardRun` `:270-283` | ✅ байгаа |
| Тариф засахаас алхам-буцалт | `PopScope(canPop:false)` `:321-330` → `_cancelTariffEdit` `:149-154` | ✅ байгаа |
| Биен дэх «Цуцлах» товч (зөвхөн засварын үед) | `_TariffStep` `:417-420`, `l.cancelAction` | ✅ байгаа |
| Хадгалсан тариф руу буцаж засах гарц | `_IdleStep` `:455-459`, `meterEditTariffAction` → `_editTariff` `:132-140` | ✅ байгаа |
| Хоёр pop-хамгаалалт хэзээ ч зэрэг байхгүй | `build` `:312-330` тайлбар | ✅ байгаа |

**Зорилтот төлөвт нэмэгдэх ерөнхий зүйлс (бүх 4 дэлгэцэд хамаарна):**

1. **AppBar гарчиг алхам бүрт өөр** — одоо дөрвүүлээ `taximeterTitle` = «Таксиметр» (`:309`).
2. **Алтан текст цайван суурин дээр = хориотой** (`00-style.md`, 2.28:1). Код одоо дөрвөн газарт
   зөрчиж байна: `:472-479` (үнэлгээ 24sp gold), `:507-514` (ажиллаж буй дүн 56sp gold),
   `:559-565` (`meterSummaryTitle` gold), `:567-574` (эцсийн дүн 40sp gold). Зорилтот: **тоо нь
   ink, алт нь ард нь блок дүүргэлт**.
3. **Мянгатын таслал алга** — `meterFareLabel` = `"{mnt}₮"` (`app_mn.arb:82`) тул «12400₮» гэж
   гардаг. Жолооч хормын зуур харах тул `12 400₮` болгох (форматын өөрчлөлт, шинэ мөр биш).
4. **Ачаалалт = 3px gold indeterminate bar**, spinner биш (`00-style.md`).

---

### S19. Тариф тохируулах

**Файл:** `app/lib/meter/taximeter_page.dart` (`_MeterStep.needsTariff` арм `:345-350`;
`_TariffStep` `:379-425`; `_saveTariff` `:102-125`; `_editTariff` `:132-140`) +
`app/lib/meter/tariff_store.dart` (`:9-25`)

**Зорилго:** Жолооч 1 км-ийн үнээ тогтооно — энэ тоо цаашид явсан км бүрийг үржүүлж, аяллын
төлбөрийг бүхэлд нь тодорхойлно.

**Хаанаас ирнэ:** Нүүр → «Жолооч» горим → «Таксиметр» (`startAsMeterAction`,
`router.dart:209-217`) → `/meter`. Хадгалсан тариф байхгүй бол `_loadTariff` (`:93-100`) энэ
алхмыг үлдээнэ. Мөн **S20-оос** «Тариф: {mnt}₮/км — засах» дарахад засварын горимоор энд ирнэ
(`_editTariff` `:132-140`).

**Агуулга:**
1. AppBar — одоо `taximeterTitle` = «Таксиметр». Зорилтот: «Тариф» **(шинэ)**.
2. Тоон гар оруулах талбар, `labelText` = `meterTariffFieldLabel` = «1 км-ийн үнэ (₮)»
   (`:406-414`), `keyboardType: number`.
3. Алдааны мөр — зөвхөн буруу оролтын дараа: `meterTariffInvalidHint` (`:412`).
4. Үндсэн товч `saveTariffAction` = «Хадгалах» (`:416`).
5. **Зөвхөн засварын үед** — «Цуцлах» текст-товч (`cancelAction`, `:417-420`). Анх удаа
   тохируулж байгаа бол энэ товч огт байхгүй (`onCancel == null`, `:349`).
6. Зорилтот **(шинэ)**: талбарын доор нэг мөр жишээ-туслах текст ба хурдан сонголтын чипүүд
   (1500 / 1800 / 2000) — гараар бичих алдааг багасгана.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум (анхны тохиргоо) | — (icon) | Навигаци | Хамгаалалт байхгүй (`_canCancelTariffEdit == false` тул `ConfirmLeaveScope(enabled:false)`) | Нүүр хуудас |
| AppBar буцах сум (засварын үед) | — (icon) | Навигаци | `PopScope(canPop:false)` `:321-330` → `_cancelTariffEdit` — засвар хаягдана, хуучин тариф хэвээр | S20 |
| AppBar гарчиг | «Тариф» **(шинэ)** | Текст | Одоо «Таксиметр» — алхам ялгагдахгүй | — |
| Үнийн талбар | `meterTariffFieldLabel` | Оролт | `_tariffController`; хоосон зай автоматаар хасагдана («15 000» → 15000, `:106-108`) | — |
| «Хадгалах» | `saveTariffAction` | Үндсэн товч | `_saveTariff`: `null` эсвэл `<= 0` бол алдаа тавина (`:114-117`), зөв бол `TariffStore`-д бичээд алхам солино | S20 |
| «Цуцлах» (зөвхөн засвар) | `cancelAction` | Текст-товч | `_cancelTariffEdit` — юу ч бичихгүй | S20 |
| Хурдан сонголтын чип | «1800» **(шинэ)** | Чип | Талбарыг дүүргэнэ, хадгалахгүй | — |
| Хадгалсны дараах засах гарц | `meterEditTariffAction` («Тариф: {mnt}₮/км — засах») | Холбоос (S20 дээр) | S20-ийн эхлүүлэх товчны доор үргэлж харагдана (`:455-459`) → энэ дэлгэцийг **засварын горимоор** нээнэ | S19 (засвар) |

**Төлөвүүд:**
- **Ачаалж буй** — `_step`-ийн эхний утга `needsTariff` (`:54`) бөгөөд `_loadTariff` async тул
  **тариф хадгалсан жолоочид ч энэ дэлгэц хормын төдий анивчина**. Зорилтот: уншиж дуустал
  талбарын оронд 3px gold indeterminate bar.
- **Хоосон** — талбар хоосон байхад ч товч идэвхтэй хэвээр (санаатай: шалгалт нь «дарах» мөчид
  л хийгдэнэ, `:109-113`). Зорилтот үүнийг хадгална, зөвхөн алдааг тод харуулна.
- **Алдаа** — `meterTariffInvalidHint` = «Зөв тоо оруулна уу (жишээ нь 1000)», талбарын хүрээ
  улаан #9E3327 болно.
- **Зөвшөөрөл татгалзсан** — хамаарахгүй: энэ алхам GPS огт шаарддаггүй.

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

Android mobile app screen where a taxi driver sets the per-kilometre price their own meter
will charge. Top: a flat app bar on paper ground, no shadow, a 3px solid ink rule along its
bottom edge, a back arrow on the left inside a 48dp touch target, and the bold left-aligned
title "Тариф". Below it, generous empty space, then a small uppercase Cyrillic label with
wide letter tracking "1 км-ийн үнэ (₮)" sitting directly above a single text input on paper
ground with a 1.5px ink border and 4px radius; inside the input the typed value reads as huge
right-aligned tabular ink figures "1800" at about 56sp with a smaller ink "₮" after it, and a
blinking ink caret. Under the input, a one-line helper in red #9E3327: "Зөв тоо оруулна уу
(жишээ нь 1000)". Below that a row of three small rounded outline chips with ink numerals
"1500", "1800", "2000". Then a 3px solid ink section rule. At the bottom, a full-width solid
gold #C99A3C button with 14px radius, 18px vertical padding and a centred bold ink label
"Хадгалах"; directly beneath it a plain ink text button "Цуцлах" with no fill or border. The
typed number must be the largest element on screen; everything else stays quiet.
```

---

### S20. Эхлүүлэхэд бэлэн + чиглэл/тооцоо

**Файл:** `app/lib/meter/taximeter_page.dart` (`_buildIdleStep` `:359-376`; `_IdleStep`
`:427-486`; `_onDestinationChanged` `:156-167`; `_estimateDestinationFare` `:179-202`;
`_start` `:204-229`) + `app/lib/map/location_picker.dart` (`:32-114`) +
`app/lib/meter/fare_estimate.dart` + `app/lib/meter/routing_client.dart`

**Зорилго:** Жолооч зорчигчийг суулгачихсан, тоолуураа асаах нэг товчны зайд байна; хүсвэл очих
цэгээ тавьж ойролцоогоор хэдэн төгрөг болохыг **урьдчилан** хэлж өгнө.

**Хаанаас ирнэ:** S19-ийн «Хадгалах»-аас; хадгалсан тарифтай жолооч нүүрнээс шууд энд ирнэ
(`_loadTariff` `:93-100`); S22-ийн «Эхлүүл»-ээс (`_resetToIdle` `:285-293`).

**Агуулга (кодын дараалал — дээрээс доош):**
1. AppBar «Таксиметр». Зорилтот: «Тоолуур» **(шинэ)**.
2. **Хамгийн дээр** үндсэн товч `startMeterAction` = «Эхлүүл» (`:450`) — энэ дэлгэцийн цорын
   ганц жинхэнэ үйлдэл, тиймээс дээд байрлал зөв.
3. Тарифын мөр — харандааны дүрс + `meterEditTariffAction` = «Тариф: {mnt}₮/км — засах»
   (`:455-459`). Санаатай ил: 1500-г 15000 гэж бичсэнээ явахаас өмнө л анзаарна (`:452-454`).
4. `meterDestinationOptionalHint` = «Очих цэг (сонголттой)» (`:461`).
5. Төв-зүү газрын зураг, өндөр 260 (`location_picker.dart:78-99`) + тэмдэглэлийн талбар
   `landmarkHint` (`location_picker.dart:101-111`). **Тэмдэглэлийн текст энэ дэлгэцэд
   ашиглагддаггүй** — зөвхөн координат нь тооцоонд ордог (`:196-198`); зорилтот төлөвт
   тэмдэглэлийн талбарыг эндээс нуух.
6. Үнэлгээний блок — зөвхөн тооцоо ирсний дараа: `estimatedFareLabel` = «≈ {mnt}₮» (24sp) ба
   оффлайн тооцоо байвал `estimatedFareApproxLabel` = «ойролцоогоор» (`:470-481`).

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | — (icon) | Навигаци | `ConfirmLeaveScope(enabled:false)` — алдах зүйл алга, шууд гарна | Нүүр хуудас |
| AppBar гарчиг | «Тоолуур» **(шинэ)** | Текст | Одоо «Таксиметр» | — |
| «Эхлүүл» | `startMeterAction` | Үндсэн товч | `_start`: зөвшөөрөл шалгана → GPS урсгал + 2 сек тик асаана (`:216-222`) | S21 (эсвэл зөвшөөрөл татгалзсан төлөв) |
| «Тариф: {mnt}₮/км — засах» | `meterEditTariffAction` | Текст-товч (icon) | `_editTariff` — талбарыг одоогийн утгаар дүүргээд засварын горим нээнэ | S19 |
| Газрын зураг чирэх | — | Дохио | `onCenterChanged` → `_onDestinationChanged`; хуучин үнэлгээ **шууд арилна** (`:163`), 600 мс тайвширсны дараа л тооцоо явна (`:38`, `:164-166`) | Байрандаа |
| Тэмдэглэл талбар | `landmarkHint` | Оролт | Бичих бүрд debounce дахин эхэлнэ; утга нь тооцоонд ордоггүй | — |
| Үнэлгээний тоо | `estimatedFareLabel` | Текст | OSRM-ээс жинхэнэ замын зай ирвэл яг тоо; сүлжээ унтарсан/4 сек хэтэрвэл шулуун зай ×1.35 | — |
| «ойролцоогоор» | `estimatedFareApproxLabel` | Тэмдэглэгээ | `isApproximate == true` үед л гарна (`fare_estimate.dart:52-59`) | — |
| «Зөвшөөрөл өгөх» | `grantLocationPermissionAction` | Товч | `_retryLocationPermission` (`:258-262`) | Байрандаа (эсвэл хэвийн төлөв рүү) |

**Төлөвүүд:**
- **Ачаалж буй** — очих цэгийн тооцоо явж байх үе (debounce 600 мс + зөвшөөрөл + GPS + HTTP,
  4 сек хүртэл). Одоо **ямар ч заалт байхгүй** — хуучин тоо арилаад хоосон зай үлддэг. Зорилтот:
  үнэлгээний блокийн оронд 3px gold indeterminate bar.
- **Хоосон** — очих цэг сонгоогүй бол үнэлгээний блок огт байхгүй; «Эхлүүл» ямагт идэвхтэй
  (очих цэг заавал биш).
- **Алдаа** — сүлжээний алдаа тусдаа алдаа гэж харагдахгүй, **чимээгүй** оффлайн тооцоо руу
  шилжээд «ойролцоогоор» гэж тэмдэглэгдэнэ (санаатай, `fare_estimate.dart:16-22`).
- **Зөвшөөрөл татгалзсан** — бүх бие солигдож `LocationPermissionDeniedView` гарна
  (`:360-362`): `locationPermissionNeededHint` + `grantLocationPermissionAction`. AppBar болон
  буцах сум хэвээр үлдэнэ.

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

Android mobile app screen where a taxi driver has just picked someone up from the street and
is one tap away from starting the meter, with an optional destination price check. Top: a
flat app bar on paper ground, no shadow, a 3px solid ink rule along its bottom edge, a back
arrow on the left in a 48dp touch target, bold left-aligned title "Тоолуур". Immediately
below, the main action: a full-width solid gold #C99A3C button, 14px radius, at least 64dp
tall, with a centred bold ink label "Эхлүүл". Directly under it a quiet single line with a
small ink pencil icon and underlined ink text "Тариф: 1800₮/км — засах". Then a 3px solid ink
section rule carrying the small uppercase label "Очих цэг (сонголттой)" on its left end. Below
that a warm paper-toned map with ink-drawn roads, about 260dp tall, with one large gold
#C99A3C pin fixed dead centre that never moves while the map slides beneath it. At the bottom
of the screen a flat #E7DEC9 card with 4px radius and a hard 3px solid ink offset behind it,
holding huge tabular ink figures "≈ 8400₮" and, under them, small uppercase ink text
"ойролцоогоор". Money is ink on gold or sand — never gold text on paper.
```

---

### S21. ТООЛУУР АЖИЛЛАЖ БАЙНА

> **Энэ бол бүх аппын хамгийн онцгой шаардлагатай дэлгэц.** Жолооч жолоо барьж, нарны гэрэлд,
> хормын зуур харна. Зорчигч хажуугаас хардаг — тоо нь итгэл төрүүлэх ёстой.

**Файл:** `app/lib/meter/taximeter_page.dart` (`_RunningStep` `:488-543`; `_start` `:204-229`;
`_finish` `:231-256`; `_discardRun` `:270-283`; тик `:30`) + `app/lib/meter/meter_session.dart`
+ `app/lib/meter/fare_calc.dart` (`:6-7`) + `app/lib/geo/gps_track.dart` (`:28-47`)

**Зорилго:** Явж байх хугацаанд төлбөр хэрхэн өсөж байгааг хоёр тал маргаангүй харна.

**Хаанаас ирнэ:** Зөвхөн S20-ийн «Эхлүүл»-ээс (`_start` `:224-228`).

**Агуулга:**
1. AppBar «Таксиметр». Зорилтот: «Тоолуур ажиллаж байна» **(шинэ)** + баруун талд амьд
   төлөвийн pill **(шинэ)**.
2. Асар том дүн — `meterFareLabel` = «{mnt}₮», одоо 56sp gold (`:505-515`). Зорилтот: ~96sp
   **ink**, ард нь бүтэн өргөний **gold блок**; дэлгэцийн дээд гуравны нэгийг эзэлнэ.
3. `meterRunningDistanceLabel` = «{km} км» (`:516`) ба `meterRunningDurationLabel` = «{min} мин»
   (`:517`) — хоёрдогч, хажуу хажуугаа.
4. Газрын зураг — үлдсэн зайг бүтэн эзэлнэ (`Expanded`, `:519-535`), явсан зам gold polyline
   4px (`:522-532`), төв нь сүүлийн GPS цэг (`:500-502`).
5. Доод талд `finishMeterAction` = «Дуусгах» (`:536-539`).

**Шинэчлэлтийн хэмнэл:** GPS цэг ирэх бүрд (`:216-219`) + 2 секунд тутам (`_fareTickInterval`
`:30`) rebuild. **Тоо огт анимацлахгүй** (`00-style.md`: odometer roll хориотой) — хормын зуур
харах үед хөдөлж буй цифр уншигдахгүй.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | — (icon) | Навигаци | `ConfirmLeaveScope(enabled:true)` `:331-341` → баталгаажуулах диалог | Диалог |
| Хардвэр буцах / свайп | — | Навигаци | Мөн адил диалогт орно (`confirm_leave_scope.dart:69-84`) | Диалог |
| Диалогийн гарчиг | `leaveMeterTitle` («Тоолуурыг зогсоох уу?») | Диалог | — | — |
| Диалогийн тайлбар | `leaveMeterMessage` | Диалог | Км, хугацаа, дүн **хадгалагдалгүй устана** гэж шууд хэлнэ | — |
| «Үлдэх» | `stayAction` | Диалогийн товч | Юу ч болохгүй, тоолуур үргэлжилнэ | S21 |
| «Гарах» | `leaveAction` | Диалогийн товч | `_discardRun` — GPS/тик таслаад **журналд бичихгүй** (`:264-283`) | Нүүр хуудас |
| Ажиллаж буй pill | «ЯВЖ БАЙНА» **(шинэ)** | Төлөвийн pill | Тоолуур амьд гэдгийг зорчигчид харуулна (steppe #2E6E5E; **харанхуйд `steppeLight #4E9E88`**) | — |
| Том дүн | `meterFareLabel` | Текст | `computeFareMnt` = тариф × метр ÷ 1000, бүхэл төгрөг рүү нь тойрно | — |
| Зай / хугацаа | `meterRunningDistanceLabel`, `meterRunningDurationLabel` | Текст | Зай = haversine нийлбэр; хугацаа = эхний ба сүүлийн GPS цэгийн зөрүү (`gps_track.dart:44-47`) | — |
| Газрын зураг | — | Дүрслэл | Явсан зам gold шугамаар; чирэхэд зөвхөн харагдац хөдөлнө, тооцоонд нөлөөлөхгүй | — |
| «Дуусгах» | `finishMeterAction` | Үндсэн товч | `_finish`: GPS+тик таслаад `MeterTripEntry`-г локал журналд бичнэ (`:244-250`) | S22 |

**Санамсаргүй хүрэлтээс хамгаалах (зорилтот, шинэ мөр шаардахгүй):** «Дуусгах» товчийг нэг
хүрэлтээр биш **≈1 секунд дарж барихад** ажиллуулна — товчны зүүн ирмэгээр нимгэн ink цагираг
дүүрч байгааг харуулна. Ингэснээр шошго «Дуусгах» хэвээр, шинэ диалог/шинэ текст хэрэггүй.
Хүрэлтийн талбай ≥64dp (`00-style.md`).

**Төлөвүүд:**
- **Ачаалж буй** — эхний GPS цэг ирэх хүртэл: 0₮ / 0.0 км / 0 мин, зураг УБ-ын анхны төв дээр
  (`city_config`, `:500-502`). Зорилтот: «GPS хүлээж байна» **(шинэ)** гэсэн pill + 3px gold
  indeterminate bar; тэг тоог гэрэлгүйдүүлж (60% ink) харуулна.
- **Хоосон** — байхгүй: тоолуур асахаас эхлээд үргэлж утгатай.
- **Алдаа** — GPS урсгал алдаа өгвөл `listen(...)` дээр `onError` **байхгүй** (`:216-219`) тул
  тоо чимээгүй хөлдөнө. Зорилтот: «GPS тасарлаа» **(шинэ)** улаан pill + сүүлийн зөв утгыг
  хадгалж харуулах.
- **Зөвшөөрөл татгалзсан** — энэ алхамд орохын өмнө шалгагдсан (`:207-213`); гүйж байхад
  зөвшөөрөл цуцлагдвал одоогийн код үүнийг мэдрэхгүй (цоорхой).

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

Android mobile app screen showing a taxi meter that is currently running, read at a glance by
a driver whose hands are on the wheel, in direct sunlight, while the passenger watches from
the side. Top: a flat app bar on paper ground with a 3px solid ink rule along its bottom edge,
a back arrow on the left in a 48dp touch target, the bold title "Тоолуур ажиллаж байна", and
on the right a fully round steppe green #2E6E5E pill with small uppercase white text "ЯВЖ
БАЙНА". Directly below, a solid gold #C99A3C block spanning the full screen width and about a
third of its height, carrying a tiny uppercase ink label "ТӨЛБӨР" and under it the fare as
enormous tabular ink numerals "12 400₮" at roughly 96sp, optically centred, perfectly still.
Beneath the gold block one row split into two equal cells by a 1px ink hairline: left cell
small uppercase label "ЯВСАН ЗАЙ" over "8.2 км", right cell "ХУГАЦАА" over "17 мин", both in
about 34sp tabular ink figures. The rest of the screen is a warm paper-toned map with ink
roads and the driven track drawn as a thick gold #C99A3C line. Pinned at the bottom above a
3px ink rule: a full-width 72dp-tall button, #E7DEC9 fill with a 1.5px ink border, bold ink
label "Дуусгах", and a thin ink progress ring at its left edge indicating press-and-hold.
```

---

### S22. Дууссан — дүн ба төлбөр

**Файл:** `app/lib/meter/taximeter_page.dart` (`_FinishedStep` `:545-592`; `_finish` `:231-256`;
`_resetToIdle` `:285-293`) + `app/lib/meter/meter_journal.dart` (`:12-38`, `:49-75`) +
`app/lib/payment/driver_qr_display.dart` (`:19-41`) + `app/lib/meter/onboarding_qr_config.dart`

**Зорилго:** Эцсийн дүнг маргаангүй харуулж, зорчигч бэлнээр эсвэл банкны QR-аар төлөх, дараа нь
жолооч дараагийн зорчигч руу нэг товчоор шилжих.

**Хаанаас ирнэ:** Зөвхөн S21-ийн «Дуусгах»-аас — журналд бичигдсэний **дараа** (`:250-255`).

**Агуулга:**
1. AppBar «Таксиметр». Зорилтот: `meterSummaryTitle` = «Аяллын дүн» (**мөр бэлэн байгаа**).
2. `meterSummaryTitle` = «Аяллын дүн» гарчиг (`:559-565`).
3. Эцсийн дүн — `meterFareLabel`, одоо 40sp gold (`:567-574`). Зорилтот: ink, gold блок дээр.
4. `meterRunningDistanceLabel` ба `meterRunningDurationLabel` (`:575-576`). Анхаар: энд хугацаа
   нь **хананы цагаар** (`endedAt - startedAt`, `:554`), S21-д GPS цэгийн зөрүүгээр тооцогддог —
   хоёр тоо 1-2 минутаар зөрж болно.
5. **Төлбөрийн хэсэг** — `DriverQrDisplay` (`:581`): хадгалсан QR зураг 220×220, эсвэл
   `qrNotSetHint` + `qrCaptureAction`.
6. «Тахь тат» QR — 96px, `kTakhiAppDownloadUrl` руу заана (`:583`) + `downloadTakhiQrLabel` =
   «Тахь — эзэнгүй такси» (`:585`).
7. Үндсэн товч `startMeterAction` = «Эхлүүл» → дараагийн зорчигч (`:587`).

**Төлбөрийн хоёр арга (зорилтот бүтэц):** энэ дэлгэцэд «бэлэн» ба «банкны шилжүүлэг» гэсэн хоёр
арга **зэрэгцээ** харагдана — сонголт биш, зорчигчид өгч буй хоёр гарц. Зүүн талд жижиг
«Бэлнээр» **(шинэ)** блок (мөнгөн дэвсгэртийн ink дүрс, дүн нь дээр аль хэдийн бичигдсэн тул
дахин тоо бичихгүй). Баруун талд өргөн «Банкны QR» **(шинэ)** блок.

**QR харуулах хэсэг (тусад нь — зорчигч өөрийн утсаараа уншина):**
- QR-ыг **цэвэр цагаан** дэвсгэр дээр **цэвэр хар** модулиар зурна (paper/ink өнгө QR-т
  хэрэглэхгүй — уншилтын контраст эвдэрдэг), эргэн тойронд quiet zone бүрэн үлдээнэ.
- Хэмжээ ≥260dp тал (одоо 220), 1.5px ink хүрээ + hard 3px ink offset — «энэ бол уншуулах зүйл»
  гэдэг нь эргэлзээгүй байх.
- QR дээр юу ч давхцахгүй: тэмдэг, лого, дүн, ямар ч overlay байхгүй.
- Дэлгэцийн гэрлийг энэ мөчид түр дээшлүүлнэ **(шинэ, зан төлөв)** — нарны гэрэлд утаснаас утас
  руу уншуулах цорын ганц найдвартай арга.
- QR-ын доор `payWithQrOrCashHint` = «Жолоочийн QR-ыг уншуулах эсвэл бэлнээр төлнө үү»
  (**мөр бэлэн байгаа**, одоо зөвхөн зорчигчийн талд ашиглагддаг) — энэ дэлгэцийг зорчигч
  харах тул яг тохирно.
- QR хадгалаагүй бол: `qrNotSetHint` + `qrCaptureAction` — гэхдээ **энэ бол алдаа биш**, бэлэн
  мөнгөний блок хэвээр ажиллана.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | — (icon) | Навигаци | `ConfirmLeaveScope(enabled:false)` — бичилт аль хэдийн журналд орсон, алдах зүйл алга | Нүүр хуудас |
| AppBar гарчиг | `meterSummaryTitle` | Текст | Одоо «Таксиметр» гэж бичдэг | — |
| Эцсийн дүн | `meterFareLabel` | Текст | `MeterTripEntry.fareMnt` — цаашид өөрчлөгдөхгүй | — |
| Зай / хугацаа | `meterRunningDistanceLabel`, `meterRunningDurationLabel` | Текст | Журналд бичигдсэн утгууд | — |
| «Бэлнээр» блок | «Бэлнээр» **(шинэ)** | Мэдээллийн блок | Үйлдэл шаардахгүй — дүнг бэлнээр авна | — |
| Банкны QR | — (зураг) | Дүрслэл | `driverQrBytesProvider`-оос локал файл; сүлжээ шаардахгүй | — |
| QR тайлбар | `payWithQrOrCashHint` | Текст | Зорчигчид хандсан мөр | — |
| «Зураг сонгох» (QR байхгүй үед) | `qrCaptureAction` | Текст-товч | `DriverQrCapturePage` push хийнэ (`driver_qr_display.dart:31-34`) | Банкны QR зураг дэлгэц → буцахад энд ирнэ |
| «Тахь тат» QR | `downloadTakhiQrLabel` | Дүрслэл | `kTakhiAppDownloadUrl` руу заасан статик QR; дарагддаггүй | — |
| «Эхлүүл» | `startMeterAction` | Үндсэн товч | `_resetToIdle` — session, дүн, үнэлгээ цэвэрлэгдэнэ | S20 |
| «Нүүр хуудас руу» **(нэмэх)** | `backToHomeAction` | Текст-товч | Ээлж дуусгаж буй жолоочид ил гарц (мөр бэлэн: `app_mn.arb:154`) | Нүүр хуудас |

**Төлөвүүд:**
- **Ачаалж буй** — `_finish` журналд бичиж дуустал (`await ... append`, `:250`) энэ дэлгэц огт
  гарахгүй, S21 хэвээр хүлээнэ. Зорилтот: «Дуусгах» товчны `loading` төлөвийг ашиглах
  (`primary_button.dart:38-46` дэмждэг).
- **Хоосон** — QR хадгалаагүй жолооч: `qrNotSetHint` + `qrCaptureAction`. Бэлэн мөнгөний блок
  ямагт байдаг тул дэлгэц утгагүй болохгүй.
- **Алдаа** — (а) `driverQrBytesProvider`-ийг `.valueOrNull`-аар уншдаг тул **ачаалж байх үе ба
  QR байхгүй үе ялгагддаггүй** (`driver_qr_display.dart:25-26`) — «оруулаагүй байна» гэж
  хормын зуур анивчиж болно; (б) журналд бичих алдаа баригддаггүй (`:250`). Хоёулаа зорилтот
  төлөвт засагдана.
- **Зөвшөөрөл татгалзсан** — хамаарахгүй: энэ дэлгэц GPS шаарддаггүй.

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

Android mobile app screen showing the final amount of a finished offline metered taxi ride and
how the passenger pays it. Top: a flat app bar on paper ground with a 3px solid ink rule along
its bottom edge, a back arrow on the left in a 48dp touch target, and the bold left-aligned
title "Аяллын дүн". Below it a full-width solid gold #C99A3C block with a tiny uppercase ink
label "НИЙТ" over the final fare in enormous tabular ink numerals "12 400₮" at about 72sp;
under the block one row split by a 1px ink hairline: "8.2 км" on the left, "17 мин" on the
right, in small tabular ink figures. Then a 3px solid ink section rule. Payment area: on the
left a narrow flat #E7DEC9 card, 4px radius, hard 3px ink offset, with an ink banknote icon
and the label "Бэлнээр"; on the right a wider card labelled "Банкны QR" containing a bank QR
code drawn pure black on pure white inside a 1.5px ink frame, at least 260dp square, quiet
zone intact and nothing overlapping it. Under both cards, small ink caption "Жолоочийн QR-ыг
уншуулах эсвэл бэлнээр төлнө үү". At the bottom a small 96dp QR with caption "Тахь — эзэнгүй
такси", then a full-width gold button "Эхлүүл" and a plain ink text button "Нүүр хуудас руу".
```

---

## Шинээр шаардлагатай l10n мөрүүд (нэгтгэлд)

| Санал болгож буй түлхүүр | Монгол текст | Хаана |
|---|---|---|
| `meterTariffStepTitle` | «Тариф» | S19 AppBar |
| `meterIdleStepTitle` | «Тоолуур» | S20 AppBar |
| `meterRunningStepTitle` | «Тоолуур ажиллаж байна» | S21 AppBar |
| `meterRunningPill` | «ЯВЖ БАЙНА» | S21 төлөвийн pill |
| `meterWaitingGpsPill` | «GPS хүлээж байна» | S21 эхний фикс хүртэл |
| `meterGpsLostPill` | «GPS тасарлаа» | S21 урсгалын алдаа |
| `meterFareMicroLabel` | «ТӨЛБӨР» | S21 том тооны дээд шошго |
| `meterTotalMicroLabel` | «НИЙТ» | S22 том тооны дээд шошго |
| `meterDistanceMicroLabel` | «ЯВСАН ЗАЙ» | S21/S22 |
| `meterDurationMicroLabel` | «ХУГАЦАА» | S21/S22 |
| `payCashLabel` | «Бэлнээр» | S22 төлбөрийн блок |
| `payBankQrLabel` | «Банкны QR» | S22 төлбөрийн блок |

**Аль хэдийн байгаа тул шинээр бичих ШААРДЛАГАГҮЙ:** `meterSummaryTitle` («Аяллын дүн»),
`backToHomeAction` («Нүүр хуудас руу»), `payWithQrOrCashHint`, `cancelAction`, `stayAction`,
`leaveAction`, `leaveMeterTitle`, `leaveMeterMessage`.
