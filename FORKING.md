# Тахь-г өөр хотод/улсад асаах — FORKING.md

Энэ протокол хот-агностик (спек §11): УБ ямар ч тусгай эрх эдэлдэггүй,
кодонд hardcode-логдоогүй.

1. **Fork хий.** GitHub дээр "Fork", эсвэл `git clone` + шинэ origin.
2. **Хотын төв солих.** `app/lib/config/city_config.dart`-ийн
   `defaultCityConfig`-г өөрийн хотын координатаар солино уу.
3. **Брэнд солих (сонголттой).** `brand/` доторх лого/өнгө, `app/lib/
   theme/takhi_theme.dart`-ийн `TakhiColors`, `applicationId`
   (`app/android/app/build.gradle.kts`) өөрийн нэрээр.
4. **Relay жагсаалт шалга.** `app/lib/nostr/relay_pool_provider.dart`-ийн
   `defaultRelayUrls` таны бүс нутагт хүрдэг эсэхийг шалгаад шаардлагатай
   бол өөрчил.
5. **Аялал-хуваалцах хуудас.** `docs/share/index.html`-г GitHub Pages-ээр
   ("Settings → Pages → Deploy from /docs")  нийтэл, `app/lib/safety/
   share_link.dart`-ийн `kShareBaseUrl`-г шинэ URL-аараа солино уу.
6. **APK build.** `docs/superpowers/plans/2026-07-22-takhi-calling-safety-ship.md`-ийн
   Task 10-ийн build алхмуудыг дага (өөрийн release keystore үүсгэнэ).
7. Ингээд та зохиогчоос **бүрэн хараат бус**, протоколын хувьд бүрэн
   нийцтэй, өөрийн хот/улсад ажилладаг Тахь-ийн хувилбартай боллоо.
   AGPL-3.0 нь зөвхөн танай өөрчлөлт нээлттэй хэвээр байхыг шаардана —
   бусад бүх зүйл чөлөөтэй.
