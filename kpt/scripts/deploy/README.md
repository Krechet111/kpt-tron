# Скрипты деплоя KPT TRON Node

Скрипты для деплоя, управления и мониторинга **KPT TRON FullNode** на удалённом
сервере. Начиная с 2026-07-05 нода работает как **systemd-сервис `kpt-tron`**
(раньше запускалась вручную через `nohup`).

## Конфигурация

- **Host**: `186.246.12.181`
- **User**: `bisq`
- **Remote Directory**: `/home/bisq/kpt/kpt-tron`
- **systemd unit**: `kpt-tron.service`

## Предварительные требования

- SSH-доступ к `bisq@186.246.12.181` (по ключу)
- Java 8 (`zulu-8.jdk`) локально — для сборки; Java 8 (`java-8-openjdk-amd64`) на сервере
- `rsync` локально

---

## ⚙️ Первичная установка (один раз, требует root)

systemd-юнит, swap и sudoers-правило ставятся **один раз** через root-скрипт.
Артефакты лежат в этом каталоге и копируются на сервер (в `…/kpt-tron/deploy/`)
любым `deploy-to-server.sh`, либо вручную через `rsync`.

Файлы установки:

| Файл | Назначение |
|------|-----------|
| `kpt-tron.service` | systemd-юнит: heap `-Xms6g -Xmx12g`, graceful SIGTERM (300s на flush), `SuccessExitStatus=143` (SIGTERM-выход = успех), `Restart=on-failure`, `OOMScoreAdjust=-500` |
| `setup-swap.sh` | создаёт swap-файл (4G, `vm.swappiness=10`) |
| `sudoers-kpt-tron` | разрешает `bisq` управлять **только** `kpt-tron` без пароля (нужно скриптам) |
| `kpt-tron-watchdog.{sh,service,timer}` | таймер (каждые 2 мин): рестартит ноду, если высота блока перестала расти при живом процессе (consensus-stall, который `Restart=on-failure` не ловит) |
| `install-root.sh` | ставит всё перечисленное разом (+ включает watchdog-таймер) |

**Запуск на сервере (нужен пароль sudo):**

```bash
sudo bash /home/bisq/kpt/kpt-tron/deploy/install-root.sh
```

Скрипт **намеренно не стартует ноду** — сначала должен быть развёрнут снапшот БД
(см. `crypto/kpt/scripts/tron-grid-api/lite-node/`). После распаковки снапшота:

```bash
sudo systemctl enable kpt-tron    # автостарт при загрузке
sudo systemctl start  kpt-tron    # запустить сейчас
```

> После установки `sudoers-kpt-tron` команды `start/stop/restart/status/enable/disable`
> для `kpt-tron` работают **без пароля** — поэтому скрипты ниже неинтерактивны.

---

## Управляющие скрипты (запускаются локально)

| Скрипт | Что делает |
|--------|-----------|
| `deploy-to-server.sh` | Сборка `FullNode.jar` → синк deploy-артефактов → **graceful stop** сервиса → синк jar+config → **start** → проверка |
| `start-on-server.sh` | `systemctl start kpt-tron` + проверка |
| `stop-on-server.sh` | `systemctl stop kpt-tron` (SIGTERM, ждёт flush до 300s — **безопасно**) |
| `restart-on-server.sh` | `systemctl restart kpt-tron` |
| `check-server.sh` | статус юнита + HTTP API (8091, высота блока) + RAM/Swap + хвост лога |
| `logs-server.sh [full\|tail\|N]` | показать `logs/tron.log` (лог приложения от logback) |
| `remove-from-server.sh` | **деструктивно**: остановить и удалить каталог ноды |

> ⚠️ Никогда не завершайте ноду через `kill -9` / `pkill -9`. Прерванный flush
> RocksDB-checkpoint — вероятная причина инцидента с расхождением состояния
> (см. `crypto/kpt/docs/TRON_NODE_SYNC_INCIDENT_2026-07-05.md`).

## Watchdog высоты блока

`kpt-tron-watchdog.timer` запускает `kpt-tron-watchdog.sh` **каждые 2 минуты** (от root).
Юнит-настройки ловят краши/OOM (`Restart=on-failure`), но **consensus-stall** — когда
процесс жив и API отвечает, а локальная голова блока перестала расти — процесс не завершает,
поэтому systemd его не видит. Watchdog закрывает именно эту дыру:

- проверяет только `active`-сервис (уважает ручной `stop` и не мешает `Restart=on-failure`);
- пропускает окно прогрева (`STARTUP_GRACE=180s`) и cooldown после рестарта (`COOLDOWN=600s`);
- если голова не выросла **3 проверки подряд** (≈6 мин) или API не отвечает — делает
  `systemctl restart kpt-tron` (graceful).

Рестарт JVM лечит только внутрипроцессные проблемы. Если после
**3 рестартов подряд** (`RESTARTS_NO_PROGRESS_MAX`) высота так и не сдвинулась
(например, БД побита жёстким ресетом — «Tapos failed», инцидент 2026-07-10),
watchdog **перестаёт рестартовать** и шлёт алерт в Telegram (креды — тот же
`~/.config/tron-telegram.env`, что у sync-report; повтор каждые 6 ч,
`ALERT_INTERVAL=21600`). Счётчик сбрасывается любым реальным ростом высоты,
ручным `systemctl restart` или перезагрузкой сервера — надзор возобновляется.

```bash
systemctl list-timers kpt-tron-watchdog     # когда следующий запуск
journalctl -u kpt-tron-watchdog -n 50       # что решал watchdog
```
Пороги переопределяются через env в `kpt-tron-watchdog.service` (`STALL_STRIKES_MAX`,
`STARTUP_GRACE`, `COOLDOWN`, `RESTARTS_NO_PROGRESS_MAX`, `ALERT_INTERVAL`).
Логику `.sh` можно менять обычным деплоем (без root) —
`.service` ссылается на скрипт в `deploy/`.

## Логи

- **Логи приложения** (logback): `logs/tron.log` (+ ротация `tron-YYYY-MM-DD.N.log.gz`).
  Смотреть: `./logs-server.sh tail` или `journalctl -u kpt-tron -f` для systemd-вывода.
- **Консоль/старт/uncaught** (stdout+stderr сервиса): `logs/console.log`.
- **systemd/journal**: `journalctl -u kpt-tron`.

## Пример рабочего процесса

```bash
# первичная установка (один раз, на сервере, с паролем sudo)
sudo bash /home/bisq/kpt/kpt-tron/deploy/install-root.sh
# ... развернуть снапшот БД ...
sudo systemctl enable kpt-tron && sudo systemctl start kpt-tron

# повседневно (локально):
./check-server.sh
./restart-on-server.sh
./deploy-to-server.sh    # выкатить новую сборку jar
```
