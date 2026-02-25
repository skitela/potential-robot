# Trade Window Extensions (v1)

Cel: "srodek drogi" miedzy sztywnym routowaniem po oknach a potrzeba ciaglosci obserwacji.

Zasady:
- Nie zmieniamy bazowych `trade_windows`.
- Domyslnie nie otwieramy nowych wejsc poza aktywnym oknem grupy (brak zmiany zachowania).
- Dodatki sa kontrolowane flagami i sa deterministyczne (powtarzalne).

## 1) Prefetch (observation-only)

Prefetch sluzy do:
- wyliczenia shortlisty symboli dla *nastepnego* okna zanim sie zacznie,
- (opcjonalnie) rozgrzania wskaznikow tylko z lokalnego store (bez fetchy do MT5).

Konfiguracja:
- `trade_window_prefetch_enabled` (bool)
- `trade_window_prefetch_lead_min` (int) – ile minut przed startem nastepnego okna uruchomic prefetch
- `trade_window_prefetch_max_symbols` (int) – max symboli w shortlist
- `trade_window_prefetch_warm_store_indicators` (bool) – best-effort: policz M5 wskazniki ze snapshot/store; jesli brak store lub za malo danych -> skip

Telemetria (log):
- `WINDOW_PREFETCH ...`
  - `active_window`, `active_group`
  - `next_window`, `next_group`
  - `t_minus_min`
  - `selected` (CSV symboli)
  - `warm_store` (0/1)

## 2) Carryover (grace po przelaczeniu okna)

Carryover sluzy do:
- krotkiego okresu "lagodnego" po przelaczeniu okna (np. 3 minuty),
- moze byc tylko obserwacyjny (domyslnie) albo dopuscic limitowane wejscia z poprzedniej grupy (opcjonalnie).

Konfiguracja:
- `trade_window_carryover_enabled` (bool)
- `trade_window_carryover_minutes` (int)
- `trade_window_carryover_max_symbols` (int) – shortlist z poprzedniej grupy
- `trade_window_carryover_trade_enabled` (bool) – jesli `false` to tylko log/telemetria
- `trade_window_carryover_groups` (list[str]) – pusta lista => wszystkie grupy; w innym razie tylko wskazane

Telemetria (log):
- `WINDOW_CARRYOVER ...`
  - `window`, `group`
  - `prev_window`, `prev_group`
  - `age_min`
  - `trade` (0/1)
  - `symbols` (CSV symboli)

## 3) FX Rotation (deterministyczne buckety)

Cel: gdy liczba symboli FX przekracza cap skanowania, ograniczyc obciazenie i rotowac subset w sposob deterministyczny.

Konfiguracja:
- `trade_window_fx_rotation_enabled` (bool)
- `trade_window_fx_rotation_bucket_size` (int) – rozmiar bucketu (np. 4)
- `trade_window_fx_rotation_period_sec` (int) – co ile sekund zmieniac bucket
- `trade_window_fx_rotation_only_when_over_capacity` (bool)
  - jesli `true`: rotacja wlacza sie tylko gdy `len(FX_symbols) > cap_scan`

Telemetria (log):
- `FX_ROTATION ...`
  - `window`
  - `bucket` (k/buckets)
  - `period_sec`, `bucket_size`
  - `cap`, `total`
  - `symbols` (CSV bucketu)

## Rollout (bezpieczne etapy)

1. Wlacz `trade_window_prefetch_enabled` (observation-only) i obserwuj logi.
2. (Opcjonalnie) wlacz `trade_window_prefetch_warm_store_indicators` jesli store ZMQ jest stabilny.
3. Wlacz `trade_window_fx_rotation_enabled` z `only_when_over_capacity=true` (brak zmiany zachowania dopoki FX <= cap).
4. Carryover w trybie `trade_window_carryover_trade_enabled=false` (telemetria).
5. Dopiero po weryfikacji telemetrii: rozwa z wlaczenie `trade_window_carryover_trade_enabled=true` (maly `max_symbols`, krotkie `minutes`).

