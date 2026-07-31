# 00 — Стилийн суурь · Тахь

> Энэ файл бол **бүх дэлгэцийн Stitch prompt-ын нэгдсэн эх**.
> Дэлгэц бүрийн prompt нь доорх §2-ын STYLE PREAMBLE-ээр **бүтнээр, үг үсэггүй өөрчлөлтгүй** эхэлнэ.
>
> Эх сурвалж: `brand/BRAND.md`, `app/lib/theme/takhi_theme.dart`, `docs/design/UI_SURFACES.md`,
> ECC `web/design-quality.md` (anti-template дүрэм).
>
> **Хэлний дүрэм (дараагийн агентуудад):** хэрэглэгчид харагдах монгол текстийг ЗОХИОХГҮЙ.
> `app/lib/l10n/app_mn.arb`-аас яг байгаа мөрийг авч, l10n түлхүүрийг хамт бичнэ.
> Тухайн текст arb-д байхгүй бол «(шинэ)» гэж тэмдэглэнэ.

---

## 1. Стилийн чиглэл — **«Талын хэвлэмэл» / `steppe-print`**

Warm brutalist + editorial хосолсон тодорхой чиглэл. Дүрслэлийн лавлагаа нь SaaS апп биш:
**хээрийн гарын авлагын хэвлэмэл хуудас, паалантай төмөр хаяг, тасалбарын хэвлэл, тамга.**

Гурван бодит зарчим:

1. **Суурь нь цаас, дэлгэц биш.** Дэвсгэр хэзээ ч цагаан (`#FFFFFF`) биш — дулаан `#F4F1E9`.
   Харанхуйд ч хар (`#000000`) биш — `#211E19`.
2. **Гүн нь сүүдрээс биш, давхцалаас.** Blur, soft shadow, elevation, glass, gradient — **байхгүй**.
   Оронд нь: хавтгай блокууд давхцана, ink зураас (1px нимгэн / 3px бүдүүн) бүтцийг **харуулна**,
   өргөгдсөн гадаргуу доороо **3px хатуу ink шилжилт** (offset) үлдээнэ — хэвлэлийн misregistration шиг.
3. **Gold бол чимэглэл биш, бүтэц.** `#C99A3C` нь жижиг цэг/дүрс биш — **бүтэн талбай дүүргэнэ**,
   тэр талбай дээр ink текст сууна. (Техникийн шалтгаан §3-т: gold нь paper дээр 2.28:1 — текстэнд огт тэнцэхгүй.)

### Яагаад энэ нь Тахийн утгад тохирох вэ

Тахь бол дэлхийн цорын ганц **хэзээ ч гаршуулагдаагүй** адуу — гэрийн амьтны зөөлөн, гөлгөр дүр төрх түүнд байхгүй,
тиймээс UI нь ч зөөлөн бөөрөнхий, гялгар, эелдэг «бүтээгдэхүүн» шиг харагдаж болохгүй: хатуу ирмэг, ил бүтэц,
чамирхалгүй хэвлэлийн мэдрэмж нь брэндийн мөн чанарын шууд орчуулга.
Брэнд өөрөө **эзэнгүй, нийтийн өмч** учир интерфэйс нь компанийн танилцуулга биш, **нийтийн хэрэглээний хэрэгсэл**
байх ёстой — тиймээс ятгах давхарга (marketing banner, upsell, gloss, mascot) огт байхгүй, зөвхөн баримт:
хэдэн төгрөг, хэдэн км, хэдэн минут, хэн жолоодож байна.
Дулаан цаас, шаргал, ink гурав нь монгол талын бодит зүсийг (хатсан өвс, тахийн зүс, сүүдэр) авчирдаг ба
premium-earthy өнгө аяс нь хямд «үнэгүй апп» гэсэн мэдрэмжийг зайлуулна.

### Uber / Bolt / QGO-оос юугаараа ялгарах

| Талбар | Түгээмэл такси-апп | Тахь (`steppe-print`) |
|---|---|---|
| Суурь | Хүйтэн цагаан / цэвэр хар, саарал | Дулаан цаас `#F4F1E9` / дулаан ink `#211E19` |
| Гүн | Зөөлөн сүүдэр, elevation, blur | Хавтгай блок + хатуу 3px offset + ink зураас |
| Радиус | Бүх зүйл ижил 8–12px, бүх зүйл pill | **Санаатай холимог**: товч 14, карт 4, pill бүтэн дугуй |
| Өнгө | 1 accent өнгө маш бага, бусад нь саарал | Gold бүтэн талбай дүүргэнэ, steppe/улаан нь **семантик** |
| Типографи | Нимгэн, жижиг, эелдэг | Өргөн, зузаан гарчиг + **асар том tabular тоо** |
| Газрын зураг | Ханасан бус саарал tile | Дулаан цаасан tile, ink зам, gold маршрут |
| Мэдрэмж | Корпорацийн бүтээгдэхүүн | Хээрийн гарын авлага / паалантай хаяг / нийтийн хэрэгсэл |
| Брэнд | Chrome дотор алга болно | Бүтцийн нэг хэсэг — gold блок, ink зураас нь өөрөө брэнд |

---

## 2. STYLE PREAMBLE

**Дэлгэц бүрийн Stitch prompt-ын эхэнд ЯГ ЭНЭ ТЕКСТИЙГ бүтнээр тавина.** Дараа нь тухайн дэлгэцийн
зорилго → layout → элементүүд → онцгой анхаарах зүйл гэсэн дарааллаар үргэлжилнэ.

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
```

*(124 үг. Хэрэв prompt-ын урт хязгаарлагдвал энэ preamble-ийг богиносгохгүй — дэлгэцийн
тайлбарыг богиносго.)*

---

## 3. Өнгө ба контраст

### Токенууд (`app/lib/theme/takhi_theme.dart`-д бодитоор байгаа)

| Токен | Hex | Үүрэг |
|---|---|---|
| `gold` | `#C99A3C` | Үндсэн дүүргэлт, primary товч, маршрут, брэнд талбай |
| `goldDeep` | `#A67C28` | Gold-ийн pressed төлөв, ирмэг, гүн |
| `ink` | `#1C1A16` | Бүх текст, зураас, бүтэц, gold дээрх текст |
| `steppe` | `#2E6E5E` | Семантик: амьд / баталгаажсан / холбогдсон / OK |
| `paper` | `#F4F1E9` | Цайвар суурь (ground) |
| `sand` | `#E7DEC9` | Өргөгдсөн гадаргуу (card, sheet) — зөвхөн цайван дээр |
| `error` | `#9E3327` | Аюул — зөвхөн цайван суурин дээр |
| `errorDark` | `#E18579` | Аюул — зөвхөн харанхуй суурин дээр |
| dark surface | `#211E19` | Харанхуй ground |

### ⚠️ Хатуу контрастын дүрмүүд (бодит тооцоо)

Эдгээрийг зөрчих нь энэ төслийн хамгийн олон давтагдах алдаа болно — тиймээс тоогоор нь бичив:

| Хослол | Харьцаа | Дүгнэлт |
|---|---|---|
| ink `#1C1A16` дээр paper | **15.4 : 1** | ✅ Үндсэн текстийн хослол |
| ink дээр sand | **13.0 : 1** | ✅ Картан дээрх текст |
| ink дээр gold | **6.8 : 1** | ✅ Gold товч дээрх шошго |
| steppe дээр paper | **5.3 : 1** | ✅ Цайван дээр текст болно |
| **gold дээр paper** | **2.28 : 1** | ❌ **ХОРИОТОЙ.** Gold нь цайван суурин дээр ТЕКСТ болж хэзээ ч болохгүй — зөвхөн дүүргэлт |
| **steppe дээр dark** | **2.77 : 1** | ❌ Харанхуйд steppe-г шууд бүү хэрэглэ (доорх санал үз) |
| gold дээр dark `#211E19` | **6.5 : 1** | ✅ Харанхуйд gold нь ТЕКСТ болж болно |
| paper дээр dark | **14.7 : 1** | ✅ Харанхуйн үндсэн текст |

**Гол асимметр дүрэм:** `gold` нь **цайван дээр дүүргэлт, харанхуй дээр текст**. Хэзээ ч эсрэгээр биш.

### Санал болгож буй шинэ токенууд *(одоо theme-д БАЙХГҮЙ — код бичих агент нэмнэ)*

| Санал | Hex | Шалтгаан |
|---|---|---|
| `steppeLight` | `#4E9E88` | Харанхуйд steppe-г орлоно — dark ground дээр **5.2 : 1** |
| `surfaceDark` | `#2C2822` | Харанхуйн өргөгдсөн гадаргуу (sand-ийн харанхуй хос) — ground-ээс **1.13 : 1** зөөлөн шат |

---

## 4. Типографи — 3 үүрэг

Одоогийн бодит байдал: зөвхөн **NotoSans** bundled (`assets/fonts/`, кирилл бүрэн).
BRAND.md-д «wordmark-ийн жинхэнэ фонт» дутуу гэж тэмдэглэсэн хэвээр.
Тиймээс **гурван үүргийг нэг гэр бүлээр, гэхдээ туйлын контрастаар** гүйцэтгэнэ —
жин, хэмжээ, tracking гурвыг л ялгана. Энэ нь түр биш, ажиллах шийдэл.

| Үүрэг | Гүйцэтгэл | Хэмжээ (заавар) |
|---|---|---|
| **Display / гарчиг** | NotoSans ExtraBold/Black, tracking чангатгасан (−0.01em), богино мөр | 28–40sp |
| **Body / их бие** | NotoSans Regular 400 / Medium 500, line-height 1.45 | 15–17sp |
| **Numeric / тоо** | NotoSans, **tabular figures заавал** (`FontFeature.tabularFigures()`) | 20sp → таксиметрт **72–96sp** |
| **Micro / шошго** | NotoSans SemiBold, ЖИЖИГ ТОМ ҮСЭГ, tracking **+0.06em** | 11–12sp |

**Кирилл дүрэм:** том үсгээр бичсэн кирилл шошго (ЖИШЭЭ) tracking нэмэхгүй бол зуурч уншигдана —
`+0.06em`-ээс бага байж болохгүй. Урт кирилл үг латинаас 15–20% өргөн тул товчны шошго
**хоёр мөр болох магадлалыг үргэлж тооцно** (товч тогтмол өндөртэй биш, min-height-тэй байна).

Хожим display фонт нэмэх бол: Clash Display / Space Grotesk маягийн geometric, өргөн, кирилл бүрэн face.

---

## 5. Зай, радиус, зураас, хүрэлт

**Зайн шат (4px суурьтай, гэхдээ санаатай ЖИГД БУС):**
`4 · 8 · 12 · 20 · 32 · 56`. Хэсэг доторх зай жижиг (8/12), хэсэг хоорондын зай том (32/56).
Бүх талд ижил padding тавихыг **хоригло** — энэ бол «template» гэж танигдах гол шинж.

**Радиус (санаатай холимог — энэ бол гарын үсэг):**

| Элемент | Радиус |
|---|---|
| Primary/secondary/danger товч | **14px** (`primary_button.dart`-д аль хэдийн байгаа) |
| Surface card, list row | **4px** — бараг дөрвөлжин, хэвлэмэл картын мэдрэмж |
| Status pill | бүтэн дугуй (`999px`) |
| Bottom sheet | зөвхөн дээд хоёр өнцөг **20px** |
| Input field | **4px** (картын хэмнэлтэй нийцнэ) |
| Газрын зураг дээрх floating блок | **4px** |

**Зураасын жин:** нимгэн `1px ink @ 20% alpha` (жагсаалтын хуваалт),
бүдүүн `3px ink @ 100%` (хэсэг тусгаарлах, идэвхтэй төлөв, гарчгийн доогуур).
Гурав дахь жин байхгүй.

**Хүрэлтийн талбай:** хамгийн бага **48×48dp**. Таксиметр болон SOS дээр **64dp-ээс багагүй**.
Жолооч жолоо барьж байхдаа хардаг ямар ч элемент 56dp-ээс жижиг байж болохгүй.

---

## 6. Компонентын толь бичиг

Дараагийн агентууд Stitch prompt дотор **яг эдгээр нэр томьёог** ашиглана.
Баруун баганын англи өгүүлбэрийг prompt руу шууд хуулж болно.

| Нэр | Тодорхойлолт (монгол) | Prompt-д бичих англи спек |
|---|---|---|
| **primary button** | Бүтэн өргөн, gold дүүргэлттэй, ink шошготой, 14px радиус, 18px босоо padding — дэлгэц бүрийн ганц гол үйлдэл. | A full-width solid gold #C99A3C button with 14px radius, 18px vertical padding, and centered bold ink #1C1A16 label; the single main action of the screen. |
| **secondary button** | Дүүргэлтгүй, 1.5px ink хүрээтэй, ink шошготой, ижил 14px радиус — гол үйлдлээс жин багатай ч бүрэн харагдана. | An outlined button with a 1.5px ink #1C1A16 border, transparent fill, ink label, and the same 14px radius as the primary button. |
| **danger button** | Улаан `#9E3327` хүрээ ба улаан шошго, дүүргэлтгүй; зөвхөн баталгаажуулах диалог дотор л бүтэн улаан дүүргэлттэй болно. | An outlined button with a #9E3327 red border and red label, filled solid red with white label only inside a confirmation dialog. |
| **surface card** | `sand #E7DEC9` дүүргэлт, 4px радиус, сүүдэргүй, доогуураа 3px хатуу ink offset-тэй өргөгдсөн блок. | A flat #E7DEC9 block with 4px radius, no shadow, offset 3px down-right by a solid ink #1C1A16 shape behind it. |
| **list row** | Бүтэн өргөн мөр, зүүн талд 40px дүрс/аватар, дунд нь гарчиг + туслах мөр, баруун талд тоо буюу chevron; мөр хооронд 1px ink@20% зураас. | A full-width row with a 40px icon block on the left, a bold title with a lighter secondary line beneath it, a right-aligned value or chevron, separated by a 1px ink line at 20% opacity. |
| **input field** | Цаасан дэвсгэр, 1.5px ink хүрээ, 4px радиус, доор нь жижиг туслах текст; фокус дээр хүрээ 3px gold болно. | A text input on paper ground with a 1.5px ink border, 4px radius, small helper text below, and a 3px gold #C99A3C border when focused. |
| **map surface** | Дулаан цаасан өнгөт газрын зураг, ink зам, gold маршрут шугам, зурган дээр хөвөх бүх блок нь 4px радиус + 3px ink offset. | A warm paper-toned map with ink-drawn roads, a thick gold #C99A3C route line, and floating blocks over it using 4px radius and a hard 3px ink offset. |
| **big-number display** | Дэлгэцийн голд, tabular тоогоор, 72–96sp, ink өнгөтэй; дээр нь жижиг ТОМ ҮСЭГТ micro шошго, доор нь нэгж. Хэзээ ч анимацлахгүй. | A huge tabular-figure number, 72–96sp, ink #1C1A16, with a small uppercase micro label above it and the unit below; it never animates. |
| **status pill** | Бүтэн дугуй, жижиг, ТОМ ҮСЭГТ; амьд төлөв = steppe дүүргэлт + цагаан текст, хүлээлт = sand дүүргэлт + ink текст, аюул = улаан хүрээ + улаан текст. | A small fully-rounded pill with an uppercase micro label: steppe green #2E6E5E fill with white text when live, #E7DEC9 fill with ink text when waiting, red outline with red text when at risk. |
| **bottom sheet** | Дээд хоёр өнцөг 20px, дээр нь 3px ink зураас (grab bar биш — бүтцийн зураас), цаасан дэвсгэр, доод хэсэгт primary button. | A sheet with 20px top corners on paper ground, a 3px solid ink rule across the top edge, and a primary button pinned at the bottom. |

**Нэмэлт (нэгдмэл байдлын тулд — навигацийн ажилтай шууд холбоотой):**

| Нэр | Тодорхойлолт (монгол) | Prompt-д бичих англи спек |
|---|---|---|
| **app bar** | Цаасан дэвсгэр, сүүдэргүй, доогуураа 3px ink зураас; зүүн талд буцах сум (48dp хүрэлт), дараа нь зүүн эгнүүлсэн гарчиг; баруун талд хамгийн ихдээ 1 үйлдэл. | A flat app bar on paper ground with no shadow, a 3px solid ink rule along its bottom edge, a back arrow on the left inside a 48dp touch target, a left-aligned bold title, and at most one action on the right. |
| **section rule** | Хэсэг тусгаарлах 3px ink зураас; заримдаа зүүн талдаа ТОМ ҮСЭГТ micro шошготой. | A 3px solid ink divider that separates sections, optionally with a small uppercase label sitting on its left end. |

---

## 7. Хөдөлгөөн (motion)

Одоо аппад хөдөлгөөн огт байхгүй (`UI_SURFACES.md` систем-5). Нэмэхдээ **чимэглэлийн хөдөлгөөн хийхгүй**:

- Micro (товч, pill, чекбокс): **150ms**, `easeOutCubic`.
- Дэлгэц хоорондын шилжилт: **240ms**, зүүн→баруун 12px гулсалт + fade.
- Төлөв солигдох (хүлээж буй → холбогдсон): crossfade + 8px өргөгдөх, зөвхөн pill болон түүний зураас өөрчлөгдөнө.
- **Таксиметрийн тоо огт анимацлахгүй** — odometer/roll эффект хориотой. Жолооч агшин зуур уншина.
- Ачаалалт: эргэлдэх spinner биш, **gold блок зүүнээс баруун тийш дүүрэх 3px зураас** (indeterminate bar).

---

## 8. Харанхуй горим

Автоматаар харанхуй болгохгүй — гэхдээ жолооч шөнө ажилладаг тул **хоёулаа санаатай** байх ёстой.

- Ground `#211E19`, өргөгдсөн гадаргуу `#2C2822` *(шинэ токен санал)*, текст `#F4F1E9`.
- `sand` харанхуйд хэрэглэгдэхгүй.
- `gold` энд **текст болно** (6.5 : 1) — гарчиг, тоо, идэвхтэй төлөвт.
- `steppe` шууд хэрэглэгдэхгүй → `steppeLight #4E9E88` *(шинэ токен санал)*.
- Алдаа: `errorDark #E18579`.
- Ink зураас нь харанхуйд **paper @ 20%** болж хувирна (ink зураас харагдахгүй).

---

## 9. Хориотой зүйлс (anti-template шалгах хуудас)

Дэлгэц бүрийн prompt бичихээс өмнө:

- ❌ Зөөлөн сүүдэр, elevation, blur, glassmorphism, gradient (ганц үл хамаарах: splash дээрх лого).
- ❌ Цагаан `#FFFFFF` эсвэл цэвэр хар `#000000` дэвсгэр.
- ❌ Бүх элемент ижил радиустай, бүх талд ижил padding.
- ❌ Ижил хэмжээтэй картуудын жигд тор (uniform card grid).
- ❌ Gold-ыг жижиг чимэглэлийн цэг/дүрс болгож хэрэглэх; gold-ыг цайван дээр текст болгох.
- ❌ Нимгэн (300/Light) фонт — наранд болон хөдөлгөөнд уншигдахгүй.
- ❌ Marketing banner, upsell, «Урамшуулал!», emoji, mascot, гялгар зураг.
- ❌ Ерөнхий үг агуулсан prompt («clean modern UI», «beautiful design»).

Дэлгэц бүр доорхоос **дор хаяж 4-ийг** биелүүлсэн байна:
хэмжээний контрастаар үүссэн тодорхой шатлал · жигд бус хэмнэлтэй зай ·
давхцал/хатуу offset-ээр үүссэн гүн · тэмдэгтэй типографи ·
семантик өнгө · зориудаар зохиогдсон дарах/фокусын төлөв ·
торыг эвдсэн editorial композиц · хэвлэлийн бүтэц/уур амьсгал ·
урсгалыг тодруулах хөдөлгөөн · дизайн системийн нэг хэсэг болсон дата дүрслэл.
