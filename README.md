# Тахь (takhi)

Эзэнгүй, шимтгэлгүй, нээлттэй эхийн такси-учралын апп — Nostr дээр
суурилсан. Жолооч, зорчигч хоёр шууд учирч, өөрсдөө үнээ тохирч,
өөрсдөө төлбөрөө шийддэг. Голд нь хэн ч байхгүй.

## Баримт бичгүүд

- [`docs/superpowers/specs/2026-07-21-takhi-design.md`](docs/superpowers/specs/2026-07-21-takhi-design.md) — бүрэн дизайны спек
- [`PROTOCOL.md`](PROTOCOL.md) — протоколын лавлагаа (kind, event схем)
- [`FORKING.md`](FORKING.md) — өөр хот/улсад асаах заавар
- [`HELPER.md`](HELPER.md) — туслагч зангилаа (blind TURN relay) асаах заавар
- [`brand/BRAND.md`](brand/BRAND.md) — брэнд систем
- [`LICENSE`](LICENSE) — AGPL-3.0-or-later

## Бүтэц

```
takhi/
├── packages/takhi_protocol/   # цэвэр Dart протокол (UI-гүй, сервергүй)
└── app/                       # Flutter апп "Тахь"
```

## Ажиллуулах

```bash
cd app
flutter pub get
flutter run
```

## Лиценз

AGPL-3.0-or-later. CLA байхгүй. Нийтийн өмч хэвээр үлдэнэ.
