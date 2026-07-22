# Туслагч зангилаа (blind TURN relay) асаах — HELPER.md

Спек §6/§7.3-①: хэн ч энэ зангилааг ажиллуулж, Nostr-оор зарлаж болно.
Зохиогч ХЭЗЭЭ Ч энэ зангилааг ажиллуулахгүй.

## 1. coturn суулгах

Жижиг VM (1 vCPU / 512MB хангалттай):

```bash
sudo apt install coturn
```

`/etc/turnserver.conf`:

```
listening-port=3478
realm=takhi-helper
use-auth-secret
static-auth-secret=<өөрийн нууц үг>
```

```bash
sudo systemctl enable --now coturn
```

## 2. Nostr-оор зарлах

`nak` (nostr army knife, https://github.com/fiatjaf/nak) ашиглан:

```bash
nak event -k 30178 \
  --tag d=<өвөрмөц-helper-id> \
  --tag host=<таны IP эсвэл домэйн> \
  --tag port=3478 \
  --tag expiration=$(($(date +%s) + 3600)) \
  --content "<static-auth-secret>" \
  --sec <таны Nostr хувийн түлхүүр> \
  wss://relay.damus.io wss://nos.lol
```

Эсвэл `packages/takhi_protocol`-ийн `buildHelperAnnouncement` функцийг Dart
скриптдээ шууд ашиглаж болно (жишээ: `tool/announce_helper.dart`,
`buildHelperAnnouncement` + `signEvent` + WebSocket publish).

## 3. Дахин зарлах

`expiration` (NIP-40) tag-тай тул зарлал хугацаа дуусахад автоматаар
устана. Cron-оор 30 минут тутам дахин зарлаарай:

```
*/30 * * * * /path/to/announce.sh
```

## 4. Болоо

Ямар ч Тахь клиент (энэ апп, эсвэл өөр хэн нэгний бичсэн бусад клиент)
таны зарлалыг олж, ICE тохиргоондоо автоматаар нэмнэ. Бүртгэл,
зөвшөөрөл шаардахгүй.
