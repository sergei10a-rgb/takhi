# 06 — Дуудлага, аюулгүй байдал, тохиргоо, төлөв (S23–S31) · Тахь

> Хэв маяг: `docs/design/screens/00-style.md` (STYLE PREAMBLE) — доорх prompt бүр түүгээр эхэлнэ.
> Эх код (бүгдийг уншиж нотолсон): `app/lib/call/call_screen.dart`, `app/lib/call/call_service.dart`,
> `app/lib/call/fallback_decision.dart`, `app/lib/call/ice_servers.dart`,
> `app/lib/call/voice_note_service.dart`, `app/lib/call/phone_share_settings_page.dart`,
> `app/lib/safety/sos_button.dart`, `app/lib/safety/sos_service.dart`,
> `app/lib/safety/share_link.dart`, `app/lib/safety/share_session.dart`,
> `app/lib/safety/emergency_contact_settings_page.dart`, `app/lib/settings/settings_page.dart`,
> `app/lib/legal/legal_notice_page.dart`, `app/lib/widgets/location_permission_denied_view.dart`,
> `app/lib/widgets/confirm_leave_scope.dart`, `app/lib/router.dart`, `app/lib/l10n/app_mn.arb`,
> `docs/share/index.html`.
>
> **Монгол текст бүр `app_mn.arb`-аас (эсвэл S26-д `index.html`-ээс) яг байгаагаар нь авсан.**
> arb-д байхгүйг «(шинэ)» гэж тэмдэглэв — зохиогоогүй.

---

## 0. Энэ бүлгийн бүтцийн үндэс (кодоос нотлогдсон)

### 0.1 Дуудлагын fallback гинж — үнэндээ 4 биш, **2 шийдвэрийн цэг**

Хэрэглэгчид «яагаад гэнэт утсаар залга гэж байна вэ?» гэдэг ойлгомжтой байхын тулд эхлээд
кодын жинхэнэ бүтцийг тогтоов:

| Шат | Хаана шийдэгддэг | Апп юу хийдэг | Нотолгоо |
|---|---|---|---|
| ① P2P шууд (STUN) | **ICE agent дотор**, апп биш | STUN + helper TURN-ийг **нэг л жагсаалт** болгож дамжуулна | `ice_servers.dart:40-54` |
| ② Нийтийн туслах relay (TURN) | **ICE agent дотор**, апп биш | мөн тэр нэг жагсаалтын нэг мөр | `ice_servers.dart:46-52`, тайлбар 27-39 |
| ③ Утсаар залгах | **апп** — таймаут дараа | `CallStateFallbackPhone(phone)` | `call_service.dart:199-200` |
| ④ Дуут зурвас | **апп** — мөн тэр таймаут дараа | `CallStateFallbackVoiceNote()` | `call_service.dart:201-202` |

`fallback_decision.dart:13` дээр enum-д `offerHelperRelay` **зориудаар байхгүй** — ①/② хоёрын
хооронд шилжих нь RFC 8445-ын ICE-ийн ажил, аппын дахин оролдлого биш. Тэгэхээр аппын
хувьд шийдвэрийн цэг ганц: **«15 секундэд WebRTC холбогдов уу?»**
(`call_service.dart:94` `connectTimeout = 15s`; `_startTimeout` 181-186;
холболт `failed` болбол мөн адил 176-178).

Тэр цэгээс цааш заавал ③ болно гэсэн үг биш:

```
decideFallbackAction(...)   // fallback_decision.dart:20-33
  webrtcConnected || !webrtcTimedOut      → keepTryingWebrtc
  counterpartyPhoneKnown && phoneShareEnabled → offerPhoneCall   (③)
  бусад тохиолдолд                         → offerVoiceMessage  (④)
```

Өөрөөр хэлбэл **③ гарч ирнэ гэдэг нь нөгөө тал өөрөө дугаараа хуваалцахаар тохируулсан**
гэсэн үг (S28), эс бөгөөс шууд ④ руу орно. Дизайны үүрэг: ③-ын дэлгэц дээр «интернэтээр
холбогдож чадсангүй» ба «энэ дугаарыг нөгөө тал өөрөө өгсөн» гэсэн хоёр зүйл ойлгогдох ёстой.
Одоо код зөвхөн нэг мөр харуулдаг: «Апп доторх дуудлага бүтсэнгүй» (`callFailedOfferPhoneLabel`).
Хоёр дахь тайлбар мөр = **(шинэ)**.

### 0.2 SOS-ийн жинхэнэ үйлдэл — апп өөрөө хэзээ ч залгадаггүй

`sos_service.dart` бүхэлдээ хоёр цэвэр функц: `buildEmergencyDialUri` → `tel:102` /
`tel:103` (`ACTION_DIAL`, `ACTION_CALL` **биш**), `buildEmergencySmsUri` → `sms:` +
Plus Code + OSM холбоос бүхий бэлэн бичвэр. `CALL_PHONE`/`SEND_SMS` зөвшөөрөл огт
шаардахгүй (мөр 11-15, 20-23). Тэгэхээр SOS дарахад **утасны өөрийнх нь залгагч/зурвасын
апп нээгдэж, эцсийн товчийг хэрэглэгч өөрөө дарна**. Энэ нь дизайнд шууд нөлөөлнө: SOS
хуудас бол «яаралтай тусламж дуудах» товч биш, «яаралтай дугаарыг залгагчид бэлдэж өгөх»
товч. Одоо UI дээр үүнийг хэлж буй ямар ч мөр байхгүй — **(шинэ)**.

`kFireNumber = '101'` (`sos_service.dart:9`) **тодорхойлогдсон боловч UI-д огт гарахгүй** —
`sos_button.dart` зөвхөн 102/103-ыг л жагсаадаг. Гал командын мөр нэмэх бол шошго нь
**(шинэ)**.

### 0.3 Навигацийн одоогийн байдал (энэ бүлгийн 9 дэлгэц)

| Дэлгэц | Хэрхэн нээгддэг | Буцах сум ил байна уу | Баталгаажуулах диалог |
|---|---|---|---|
| S23 Дуудлага | `Navigator.push(MaterialPageRoute)` — `active_trip_view.dart:367-378`, `call_screen.dart:468-478` | **Үгүй, AppBar байхгүй** — гэхдээ `PopScope(canPop:false)` буцахыг **таслан** `_hangUp()` болгодог (мөр 200-205) | Үгүй — зориуд (кодын тайлбар 196-199: «дуудлага таслахад хоёр дахин бодох хэрэггүй») |
| S24 SOS хуудас | `showModalBottomSheet` (`sos_button.dart:43`) | доод хуудас — чирж хаана | Үгүй |
| S25 Хуваалцах | Route биш — icon дармагц шууд OS-ийн share sheet | — | Үгүй |
| S26 Вэб хуудас | Гадны браузер | браузерын буцах | — |
| S27 Тохиргоо | `context.push('/settings')` (`router.dart:142`) | **Тийм** (go_router-ийн автомат сум) | Үгүй |
| S28 Утасны дугаар | `context.push('/settings/phone-share')` | **Тийм** | Үгүй |
| S29 Яаралтай холбоо | `context.push('/settings/emergency-contact')` — **зөвхөн SOS хуудсаас** | **Тийм** | Үгүй |
| S30 Хууль зүйн | `context.push('/settings/legal')` | **Тийм** | Үгүй |
| S31 Зөвшөөрөл татгалзсан | Route биш, шигтгэсэн харагдац | хостынхоо сумыг өвлөнө | — |

**Зорилтот төлөв (энэ бүлэгт):**
- S27–S30 дээр AppBar-ийн буцах сум **48dp хүрэлтийн талбайтай, ил** байх (одоо go_router
  автоматаар өгдөг ч 3px ink дүрмийн доор нь тодоор зурагдана).
- **S23 бол зориудын үл хамаарах зүйл**: AppBar-гүй, буцах = таслах. Улаан «таслах» товч
  өөрөө буцах үйлдэл болно (`call_screen.dart:188-205` дээр яг ингэж нотлогдсон), тиймээс
  давхар сум нэмэхгүй.
- S28/S29 дээр хадгалаагүй текст буцахад чимээгүй устдаг (одоогийн зан). Энэ нь идэвхтэй
  аялал/ажиллаж буй таксиметр биш тул `ConfirmLeaveScope` **шаардлагагүй** — гэхдээ товч
  идэвхгүй/идэвхтэй болох нь ил байх ёстой (`onPressed: null` хоосон талбар дээр,
  `phone_share_settings_page.dart:99`, `emergency_contact_settings_page.dart:75`).
- **Цоорхой:** `/settings/emergency-contact` зам байгаа мөртлөө `SettingsPage`-д мөр нь
  **алга** — зөвхөн SOS хуудсын «Дугаар нэмэх»-ээр л хүрнэ. S27-д мөр нэмэх санал доор.

---

## S23. Дуудлагын дэлгэц

**Файл:** `app/lib/call/call_screen.dart` (27-247 `CallScreen`; төлөв бүрийн бие 249-397; ирж буй дуудлагын давхарга 419-610)
**Зорилго:** аялалын хоёр тал дугаараа солилцолгүйгээр ярих — интернэт бүтэхгүй бол ойлгомжтойгоор дараагийн шат руу шилжүүлэх.
**Хаанаас ирнэ:** S10 «Идэвхтэй аялал»-ын фазын мөрөн дэх дуудлагын icon-товчоор («Дуудлага хийх», `startCallAction`) — `active_trip_view.dart:367-378`; эсвэл нөгөө тал залгахад `IncomingCallListener`-ийн бүтэн дэлгэцийн давхаргаас «Хариулах» дарахад (`call_screen.dart:461-480`).
**Агуулга:** бүтэн дэлгэц, ink дэвсгэр (`TakhiColors.ink`, мөр 207), AppBar **байхгүй**, SafeArea дотор төвлөрсөн нэг багана. Дотор нь `_uiState`-аас хамаарсан **дөрвөн өөр бие** (switch, мөр 210-241) + дуусгах төлөв.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| Төхөөрөмжийн буцах / зангаа | — (харагдах шошгогүй) | систем | `PopScope` таслаж `_hangUp()` дуудна: hangup DM явуулж, route-аас гарна | S10 руу |
| Таслах товч (бүх төлөвт) | — (зөвхөн `call_end` дүрс, улаан) | icon-товч 48 | `CallService.hangUp` → нөгөө талд hangup DM, дараа нь pop | S10 руу |
| Дуу хаах | — **(шинэ, tooltip алга)** | icon-товч 40 | `setMuted` — микрофоныг хаана/нээнэ, дүрс `mic`↔`mic_off` | Тухайн дэлгэц дээрээ |
| «Утсаар залгах» | «Утсаар залгах» (`callViaPhoneAction`) | дүрстэй дүүргэсэн товч | `tel:` URI-г OS-д дамжуулж, дараа нь pop | Утасны залгагч |
| Дуут зурвас бичих | «Дараад бариад ярь» (`holdToRecordVoiceNoteHint`) | 64px дүрс, урт дарах | дарж эхлэхэд бичиж эхэлнэ, тавихад **автоматаар илгээгээд** pop | S10 руу |
| Ирж буй дуудлага → хариулах | «Хариулах» (`acceptCallAction`) | дүрс+шошготой товч | `CallScreen(isCaller:false)` push | S23-B/C/D |
| Ирж буй дуудлага → татгалзах | «Татгалзах» (`declineCallAction`) | дүрс+шошготой товч | hangup DM явуулж давхаргыг хаана | S10 дээрээ үлдэнэ |

**Төлөвүүд:**
- **A) Залгаж буй / дуугарч буй / холбогдож буй** — `CallStateDialing`/`Ringing`/`Connecting` гурвуулаа **нэг л UI**: «Холбогдож байна…» (`callConnectingLabel`) + ачаалалтын индикатор + таслах товч (мөр 211-216).
- **B) Холбогдсон** — `mm:ss` тоолуур (1 секунд тутам, мөр 116-123), дуу хаах товч, таслах товч.
- **C) Утсаар шилжих** — `CallStateFallbackPhone(phone)`: «Апп доторх дуудлага бүтсэнгүй» (`callFailedOfferPhoneLabel`) + «Утсаар залгах».
- **D) Дуут зурвас** — `CallStateFallbackVoiceNote`: бичих товч + «Дараад бариад ярь». Бичлэг явж байхад дүрс улаан `fiber_manual_record` болно.
- **Алдаа (D дотор):** 10 секундээс урт бол snackbar «10 секундээс богино байх ёстой» (`voiceNoteTooLongHint`) — сүлжээнд огт хүрэлгүй локалд зогсоно (`voice_note_service.dart:38-45`).
- **Дуусах:** `CallStateEnded` → «Дуудлага дууслаа» (`callEndedLabel`) 2 секунд харагдаад автоматаар pop (мөр 125-129).
- **Хоосон/зөвшөөрөл:** энэ дэлгэцэд хамаарахгүй (микрофоны зөвшөөрлийг `CallEngine` өөрөө хүсдэг).

**⚠ Хэв маягийн зөрчлүүд (одоогийн код):** ① ачаалалт `CircularProgressIndicator` — 00-style дүрмээр **3px gold indeterminate bar** байх ёстой. ② тоолуур 28sp — «big-number display» дүрмээр 72–96sp tabular. ③ таслах/хариулах товч улаан нь `Colors.redAccent` — брэндийн `#9E3327` биш. ④ нөгөө талын нэр/машин огт харагдахгүй (аппд pubkey л байдаг) — Prompt-д нэр оруулаагүй.

**Stitch prompt — A) ЗАЛГАЖ БАЙНА:**

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

SCREEN — Android mobile app screen: an outgoing in-app voice call that has not connected
yet. This is the one deliberately inverted surface in the whole product: the entire screen
is solid ink #1C1A16, so here gold #C99A3C is used as TEXT, not as fill.
There is no app bar and no back arrow — the red end-call button is the only way out.
Composition sits high, centred at about 40% of the screen height, top to bottom: a 3px-tall
gold #C99A3C indeterminate progress bar, 140px wide, with square ends and no rounding — not
a spinning circle; then a 24px gap; then one line of gold body text at 18sp reading
"Холбогдож байна…"; then a deliberate 56px gap; then a single circular end-call button
72dp across, filled solid red #9E3327, with a white handset-down glyph centred in it.
Nothing else at all: no avatar, no name, no keypad, no mute control, no elapsed time. The
emptiness is the point — the screen must read as one action waiting on one outcome.
```

**Stitch prompt — B) ХОЛБОГДЛОО:**

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

SCREEN — Android mobile app screen: an in-app voice call that is connected and running.
The whole screen is solid ink #1C1A16; on this dark ground gold #C99A3C is used as text.
Centred vertically: the elapsed call time as enormous gold tabular numerals at 88sp reading
"04:12", with the colon optically balanced and the digits monospaced so they never shift
width as seconds tick. The number never animates, never slides, never rolls.
Below it a 56px gap, then a horizontal row of exactly two controls, 32px apart: on the left
a 64dp circular button with a 1.5px gold border, transparent fill and a gold microphone
glyph — the mute toggle; on the right a 72dp circular button filled solid red #9E3327 with
a white handset-down glyph — end call. The red button is visibly larger than the mute one.
No status pill, no name, no avatar, no speaker or keypad row: the running timer is itself
the proof that the call is live.
```

**Stitch prompt — C) УТСААР ШИЛЖИХ:**

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

SCREEN — Android mobile app screen: the in-app voice call failed to connect, so the app now
offers an ordinary phone call instead. The whole screen is solid ink #1C1A16 and gold
#C99A3C is used as text on it. This screen must explain itself, not just offer a button.
Centred, top to bottom with unequal spacing: a 3px solid gold horizontal rule 64px wide;
20px below it a two-line gold headline at 22sp, tight tracking, centred, reading
"Апп доторх дуудлага бүтсэнгүй"; 12px under that a dimmer secondary caption line in
Mongolian Cyrillic at 15sp with 70% opacity — copy not yet written, so render it as a
neutral two-line placeholder of Cyrillic body text explaining why the app is switching.
Then a 40px gap and one full-width action button inset 32px from both edges: solid gold
#C99A3C fill, 14px radius, 18px vertical padding, a small ink handset glyph and bold ink
#1C1A16 label reading "Утсаар залгах".
At the very bottom, 48px lower and clearly detached, a 64dp circular solid red #9E3327
end-call button with a white glyph. The two buttons must never look like a pair.
```

**Stitch prompt — D) ДУУТ ЗУРВАС:**

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

SCREEN — Android mobile app screen: the call could not connect and no phone number is
available, so the only remaining option is a short push-to-talk voice message, maximum ten
seconds. The whole screen is solid ink #1C1A16 with gold #C99A3C as the text colour.
Centred: one very large press-and-hold target, a 120dp circle with a 3px gold border,
transparent fill and a gold microphone glyph at 56px in the middle. Directly beneath it,
20px down, a gold instruction line at 17sp reading "Дараад бариад ярь".
Show the pressed state in the same frame as a second smaller circle to the side: identical
size but filled solid red #9E3327 with a white filled-dot record glyph, and a thin ten-segment
gold tick scale arcing around it showing recording seconds — the segments fill one by one,
they do not animate smoothly.
At the bottom edge, 56px below everything, a 64dp circular solid red end-call button with a
white handset-down glyph. Nothing else on screen: no waveform art, no send button — releasing
the hold is what sends.
```

**Stitch prompt — E) ИРЖ БУЙ ДУУДЛАГЫН ДАВХАРГА** *(мөн энэ файлд, `_IncomingCallOverlay`)*:

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

SCREEN — Android mobile app screen: a full-screen incoming-call overlay laid over the live
trip map, which stays faintly visible behind it. The overlay is ink #1C1A16 at 92% opacity
covering everything; gold #C99A3C is the text colour on it.
Centred in the upper half: a gold headline at 22sp with tight tracking reading
"Ирж буй дуудлага", and directly above it a 3px solid gold rule 48px wide.
In the lower third, a single row with a deliberately wide 48px gap between two large targets,
each an icon stacked over its own label so the label is tappable too:
on the left a 72dp circular button filled steppe green #2E6E5E with a white handset glyph,
and beneath it a gold label at 15sp reading "Хариулах";
on the right a 72dp circular button filled red #9E3327 with a white handset-down glyph, and
beneath it a gold label at 15sp reading "Татгалзах".
No avatar, no caller name, no ringtone art. The gap between accept and decline must be wide
enough that a startled thumb cannot hit the wrong one.
```

---

## S24. SOS хуудас (доод хуудас)

**Файл:** `app/lib/safety/sos_button.dart` (22-112; товч 28-35, хуудас 37-90) + `app/lib/safety/sos_service.dart`
**Зорилго:** аюулын мөчид гурван хүрэлтээс цөөнөөр цагдаа/түргэн тусламж руу залгах, эсвэл өөрийн сонгосон хүнд байршлаа SMS-ээр бэлдэж илгээх.
**Хаанаас ирнэ:** S10 «Идэвхтэй аялал»-ын фазын мөрөн дэх улаан SOS icon-товчоор (`active_trip_view.dart:626`, tooltip «SOS» = `sosAction`).
**Агуулга:** доод хуудас (`showModalBottomSheet`), `SafeArea` дотор `Column(mainAxisSize: min)` — гарчиг **байхгүй** (одоогийн код), доор нь хамгийн ихдээ гурван `ListTile`:

1. `local_police` дүрс (улаан) + «102 — цагдаа»
2. `local_hospital` дүрс (улаан) + «103 — түргэн тусламж»
3. **Салаа:** дугаар хадгалсан бол `sms` дүрс + «Яаралтай холбоо барих хүнд SMS»; **хадгалаагүй** бол `person_add_alt` дүрс + «Яаралтай үед холбогдох дугаар хадгалагдаагүй байна» + баруун талд «Дугаар нэмэх» текст-товч.

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| SOS нээх (эх товч) | «SOS» (`sosAction`, tooltip) | улаан icon-товч | доод хуудас нээхийн өмнө хадгалсан дугаарыг уншина (`loadPhone`) | Энэ доод хуудас |
| Цагдаа | «102 — цагдаа» (`sosCallPoliceAction`) | жагсаалтын мөр | хуудсыг хааж `tel:102` URI-г OS-д өгнө | Утасны залгагч (**залгах товчийг хэрэглэгч дарна**) |
| Түргэн тусламж | «103 — түргэн тусламж» (`sosCallAmbulanceAction`) | жагсаалтын мөр | хуудсыг хааж `tel:103` URI-г OS-д өгнө | Утасны залгагч |
| Гал команд (101) | — **(шинэ, UI-д огт байхгүй)** | — | `kFireNumber` тодорхойлогдсон ч мөр нэмээгүй | — |
| Байршил SMS | «Яаралтай холбоо барих хүнд SMS» (`sosSendLocationSmsAction`) | жагсаалтын мөр | Plus Code + OSM холбоос бүхий `sms:` бичвэр бэлдэнэ | SMS апп (**илгээхийг хэрэглэгч дарна**) |
| Дугаар алга (сануулга) | «Яаралтай үед холбогдох дугаар хадгалагдаагүй байна» (`sosNoContactHint`) | жагсаалтын мөр (үйлдэлгүй) | зөвхөн мэдээлнэ | — |
| Дугаар нэмэх | «Дугаар нэмэх» (`sosAddContactAction`) | текст-товч | хуудсыг хааж тохиргоо руу шилжинэ | **S29** (`/settings/emergency-contact`) |
| Хаах | — (шошгогүй) | чирэх / гадна дарах | хуудсыг хаана | S10 дээрээ |

**Төлөвүүд:**
- **Ачаалж буй:** `loadPhone()` дуустал доод хуудас **нээгдэхгүй** (`await` дараа нь `showModalBottomSheet`) — өөрөөр хэлбэл товч дарснаас хуудас гарах хүртэл маш богино саатал байна; тусдаа spinner байхгүй.
- **Хоосон:** «дугаар хадгалаагүй» гэдэг нь хоосон төлөв — 3 дахь мөр сануулга+товч болж солигдоно.
- **Алдаа:** `launchUrl` бүтэхгүй бол (залгагч апп байхгүй төхөөрөмж) UI-д **ямар ч хариу байхгүй** — `unawaited` (мөр 54, 62, 110). Зорилтот: алдааны snackbar **(шинэ)**.
- **Байршил тодорхойгүй:** GPS fix ирээгүй бол SMS-ийн бие «Байршил тодорхойгүй байна» (`locationUnavailableHint`) болно, худал координат явуулахгүй (мөр 96-110).
- **Зөвшөөрөл татгалзсан:** SOS өөрөө байршлын зөвшөөрөл шаардахгүй — зөвхөн сүүлийн мэдэгдэж буй fix-ийг ашиглана.

**Дизайны сорилт (энэ бүлгийн гол зүйл):** андуурч дарагдахгүй, гэхдээ эргэлзээгүй. Шийдэл:
эх товчийг бусад icon-оос **20px тусгаарлаж**, зөвхөн **улаан хүрээтэй** (дүүргэсэн улаан
биш — дүүргэсэн улаан нь «одоо дуудлаа» гэсэн худал амлалт төрүүлнэ); доод хуудсан дээр
мөр бүр **≥64dp**, гурав нь босоо жагсаалт (сүлжээ биш) тул алдаж дарах магадлал бага;
эцсийн үйлдлийг апп биш **утасны өөрийн залгагч** гүйцэтгэдгийг мөр бүрийн дор жижиг
тайлбараар хэлнэ (**шинэ** текст).

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

SCREEN — Android mobile app screen: an emergency bottom sheet slid up over a live trip map,
which stays dimmed behind it. Panic-moment UI: unmistakable, but impossible to hit by
accident.
The sheet has 20px top corners on paper #F4F1E9 ground and a 3px solid red #9E3327 rule
across its entire top edge — the only place in the product where the top rule is red instead
of ink. A short ink drag handle sits above it.
Inside, a heading in bold ink at 20sp — copy not yet written, so render a short neutral
Mongolian Cyrillic placeholder headline — then a 1px ink hairline at 20% opacity.
Then three stacked rows, each a full 72dp tall with 20px horizontal padding and separated by
1px ink hairlines: row one has a 40px red police-badge glyph in a red-bordered square block
and bold ink text "102 — цагдаа"; row two the same with a hospital-cross glyph and
"103 — түргэн тусламж"; row three a message glyph and "Яаралтай холбоо барих хүнд SMS".
Each row's label sits over a smaller 13sp ink caption line at 65% opacity — placeholder
Cyrillic text noting the phone's own dialer opens. No red fills, no sirens, no flashing.
```

---

## S25. Аялал хуваалцах (апп доторх хэсэг)

**Файл:** `app/lib/safety/share_session.dart` (13-23), `app/lib/safety/share_link.dart` (11-48); дуудагдах цэг `app/lib/ride/active_trip_view.dart:317-320, 616-620`
**Зорилго:** гэр бүл/найз аяллыг гаднаас, апп суулгалгүйгээр амьдаар харж чадах холбоос үүсгэж хуваалцах.
**Хаанаас ирнэ:** S10 «Идэвхтэй аялал»-ын фазын мөрөн дэх хуваалцах icon-товчоор (tooltip «Аялал хуваалцах» = `shareTripAction`).
**Агуулга (одоогийн бодит байдал):** **Тахийн өөрийн дэлгэц үүсэхгүй.** Товч дарахад
`ShareSession()` шинэ түр түлхүүр үүсгээд (`share_session.dart:15`) `Share.share(url)`-аар
**шууд Android-ын системийн share sheet** нээгддэг (`active_trip_view.dart:317-320`).
Хэрэглэгч ямар холбоос явахыг, дотор нь юу байгааг харахгүй. Холбоосын хэлбэр:
`https://takhi-app.github.io/takhi/share/#k=<түр хувийн түлхүүр>&trip=<id>&relays=<...>`
(`share_link.dart:11-22, 48`). Фрагмент (`#`-ийн ард) нь браузерын дүрмээр **ямар ч сервер
рүү явдаггүй** — үүн дээр энэ бүхэн эзэнгүй ажилладаг үндэс тогтдог.

**Зорилтот төлөв:** системийн sheet нээхийн өмнө **нэг богино баталгаажуулах доод хуудас**
— юу хуваалцаж байгаа, хэдий хугацаанд амьд байх нь ойлгомжтой болгоно. Тайлбар текстүүд
**(шинэ)**; товчны шошго нь одоо байгаа «Аялал хуваалцах» (`shareTripAction`).

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| Хуваалцах icon (S10 дээр) | «Аялал хуваалцах» (`shareTripAction`, tooltip) | icon-товч | түр түлхүүр үүсгэж, тэр агшнаас эхлэн байршлын ping-ийн **хоёр дахь хуулбар** тэр түлхүүр рүү явж эхэлнэ (`active_trip_view.dart:300-314`) | Одоо: OS share sheet. Зорилтот: баталгаажуулах хуудас |
| Холбоосын урьдчилсан харагдац | — **(шинэ)** | monospace текст блок | зөвхөн харуулна, дарвал хуулна | — |
| Үндсэн товч | «Аялал хуваалцах» (`shareTripAction`) | үндсэн товч | системийн share sheet нээнэ | Android share sheet (WhatsApp, зурвас г.м.) |
| Хаах | — | чирэх/гадна дарах | юу ч хийхгүй хаана | S10 дээрээ |

**Төлөвүүд:**
- **Ачаалж буй:** байхгүй — түлхүүр үүсэх нь синхрон.
- **Хоосон:** байхгүй.
- **Алдаа:** байхгүй — `Share.share` `unawaited`.
- **Дахин дарвал:** ижил session дахин ашиглагдана (`_shareSession ??= ...`) — өөрөөр хэлбэл
  **нэг аялалд нэг холбоос**; аялал дуусахад ping зогсдог тул хуучин холбоос өөрөө «идэвхгүй»
  болно (`share_session.dart:8-12`).

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

SCREEN — Android mobile app screen: a confirmation bottom sheet shown before handing a live
trip-tracking link to the system share sheet. The live map stays dimmed behind it.
The sheet has 20px top corners on paper #F4F1E9 ground and a 3px solid ink #1C1A16 rule
across its top edge, with a short ink drag handle above.
Inside, 32px of top padding, then a bold ink headline at 22sp reading "Аялал хуваалцах".
Beneath it, 12px down, two lines of 15sp ink body text at 70% opacity — copy not yet written,
so render neutral Mongolian Cyrillic placeholder text explaining what the recipient will see.
Then a 20px gap and a flat #E7DEC9 surface card with 4px radius, offset 3px down-right by a
solid ink shape behind it, containing a long URL in small ink monospace at 12sp, wrapping to
two lines and ending in an ellipsis, with a small ink copy glyph at its right edge.
Then a 32px gap and one full-width solid gold #C99A3C button, 14px radius, 18px vertical
padding, with a bold ink #1C1A16 centred label reading "Аялал хуваалцах".
```

---

## S26. Аялал хуваалцах ВЭБ хуудас *(апп биш — гадны хүн харах цорын ганц нүүр)*

**Файл:** `docs/share/index.html` (бүтнээр; текстүүд 111-118, логик 120-261)
**Зорилго:** аялал явж буй хүний гэр бүл апп суулгалгүй, бүртгэлгүй, ганц холбоосоор
машины байршлыг амьдаар харах.
**Хаанаас ирнэ:** S25-аас илгээсэн холбоосыг зурвасаар хүлээж авсан хүн браузераар нээнэ.
**Агуулга:** (дээрээс доош, DOM дараалал 111-118)

1. `h1` — «Тахь — Аялал хуваалцах» (одоо **gold текст цайван дэвсгэр дээр** — зөрчил, доор үз)
2. `#status` — «Холбогдож байна…»
3. `#coords` — эхэндээ «—», дараа нь `lat, lon` 5 оронтой (жишээ: `47.91820, 106.91760`)
4. `#map-wrap` — OpenStreetMap `embed.html` iframe, 4:3, gold хүрээтэй
5. `#updated` — «{N} секундийн өмнө шинэчлэгдсэн» (1 секунд тутам шинэчлэгдэнэ)
6. `#inactive` — «Аялал идэвхгүй эсвэл дуусгавар болсон.» (анхандаа нуугдмал)
7. `#download` — «Тахь татах» (gold дүүргэсэн, бүтэн бөөрөнхий 999px)

> ⚠ Эдгээр нь **l10n биш** — HTML дотор шууд бичигдсэн (энэ хуудас Dart-ын мөрүүдийг
> импортлож чадахгүй, файлын толгойн тайлбар 25-26).

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (эх сурвалж) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| Гарчиг | «Тахь — Аялал хуваалцах» (`index.html:111`) | текст | — | — |
| Төлөвийн мөр | «Холбогдож байна…» (мөр 112) | текст | relay-д холбогдмогц хоосорно | — |
| Координат | `lat, lon` (мөр 171) | том тоо | шинэ ping ирэх бүрд шинэчлэгдэнэ | — |
| Газрын зураг | — (iframe) | OSM embed | маркер шинэ байршил руу шилжинэ | OSM (шинэ таб, хэрэв дарвал) |
| Шинэчлэлтийн хугацаа | «{N} секундийн өмнө шинэчлэгдсэн» (мөр 181) | жижиг текст | 1 сек тутам тоолно | — |
| Идэвхгүйн мэдэгдэл | «Аялал идэвхгүй эсвэл дуусгавар болсон.» (мөр 116) | текст | 60 секунд ping ирэхгүй бол гарна | — |
| Татах товч | «Тахь татах» (мөр 118) | холбоос-товч | GitHub-ийн сүүлийн хувилбар руу | `github.com/takhi-app/takhi/releases/latest` |
| Буруу холбоос | «Холбоос буруу байна.» (мөр 193, 202) | текст | fragment задрахгүй/түлхүүр буруу бол | — |

**Төлөвүүд:**
- **Ачаалж буй:** «Холбогдож байна…» + координат «—» + хоосон саарал зураг.
- **Амьд:** координат + зураг + «N секундийн өмнө шинэчлэгдсэн».
- **Идэвхгүй:** 60 секунд (`INACTIVE_TIMEOUT_MS`) ping ирэхгүй бол — эхнээсээ огт ирээгүй ч,
  дундаас тасарсан ч (мөр 164-167, 182-184, 208-210).
- **Алдаа:** зөвхөн «Холбоос буруу байна.» Тайлагдахгүй event чимээгүй хаягдана (мөр 249-252),
  relay нэг нь унтарсан бол бусад нь үргэлжилнэ (мөр 254-256).

**⚠ Хэв маягийн зөрчлүүд (одоогийн HTML):** ① `h1` **gold on paper = 2.28:1** — хориотой,
ink болгоно. ② `--ink: #1A1A1A` (дизайн токен `#1C1A16`), `--bg` харанхуйд `#1A1A1A`
(токен `#211E19`) — зөрүүтэй. ③ Татах товч 999px бөөрөнхий — системийн 14px биш.
④ Хүрээ, өнцөг 8px — картын 4px биш. ⑤ Тоонууд tabular биш, `font-family: system-ui` тул
секунд тоолохдоо өргөн нь хэлбэлзэнэ.

**Stitch prompt** *(энэ ганцад «Android mobile app screen» гэж бичихгүй — **responsive web
page** гэж бичнэ, учир нь энэ бол апп биш вэб):*

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

PAGE — A responsive web page, not an app screen: a single-column live trip-tracking page a
family member opens from a shared link on a phone browser, and which must also hold up at
desktop width by centring a 640px column. No navigation, no menu, no login, no footer links.
Top: a heavy ink #1C1A16 display heading at 28sp reading "Тахь — Аялал хуваалцах", sitting
directly on a 3px solid ink rule that spans the full column width.
Under it, 20px down, a fully round steppe-green #2E6E5E status pill with small white
uppercase Cyrillic text. Then the live coordinates as huge ink tabular numerals at 48px
reading "47.91820, 106.91760" — monospaced figures so the digits never jitter as they update.
Below that a 4:3 map block with a 3px solid ink border and 4px radius, warm paper-toned map
tiles with ink-drawn roads and one solid gold #C99A3C marker disc; the block sits on a hard
3px ink offset. Beneath it a small 13px ink line at 70% opacity reading
"12 секундийн өмнө шинэчлэгдсэн".
At the bottom, separated by 48px, a solid gold #C99A3C link button with 14px radius, 18px
vertical padding and a bold ink label reading "Тахь татах".
```

---

## S27. Тохиргооны нүүр

**Файл:** `app/lib/settings/settings_page.dart` (13-51)
**Зорилго:** төхөөрөмжийн бүх байнгын тохиргоог нэг байрнаас олох.
**Хаанаас ирнэ:** S03 «Нүүр»-ийн AppBar-ийн араа icon (`router.dart:139-143`, tooltip «Тохиргоо» = `settingsAction`).
**Агуулга:** AppBar «Тохиргоо» (`settingsTitle`) + автомат буцах сум; доор нь `ListView` дотор гурван мөр:

1. `badge_outlined` + «Жолоочийн профайл» (`settingsDriverProfileMenuLabel`)
2. `phone_outlined` + «Утасны дугаар» (`settingsPhoneShareMenuLabel`)
3. `gavel_outlined` + «Хууль зүйн сануулга» (`settingsLegalNoticeMenuLabel`)

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | «Буцах» (`backAction`, зорилтот tooltip) | icon-товч | route pop | S03 Нүүр |
| Жолоочийн профайл | «Жолоочийн профайл» (`settingsDriverProfileMenuLabel`) | жагсаалтын мөр | push | `/settings/driver-profile` |
| Утасны дугаар | «Утасны дугаар» (`settingsPhoneShareMenuLabel`) | жагсаалтын мөр | push | **S28** `/settings/phone-share` |
| Хууль зүйн сануулга | «Хууль зүйн сануулга» (`settingsLegalNoticeMenuLabel`) | жагсаалтын мөр | push | **S30** `/settings/legal` |
| *(дутуу)* Яаралтай холбоо | «Яаралтай үед холбогдох дугаар» (`emergencyContactPhoneFieldLabel`) — цэсийн шошго **(шинэ)** | жагсаалтын мөр | зам байгаа ч мөр нь **алга** | **S29** `/settings/emergency-contact` |

**Төлөвүүд:** ачаалалт байхгүй (статик жагсаалт), хоосон төлөв байхгүй, алдаа байхгүй,
зөвшөөрөл хамаарахгүй. Мөр бүр ижил жинтэй — **шатлал огт байхгүй** нь одоогийн сул тал.

**Зорилтот төлөв:** ① дутуу байгаа яаралтай-холбооны мөрийг нэмэх; ② мөрүүдийг утгаар нь
хоёр бүлэг болгож 3px ink зураасаар тусгаарлах — «миний тухай» (профайл, утас, яаралтай
холбоо) ба «энэ аппын тухай» (хууль зүйн сануулга); ③ мөр бүрийн баруун талд chevron.

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

SCREEN — Android mobile app screen: the settings hub, a plain index page and nothing more.
Top: a flat app bar on paper #F4F1E9 ground with no shadow, a 3px solid ink #1C1A16 rule
along its bottom edge, a back arrow on the left inside a 48dp touch target, and a bold
left-aligned ink title at 22sp reading "Тохиргоо". No action on the right.
Below it, 32px of breathing room, then four full-width rows, each 64dp tall with 20px
horizontal padding and separated by 1px ink hairlines at 20% opacity. Each row has a 40px
square ink-outlined glyph block on the left, a bold ink label, and a small ink chevron on the
right. In order: an ID-badge glyph with "Жолоочийн профайл"; a handset glyph with
"Утасны дугаар"; a red-outlined life-ring glyph with "Яаралтай үед холбогдох дугаар".
Then a 3px solid ink section rule spanning the full width with 32px of space above and below
it, separating personal settings from information about the app. After the rule, one final
row: a gavel glyph with "Хууль зүйн сануулга".
No switches, no descriptions under the labels, no avatars, no version number.
```

---

## S28. Утасны дугаар хуваалцах

**Файл:** `app/lib/call/phone_share_settings_page.dart` (20-107)
**Зорилго:** апп доторх дуудлага бүтэхгүй үед нөгөө тал утсаар холбогдож чадахаар өөрийн дугаараа урьдчилан бэлдэх, эсвэл огт хуваалцахгүйг сонгох.
**Хаанаас ирнэ:** S27 Тохиргооны «Утасны дугаар» мөрөөр (`/settings/phone-share`).
**Агуулга:** AppBar «Утасны дугаар» (`phoneShareSettingsTitle`) + буцах сум; body-д 16px padding доторх багана:

1. Текст талбар — `labelText` «Таны утасны дугаар» (`phoneShareOwnPhoneFieldLabel`), `keyboardType: phone`
2. `SwitchListTile` — «Дугаараа тохирсон хүнд илгээх» (`phoneShareEnabledToggleLabel`), **анхдагч утга нь асаалттай** (мөр 37 + тайлбар 32-36)
3. Үндсэн товч — «Хадгалах» (`savePhoneShareSettingsAction`), талбар хоосон бол **идэвхгүй**

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | «Буцах» (`backAction`, зорилтот tooltip) | icon-товч | pop — **бичсэн текст хадгалагдахгүй** | S27 |
| Дугаарын талбар | «Таны утасны дугаар» (`phoneShareOwnPhoneFieldLabel`) | текст оролт (утасны гар) | бичих бүрд товчийн идэвх шинэчлэгдэнэ | — |
| Хуваалцах унтраалга | «Дугаараа тохирсон хүнд илгээх» (`phoneShareEnabledToggleLabel`) | switch | асаалттай бол зөвшөөрсөн жолооч/зорчигчид дугаар очно; унтраалттай бол S23-C **хэзээ ч гарахгүй**, шууд S23-D руу орно | — |
| Хадгалах | «Хадгалах» (`savePhoneShareSettingsAction`) | үндсэн товч | дугаар + унтраалгыг хадгалж, pop | S27 |

**Төлөвүүд:**
- **Ачаалж буй:** хадгалсан утгыг `initState`-д async уншина; уншиж дуустал талбар хоосон,
  унтраалга **асаалттай** (буруу утгаас эргэж харайхгүйн тулд, мөр 32-37). Тусдаа spinner байхгүй.
- **Хоосон:** дугаар хоосон → «Хадгалах» саарал/идэвхгүй (`onPressed: null`, мөр 99).
- **Алдаа:** формат шалгалт **байхгүй** — юуг ч оруулж болно. Зорилтот: буруу форматын
  туслах текст **(шинэ)**.
- **Нууцлалын мэдэгдэл:** дугаар хэнд, хэзээ очих тухай тайлбар **UI-д огт байхгүй** —
  зөвхөн унтраалгын шошго. Зорилтот: талбарын доор нэг мөр **(шинэ)**.

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

SCREEN — Android mobile app screen: a one-field settings page where the user stores their own
phone number and decides whether it may be handed to the person they are riding with.
Top: a flat app bar on paper #F4F1E9 ground with a 3px solid ink #1C1A16 rule along its
bottom edge, a back arrow in a 48dp target on the left, and a bold left-aligned ink title
at 22sp reading "Утасны дугаар".
Body with 20px side padding: 32px down, a text input on paper ground with a 1.5px ink border
and 4px radius, its label "Таны утасны дугаар" sitting on the border line, containing large
ink tabular digits "9911 2233" at 24sp. Under it a 13sp ink helper line at 65% opacity —
copy not yet written, so render neutral Mongolian Cyrillic placeholder text.
Then a 1px ink hairline, and a full-width switch row 64dp tall: bold ink label
"Дугаараа тохирсон хүнд илгээх" on the left and, on the right, a switch shown ON — its track
a solid gold #C99A3C block with 4px radius and its knob a solid ink #1C1A16 square, not a
rounded pill toggle.
Pinned 32px below, a full-width solid gold button with 14px radius, 18px vertical padding and
a bold centred ink label reading "Хадгалах".
```

---

## S29. Яаралтай холбоо барих хүн

**Файл:** `app/lib/safety/emergency_contact_settings_page.dart` (13-83)
**Зорилго:** SOS-ийн SMS хэнд явахыг урьдчилан тодорхойлох — аюул тохиолдох мөчид сонгож зогсох цаг байхгүй.
**Хаанаас ирнэ:** одоогоор **зөвхөн** S24 SOS хуудсын «Дугаар нэмэх» товчоор (`sos_button.dart:81`). Зорилтот: S27-оос ч мөн (дээрх дутуу мөр).
**Агуулга:** AppBar-ийн гарчиг нь **«SOS»** (`sosAction`) — тухайн хуудсын агуулгыг тодорхой хэлдэггүй (мөр 56); body-д 16px padding доторх багана:

1. Текст талбар — «Яаралтай үед холбогдох дугаар» (`emergencyContactPhoneFieldLabel`), утасны гар
2. Үндсэн товч — «Хадгалах» (`saveEmergencyContactAction`), хоосон бол идэвхгүй

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | «Буцах» (`backAction`, зорилтот tooltip) | icon-товч | pop — бичсэн текст хадгалагдахгүй | S24-ийг дуудсан дэлгэц (S10) |
| Дугаарын талбар | «Яаралтай үед холбогдох дугаар» (`emergencyContactPhoneFieldLabel`) | текст оролт | бичих бүрд товчийн идэвх шинэчлэгдэнэ | — |
| Хадгалах | «Хадгалах» (`saveEmergencyContactAction`) | үндсэн товч | дугаарыг хадгалж pop; дараа SOS хуудсанд SMS мөр гарч ирнэ | буцаад SOS дуудсан дэлгэц рүү |

**Төлөвүүд:**
- **Ачаалж буй:** `loadPhone()` async — уншиж дуустал талбар хоосон, spinner байхгүй.
- **Хоосон:** «Хадгалах» идэвхгүй (мөр 75).
- **Алдаа:** формат шалгалт байхгүй.
- **Тайлбарын цоорхой:** энэ дугаарт **юу** явахыг (SOS үед сүүлийн байршил + Plus Code +
  OSM холбоос) хэлсэн мөр UI-д **байхгүй** — `sos_service.dart:30-32`-т бэлэн бичвэр байгаа
  атал хэрэглэгч урьдчилж харахгүй. Зорилтот: жишээ бичвэрийн урьдчилсан харагдац **(шинэ)**.

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

SCREEN — Android mobile app screen: the page where the user stores the one phone number their
emergency SOS message will be addressed to. Calm and plain — this is set up in advance, not
during an emergency, so nothing here is red except one small marker.
Top: a flat app bar on paper #F4F1E9 ground with a 3px solid ink rule along its bottom edge,
a back arrow in a 48dp target on the left, and a bold left-aligned ink title at 22sp reading
"SOS", with a small red #9E3327 square block 8px wide sitting immediately before the title.
Body with 20px side padding: 32px down, a text input on paper ground with a 1.5px ink border
and 4px radius, its label "Яаралтай үед холбогдох дугаар" sitting on the border line, holding
large ink tabular digits "9911 2233" at 24sp.
Below it, 24px down, a flat #E7DEC9 surface card with 4px radius offset 3px down-right by a
solid ink shape, previewing the message that will be sent: small ink monospace text at 12sp
beginning "SOS. Миний сүүлийн байршил:" followed by a Plus Code and a wrapped map link.
Then a 32px gap and a full-width solid gold #C99A3C button, 14px radius, 18px vertical
padding, bold centred ink label reading "Хадгалах".
```

---

## S30. Хуулийн мэдэгдэл

**Файл:** `app/lib/legal/legal_notice_page.dart` (12-35)
**Зорилго:** Тахь эзэнгүй, зохиогч хариуцлага хүлээхгүй, хэрэглэгч өөрөө эрсдэлээ хариуцна гэдгийг ойлгомжтой, шударгаар хэлэх.
**Хаанаас ирнэ:** S27 Тохиргооны «Хууль зүйн сануулга» мөрөөр (`/settings/legal`). Мөн ижил бичвэр **S01 Onboarding**-д анхны нэвтрэлтийн үед шигтгээ хэлбэрээр гарна (файлын тайлбар 6-11).
**Агуулга:** AppBar «Хууль зүйн мэдэгдэл» (`legalNoticeTitle`) + буцах сум; body-д 24px padding доторх **ганц урсгал текст** — `legalNoticeBody`:

> «Тахь бол эзэнгүй P2P платформ. Жолоочийн шалгалт байхгүй. Хэрэглэгч ба жолооч эрсдэлээ өөрсдөө хариуцна.» (мөрийн өндөр 1.5)

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| AppBar буцах сум | «Буцах» (`backAction`, зорилтот tooltip) | icon-товч | pop | S27 |
| Мэдэгдлийн бичвэр | `legalNoticeBody` | урсгал текст (үйлдэлгүй) | зөвхөн уншина | — |

**Төлөвүүд:** ачаалалт/хоосон/алдаа/зөвшөөрөл — **алийг нь ч** хамаарахгүй. Хуудас бүрэн статик.
⚠ Одоо `SingleChildScrollView`-гүй тул текст урт болбол бага дэлгэцэд **халина** — зорилтот
төлөвт гүйлгэдэг болгоно.

**Дизайны зарчим (энэ дэлгэцийн гол):** корпорацийн «Terms & Conditions» шинжгүй байх.
Жижиг саарал 11sp хуулийн үсэг, «Би зөвшөөрч байна» шалгах нүд, гүйлгэж дуусгах шаардлага —
**аль нь ч байхгүй**. Гурван өгүүлбэрийг тус тусад нь, том, ink өнгөөр, хэвлэмэл хуудасны
хэмнэлтэй байрлуулна: энэ бол нуух гэж буй заавар биш, ил хэлж буй үнэн.

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

SCREEN — Android mobile app screen: a plain-spoken legal notice saying this app has no
operator, no company behind it, and no driver vetting. It must read like an honest printed
notice, never like corporate terms and conditions — no tiny grey legal type, no scroll-to-
accept, no checkbox, no "I agree" button.
Top: a flat app bar on paper #F4F1E9 ground with a 3px solid ink #1C1A16 rule along its
bottom edge, a back arrow in a 48dp target on the left, and a bold left-aligned ink title
at 22sp reading "Хууль зүйн мэдэгдэл".
Body with 28px side padding and 40px of top space: the notice set as three separate ink
statements, each on its own, at 20sp with 1.6 line height and 28px of space between them,
left-aligned and never centred: "Тахь бол эзэнгүй P2P платформ." then
"Жолоочийн шалгалт байхгүй." then "Хэрэглэгч ба жолооч эрсдэлээ өөрсдөө хариуцна."
A 3px solid ink rule 64px wide sits above the first statement, and a 1px ink hairline at 20%
opacity closes the block below the last one. Everything is ink on paper — no gold anywhere,
no icons, no illustration, no card.
```

---

## S31. Байршлын зөвшөөрөл татгалзсан

**Файл:** `app/lib/widgets/location_permission_denied_view.dart` (13-37)
**Зорилго:** GPS зөвшөөрөлгүй үед дэлгэц хоосон царайчилж зогсохын оронд шалтгааныг хэлж, дахин оролдох гарц өгөх.
**Хаанаас ирнэ:** route биш — хоёр газарт **шигтгэгдэнэ**: ① S10 «Идэвхтэй аялал»-ын хяналтын алхам (`active_trip_view.dart:491`), ② «Таксиметр»-ийн сул зогсолтын алхам (`taximeter_page.dart:361`). Хоёулаа `locationPermissionCheckProvider` `false` буцаахад солигдоно.
**Агуулга:** хостынхоо `Scaffold`/AppBar-ыг өвлөнө (өөрийн AppBar **байхгүй**); төвлөрсөн, 24px padding доторх хамгийн бага багана:

1. Тайлбар текст, төвд зэрэгцүүлсэн — «Аялал хянахын тулд байршлын зөвшөөрөл шаардлагатай» (`locationPermissionNeededHint`)
2. 16px зай
3. Үндсэн товч — «Зөвшөөрөл өгөх» (`grantLocationPermissionAction`)

**Үйлдэл ба шилжилт:**

| Элемент | Шошго (l10n түлхүүр) | Төрөл | Юу болох | Хаашаа очих |
|---|---|---|---|---|
| Хостын AppBar буцах сум | «Буцах» (`backAction`, зорилтот tooltip) | icon-товч | хостын дүрэм үйлчилнэ — идэвхтэй аялал/тоолуур бол `ConfirmLeaveScope` диалог гарна | Диалогийн хариултаас хамаарна |
| Тайлбар текст | «Аялал хянахын тулд байршлын зөвшөөрөл шаардлагатай» (`locationPermissionNeededHint`) | текст (үйлдэлгүй) | шалтгааныг хэлнэ | — |
| Зөвшөөрөл өгөх | «Зөвшөөрөл өгөх» (`grantLocationPermissionAction`) | үндсэн товч | `onRetry` — хост зөвшөөрлийг **дахин асууна**; олгогдвол хэвийн харагдац руу шилжинэ | S10 хяналт / Таксиметр |

**Төлөвүүд:**
- **Энэ өөрөө нэг төлөв:** «зөвшөөрөл татгалзсан» гэдэг нь хостын хэвийн урсгалын салаа.
- **Дахин татгалзвал:** ижил харагдац хэвээр — хязгааргүй дахин оролдож болно.
- **Систем «дахин бүү асуу» болсон бол:** энэ товч цаашид ямар ч диалог гаргахгүй, хэрэглэгч
  Android-ын тохиргоо руу орох шаардлагатай болно — үүнийг хэлэх мөр **(шинэ)**, зорилтот
  төлөвт хоёрдогч товч болгож нэмэх.
- **Ачаалж буй/хоосон/алдаа:** тусад нь байхгүй.

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

SCREEN — Android mobile app screen: the state a trip or meter screen falls into when location
permission has been refused. It replaces the map entirely, so the screen must not look broken
or empty — it must look like a printed notice deliberately placed where the map would be.
Top: the host app bar stays — flat, on paper #F4F1E9 ground, a 3px solid ink #1C1A16 rule
along its bottom edge, a back arrow in a 48dp target on the left and a bold ink title "Тахь".
The whole area below is paper ground with a faint ink hairline grid at 8% opacity suggesting
the absent map. Centred in it, a flat #E7DEC9 surface card with 4px radius, 28px inner
padding and a hard 3px solid ink offset down-right, occupying about 80% of the width.
Inside the card, top to bottom: a 40px ink outline glyph of a crossed-out location pin; 20px
below it two lines of bold ink text at 18sp, centred, reading
"Аялал хянахын тулд байршлын зөвшөөрөл шаардлагатай"; then 24px down a full-width solid gold
#C99A3C button with 14px radius, 18px vertical padding and a bold centred ink label reading
"Зөвшөөрөл өгөх". Nothing else — no error colour, no red, no illustration of a person.
```

---

## Хавсралт — Энэ бүлэгт илэрсэн l10n цоорхойнууд (бүгд «шинэ»)

| Хаана | Ямар текст дутуу | Яагаад хэрэгтэй |
|---|---|---|
| S23-C | «яагаад утсаар болов» тайлбар мөр | Одоо зөвхөн «бүтсэнгүй» гэдэг; шалтгаан (интернэт) ба эх сурвалж (нөгөө талын тохиргоо) тодорхойгүй |
| S23-B | дуу хаах товчны tooltip | Хараагүй хэрэглэгчид дүрс дангаар ойлгогдохгүй |
| S24 | доод хуудасны гарчиг | Хуудас гарчиггүй нээгддэг |
| S24 | «утасны залгагч нээгдэнэ, илгээхийг та дарна» тайлбар | Аппын жинхэнэ зан үйлийг илэрхийлнэ (`ACTION_DIAL`) |
| S24 | «101 — гал команд» мөр | `kFireNumber` кодод байгаа ч UI-д алга |
| S24 | `launchUrl` бүтэлгүйтсэн үеийн алдаа | Одоо чимээгүй алдана |
| S25 | хуваалцах хуудасны тайлбар | Хэн юу харахыг мэдэхгүйгээр холбоос явуулж байна |
| S27 | «Яаралтай үед холбогдох дугаар» цэсийн мөр | Зам байгаа ч цэсэнд алга |
| S28 | дугаар хэнд/хэзээ очих тайлбар | Нууцлалын шийдвэрийг мэдээлэлгүйгээр гаргаж байна |
| S29 | SMS-ийн урьдчилсан харагдац | Юу явахыг урьдчилан харуулах |
| S31 | «дахин бүү асуу» болсон үеийн заавар | Товч ажиллахаа болиход гарц алга |
