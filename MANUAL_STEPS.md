# MANUAL_STEPS — что нужно сделать тебе

Эти шаги нельзя выполнить без твоего аккаунта Roblox и без Studio на твоём Mac.
Названия кнопок Studio и Creator Hub даны по-английски, как в интерфейсе. Roblox иногда
переименовывает пункты меню; если что-то не совпадает, ищи ближайший по смыслу пункт
в левой навигации Creator Hub.

---

## 1. Инструменты на Mac (один раз)

1. **Git.** Открой Terminal и выполни `git --version`. Если macOS предложит установить
   Command Line Tools, соглашайся (или запусти `xcode-select --install`).
2. **Rokit** (менеджер инструментов Roblox):
   ```bash
   curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
   ```
   Закрой и снова открой Terminal.
3. **Инструменты проекта** (Rojo, StyLua, Selene, Lune, Wally с версиями из `rokit.toml`):
   ```bash
   cd ~/Desktop/Rblx_game
   rokit install
   ```
   Rokit может спросить, доверяешь ли ты каждому инструменту. Отвечай «да».
   Если какая-то версия не найдётся, выполни `rokit add rojo-rbx/rojo` (или нужный инструмент):
   так поставится последняя версия.
4. **Плагин Rojo для Studio.** Закрой Studio и выполни `rojo plugin install`.

## 2. История git

История всех этапов уже лежит в папке `.git` проекта: `git log` покажет коммиты
этапов 0–8. Если папки `.git` по какой-то причине нет, восстанови её из файла
`skyheart-ranch.bundle`:
```bash
cd ~/Desktop/Rblx_game
bash scripts/restore-git-history.sh
```
Файл `.bundle` после этого можно удалить (он в `.gitignore`).

## 3. Проверить код без Studio (по желанию)

```bash
lune run tests/lune/run.luau      # 105 юнит-тестов + проверка компиляции всех файлов
lune run tests/lune/smoke.luau    # сборка мира, визуалов и всех панелей UI (71 проверка)
lune run tests/lune/audit.luau    # аудит сетевого слоя
stylua --check src tests
selene src tests/specs
```

## 4. Создать place и experience, подключить проект

1. Открой Roblox Studio и войди в аккаунт.
2. **New → Baseplate**.
3. В Explorer **удали `Baseplate` и `SpawnLocation`** внутри Workspace: мир игра строит
   сама, а стандартный пол наложится на наш.
4. **File → Publish to Roblox As…** → **Create new experience**, название
   «Skyheart Ranch» (позже можно поменять). Опубликуй.
5. В Terminal:
   ```bash
   cd ~/Desktop/Rblx_game
   rojo serve
   ```
6. В Studio: вкладка **Plugins → Rojo → Connect** (адрес по умолчанию `localhost:34872`).
   Код появится в ReplicatedStorage / ServerScriptService / StarterPlayerScripts.
7. **File → Save to Roblox** (или Publish), чтобы place сохранился с кодом.
   Код и дальше правится в папке, а Rojo синхронизирует его в Studio, пока запущен `rojo serve`.

## 5. Включить DataStore в Studio

**Home → Game Settings → Security → Enable Studio Access to API Services → ON → Save.**

Без этого игра в Studio работает на временном хранилище в памяти (в Output будет
предупреждение `USING IN-MEMORY MOCK DATASTORE`), прогресс не сохраняется, а лидерборды
выключены. Это нормально для быстрых тестов, но DataStore нужно проверить и с включённым API.

## 6. Тесты TestEZ внутри Studio (по желанию)

```bash
wally install                   # скачает TestEZ в DevPackages/
rojo serve test.project.json
```
Подключись плагином и нажми **Play**: результаты тестов появятся в Output.

## 7. Геймпассы и Developer Products

Сначала игра должна быть опубликована (шаг 4).

**Геймпассы** (Creator Hub → **Creations** → твоя игра → **Monetization → Passes**):
1. **Create pass** → иконка 512×512 → имя и описание → категория → **Create pass**.
2. Открой созданный пасс и включи продажу с ценой (страница пасса → раздел продаж,
   переключатель «Item for Sale» + цена). Если интерфейс отличается, ищи поле цены на
   странице пасса.
3. ID: в списке Passes наведи на иконку → **⋯ → Copy Asset ID**.

**Developer Products** (**Monetization → Developer Products**):
1. **Create developer product** → иконка → имя, описание → категория → цена → **Save Changes**.
2. ID: **⋯ → Copy Asset ID**.

Создай вот это (цены — мои рекомендации, выбирай сам):

| key в конфиге | Тип | Название | Рекомендуемая цена |
|---|---|---|---|
| DoubleCoins | Pass | Double Coins | 299 R$ |
| ExtraNestSlots | Pass | Extra Nest Beds | 199 R$ |
| BigBackpack | Pass | Big Backpack | 99 R$ |
| VIP | Pass | VIP (косметика) | 249 R$ |
| LuckBoost15 | Product | Luck Boost (15 min) | 49 R$ |
| GrowthBoost15 | Product | Growth Boost (15 min) | 39 R$ |
| InstantGrow | Product | Instant Grow | 25 R$ |
| ServerBloom | Product | Server Bloom | 99 R$ |
| SproutKeys3 | Product | 3 Sprout Keys (ключи кейсов) | 49 R$ |
| MoonKeys3 | Product | 3 Moon Keys | 199 R$ |
| StarKey1 | Product | Star Key | 149 R$ |
| CoinsSmall | Product | Pouch of Coins (+2,500) | 29 R$ |
| CoinsMedium | Product | Sack of Coins (+15,000) | 129 R$ |
| CoinsLarge | Product | Chest of Coins (+80,000) | 499 R$ |

Вставь ID в `src/shared/config/Monetization.luau`: замени `id = 0` у соответствующего `key`.
Пока ID равен 0, товар скрыт в магазине и купить его нельзя.
Покупки в Studio тестовые и Robux не списывают.

## 8. Настройки experience в Creator Hub

- **Максимум игроков: 6** (в мире 6 участков). Ищи в настройках place
  (Creations → игра → Places → place → настройки сервера / Server Size или Max Players).
- **Устройства:** включи Phone, Tablet, Computer (и при желании Console).
- **Описание** (пример, на английском, потому что аудитория глобальная):
  > Hatch adorable elemental critters on your floating sky ranch! Plant nests, discover
  > rare mutations, fill the giant Skyheart together with everyone on the server and
  > trade safely with friends. Every rarity is reachable for free, and all odds are shown in game.
- **Жанр:** Simulation (или Casual). **Иконка и минимум 3 скриншота**: см. ASSETS_TO_REPLACE.md.
- **Content rating** (анкета Maturity & Compliance): Creations → игра →
  **Publish settings → Content rating**. Без неё игра недоступна игрокам. Отвечай честно:
  насилия, крови, страшного контента, романтики и чата вне стандартного нет. В пунктах про
  платные случайные предметы отвечай «да»: Luck Boost и Server Bloom влияют на шансы,
  а монеты, которые можно купить, тратятся на гнёзда со случайным результатом.
  Шансы показаны в игре. Ожидаемый рейтинг — **Minimal**. Заполни анкету **целиком**,
  иначе игра не попадёт к младшей аудитории.
- **Доступ:** после проверки в Studio переключи игру в **Public**
  (Creations → игра → настройки доступа / Privacy).

## 9. Ручная проверка в Studio (чек-лист)

Запусти **Play** (одиночно), затем **Test → Clients and Servers → 2 Players**
(для торговли и Cheer), затем **Test → Device** с эмулятором телефона (iPhone, landscape).

1. В Output есть `[Server] Skyheart Ranch started`, красных ошибок нет.
2. Персонаж появляется на своём участке, табличка с ником.
3. Туториал: стрелка ведёт к грядке → «Plant» → Starter Nest растёт 10 с → «Hatch!» →
   Shiny Puffpaw с празднованием → стрелка к площадке → поставить зверька → «Open gift» →
   Nests → Buy (Meadow) → посадить. После этого подсказки исчезают.
4. Монеты растут от зверька в хабитате (+N/min под балансом).
5. Магазин: «View odds» показывает шансы, проценты суммируются примерно в 100%.
6. Продажа в Market, замок 🔒 защищает от продажи.
7. Апгрейды: грядки и хабитаты открываются на участке.
8. Skyheart: шкала растёт от вылуплений, при заполнении Bloom (баннер, бафф в HUD,
   награда Skyheart Nest).
9. Погода: в Command Bar выполни `workspace:SetAttribute("ForceWeather", "blizzard")`.
   Через ~30 с начнётся Blizzard (баннер слева сверху, оттенок).
10. Два игрока: Cheer на чужой растущей грядке (подойди ближе 20 studs).
11. Торговля (оба игрока должны вылупить 10 зверьков, в Studio можно временно снизить
    `unlockAtHatched` в `config/Trade.luau`): запрос → окно → добавить зверьков и монеты →
    Ready у обоих → блокировка 5 с → Confirm у обоих → предметы переехали. Проверь, что
    изменение предложения сбрасывает Ready.
12. Сохранение (с включённым API): заработай монеты → Stop → Play → монеты на месте.
13. Мобильный эмулятор: кнопки не перекрывают джойстик и прыжок, панели помещаются на экран.
14. Покупки (после шага 7): тестовая покупка Luck Boost → в HUD бафф, шансы пересчитаны.

О любых ошибках из Output пиши мне: по тексту ошибки я исправлю.

## 10. Публикация

1. **File → Publish to Roblox** (после последних правок и синка Rojo).
2. Проверь игру через сайт: кнопка Play у experience.
3. Включи Public (шаг 8).
4. Первые дни следи за **Creator Hub → твоя игра → Analytics**: Retention, Funnels
   (Onboarding — шаги туториала), Economy (источники и стоки монет), Monetization.

## 11. Обязанности после запуска

- **Right to Erasure.** Roblox присылает запросы на удаление данных пользователя
  (сообщения в Creator Hub). Нужно удалить ключи: `u_<UserId>` в DataStore `PlayerData_v1`,
  `pending_<UserId>` в `TradeJournal_v1` и записи `<UserId>` в `LB_CoinsEarned_v1`
  и `LB_IndexEntries_v1`. Инструмент: `ROBLOX_API_KEY=... lune run scripts/erase-user <universeId> <userId> --dry-run`
  (сначала dry-run; ключу Open Cloud нужны права на удаление записей DataStore и запись в Ordered DataStore).
- **Админ-инструменты.** Впиши UserId сотрудников в `src/shared/config/Admin.luau`. Команды в чате:
  `/inspect <ник>`, `/trade <id>`, `/grant <ник> <монеты>`. Владелец игры — админ по умолчанию.
  Все действия пишутся в серверный лог (`[Admin]`).
- **Cross-server объявления** о Mythic используют MessagingService; ничего настраивать не нужно.
- **Сезонные события** добавляются в `src/shared/config/Seasons.luau` (даты в UTC unix-времени),
  после этого нужен Publish.
- **Не переименовывай** DataStore в `config/Data.luau`, иначе игроки потеряют прогресс.
  Изменения схемы данных делаются через `server/data/Migrations.luau`.
