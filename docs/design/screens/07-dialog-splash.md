# 07 — Модал баталгаажуулах диалог ба эхлэлийн дэлгэц (S32–S33) · Тахь

> Хэв маяг: `docs/design/screens/00-style.md` (STYLE PREAMBLE) — доорх prompt бүр түүгээр эхэлнэ.
> Эх код (бүгдийг уншиж нотолсон): `app/lib/widgets/confirm_leave_scope.dart`,
> `app/lib/onboarding/seed_backup_page.dart`, `app/lib/onboarding/onboarding_page.dart`,
> `app/lib/ride/passenger_ride_page.dart`, `app/lib/ride/driver_inbox_page.dart`,
> `app/lib/meter/taximeter_page.dart`, `app/lib/router.dart`, `app/lib/main.dart`,
> `app/lib/identity/identity_state.dart`, `app/lib/theme/takhi_theme.dart`,
> `app/lib/l10n/app_mn.arb`, `app/pubspec.yaml`,
> `app/android/app/src/main/res/values-v31/styles.xml`, `values-night-v31/styles.xml`,
> `drawable*/launch_background.xml`, `brand/BRAND.md`, `brand/out/`.
>
> **Монгол текст бүр `app_mn.arb`-аас яг байгаагаар нь авсан.** arb-д байхгүйг «(шинэ)» гэж
> тэмдэглэв — зохиогоогүй.

---

## Энэ файл яагаад тусад нь бичигдсэн бэ

`SCREEN_SPECS.md`-ийн төгсгөлд байгаа **«ДУТУУ»** хэсэг `UI_SURFACES.md`-ийн 31 гадаргууг
S1–S31-тэй тулгаад **хоёр цоорхой** тодорхойлсон. Тэр хоёр нь дараах шалтгаанаар үлдсэн юм:

1. **Модал диалогууд.** Диалог бол *дэлгэц* биш — тэр нь **зургаа-долоон өөр дэлгэцэн дээр**
   давхарлагдаж гарах ганц компонент. Тиймээс S1, S2, S8, S9, S10, S16, S21-ийн үйлдлийн
   хүснэгтүүдэд «диалог гарна» гэсэн **мөр** бүгд бичигдсэн атлаа диалогийн өөрийнх нь
   scrim, өргөн, радиус, товчны дараалал, урт кирилл шошгын зан төлөв **хаана ч тогтоогдоогүй**
   үлдсэн. Долоон газарт долоон янзаар зурагдахаас сэргийлэх ганц арга нь тэдгээрийг **нэг
   хэсэгт цуглуулж, нэг стандарт** гаргах — энэ нь **S32**.
2. **Splash.** `UI_SURFACES.md`-ийн «Систем түвшний ажил» №6 — 31 дэлгэцийн жагсаалтад
   огт ороогүй тул S дугаар аваагүй. Гэвч энэ бол хэрэглэгчийн **хамгийн түрүүнд харах** зураг
   учир дизайнгүй үлдэж болохгүй — энэ нь **S33**.

**Хаана нийлэх вэ.** Хоёр хэсэг хоёулаа `SCREEN_SPECS.md`-ийн `S31`-ийн **дараа** шууд
залгагдана; «ДУТУУ» хэсгийн 1 ба 2 дугаар цэг тэр үед хаагдана. Нийлүүлсний дараа тоо
дараах болж өөрчлөгдөнө: дугаарлагдсан дэлгэц **31 → 33**, нийт спек нэгж **32 → 34**,
Stitch prompt **38 → 44** (S32-т дөрөв, S33-т хоёр). Хавсралт А-гийн хүснэгтэд хоёр мөр
нэмэгдэнэ. *(Энэ файл `SCREEN_SPECS.md`-ийг өөрөө засаагүй.)*

---

## 0. Энэ бүлгийн бүтцийн үндэс (кодоос нотлогдсон)

### 0.1 Диалог хэдэн хувилбартай вэ — **зургаа биш, долоо**

«ДУТУУ» хэсэг зургаан хувилбар нэрлэсэн. `app_mn.arb`-аас `leave*` / `stay*` / `confirm*` /
`overwrite*` бүх түлхүүрийг татаж, тэдгээрийг кодоос буцаан мөшгиход **долоо** гарч ирэв —
`leaveTripTitle` нь **хоёр өөр дэлгэцэд, өөр өөр кодын замаар** ашиглагддаг тул тусад нь
тоологдох ёстой (зорчигчийн тал нь `_abandonRequest`, жолоочийн тал нь `_abandonTrip`
дуудаж, өөр өөр сүлжээний мессеж явуулдаг):

| # | Гарчиг / бичвэрийн l10n түлхүүр | Товчнууд | Хаана (кодын байрлал) | Хэв шинж |
|---|---|---|---|---|
| 1 | `leaveMeterTitle` / `leaveMeterMessage` | `stayAction` / `leaveAction` | `meter/taximeter_page.dart:331-340`, `enabled: _step == _MeterStep.running` | ② гарах хамгаалалт |
| 2 | `leaveTripTitle` / `leaveTripMessage` — **жолооч** | `stayAction` / `leaveAction` | `ride/driver_inbox_page.dart:222-227`, `enabled: _activeTrip && _tripInFlight` | ② гарах хамгаалалт |
| 3 | `leaveTripTitle` / `leaveTripMessage` — **зорчигч** | `stayAction` / `leaveAction` | `ride/passenger_ride_page.dart:386-390`, `_step` = `done`/`activeTrip` | ② гарах хамгаалалт |
| 4 | `leaveRideRequestTitle` / `leaveRideRequestMessage` | `stayAction` / `leaveAction` | `ride/passenger_ride_page.dart:377,388-389`, `_step == _PassengerStep.offers` | ② гарах хамгаалалт |
| 5 | `leaveSeedBackupTitle` / `leaveSeedBackupMessage` | `stayAction` / **`backToHomeAction`** | `onboarding/seed_backup_page.dart:48-64` — **`ConfirmLeaveScope` БИШ** | ② гарах хамгаалалт |
| 6 | `confirmSelectOfferTitle` / `confirmSelectOfferMessage` | `cancelAction` / `confirmSelectOfferAction` | `ride/passenger_ride_page.dart:210-232` | ① үйлдэл баталгаажуулах |
| 7 | `overwriteIdentityTitle` / `overwriteIdentityMessage` | `overwriteIdentityCancel` / `overwriteIdentityConfirm` | `onboarding/onboarding_page.dart:91-107` | ① үйлдэл баталгаажуулах |

№1–4 нь `ConfirmLeaveScope` дундаа хуваалцдаг ганц widget-ээр гардаг; №5–7 нь тус тусдаа
**гараар бичсэн `showDialog`** — гэхдээ бүтэц нь яг ижил (гарчиг + бичвэр + хоёр товч),
тиймээс визуал стандарт нь нэг байх ёстой.

### 0.2 Нөөц үгсийн дэлгэц яагаад `ConfirmLeaveScope` хэрэглэдэггүй вэ

`confirm_leave_scope.dart:125-142` энэ асуултад өөрөө хариулдаг. `ConfirmLeaveScope` нь
баталгаажсаны дараа **`Navigator.pop()`**-оор дуусдаг. Харин `OnboardingPage` нь нөөц үгсийн
хуудас руу `context.go('/seed')`-ээр очдог — `go` нь стекийг **орлуулдаг** тул `/seed` бол
стекийн цорын ганц гишүүн, `canPop()` = `false`, `pop()` нь юу ч хийхгүй. Тэгвэл «Гарах»
дарсан хүн байсан газраа үлдэж, дараагийн буцах дарахад нь **мөнөөх диалог дахин нээгдэж,
мөнхийн гогцоо** үүснэ. Кодод үүнийг ажиллах үед засахыг оролдоогүй — `assert(false, …)`-аар
хөгжүүлэгчид **шууд алдаа** гэж хэлдэг (мөр 136-142).

Тиймээс `SeedBackupPage` өөрийн `PopScope` + өөрийн `showDialog`-ийг барьж (мөр 38-42, 80-85),
баталгаажсан үед `pop` биш **`context.go('/home')`** хийдэг. Энэ бол хуулбарласан код биш,
**өөр утгатай үйлдэл**: энд «гарах» гэдэг нь буцахыг биш, **урагшлахыг** хэлнэ.

**Дизайнд шууд нөлөө:** яг ийм учраас энэ ганц хувилбарын баталгаажуулах товч нь «Гарах»
(`leaveAction`) биш, **«Нүүр хуудас руу»** (`backToHomeAction`) — өөрөөр хэлбэл **бүх
хувилбарын дотроос хамгийн урт кирилл шошго** энэ дээр гарна (§S32-ын урт шошгын дүрэм үз).

### 0.3 Хоёр хэв шинж — яагаад товчны эмфаз нь ялгаатай байх ёстой вэ

| | ① Үйлдэл баталгаажуулах (№6, 7) | ② Гарах хамгаалалт (№1–5) |
|---|---|---|
| Диалогийг юу нээв | Хэрэглэгчийн **зориудын** товч даралт | **Рефлекс** буцах зангаа / хатуу товч |
| Хэрэглэгч юу хүлээж байна | «Одоо нэг зүйл болно» | «Би зүгээр л буцах гэсэн юм» |
| Аюултай тал нь аль вэ | **Баталгаажуулах** (баруун) | **Гарах** (баруун) |
| Аюулгүй хариулт | `cancelAction` / `overwriteIdentityCancel` | `stayAction` |
| Товчны эмфаз | Баталгаажуулах нь **дүүргэсэн** товч | Гарах нь **зөвхөн улаан текст**, дүүргэлтгүй |

Энэ ялгаа санамсаргүй биш. 00-style §6-гийн danger button-ы тодорхойлолт «…зөвхөн
баталгаажуулах диалог дотор л бүтэн улаан дүүргэлттэй болно» гэсэн нь **зөвшөөрөл**, бүх
диалогт хамаарах үүрэг биш. Дүүргэсэн улаан бол **зогсоох тэмдэг** — зориудаар алхаж явсан
хүний замд тавихад зөв. Харин ② дээр диалогийг нээсэн зүйл нь буцах **рефлекс** учир тэр
рефлекс үргэлжлээд хамгийн тод, хамгийн бүдүүн товчинд буух ёсгүй: энд эмфаз нь **аюулгүй
талд** байх ёстой. Тиймээс ②-т «Үлдэх» нь ink SemiBold (paper дээр 15.4:1 — дэлгэцийн хамгийн
хүчтэй контраст), «Гарах» нь улаан Regular (6.3:1 — тод боловч хөнгөн).

Энэ шийдэл нь `04-driver.md`-ийн S16-д аль хэдийн зурагдсан диалогтой **яг таарна**
(«a plain ink text button "Үлдэх" and a text button "Гарах" in red #9E3327»), тиймээс шинэ
зөрчил үүсгэхгүй.

### 0.4 Диалогийн зан төлөв — кодоос нотлогдсон дөрвөн дүрэм

1. **Scrim дарах = аюулгүй хариулт.** Гурван газарт гурвуулаа `null`-ыг «үлдэх / цуцлах» гэж
   уншдаг: `confirm_leave_scope.dart:116-118`, `seed_backup_page.dart:68-70`,
   `passenger_ride_page.dart:233-235`. Диалогийн гадна дарах, эсвэл диалог дээр буцах дарах нь
   **хэзээ ч аюултай үйлдэл хийхгүй**.
2. **Хоёр диалог давхарлахгүй.** `_asking` тугийг `ConfirmLeaveScope` (мөр 62-66, 92-114) ба
   `SeedBackupPage` (мөр 33-36, 45-67) хоёулаа барьдаг — хоёр дахь буцах даралт диалогийн
   нээгдэх анимацтай уралдаад хоёр дахь ижил диалог үүсгэхгүй.
3. **Унтраасан хамгаалалт чимээгүй байна.** `enabled: false` үед widget нь бүрэн идэвхгүй
   (мөр 72-82) — доор нь өөр `PopScope` (жишээ нь зорчигчийн «нэг алхам буцах») pop-ыг
   татгалзвал энэ нь **өөрийн диалогийг тэр татгалзал дээр гаргахгүй**.
4. **Хамгаалалт унтрах цэг бий.** `onTripSettled` (баримт нийтлэгдсэн эсвэл дүн татгалзсан)
   болмогц `_tripInFlight = false` → тэр мөчөөс буцах диалоггүй. Дууссан аяллаас гарахад
   асуух нь хэрэггүй төдийгүй **хортой**: нөгөө талд «цуцаллаа» гэсэн худал мессеж явуулна.

---

## S32. Модал баталгаажуулах диалог

**Файл:** `app/lib/widgets/confirm_leave_scope.dart` (30-144 — дундын widget; диалогийн бие 95-111);
гараар бичсэн ижил бүтэцтэй гурав: `app/lib/onboarding/seed_backup_page.dart` (43-72),
`app/lib/ride/passenger_ride_page.dart` (207-236), `app/lib/onboarding/onboarding_page.dart` (89-109).
Дуудагдах цэгүүд: `meter/taximeter_page.dart:331-340`, `ride/driver_inbox_page.dart:222-227`,
`ride/passenger_ride_page.dart:376-399`.
**Зорилго:** буцаагдахгүй алдагдал үүсгэх мөчид ганцхан удаа, ойлгомжтойгоор зогсоож,
**юу алдагдахыг нэрлэж** хэлээд шийдвэрийг хэрэглэгчид үлдээх.
**Хаанаас ирнэ:** долоон контекст — доорх үйлдлийн хүснэгтэд S дугаараар.
**Агуулга:** дэвсгэр дэлгэцээ бүрэн бүтэн үлдээсэн, түүн дээр хавтгай ink scrim, түүн дээр
цаасан блок. Блок дотор дээрээс доош: **гарчиг → 3px ink зураас → бичвэр → хоёр товчны эгнээ**.
Дүрс, зураг, дүрслэл, ачаалалтын индикатор **хэзээ ч байхгүй**.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| ② Тоолуураас гарах — гарчиг/бичвэр | «Тоолуурыг зогсоох уу?» (`leaveMeterTitle`) / `leaveMeterMessage` | диалог | S21-ээс буцах зангаа таслагдана | ↓ |
| ② Тоолуур — үлдэх | «Үлдэх» (`stayAction`) | текст-товч | юу ч болохгүй, тоолуур үргэлжилнэ | **S21** |
| ② Тоолуур — гарах | «Гарах» (`leaveAction`) | улаан текст-товч | `_discardRun()` — GPS таслаж, км/хугацаа/дүнг **журналд бичихгүй устгана** | **S4** Нүүр |
| ② Аялалаас гарах (жолооч) — гарчиг/бичвэр | «Аялалаас гарах уу?» (`leaveTripTitle`) / `leaveTripMessage` | диалог | S16-аас буцах зангаа таслагдана | ↓ |
| ② Аялал (жолооч) — гарах | «Гарах» (`leaveAction`) | улаан текст-товч | `_abandonTrip()` — зорчигч руу «хүрлээ» статус илгээж чөлөөлнө, баримт нийтлэхгүй | **S4** Нүүр |
| ② Аялалаас гарах (зорчигч) — гарчиг/бичвэр | «Аялалаас гарах уу?» (`leaveTripTitle`) / `leaveTripMessage` | диалог | S9/S10-аас буцах зангаа таслагдана | ↓ |
| ② Аялал (зорчигч) — гарах | «Гарах» (`leaveAction`) | улаан текст-товч | `_abandonRequest()` — жолоочид цуцлалт илгээж, дуудлагын төлөвийг цэвэрлэнэ | **S4** Нүүр |
| ② Нийтэлсэн дуудлагаас гарах — гарчиг/бичвэр | «Дуудлагаа цуцлах уу?» (`leaveRideRequestTitle`) / `leaveRideRequestMessage` | диалог | S8-аас буцах зангаа таслагдана | ↓ |
| ② Дуудлага — гарах | «Гарах» (`leaveAction`) | улаан текст-товч | `_abandonRequest()` — ирсэн бүх санал устаж, дуудлага цуцлагдана | **S4** Нүүр |
| ② Нөөц үгсээс гарах — гарчиг/бичвэр | «Нөөц үгсээ хадгалсан уу?» (`leaveSeedBackupTitle`) / `leaveSeedBackupMessage` | диалог | S2-оос буцах зангаа таслагдана | ↓ |
| ② Нөөц үг — үлдэх | «Үлдэх» (`stayAction`) | текст-товч | 12 үг дэлгэц дээрээ үлдэнэ | **S2** |
| ② Нөөц үг — гарах | **«Нүүр хуудас руу»** (`backToHomeAction`) | улаан текст-товч | `context.go('/home')` — pop **биш**; 12 үг дахин **хэзээ ч** харагдахгүй | **S4** Нүүр |
| ① Жолооч сонгохыг батлах — гарчиг/бичвэр | «Энэ жолоочийг сонгох уу?» (`confirmSelectOfferTitle`) / `confirmSelectOfferMessage` | диалог | S8 дээр саналын мөр дармагц гарна | ↓ |
| ① Жолооч сонгох — цуцлах | «Цуцлах» (`cancelAction`) | текст-товч | санал сонгогдоогүй хэвээр | **S8** |
| ① Жолооч сонгох — батлах | «Тийм, илгээх» (`confirmSelectOfferAction`) | **gold дүүргэсэн** товч | яг байршил + тэмдэглэл + (зөвшөөрсөн бол) утасны дугаар тэр жолоочид явна | **S9** |
| ① Түлхүүр дарж бичих — гарчиг/бичвэр | «Одоогийн бүртгэлийг дарж бичих үү?» (`overwriteIdentityTitle`) / `overwriteIdentityMessage` | диалог | S1 дээр «Шинээр эхлэх» дармагц, хадгалсан түлхүүртэй үед | ↓ |
| ① Дарж бичих — цуцлах | «Цуцлах» (`overwriteIdentityCancel`) | текст-товч | хуучин түлхүүр хэвээр | **S1** |
| ① Дарж бичих — батлах | «Тийм, үргэлжлүүл» (`overwriteIdentityConfirm`) | **улаан дүүргэсэн** товч | хуучин хувийн түлхүүр **устаж**, шинэ бүртгэл үүснэ | **S2** |
| Scrim / гадна дарах | — (шошгогүй) | зангаа | `null` буцаана = аюулгүй хариулт (үлдэх / цуцлах) | Дэвсгэр дэлгэцээ |
| Диалог дээр буцах дарах | — (шошгогүй) | систем | мөн `null` = аюулгүй хариулт | Дэвсгэр дэлгэцээ |

> ⚠ **Кодоос илэрсэн нэг зөрүү:** зорчигчийн `done` алхам (**S9** «Сонгосон / хүлээж байна»)
> дээр аялал хараахан **эхлээгүй** атал диалогийн гарчиг «Аялалаас гарах уу?» гэж гардаг
> (`passenger_ride_page.dart:377` — `leavingRequest` нь зөвхөн `offers` алхамд `true`).
> Тэр агшинд илүү зөв гарчиг **(шинэ)** хэрэгтэй; энэ баримт үг зохиогоогүй.

**Визуал стандарт (энэ хэсгийн гол — долоон хувилбарт нэгэн адил үйлчилнэ):**

| Хэмжигдэхүүн | Утга | Шалтгаан |
|---|---|---|
| Scrim (цайван) | ink `#1C1A16` **@ 55%**, хавтгай, **blur огт үгүй** | 00-style §9 blur/soft shadow хориотой; дэвсгэр бүдгэрэх ч уншигдсан хэвээр |
| Scrim (харанхуй) | ink `#1C1A16` **@ 72%** | Харанхуйн ground `#211E19` нь ink-тэй ойрхон тул 55% нь давхарга гэж уншигдахгүй |
| Блокийн өргөн | дэлгэцийн өргөн − 2 × 24px, **дээд тал нь 400dp** | 320dp утсанд агуулгын өргөн 224dp, 360dp-д 264dp (доорх шошгын тооцоо энд тулгуурлана) |
| Блокийн радиус | **4px** (карт) — товчны 14px **биш** | 00-style §5: диалог бол хэвлэмэл карт, товч биш |
| Блокийн гүн | Сүүдэргүй; ард нь **3px хатуу ink offset** баруун-доош | 00-style §1 зарчим 2 — гүн нь давхцалаас, сүүдрээс биш |
| Блокийн дэвсгэр | цайван `paper #F4F1E9`; харанхуй `#2C2822` *(00-style §8-ын санал болгосон `surfaceDark` токен — theme-д хараахан алга)* | ground-оос ялгарах ёстой |
| Дотоод padding | **24px** дөрвөн талдаа | — |
| Гарчиг | **22sp** ExtraBold ink, tracking −0.01em, зүүн эгнүүлсэн, хамгийн ихдээ 2 мөр | 00-style §4 display үүрэг |
| Гарчгийн доорх зураас | Гарчгаас **16px** доор, агуулгын бүтэн өргөнд **3px хатуу ink** | 00-style §5 бүдүүн жин = хэсэг тусгаарлах |
| Бичвэр | Зураасаас **16px** доор, **16sp** Regular, мөрийн өндөр **1.45**, ink **100%** | Энэ бол алдагдлыг нэрлэж буй мөр — бүдгэрүүлж болохгүй |
| Бичвэр → товч | **24px** зай | 00-style §5 жигд бус хэмнэл |
| Товчны эгнээ | Баруун эгнүүлсэн, товч бүр **≥48dp** өндөр, дотор нь 20px хэвтээ padding | 00-style §5 хүрэлтийн доод хязгаар |
| Хоёр товчны хоорондох зай | **24px** (12px биш) | S23-E-ийн precedent: хос болж уншигдахаас сэргийлж, санамсаргүй дарахыг хүндрүүлнэ |
| Дараалал (хэвтээ) | **Аюулгүй нь зүүн**, аюултай нь баруун | Android-ын нийтлэг дүрэм; булчингийн ой санамжийг эвдэхгүй |

**Товчны эмфаз (хэв шинжээр):**

- **② гарах хамгаалалт:** «Үлдэх» = ink **SemiBold** текст-товч (дүүргэлтгүй, хүрээгүй);
  «Гарах» / «Нүүр хуудас руу» = **улаан `#9E3327` Regular** текст-товч, дүүргэлтгүй.
  *Харанхуйд улаан нь `errorDark #E18579`* (00-style §8) — `#9E3327` нь харанхуй дээр 2.34:1.
- **① үйлдэл баталгаажуулах:** «Цуцлах» = ink Regular текст-товч; баталгаажуулах нь
  **дүүргэсэн** товч, 14px радиус, 16px босоо padding:
  - `overwriteIdentityConfirm` = **бүтэн улаан `#9E3327` дүүргэлт + цагаан шошго**
    (хувийн түлхүүр **устана** — 00-style §6-ийн «диалог доторх дүүргэсэн danger» яг энэ);
  - `confirmSelectOfferAction` = **бүтэн gold `#C99A3C` дүүргэлт + ink шошго**
    (энэ бол устгал биш, **урагшлах амлалт** — улаан нь 00-style §3-аар зөвхөн алдагдал/аюулыг
    хэлнэ; буцаагдахгүй болохыг **бичвэр** нь хэлж байгаа, өнгө нь биш).

**⚠️ Кириллийн урт шошго — гурван шатны дүрэм**

Кирилл шошго англи эквивалентаасаа 15–20% өргөн (00-style §4), энэ дэлгэцэнд хамгийн хурцаар
мэдэгдэнэ: «Нүүр хуудас руу» = 15 тэмдэгт, англи «Home» = 4. NotoSans SemiBold 16sp дээр
кирилл тэмдэгтийн дундаж өргөн ≈ 8.8dp гэж тооцвол:

| Товчны хос | Тооцсон нийт өргөн | 320dp утас (агуулга 224dp) | 360dp утас (агуулга 264dp) |
|---|---|---|---|
| «Үлдэх» + «Гарах» | ≈ 76 + 76 + 24 = **176dp** | ✅ багтана | ✅ багтана |
| «Цуцлах» + «Тийм, илгээх» | ≈ 85 + 129 + 24 = **238dp** | ❌ **багтахгүй** | ✅ багтана |
| «Үлдэх» + «Нүүр хуудас руу» | ≈ 76 + 164 + 24 = **264dp** | ❌ **багтахгүй** | ⚠ **яг ирмэг дээр** |
| «Цуцлах» + «Тийм, үргэлжлүүл» | ≈ 85 + 164 + 24 = **273dp** | ❌ **багтахгүй** | ❌ **багтахгүй** |

Өөрөөр хэлбэл **өргөний жишиг нь `overwriteIdentityConfirm` («Тийм, үргэлжлүүл»)** —
энэ хос 360dp дээр ч багтахгүй. (Өндрийн жишиг нь өөр: `confirmSelectOfferMessage` бол
хамгийн урт бичвэр, 360dp дээр 3 мөр.) Хоёр өөр «хамгийн муу тохиолдол» гэдгийг мартаж
болохгүй — нэгийг нь багтаасан зохиомж нөгөөг нь баталгаажуулахгүй.

**Дүрэм (энэ дарааллаар):**

1. **Хэвтээ эгнээ** — хоёр шошго + 24px зай нь агуулгын өргөнд багтаж байвал.
2. **Босоо давхарлалт** — багтахгүй бол товчнууд **бүтэн өргөн** болж, хооронд нь 8px зайтай
   давхарлана. Энэ үед **дараалал урвуу болно: аюултай нь ДЭЭР, аюулгүй нь ДООД.**
   Шалтгаан: диалогийг буцах **рефлекс** нээсэн, тэр рефлекс доошоо үргэлжилдэг ба эрхий хуруу
   дэлгэцийн доод хэсэгт амардаг — аюулгүй хариулт эрхий хурууны доор байх ёстой (iOS-ийн
   action sheet «Cancel»-ыг хамгийн доор тавьдаг зарчим). Хэвтээ эгнээний зүүн→баруун
   дараалал нь давхарлахдаа дээр→доор болж **хөрвөхгүй** — энэ бол зориудын урвуулалт.
3. **Хоёр мөр болох** — ганц шошго дангаараа бүтэн өргөнд багтахгүй бол (маш нарийн дэлгэц,
   эсвэл системийн фонтын хэмжээ томруулсан үед) шошго **хоёр мөр болж эвхэгдэнэ**, товч нь
   өсөж (min-height 48dp, тогтмол өндөр **биш**), төвд эгнүүлнэ.

**Хатуу хориглох зүйл:** шошгыг **богиносгохгүй** (`…` ellipsis), фонтын хэмжээг
**автоматаар багасгахгүй** (`FittedBox`/`AutoSizeText` төрлийн шийдэл), шошгыг **товчилж
бичихгүй**. Товч нь тогтмол өндөртэй **биш**, `min-height`-тэй (00-style §4-ийн шууд заавар:
«товч тогтмол өндөртэй биш, min-height-тэй байна»).

**Төлөвүүд:**

- **Ачаалж буй:** байхгүй — диалог синхрон нээгддэг, дотор нь ямар ч async ажил байхгүй.
  Баталгаажуулсны дараах ажил (`_abandonTrip`, `_abandonRequest`, `_discardRun`) нь диалог
  хаагдсаны **дараа**, `onConfirmedLeave`-ээр ажиллана — тиймээс диалогт spinner хэрэггүй.
- **Хоосон:** байхгүй.
- **Алдаа:** диалог өөрөө алдаж чадахгүй. Гэвч `onConfirmedLeave` доторх сүлжээний илгээлт
  (жолоочид цуцлалт, зорчигчид «хүрлээ») бүгд `unawaited` — **бүтэлгүйтвэл хэрэглэгч мэдэхгүй**.
  Нөгөө тал мэдэгдэл хүлээж үлдэх эрсдэлтэй. Зорилтот төлөв: алдааны snackbar **(шинэ)**.
- **Давхар нээгдэх:** боломжгүй — `_asking` тугаар хаагдсан (§0.4.2).
- **Root route дээр буруу хэрэглэх:** debug-т `assert` унана (`confirm_leave_scope.dart:136-142`);
  release-д хэрэглэгч диалогийн мөнхийн гогцоонд орно. Тиймээс энэ widget **зөвхөн `push`-аар
  нээгдсэн route**-ыг хамгаална.
- **Хамгаалалт унтарсан:** `enabled: false` үед буцах зангаа диалоггүй, шууд ажиллана.
- **Зөвшөөрөл:** хамаарахгүй.

**⚠ Хэв маягийн зөрчлүүд (одоогийн код) — бүгд долоон хувилбарт нэгэн зэрэг хамаарна:**

① `takhi_theme.dart`-д **`dialogTheme` огт байхгүй** (мөр 50-55 — зөвхөн `colorScheme`,
`scaffoldBackgroundColor`, `fontFamily`), тиймээс бүх диалог Material 3-ийн өгөгдмөлөөр
гарна: **28px радиус** (00-style-ын 4px биш), **elevation + сүүдэр** (00-style §9-д хориотой),
surface tint. ② `TextButton`-ы M3 өгөгдмөл foreground нь `colorScheme.primary` = **gold** —
өөрөөр хэлбэл «Үлдэх», «Гарах», «Цуцлах» бүгд **gold текст цайван гадаргуу дээр ≈2.28:1**
болж гарч байна. Энэ бол 00-style §3-ын **нэрлэсэн хориотой хослол** («gold дээр paper —
ХОРИОТОЙ»), бөгөөд WCAG-ийн 4.5:1-ээс хоёр дахин доогуур. ③ Scrim нь M3-ын өгөгдмөл
`black54` — цэвэр хар, 00-style §9-д хориотой; ink `#1C1A16` байх ёстой. ④ Товчны эмфаз
одоо **урвуу**: `overwriteIdentityConfirm` нь `FilledButton` (gold дүүргэлт — устгах үйлдэлд
gold), харин бусад бүх аюултай товч энгийн `TextButton`. ⑤ Долоон газарт долоон удаа гараар
`AlertDialog` барьсан тул нэг засвар долоон файлд давтагдана — зорилтот төлөв: `DialogTheme`
+ ганц дундын `TakhiConfirmDialog` widget.

**Stitch prompt — A) ГАРАХ ХАМГААЛАЛТ (② хэв шинж, хэвтээ эгнээ):**

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

SCREEN — Android mobile app modal dialog: the guard raised when a back gesture would throw
away a running taximeter. The screen behind it is deliberately plain and only there to be
dimmed: a flat app bar on paper #F4F1E9 with a 3px solid ink rule under it, and one enormous
ink tabular number filling the upper half. Over all of it lies a flat ink #1C1A16 scrim at
55% opacity — flat colour only, the background stays sharp and merely darker, with no blur
anywhere. Centred over the scrim, a paper #F4F1E9 dialog block inset 24px from both screen
edges, 4px radius, no shadow and no elevation, offset 3px down-right by a solid ink shape
behind it, with 24px of inner padding. Inside, top to bottom: a heavy ink heading at 22sp
with tight tracking reading "Тоолуурыг зогсоох уу?"; 16px below it a 3px solid ink rule
across the full inner width; 16px under that four lines of ink body text at 16sp with 1.45
line height reading "Одоо гарвал энэ явалтын км, хугацаа, төлбөрийн дүн хадгалагдалгүй
устана. Дүнг журналд бичихийн тулд эхлээд «Дуусгах» дарна уу."
Then a 24px gap and a right-aligned action row with both targets at least 48dp tall: a bold
ink text button reading "Үлдэх", a deliberate 24px gap, then a plain red #9E3327 text button
reading "Гарах". Neither action button is filled or outlined. No icons, no illustration.
```

**Stitch prompt — B) УРТ КИРИЛЛ ШОШГО, БОСОО ДАВХАРЛАСАН (② хэв шинж, нарийн дэлгэц):**

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

SCREEN — Android mobile app modal dialog on a narrow 320dp-wide phone, showing what happens
when a Mongolian Cyrillic button label is far too long for a side-by-side row. Behind it,
dimmed, is a grid of twelve numbered recovery words on #E7DEC9 blocks. A flat ink #1C1A16
scrim at 55% opacity covers everything, with no blur. The dialog block is paper #F4F1E9,
inset 24px from both edges, 4px radius, no shadow, offset 3px down-right by a solid ink
shape, 24px inner padding. Inside: a heavy ink heading at 22sp reading
"Нөөц үгсээ хадгалсан уу?"; 16px below it a 3px solid ink rule; 16px under that two lines of
ink body text at 16sp, 1.45 line height, reading "Энэ 12 үгийг одоо бичиж авахгүй бол дахин
харах боломжгүй. Утсаа гээвэл бүртгэлээ бүрмөсөн алдана."
Then a 24px gap and — because the labels cannot fit one row — two STACKED full-width buttons
8px apart, each at least 48dp tall with its label centred and never truncated: the upper one
a plain red #9E3327 text button reading "Нүүр хуудас руу", the lower one a bold ink text
button reading "Үлдэх". The safe action is the lower one, nearest the thumb. Neither button
has a fill or a border. Nothing is shrunk, abbreviated or cut off with an ellipsis.
```

**Stitch prompt — C) ҮЙЛДЭЛ БАТАЛГААЖУУЛАХ, GOLD (① хэв шинж):**

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

SCREEN — Android mobile app modal dialog: the last stop before a passenger's exact pickup
location is handed to one chosen driver. Behind it, dimmed, is a vertical list of driver
offer cards on #E7DEC9 blocks with large ink tabular prices. A flat ink #1C1A16 scrim at 55%
opacity covers them, sharp underneath, no blur. The dialog is a paper #F4F1E9 block inset
24px from both edges, 4px radius, no shadow, offset 3px down-right by a solid ink shape, with
24px inner padding. Inside: a heavy ink heading at 22sp reading "Энэ жолоочийг сонгох уу?";
16px below it a 3px solid ink rule; 16px under that the longest body text in the whole
product, four lines of ink at 16sp with 1.45 line height, reading "Приус · 12000₮ · 6 мин.
Баталвал таны яг байршил — утсаа хуваалцахаар тохируулсан бол дугаар ч мөн — энэ жолоочид
илгээгдэнэ. Буцааж татах боломжгүй."
Then a 24px gap and a right-aligned row: a plain ink text button "Цуцлах", a 24px gap, then a
solid gold #C99A3C filled button with 14px radius, 16px vertical padding and a bold ink
#1C1A16 label "Тийм, илгээх". The filled button is gold, never red — this action commits,
it does not destroy. Both targets are at least 48dp tall. No icons, no avatar, no map.
```

**Stitch prompt — D) УСТГАХ БАТАЛГААЖУУЛАЛТ, УЛААН (① хэв шинж):**

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

SCREEN — Android mobile app modal dialog: the only dialog in the product that destroys
something unrecoverable — the private key already stored on this phone. Behind it, dimmed, is
a bare onboarding screen on paper #F4F1E9 with a heavy ink wordmark and two stacked buttons.
A flat ink #1C1A16 scrim at 55% opacity covers it, no blur. The dialog is a paper #F4F1E9
block inset 24px from both edges, 4px radius, no shadow, offset 3px down-right by a solid ink
shape, 24px inner padding. Inside: a heavy ink heading at 22sp wrapping to two lines, reading
"Одоогийн бүртгэлийг дарж бичих үү?"; 16px below it a 3px solid ink rule; 16px under that
three lines of ink body text at 16sp with 1.45 line height reading "Шинэ бүртгэл үүсгэвэл
одоогийн хувийн түлхүүр устаж, орлуулагдана. Хуучин нөөц үгээ хадгалаагүй бол дахин сэргээх
боломжгүй болно."
Then a 24px gap and — because this label pair is the widest in the product and cannot fit one
row — two STACKED full-width buttons 8px apart: the upper one filled solid red #9E3327 with
14px radius, 16px vertical padding and a bold WHITE centred label "Тийм, үргэлжлүүл"; the
lower one a plain ink text button "Цуцлах", at least 48dp tall. Red fill appears here and
nowhere else outside a dialog. No warning triangle, no icon, no exclamation mark.
```

---

## S33. Эхлэлийн дэлгэц (splash)

**Файл:** *(Flutter талд одоохондоо байхгүй — доорх §«Хоёр давхарга» үз.)*
Native тал нь **аль хэдийн байгаа**: `app/pubspec.yaml:139-148` (`flutter_native_splash:` блок),
`app/android/app/src/main/res/values-v31/styles.xml` ба `values-night-v31/styles.xml`,
`drawable*/launch_background.xml` (+ `background.png`, `splash.png`, `android12splash.png`).
Flutter талын одоогийн зан төлөв: `app/lib/main.dart:8-21` → `app/lib/router.dart:45-55`.
Ассетууд: `app/assets/brand/takhi_horse_ink.png`, `takhi_horse_gold.png` (эх нь `brand/out/`).
**Зорилго:** аппын процесс асахаас эхний жинхэнэ дэлгэц гартал өнгөрөх хугацааг **брэндийн
нэг тайван зурагаар** дүүргэж, буруу дэлгэц анивчихаас сэргийлэх.
**Хаанаас ирнэ:** өмнөх дэлгэц **байхгүй** — Android launcher-ээс процесс эхлэхэд.
**Хаашаа очих:** хадгалсан түлхүүр байвал **S4 Нүүр**, байхгүй бол **S1 Онбординг эхлэл**
(шилжилтийн логик доор нотлогдсон).
**Агуулга:** ганц зүйл — **тахь адууны хавтгай silhouette**, хоосон дулаан суурин дээр төвд.
Өөр юу ч байхгүй.

### Энэ бол «байхгүй дэлгэц» биш — хагас байгаа дэлгэц

`SCREEN_SPECS.md` «Splash — Андройдын өгөгдмөл» гэж тэмдэглэсэн боловч энэ салбар дээрх код
үүнийг **давсан байна**. Бодит байдал:

**(а) Native launch screen — БАЙГАА, брэндчлэгдсэн.**

| Юу | Утга | Эх сурвалж |
|---|---|---|
| Цайван суурь | `#F4F1E9` (paper) | `pubspec.yaml:140`, `values-v31/styles.xml` `windowSplashScreenBackground` |
| Цайван зураг | `assets/brand/takhi_horse_ink.png` (ink адуу) | `pubspec.yaml:141` |
| Харанхуй суурь | **`#1C1A16`** | `pubspec.yaml:142`, `values-night-v31/styles.xml` |
| Харанхуй зураг | `assets/brand/takhi_horse_gold.png` (gold адуу) | `pubspec.yaml:143` |
| Android 12+ зам | `windowSplashScreenAnimatedIcon` = `@drawable/android12splash` | `values-v31/styles.xml` |
| Android 11 ба доош | `layer-list`: `background.png` (1×1 px, `gravity="fill"` = хавтгай өнгө) + `splash.png` төвд | `drawable*/launch_background.xml` |
| Зургийн бодит хэмжээ | mdpi 256×256px, xxhdpi 768×768px → **256dp өргөн** | PNG толгойгоос хэмжсэн |

**(б) Flutter-ийн эхний frame — БАЙХГҮЙ, энд жинхэнэ цоорхой байна.**

`main.dart:8` `runApp` дуудмагц `MaterialApp.router` шууд суудаг, `router.dart:46`
`initialLocation: '/'` тул **эхний зурагдах Flutter frame нь S1 Онбординг**. Харин
`redirect` (мөр 48-53) нь:

```dart
final hasIdentity = ref.read(currentIdentityProvider).valueOrNull != null;
if (hasIdentity && atOnboarding) return '/home';
```

`currentIdentityProvider` бол **`FutureProvider`** (`identity/identity_state.dart:9-11`) —
түлхүүрийн агуулахаас async уншина. Тэр уншилт дуусаагүй байхад `valueOrNull` нь `null`,
тиймээс `hasIdentity` = `false`, тиймээс **redirect ажиллахгүй** → буцаж ирсэн хэрэглэгч
S1 Онбордингийг **хормын төдий хардаг**, дараа нь уншилт дуусмагц `_IdentityRouteRefresh`
(мөр 27-31) redirect-ийг дахин ажиллуулж `/home` руу шидэж байна.

**Тэгэхээр S33-ын жинхэнэ ажил бол «брэндийн зураг нэмэх» биш — тэр анивчилтыг устгах.**
Redirect нь `isLoading` ба `data(null)` хоёрыг **ялгаж** чаддаг болох ёстой:

| `currentIdentityProvider`-ийн төлөв | Одоо юу болдог | Зорилтот |
|---|---|---|
| `loading` | S1 Онбординг зурагдана | **S33** эхлэлийн дэлгэц барина |
| `data(Identity)` | S1 → дараа нь S4 (анивчилт) | шууд **S4 Нүүр** |
| `data(null)` | S1 | **S1 Онбординг** |
| `error` | S1 (`valueOrNull` = null) | **S1 Онбординг** |

### Хугацаа

| Давхарга | Хэдий хугацаа | Хяналт |
|---|---|---|
| (а) Native | Процесс эхлэхээс Flutter engine эхний frame зуртал (хүйтэн асалтад ойролцоогоор 300–900ms) | Бидэнд **хяналт байхгүй** — OS шийднэ |
| (б) Flutter | `currentIdentityProvider` `loading` байх хугацаа — secure-storage уншилт, ердийн үед **0–250ms** | Бидний хяналтад |

- **Доод хязгаар: 0ms.** Брэнд харуулах гэж frame-ийг зориудаар барихыг **хориглоно** —
  BRAND.md-ийн «чамирхалгүй» гэдэгтэй шууд зөрчилдөнө. Уншилт 40ms-д дуусвал S33 хоёрхон
  frame амьдарна, тэгээд ч хэрэглэгч юу ч анзаарахгүй — учир нь энэ хугацаанд дэлгэц дээр
  байгаа зураг нь native давхаргынхаас **ялгагдахгүй** (доорх «үсрэлт» хэсэг).
- **Дээд хязгаар: 3000ms.** Secure-store уншилт хэзээ ч буцаж ирэхгүй бол (төхөөрөмжийн
  keystore гацсан г.м.) хэрэглэгч эхлэлийн дэлгэцэн дээр **мөнхөд түгжигдэх** ёсгүй —
  3 секунд өнгөрвөл S1 Онбординг руу гарна. Түлхүүр байсан хэрэглэгч тэндээс «Сэргээх»-ээр
  явж чадна; түгжигдсэн хүн хаашаа ч явж чадахгүй.

### Хөдөлгөөн

BRAND.md-ийн дуу хоолой: «шулуун, эрх чөлөөтэй, чамирхалгүй». Үүнийг шууд орчуулбал:

- **Адуу огт хөдлөхгүй.** Гарч ирэхгүй, томрохгүй, гэрэлтэхгүй, давхихгүй. Тэр аль хэдийн
  тэнд байгаа — native давхаргаас яг тэр байрандаа, яг тэр хэмжээгээр үргэлжилж байна.
  Ямар ч fade-in/scale нь статик native frame-тэй **шууд зөрчилдөж**, үсрэлт болж харагдана.
- **Ганц зөвшөөрөгдсөн хөдөлгөөн:** хүлээлт **600ms** давбал 00-style §7-ийн ачаалалтын
  элемент гарч ирнэ — эргэлдэх spinner **биш**, **3px өндөр gold `#C99A3C` зураас, 140px
  өргөн, дөрвөлжин үзүүртэй**, зүүнээс баруун тийш дүүрнэ, дэлгэцийн ~82% өндөрт. 600ms-ээс
  доош хүлээлтэд огт гарахгүй (гялсхийх нь өөрөө чимээ шуугиан).
- **Шилжилт (S33 → S1/S4):** **160ms fade**, гулсалт байхгүй. 00-style §7-ийн дэлгэц хоорондын
  240ms гулсалт энд **тохирохгүй** — splash нь дараагийн дэлгэцтэйгээ эн тэнцүү дэлгэц биш,
  түүний ард байгаа давхарга. Суурь өнгө fade-ийн туршид **өөрчлөгдөхгүй** (хоёулаа ижил
  ground) тул зөвхөн адуу арилж, доороос жинхэнэ дэлгэц илэрнэ.

### Гэрэл / харанхуй — **хоёуланг нь**, сонголт биш

Энэ бол дизайны шийдвэр биш, **аль хэдийн тогтоогдсон баримт**: Android 12+ дээр LaunchTheme-ийг
OS нь апп ажиллахаас **өмнө** сонгодог ба `values-night-v31/styles.xml` аль хэдийн байгаа тул
харанхуй хувилбар **гарцаагүй гарна**. Нэг тогтмол харагдац сонгоно гэвэл харанхуй горимтой
утсанд native давхарга харанхуй, Flutter давхарга цайван болж **хамгийн муу төрлийн үсрэлт**
үүснэ. Тиймээс Flutter давхарга нь `MediaQuery.platformBrightness`-ийг **эхний frame дээрээ**
уншиж native-тайгаа тааруулна.

### ⚠️ Үсрэлтийн эрсдэл — гурван эх үүсвэр, гурвуулаа хэмжигдсэн

| # | Юу зөрөх вэ | Одоогийн утга | Яаж сэргийлэх |
|---|---|---|---|
| 1 | **Харанхуйн суурь өнгө** | native `#1C1A16` (`pubspec.yaml:142`) ↔ Flutter-ийн харанхуй ground **`#211E19`** (`takhi_theme.dart:45`) | **Жинхэнэ зөрүү.** `color_dark`/`android_12.color_dark`-ыг **`#211E19`** болгож `dart run flutter_native_splash:create`-ыг дахин ажиллуулна. Theme-ийн токен бол эх сурвалж (00-style §8-д харанхуй ground = `#211E19`), тиймээс native нь theme-д тааруулагдана, эсрэгээр нь биш. Цайван талд зөрүү **байхгүй** (`#F4F1E9` = `#F4F1E9`) |
| 2 | **Адууны хэмжээ/байрлал** | native pre-12 зам: **256dp өргөн, төвд** (splash.png mdpi 256×256px-ээс хэмжсэн). Android 12+ зам: OS өөрөө маскалж масштаблана, тиймээс **pre-12-оос ялимгүй ялгаатай** | Flutter давхарга нь **яг тэр PNG-г, төвд, 256dp өргөнөөр** зурна. Android 12+ дээр үлдэх өчүүхэн зөрүүг `android_12: image`-ийн дотоод зайг тохируулж арилгана. **Энэ утгыг таамаглахгүй — бүтээсэн APK дээр хэмжиж баталгаажуулна** |
| 3 | **Системийн мөрүүд** | LaunchTheme дээр `windowDrawsSystemBarBackgrounds=false`, `windowLayoutInDisplayCutoutMode=shortEdges` | Flutter давхарга нь `SystemUiOverlayStyle`-аа ижил ground өнгөтэй, ил тод байдлаар тавина — эс бөгөөс статус мөр өнгө солиод анивчина |

### Ассетын сонголт — аль файл вэ

| Файл | Шийдвэр |
|---|---|
| `brand/out/takhi_horse_ink.png` (1024×1024, транспарент) | ✅ **Цайван горимд** — BRAND.md өөрөө «splash, watermark, дотоод UI-д» гэж тэмдэглэсэн (мөр 49). Native давхарга аль хэдийн үүнийг ашиглаж байна |
| `brand/out/takhi_horse_gold.png` (1024×1024, транспарент) | ✅ **Харанхуй горимд** — мөн адил |
| `brand/out/icon_gold_{48…1024}.png` | ❌ Өөрийн gold дэвсгэртэй, 22.5% бөөрөнхий өнцөгтэй — цаасан суурин дээр **хөвж буй дугуй дөрвөлжин** мэт харагдана. App icon-ы үүрэг, splash-ынх биш |
| `brand/out/icon_ink_1024.png`, `icon_paper_1024.png` | ❌ Мөн адил дэвсгэртэй хувилбарууд |
| `brand/gen/takhi_v1.png` | ❌ Цэвэрлэгдээгүй эх концепц (bevel/сүүдэртэй) — 00-style §9-ийн хориотой зүйлсийг агуулна |
| `brand/out/final_preview.png` | ❌ Хянах хуудас, ассет биш |

**Замын дүрэм:** Flutter кодоос `assets/brand/takhi_horse_ink.png` гэж заана (`pubspec.yaml:162-165`-д
`assets/brand/` бүртгэгдсэн). `brand/out/...` руу шууд заахыг **оролдож болохгүй** — Flutter
пакет өөрийн хавтаснаас гадагш харж чаддаггүй тул PNG-үүд `app/assets/brand/`-д зориуд
хуулагдсан (`pubspec.yaml:127-138`-ын тайлбар).

### Текст — **огт байхгүй**

S33 дээр хэрэглэгчид харагдах **ганц ч мөр текст байхгүй**: «Ачаалж байна…», хувилбарын
дугаар, «Тахь» wordmark, уриа, «Powered by», хувийн эрхийн мөр — **бүгд хориотой**.
Хоёр шалтгаан:

1. **Техникийн.** Native давхаргад текст байхгүй (зөвхөн silhouette). Flutter давхаргад текст
   нэмбэл тэр текст асалтын дундуур **гэнэт үүсэж** харагдана — яг тэр үсрэлтийг л бид арилгах
   гэж байгаа.
2. **Брэндийн.** BRAND.md: «Амлалт биш — баримт», «Корпораци биш, нийтийн өмч». Эзэнгүй,
   нийтийн хэрэгсэлд өөрийгөө танилцуулах уриа тохирохгүй. Ачаалж байгааг хэлэх ч шаардлагагүй —
   аппыг нээсэн хүн ачаалж байгааг мэдэж байгаа.

**Ганц үл хамаарах зүйл (харагдахгүй):** дэлгэц уншигчид зориулсан semantics шошго нь
**«Тахь»** (`appName`) — arb-д аль хэдийн байгаа түлхүүр, шинэ мөр шаардахгүй.

**Төлөвүүд:**

- **Ачаалж буй:** энэ бол өөрөө ачаалалтын төлөв. 600ms хүртэл огт хөдөлгөөнгүй; түүнээс
  цааш 3px gold зураас гарна.
- **Хоосон:** хамаарахгүй.
- **Алдаа:** `currentIdentityProvider` алдвал (`SecureStoreException`) эхлэлийн дэлгэц дээр
  **алдааны мэдээлэл харуулахгүй** — S1 Онбординг руу гарна, тэнд «Шинээр эхлэх»/«Сэргээх»
  гэсэн жинхэнэ гарц байгаа. Splash дээр алдаа харуулах нь хэрэглэгчийг гарцгүй дэлгэцэнд
  түгжинэ.
- **Гацсан:** 3000ms дээд хязгаар → S1 Онбординг (дээрх «Хугацаа»).
- **Зөвшөөрөл:** энэ дэлгэц ямар ч зөвшөөрөл шаардахгүй, шаардах ч ёсгүй — байршил, микрофоны
  хүсэлт нь өөрсдийн дэлгэцэн дээрээ, контексттэйгээ хамт гарна.

**Stitch prompt — A) ЦАЙВАН (хүлээлт уртассан, gold зураастай):**

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

SCREEN — Android mobile app splash screen: the first frame of the app, and the emptiest
surface in the whole product. The canvas is flat warm paper #F4F1E9 edge to edge — no
gradient, no vignette, no texture, no card, no border, no rounded container of any kind.
Horizontally centred, and vertically centred at about 46% of the screen height so it does not
sit visually low, is a single solid ink #1C1A16 silhouette of a galloping Przewalski's horse,
256dp wide, drawn as one flat filled shape: no outline, no bevel, no highlight, no shadow, no
gloss. Its one defining detail is the short upright brush mane instead of a long falling one.
Low on the screen, at about 82% of the height and horizontally centred, sits a single
indeterminate progress bar: a 3px-tall gold #C99A3C rule, 140px wide, with square ends and no
rounding, filled about one third from the left — not a spinning circle, not a ring, not dots.
There is absolutely no text anywhere: no app name, no wordmark, no tagline, no version
number, no "loading" label, no copyright line. Two objects on an empty warm page, nothing else.
```

**Stitch prompt — B) ХАРАНХУЙ (богино хүлээлт, ямар ч индикаторгүй):**

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

SCREEN — Android mobile app splash screen in dark mode: the same first frame as the light
one, inverted, and this time the wait is short so nothing at all is moving. The canvas is a
flat warm dark ground #211E19 edge to edge — deliberately NOT pure black #000000, and with no
gradient, no vignette, no texture and no container. Horizontally centred and vertically
centred at about 46% of the screen height is a single solid gold #C99A3C silhouette of a
galloping Przewalski's horse, 256dp wide, drawn as one flat filled shape with no outline, no
bevel, no glow, no shadow and no gloss; its defining detail is the short upright brush mane
rather than a long falling one. This is the one context where gold is a foreground shape on a
dark ground rather than a fill carrying ink text on it.
Nothing else is on screen: no progress bar, no spinner, no ring, no dots, no app name, no
wordmark, no tagline, no version number, no loading text. One gold shape on an empty dark
page, perfectly still.
```

---

## Хавсралт — Энэ бүлэгт илэрсэн цоорхойнууд

**l10n (шинэ мөр шаардлагатай):**

| Хаана | Ямар текст дутуу | Яагаад хэрэгтэй |
|---|---|---|
| S32 № 3 (S9 «Сонгосон / хүлээж байна») | Тэр алхамд тохирох гарчиг | Аялал эхлээгүй байхад «Аялалаас гарах уу?» гэж асууж байна |
| S32 (бүх ② хувилбар) | `onConfirmedLeave`-ийн сүлжээний илгээлт бүтэлгүйтсэн үеийн мэдэгдэл | Одоо чимээгүй алдаж, нөгөө тал мэдэгдэл хүлээж үлдэнэ |
| S33 | — **байхгүй**, зориудаар | Splash дээр текст огт байх ёсгүй (дээрх «Текст» хэсэг) |

**Код/тохиргооны цоорхой (l10n биш):**

| Хаана | Юу засах | Хэр яаралтай |
|---|---|---|
| `takhi_theme.dart` | `dialogTheme` нэмэх: 4px радиус, elevation 0, paper/`#2C2822` гадаргуу, ink `#1C1A16` @55/72% scrim | **Өндөр** — 7 диалогт зэрэг үйлчилнэ |
| `takhi_theme.dart` | `textButtonTheme`-ийн foreground-ыг ink болгох | **Хамгийн өндөр** — одоо gold-on-paper 2.28:1, 00-style §3-ын нэрлэсэн хориотой хослол |
| 7 дуудагдах цэг | Дундын `TakhiConfirmDialog` widget-ээр солих | Дунд — давхардлыг арилгана |
| `pubspec.yaml:142,147` | `color_dark` → `#211E19`, дараа нь `flutter_native_splash:create` дахин ажиллуулах | **Өндөр** — харанхуй горимын үсрэлт |
| `router.dart:48-53` | `redirect`-ийг `isLoading` ↔ `data(null)` ялгадаг болгох + S33 гадаргуу | **Өндөр** — буцаж ирсэн хэрэглэгч бүрд S1 анивчиж байна |
| `04-driver.md` S16 | «Нүүр хуудас (S3)» гэсэн лавлагаа — Нүүр бол **S4** (`01-onboarding-home.md:215`), S3 нь «Түлхүүр сэргээх» | Бага — зөвхөн баримтын алдаа |
