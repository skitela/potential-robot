# EURUSD Integration Contract

## Cel

Ten dokument definiuje punkt styku miedzy:

- dojrzalym mikro-botem `EURUSD`
- nowym projektem `MAKRO_I_MIKRO_BOT`

## Warunek Nadrzedny

Integracja nie moze:

- odebrac `EURUSD` lokalnego runtime,
- odebrac `EURUSD` lokalnego kill-switcha,
- odebrac `EURUSD` lokalnych guardow symbolowych,
- odebrac `EURUSD` lokalnego `black swan`,
- odebrac `EURUSD` lokalnego execution flow,
- sprowadzic `EURUSD` do roli cienkiego klienta `Core`.

## Co Musi Sie Zgadzac

### 1. Kontrakt katalogow runtime

Bot musi miec:

- state path,
- log path,
- run path,
- key path,
- namespace projektu i symbolu.

### 2. Kontrakt runtime state

Bot musi miec mozliwosc:

- zapisac stan,
- odczytac stan,
- wznowic prace po restarcie,
- utrzymac cooldown i lokalne liczniki.

### 3. Kontrakt statusowy

Bot musi publikowac:

- runtime mode,
- cooldown_left_sec,
- incident_pressure,
- heartbeat,
- reason_code.

### 4. Kontrakt kill-switch

Bot musi lokalnie:

- czytac token,
- oceniac TTL,
- przechodzic w halt,
- nie czekac na decyzje z zewnatrz.

### 5. Kontrakt market snapshot

Bot musi lokalnie:

- czytac tick,
- oceniac tick freshness,
- liczyc spread,
- oceniac trade permissions.

### 6. Kontrakt journalingu

Bot musi lokalnie:

- zapisywac decision events,
- zapisywac incident journal,
- zapisywac execution telemetry,
- zapisywac trade transaction journal,
- aktualizowac lokalny feedback po zamknietych dealach.

### 7. Kontrakt execution ownership

Bot musi lokalnie:

- podejmowac finalna decyzje o wyslaniu zlecenia,
- uruchamiac lokalny `OrderCheck` / precheck,
- uruchamiac lokalny `send/retry`,
- interpretowac lokalne execution outcome,
- aktualizowac local execution pressure,
- utrzymywac lokalny przelacznik bezpieczenstwa dla live entries.

Bot powinien tez miec lokalne hooki strategii:

- `Init`
- `Deinit`
- `ManagePosition`

tak aby rozwoj kolejnych par nie wymagal przebudowy eksperta.

## Co Mozna Podmienic Na Core

Mozna podmienic:

- helpery storage,
- helpery heartbeat,
- helpery runtime status,
- helpery runtime control,
- helpery kill-switch,
- helpery rate guard,
- helpery market snapshot,
- helpery journalingu,
- helpery retcode,
- helpery config envelope,
- helpery execution precheck,
- helpery send/retry,
- helpery trade transaction journalingu,
- helpery lokalnego closed-deal tracking.

## Co Ma Pozostac Lokalne

Ma pozostac lokalne:

- scoring wejscia,
- setup selection,
- learning bias,
- black swan policy,
- risk sizing policy,
- execution decision,
- suchy tor `signal -> size -> precheck -> ready-to-send`,
- lokalny warunek wlaczenia live send,
- execution ownership,
- trailing i management pozycji,
- finalna logika veto symbolowego.

## Etap Integracji

### Etap A

Porownanie obecnego `EURUSD` z nowym `Core`.

### Etap B

Podmiana tylko helperow infrastrukturalnych.

### Etap C

Zachowanie lokalnej logiki `EURUSD` bez cięcia w poprzek strategii.

### Etap D

Walidacja:

- compile,
- attach readiness,
- runtime files,
- telemetry files,
- lokalny `kill-switch`,
- brak regresji w autonomy-first model.

## Kryterium PASS

Integracja jest poprawna tylko wtedy, gdy:

- `EURUSD` nadal pozostaje pelnym mikro-botem,
- `Core` pozostaje biblioteka,
- bot nadal moze byc osadzony samodzielnie na serwerze `MT5-only`,
- nie pojawia sie nowy centralny punkt decyzyjny.
