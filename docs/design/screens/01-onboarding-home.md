# 01 — Онбординг + Нүүр · S1–S4

> Хэв маяг: `00-style.md` («Талын хэвлэмэл» / `steppe-print`).
> Stitch prompt бүр §2-ын STYLE PREAMBLE-ээр бүтнээр эхэлнэ.
> Хэрэглэгчид харагдах бүх текст `app/lib/l10n/app_mn.arb`-аас авсан; arb-д
> байхгүйг «(шинэ)» гэж тэмдэглэв.
>
> Навигацийн байдал (branch `fix/navigation-back`, 2026-07-25 уншсанаар):
> S2-т буцалтын хамгаалалт **аль хэдийн хийгдсэн** (`PopScope` + баталгаажуулах
> диалог), S3 нь `push`-аар нээгддэг тул AppBar-ийн буцах сум **аль хэдийн бий**,
> S1/S4 нь стекийн үндэс тул буцах сум байх ёсгүй.

---

### S1. Онбординг эхлэл

**Файл:** `app/lib/onboarding/onboarding_page.dart` (21–184)
**Зорилго:** шинэ хэрэглэгч аппын мөн чанарыг ойлгож, горимоо сонгоод, түлхүүрээ шинээр үүсгэх эсвэл хуучнаа сэргээх хоёрын аль нэгийг сонгоно.
**Хаанаас ирнэ:** аппын анхны эхлэл (`/`, `initialLocation`). Хадгалагдсан түлхүүртэй бол `routerProvider`-ийн redirect энэ дэлгэцийг алгасаад шууд `/home` руу явуулна — өөрөөр хэлбэл энд ирсэн бүхэн бол ямар ч бүртгэлгүй хүн.

**Агуулга (дээрээс доош):**
1. Тахийн дугуй брэнд тэмдэг (132dp, `assets/icon.png`).
2. Wordmark — `l.appName` «Тахь», 52sp.
3. Горим сонгох хоёр нүдтэй шилжүүлэгч (`_ModeToggle`).
4. Хууль зүйн сануулга — `l.legalNoticeBody`, жижиг, төвлөрүүлсэн.
5. (Алдааны үед) `l.createIdentityError`.
6. Үндсэн товч `l.createIdentity` + хоёрдогч товч `l.restoreIdentity`.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| Буцах сум | — | — | Байхгүй — энэ бол стекийн үндэс | — |
| Горим — зорчигч | «Зорчигч» (`passengerMode`) | Хоёр нүдтэй сонголт | Локал `_mode` солигдоно | Хэвээрээ |
| Горим — жолооч | «Жолооч» (`driverMode`) | Хоёр нүдтэй сонголт | Локал `_mode` солигдоно | Хэвээрээ |
| Хууль зүйн сануулга | «Тахь бол эзэнгүй P2P платформ…» (`legalNoticeBody`) | Уншигдах текст | Үйлдэлгүй | — |
| Үндсэн товч | «Шинээр эхлэх» (`createIdentity`) | Primary button | Шинэ түлхүүр үүсгэж, 12 үгийг санах ойгоор дамжуулна | `go('/seed', extra: mnemonic)` — **стекийг орлуулна** |
| Дарж бичих диалог — цуцлах | «Цуцлах» (`overwriteIdentityCancel`) | Диалогийн товч | Юу ч болохгүй | Энэ дэлгэц |
| Дарж бичих диалог — батлах | «Тийм, үргэлжлүүл» (`overwriteIdentityConfirm`) | Диалогийн товч | Хуучин хувийн түлхүүр устаж, шинээр үүснэ | `/seed` |
| Хоёрдогч товч | «Сэргээх» (`restoreIdentity`) | Secondary button | Сэргээх дэлгэц нээнэ | `push('/restore')` — S1 доор үлдэнэ |

**Төлөвүүд:**
- **Ачаалж буй** — `_creating == true` үед үндсэн товч шошгоо алдаж спиннер болно (`PrimaryButton.loading`). Диалог нээлттэй байхад спиннер асахгүй (санаатай).
- **Алдаа** — `SecureStoreException` (түлхүүрийн сан түгжигдсэн/боломжгүй) үед товчны дээр `l.createIdentityError` гарч, товч дахин идэвхжинэ.
- **Баталгаажуулалт** — хадгалагдсан түлхүүр байхад «Шинээр эхлэх» дарвал `overwriteIdentityTitle` / `overwriteIdentityMessage` диалог гарна.
- Хоосон/зөвшөөрлийн төлөв энд байхгүй — сүлжээ, GPS-д огт хамаарахгүй дэлгэц.

**Дизайны заавал засах хоёр зүйл (кодод одоо байгаа, `00-style.md` зөрчиж байна):**
- `_Brandmark` дээрх `boxShadow` (blur 36) — §9-ийн «blur/soft shadow байхгүй» дүрмийг зөрчиж байна. Гүнийг хатуу 3px ink offset-ээр орлуулна.
- Wordmark нь `TakhiColors.gold` өнгөтэй, цаасан дэвсгэр дээр — **2.28 : 1**, §3-ын хориотой хослол. Wordmark ink болно; gold нь ард нь блок дүүргэлт болж орно.
- Мөн тэмдэглэх нь: энд сонгосон горим `HomePage` руу дамждаггүй (`HomePage` өөрийн `_mode`-оо зорчигчоор эхлүүлдэг). Дизайны хувьд S1-ийн сонголт S4 дээр хадгалагдаж харагдах ёстой.

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

Android mobile app screen — the first screen of a fresh install, where a rider picks a role
and then either creates a new key or restores an old one. No app bar and no back arrow.
Upper third: a 132dp circular brandmark showing a Przewalski horse head as flat ink linework
on a solid gold #C99A3C disc, with a hard 3px ink offset behind the disc and absolutely no
glow or blur. Directly beneath it the wordmark "Тахь" in heavy ink #1C1A16 display letters
at 52sp with wide tracking — the wordmark is ink, never gold, because gold on paper is
unreadable. Middle: a full-width role switch inside a 1.5px ink frame, split into two 56dp
cells with no gap; the selected cell is filled solid gold with a bold ink label, the
unselected cell stays paper with an ink label. Left cell "Зорчигч", right cell "Жолооч".
Under the switch, three lines of small ink body text: "Тахь бол эзэнгүй P2P платформ.
Жолоочийн шалгалт байхгүй. Хэрэглэгч ба жолооч эрсдэлээ өөрсдөө хариуцна." Bottom, pinned
above a generous margin: a full-width gold primary button "Шинээр эхлэх", a 12dp gap, then
an outlined ink secondary button "Сэргээх". The empty space above the buttons is far larger
than the space between them.
```

---

### S2. 12 үгийн нөөц

**Файл:** `app/lib/onboarding/seed_backup_page.dart` (23–193)
**Зорилго:** шинэ түлхүүрийн 12 үгийг хэрэглэгчид ганц удаа харуулж, түүнийг цаасан дээр бичиж авахад хүргэх — энэ 12 үг бол бүртгэлээ сэргээх цорын ганц зам.
**Хаанаас ирнэ:** S1-ээс «Шинээр эхлэх» дарсны дараа, `context.go('/seed', extra: mnemonic)`-оор. `go` учир **стек орлуулагдана**: доор нь ямар ч дэлгэц үлдэхгүй, тиймээс AppBar ч, буцах сум ч байхгүй.

**Агуулга (дээрээс доош):**
1. Гарчиг — `l.seedBackupTitle` «Нөөц үгсээ хадгал», 26sp, зузаан.
2. Улаан хүрээтэй сануулгын блок — `l.seedBackupWarning`.
3. Дугаарласан 12 үгийн сүлжээ — 2 багана, 6 мөр, `sand` карт бүр дээр «1.» гэх дугаар + үг.
4. (Шинэ) хуулах үйлдэл + «дэлгэцийн зураг бүү ав» маягийн micro сануулга.
5. Үндсэн товч — `l.iSavedIt` «Хадгаллаа».

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| Буцах сум | — | — | **Байхгүй** — `go` стекийг орлуулсан, буцах газар алга | — |
| Төхөөрөмжийн буцах товч / ирмэгийн шудрах | — | Систем үйлдэл | `PopScope(canPop: false)` таслаад баталгаажуулах диалог гаргана | Диалог |
| Диалог — үлдэх | «Үлдэх» (`stayAction`) | Диалогийн товч | Дэлгэц дээрээ үлдэнэ (диалогийг гадуур дарж хаасан ч мөн адил) | Энэ дэлгэц |
| Диалог — гарах | «Нүүр хуудас руу» (`backToHomeAction`) | Диалогийн товч | 12 үг мөнхөд алга болно | `go('/home')` |
| Үгийн карт (1–12) | үгс өөрсдөө | Уншигдах карт | Үйлдэлгүй, зөвхөн уншина | — |
| Хуулах | «Хуулах» **(шинэ)** | Текст товч | 12 үгийг түр санах ойд хуулна | Энэ дэлгэц |
| Сануулга | «ДЭЛГЭЦИЙН ЗУРАГ БҮҮ АВ» **(шинэ)** | Micro шошго | Үйлдэлгүй | — |
| Үндсэн товч | «Хадгаллаа» (`iSavedIt`) | Primary button | Онбординг дуусна | `go('/home')` |

**Диалогийн текст:** `leaveSeedBackupTitle` «Нөөц үгсээ хадгалсан уу?» / `leaveSeedBackupMessage` «Энэ 12 үгийг одоо бичиж авахгүй бол дахин харах боломжгүй. Утсаа гээвэл бүртгэлээ бүрмөсөн алдана.»

**Төлөвүүд:**
- **Хэвийн** — 12 үг үргэлж бэлэн (санах ойн `extra`-аас ирнэ), тиймээс ачаалж буй төлөв байхгүй.
- **Алдаа** — `extra` буруу/хоосон бол энэ дэлгэц огт барихгүй, `router.dart` S1 рүү унана (сүүлийн үеийн deep link-ээс хамгаалалт). Дизайны хувьд энд алдааны байрлал хэрэггүй.
- **Баталгаажуулалт** — буцах гэсэн бүх оролдлого дээр (диалог хоёр удаа давхарлахаас `_asking` хамгаална).
- Хоосон/зөвшөөрлийн төлөв байхгүй.

**Онцгой шаардлага:** энэ бол аппын хамгийн эмзэг мөч. Өнгө аяс нухацтай, хэвлэмэл аюулгүйн картын мэдрэмжтэй байх — айлгах биш. Чимэглэл, зураг, emoji, тайвшруулах ногоон өнгө байхгүй; улаан зөвхөн сануулгын блокт.

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

Android mobile app screen — shown exactly once, right after a new key is generated: the
twelve recovery words. There is no app bar and no back arrow anywhere on this screen. Top:
the heading "Нөөц үгсээ хадгал" in heavy ink display type, followed by a 3px solid ink rule
across the full width. Under it a warning block with a 1.5px red #9E3327 border, transparent
fill, a small red warning triangle on the left and red body text: "Энэ 12 үгийг бичиж
хадгал. Утсаа гээвэл зөвхөн эдгээрээр сэргээнэ. Хэнд ч бүү харуул." Middle, filling most of
the screen: the twelve words as a two-column, six-row set of flat #E7DEC9 blocks with 4px
radius, each block wide and short, left-aligned, each carrying a small deep-gold #A67C28
tabular index "1." to "12." followed by its word in bold ink; each block sits over a hard
3px solid ink offset. Directly under the grid, a small ink text button "Хуулах" with a copy
glyph on its left, and one line of micro uppercase ink label with wide letter tracking:
"ДЭЛГЭЦИЙН ЗУРАГ БҮҮ АВ". Bottom: a full-width gold primary button "Хадгаллаа". The tone is
that of a printed safety card — plain, serious, no illustration and no emoji.
```

---

### S3. Түлхүүр сэргээх

**Файл:** `app/lib/onboarding/restore_page.dart` (16–103)
**Зорилго:** буцаж ирсэн хэрэглэгч 12 нөөц үгээ оруулж, хуучин бүртгэлээ утсандаа сэргээнэ.
**Хаанаас ирнэ:** S1-ээс «Сэргээх» товч, `context.push('/restore')`. `push` учир S1 доор нь үлдэж, AppBar-ийн буцах сум автоматаар гарна.

**Агуулга (дээрээс доош):**
1. AppBar — гарчиг `l.restoreIdentity` «Сэргээх», зүүн талд буцах сум.
2. Олон мөрт оролтын талбар (одоо `maxLines: 3`, `autofocus`), hint `l.restoreHint`.
3. (Санал) талбарын доор оруулсан үгсийн тоолуур + үг тус бүрийн жижиг chip.
4. (Алдааны үед) `l.restoreError`.
5. Үндсэн товч `l.restoreIdentity`, ачаалахад спиннер.

**Оролтын UX-ийн шийдэл (кодод байгаа зүйл + санал):**
Кодод одоо **ганц олон мөрт талбар** байгаа — 12 үгийг бүтнээр нь буулгах (paste) загвар. Дизайны санал: **үүнийг хэвээр үлдээх**, учир нь (а) BIP-39 үгс латин англи үгс тул кирилл гарын хэрэглэгч 12 тусдаа талбарт нэг нэгээр шилжиж бичих нь илт хүнд, (б) нууц үг хадгалагчаас/тэмдэглэлээс бүтнээр буулгах нь бодит амьдрал дээрх гол хувилбар. Гэхдээ ганц талбар нь «зөв бичсэн эсэхээ мэдэхгүй» гэсэн эрсдэлтэй тул нэмэлт **зөвхөн харуулах баталгаа**: талбарын доор оруулсан текстийг зайгаар салгаж, «1. word» хэлбэрийн жижиг chip болгон амьдаар харуулна, баруун талд `12 / 12` **(шинэ)** тоолуур. 12 болоогүй бол үндсэн товч идэвхгүй (одоогийн кодод товч үргэлж идэвхтэй харагдаад дарахад юу ч болдоггүй — дизайны хувьд засах ёстой). 12 тусдаа талбар хийхийг **зөвлөхгүй**.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| Буцах сум | «Буцах» (`backAction`, tooltip) | AppBar үйлдэл | Оруулсан текст хаягдана (алдах зүйлгүй тул баталгаажуулалт хэрэггүй) | S1 рүү pop |
| Гарчиг | «Сэргээх» (`restoreIdentity`) | AppBar гарчиг | — | — |
| Оролтын талбар | hint «12 нөөц үгээ хооронд нь зайтай бичнэ үү» (`restoreHint`) | Олон мөрт оролт | Үг тоологдож, chip-үүд шинэчлэгдэнэ | Хэвээрээ |
| Үгийн chip | оруулсан үгс | Зөвхөн харуулах | Үйлдэлгүй | — |
| Тоолуур | «12 / 12» **(шинэ)** | Micro тоо | 12 болоход ink-ээс steppe өнгө рүү шилжинэ | — |
| Үндсэн товч | «Сэргээх» (`restoreIdentity`) | Primary button | Түлхүүрийг сэргээж хадгална | Амжилттай бол `go('/home')` — **стек орлуулагдана** |

**Төлөвүүд:**
- **Ачаалж буй** — `_restoring` үед товч спиннер болж, дахин дарагдахгүй.
- **Алдаа** — BIP-39 шалгалт унавал (үг буруу, checksum таарахгүй) товчны дээр `l.restoreError` «Нөөц үг буруу байна. Дахин шалгаад оруулна уу.» гарна. Оруулсан текст **арилахгүй**, засах боломжтой хэвээр.
- **Хоосон** — талбар хоосон бол товч идэвхгүй харагдана (одоогийн кодод `_restore` дотор чимээгүй буцдаг — дизайн үүнийг ил төлөв болгоно).
- Зөвшөөрлийн төлөв байхгүй.

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

Android mobile app screen — a returning rider pastes a twelve-word recovery phrase to bring
an old key back. Top: a flat app bar on paper with no shadow, a 3px solid ink rule along its
bottom edge, a back arrow on the left inside a 48dp touch target, and the left-aligned bold
ink title "Сэргээх"; nothing on the right. Below it, a large multi-line text area on paper
ground with a 1.5px ink border, 4px radius, about four lines tall, focused so its border is
a 3px gold #C99A3C frame, and placeholder text in muted ink: "12 нөөц үгээ хооронд нь зайтай
бичнэ үү". Immediately under the field, on the left, the words already typed shown as small
flat #E7DEC9 chips with 4px radius, each chip carrying a deep-gold tabular index and the
word in ink; on the right, a large tabular counter reading "12 / 12" in steppe green
#2E6E5E. Below that, one line of red #9E3327 error text: "Нөөц үг буруу байна. Дахин шалгаад
оруулна уу." Bottom: a full-width gold primary button "Сэргээх". Show one dimmed variant of
the same button for the state where fewer than twelve words are entered.
```

---

### S4. Нүүр (хоёр горим)

**Файл:** `app/lib/router.dart` (115–224, `HomePage`) — кодод «Placeholder» гэж бичигдсэн; дизайны хувьд бүрэн шинэ бүтэц санал болгож байна. Тусдаа файл руу гаргах нь зүйтэй.
**Зорилго:** аппын гол зангилаа — хэрэглэгч энд өөрийгөө зорчигч эсвэл жолооч гэдгээ мэдэгдээд, аяллын урсгал руугаа нэг товчоор ордог; апп «амьд» эсэхийг (relay холболт) энд харна.
**Хаанаас ирнэ:** S2-ын «Хадгаллаа» эсвэл гарах диалог, S3-ын амжилттай сэргээлт, эсвэл түлхүүртэй хэрэглэгчийн `/` → `/home` redirect. Бүх зам `go` тул **энэ бол стекийн үндэс: буцах сум байх ёсгүй**, төхөөрөмжийн буцах товч аппаас гарна.

**Агуулга (дээрээс доош) — санал болгож буй шинэ бүтэц:**
1. **App bar** — зүүн талд gold блок дотор ink wordmark `l.appName` «Тахь», баруун талд ганц үйлдэл: тохиргооны дүрс (`l.settingsAction` tooltip). Буцах сумгүй. Доогуур 3px ink зураас.
2. **Горим солих блок** — бүтэн өргөн, 1.5px ink хүрээтэй хоёр нүд: «Зорчигч» / «Жолооч». Сонгогдсон нүд бүтэн gold дүүргэлт + ink шошго; сонгогдоогүй нь цаас + ink. Өндөр 56dp. Энэ бол дэлгэцийн хамгийн том шийдвэр, тиймээс хамгийн дээр.
3. **Section rule** — 3px ink зураас, зүүн үзүүрт нь micro ТОМ ҮСЭГТ шошго «ТӨЛӨВ» **(шинэ)**.
4. **Холболтын мөр** — status pill: холбогдсон бол steppe дүүргэлт + цагаан текст `l.connected` «Холбогдлоо», хүлээж байгаа бол sand дүүргэлт + ink текст `l.connecting` «Холбогдож байна…». Pill-ийн баруун талд холбогдсон relay-ийн тоо том tabular тоогоор (кодод `${l.connected} (${pool.connectedUrls.length})` хэлбэрээр байгааг тоо + шошго болгон салгана).
5. **Түлхүүрийн мөр** — `npub…` таслагдсан хэлбэрээр monospace/tabular, зүүн талд micro шошго «МИНИЙ ТҮЛХҮҮР» **(шинэ)**, баруун талд хуулах дүрс **(шинэ)**. Энэ бол хэрэглэгчийн цорын ганц «данс» тул нуухгүй, гэхдээ гол үйлдлээс жин багатай.
6. **Гол үйлдлийн блок** — сонгосон горимоос хамаарч бүтэн өргөн gold primary button:
   - Зорчигч: `l.startAsPassengerAction` «Дуудлага өгөх».
   - Жолооч: `l.startAsDriverAction` «Дуудлага сонсох».
7. **Жолооч горимд нэмэлт** — түүний доор secondary button `l.startAsMeterAction` «Таксиметр». (Зорчигч горимд энэ блок огт байхгүй — тор жигд биш байх нь санаатай.)

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| Буцах сум | — | — | **Байхгүй** — стекийн үндэс | — |
| Wordmark | «Тахь» (`appName`) | Брэнд блок | Үйлдэлгүй | — |
| Тохиргооны дүрс | «Тохиргоо» (`settingsAction`, tooltip) | AppBar үйлдэл | Тохиргооны төв нээнэ | `push('/settings')` — буцах сумтай нээгдэнэ |
| Горим — зорчигч | «Зорчигч» (`passengerMode`) | Хоёр нүдтэй сонголт | Доод хэсгийн үйлдлүүд солигдоно, шилжилт хийхгүй | Энэ дэлгэц |
| Горим — жолооч | «Жолооч» (`driverMode`) | Хоёр нүдтэй сонголт | Таксиметрийн товч нэмж гарч ирнэ | Энэ дэлгэц |
| Холболтын pill | «Холбогдлоо» / «Холбогдож байна…» (`connected` / `connecting`) | Status pill | Мэдээлэл, дарагдахгүй | — |
| Түлхүүрийн мөр | `npub1…` + «МИНИЙ ТҮЛХҮҮР» **(шинэ)** | Мөр + хуулах | Түлхүүрийг хуулна | Энэ дэлгэц |
| Үндсэн товч (зорчигч) | «Дуудлага өгөх» (`startAsPassengerAction`) | Primary button | Зорчигчийн аяллын урсгал | `push('/ride/passenger')` — нүүр доор үлдэнэ |
| Үндсэн товч (жолооч) | «Дуудлага сонсох» (`startAsDriverAction`) | Primary button | Жолоочийн inbox | `push('/ride/driver')` |
| Таксиметр (зөвхөн жолооч) | «Таксиметр» (`startAsMeterAction`) | Secondary button | Таксиметр нээнэ | `push('/meter')` |

**Төлөвүүд:**
- **Ачаалж буй (холболт)** — `relayConnectionProvider` шийдэгдээгүй үед pill нь sand дүүргэлттэй, `l.connecting`. Ачаалалт эргэлдэх spinner биш, §7-ийн 3px gold indeterminate зураас.
- **Холбогдсон** — steppe pill + холбогдсон relay-ийн тоо.
- **Холболтын алдаа** — одоогийн кодод алдааг ч `l.connecting` гэж харуулдаг (`error:` салбар нь `loading:`-тай ижил). Дизайны хувьд гурав дахь харагдац хэрэгтэй: улаан хүрээтэй pill + дахин холбогдох үйлдэл — шошго нь **(шинэ)**.
- **Түлхүүр уншиж байгаа / байхгүй** — `currentIdentityProvider` шийдэгдээгүй эсвэл `null` бол түлхүүрийн мөр огт харагдахгүй (одоогийн зан төлөв). Дизайн энэ мөрийг skeleton биш, зүгээр л нуугдсан хэвээр үлдээнэ.
- Хоосон төлөв байхгүй; зөвшөөрлийн төлөв энд байхгүй (байршлын зөвшөөрөл нь аяллын дэлгэцүүд дээр асуугдана).

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

Android mobile app screen — the app's home hub, shown in driver mode. It is the root screen,
so there is no back arrow. Top: a flat app bar on paper with a 3px solid ink rule under it,
carrying on the left a small solid gold block with the ink wordmark "Тахь" inside it, and on
the right a single ink gear icon in a 48dp touch target. Below the bar, a full-width role
switch inside a 1.5px ink frame split into two 56dp cells with no gap: left cell "Зорчигч"
on paper with an ink label, right cell "Жолооч" filled solid gold with a bold ink label,
currently selected. Under it a 3px solid ink section rule with the small uppercase label
"ТӨЛӨВ" sitting on its left end. Then a row: a fully-rounded steppe green #2E6E5E pill with
white uppercase text "ХОЛБОГДЛОО", and to its right a large tabular numeral "4". Below that a
quieter row: the uppercase micro label "МИНИЙ ТҮЛХҮҮР", a truncated monospace key string
"npub1q8f…7m2a" in ink, and a small copy icon at the right end, separated by a 1px ink
hairline at 20% opacity. Large empty gap, then a full-width gold primary button "Дуудлага
сонсох", a 12dp gap, and an outlined ink secondary button "Таксиметр".
```
