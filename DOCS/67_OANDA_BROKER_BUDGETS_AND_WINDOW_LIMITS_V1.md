# 67. OANDA Broker Budgets And Window Limits V1

## Cel

Wyciagnac ze starego `OANDA_MT5_SYSTEM` to, co bylo jednym z czterech glownych filarow:
- dyscypline wzgledem brokera i platformy,
- limity `PRICE / SYS / ORDER`,
- oraz mechanizm przechodzenia niewykorzystanego budzetu miedzy grupami i oknami.

## Najwazniejszy wniosek od razu

To **nie byl prosty system sztywnych limitow "na okno"**.

To byl system:
- budzetow dobowych,
- udzialow per grupa,
- stopniowego odblokowywania tych udzialow wraz z postepem okna,
- oraz mozliwosci pozyczania niewykorzystanego budzetu z innych grup.

Czyli dokladnie:
- jesli jedna grupa nie wykorzysta swojego budzetu,
- kolejna moze na tym skorzystac,
- ale nie bez ograniczen i nie od razu w 100%.

## 1. Twarde limity z kontraktu i konfiguracji

### Limity z kontraktu audytowego

W `README/AUDIT_CONTRACT_V.txt` system trzymal jako jawne granice:

- `PRICE`
  - warning: `1000 / day`
  - cut-off: `5000 / day`
- `MARKET ORDERS`
  - `50 / second`
- `POSITIONS + PENDING`
  - `500` jednoczesnie

Dodatkowo licznik dobowy byl pilnowany konserwatywnie:
- rownolegle dla `PL / UTC / NY`
- i obowiazywala najbardziej restrykcyjna wersja

To byl twardy broker/platforma guard.

### Budzety operacyjne systemu

W `CONFIG/strategy.json` stary system mial:

- `price_budget_day = 900`
- `order_budget_day = 700`
- `sys_budget_day = 6500`

To nie byly limity brokera same w sobie, tylko **wewnetrzne limity bezpiecznej pracy systemu**, ustawione znacznie nizej niz absolutne granice z kontraktu.

## 2. Trzy osobne budzety

System rozdzielal:

### PRICE

To bylo wszystko, co dotyczylo poboru cen:
- ticki,
- `copy_rates_*`,
- price-like requests.

### SYS

To byly operacje techniczne i synchronizacyjne:
- account info,
- pozycje,
- reconcile,
- symbol info,
- historia, odswiezanie stanu.

### ORDER

To byla pula na:
- `order_send`,
- czyli realne proby wejsc / zlecen.

To jest bardzo wazne, bo system nie mieszal pobierania danych z samym wysylaniem zlecen.

## 3. Jak dzielono budzet na grupy

W `CONFIG/strategy.json` istnial:
- `group_price_shares`

Konkretnie:
- `FX = 1.0`
- `METAL = 0.9`
- `INDEX = 0.9`
- `CRYPTO = 0.7`

Te liczby byly normalizowane i z nich liczony byl udzial kazdej grupy w puli dobowej.

To samo podejscie bylo potem stosowane dla:
- `PRICE`
- `ORDER`
- `SYS`

czyli grupa nie miala "wlasnego osobnego swiata", tylko swoj udzial w calosci.

## 4. Mechanizm przechodzenia niewykorzystanego limitu

To jest wlasnie sedno tego, o co pytasz.

Bylo to zrobione przez trzy elementy naraz:

### A. Odblokowanie postepem okna

System nie udostepnial grupie calego budzetu od razu na starcie dnia.

Liczone bylo:
- ile okna tej grupy juz minelo,
- jaki procent jej budzetu powinien byc juz "odblokowany",
- i dopiero tyle moglo byc realnie wykorzystane albo pozyczone dalej.

Czyli:
- przed startem okna grupa ma praktycznie `0`,
- w trakcie okna odblokowuje sie stopniowo,
- po zakonczeniu okna odblokowane jest `100%`.

### B. Pozyczanie z innych grup

Jesli inne grupy nie wykorzystaly swojej odblokowanej czesci, system liczyl:
- ile zostalo u nich niewykorzystane,
- i czesc tego mogla byc pozyczona grupie aktywnej.

### C. Limit na samo pozyczanie

To nie bylo nieograniczone.

Konfig:
- `group_borrow_fraction = 0.65`
- `group_borrow_unlock_power = 1.2`

Czyli grupa mogla przejac tylko fragment niewykorzystanej puli innych grup, a nie calosc.

## 5. Co to oznaczalo w praktyce

W praktyce wygladalo to tak:

### Rano

Gdy aktywne bylo `FX_AM`:
- FX mial swoj wlasny odblokowany budzet,
- ale nie mogl od razu spalac calosci dnia,
- bo pacing i unlock ratio pilnowaly postepu sesji.

### Po poludniu

Gdy startowaly metale:
- grupa `METAL` dostawala swoj odblokowany budzet,
- a jesli `FX` nie zuzylo calej swojej odblokowanej puli,
- metale mogly pozyczyc czesc tego zapasu.

### Wieczorem

Gdy aktywne byly `INDEX_US`:
- indeksy mogly korzystac ze swojej puli,
- oraz z niewykorzystanego zapasu z wczesniejszych grup,
- o ile nie blokowalo tego risk window lub inne guardy.

Czyli tak:
- niewykorzystany limit rzeczywiscie przechodzil dalej,
- ale przechodzil jako **kontrolowany transfer**, a nie bezwarunkowe "wszystko dla kolejnego okna".

## 6. Dodatkowe tempowanie w samych oknach

Sam transfer budzetu to nie wszystko.

System mial jeszcze `budget pacing` dla rodzin:

### FX

- `fx_budget_pacing_enabled = true`
- faza 1:
  - progress `0.25`
  - ratio `0.25`
- faza 2:
  - progress `0.6667`
  - ratio `0.7`
- slack `0.05`

### METAL

- `metal_budget_pacing_enabled = true`
- identyczny uklad:
  - `0.25 / 0.25`
  - `0.6667 / 0.7`
  - slack `0.05`

To oznaczalo:
- na wczesnym etapie okna system nie powinien byl wystrzelac zbyt duzej czesci ORDER budget za szybko,
- nawet jesli teoretycznie jeszcze mial zapas.

## 7. Wazny szczegol: to nie tylko PRICE

Ten sam wzorzec dzialal dla:
- `PRICE`
- `ORDER`
- `SYS`

czyli grupa mogla miec:
- `price_borrow`
- `order_borrow`
- `sys_borrow`

To bylo potem emitowane do runtime policy i telemetrii.

## 8. Co bylo blokowane

Poza samym wyczerpaniem budzetu istnial jeszcze warunek:
- `borrow_blocked`

Pozyczanie moglo byc wycinane np. przez:
- piatkowe risk window,
- reopen guard,
- restrykcje grupowe,
- overlap arbitration,
- albo inne guardy risk-state.

Czyli grupa nie zawsze miala prawo siegac po cudzy zapas.

## 9. Godzinowe limity

Byly tez klasyczne limity tempa:

- `max_orders_per_minute = 120`
- `max_orders_per_hour = 1500`

oraz w kontrakcie ryzyka:
- `min_seconds_between_orders = 1.0`
- `max_orders_per_minute = 6`
- `max_orders_per_hour = 120`

Tu trzeba uczciwie rozroznic dwie warstwy:
- jedna byla bardziej systemowo-techniczna / zdolnosciowa,
- druga byla bardziej konserwatywna / risk-operacyjna.

Najwazniejsze dla nas jest to, ze system mial juz dawno:
- rate limit,
- budzet dobowy,
- budzet grupowy,
- pacing w oknie,
- oraz mechanizm pozyczania.

## 10. Co z tego przeniesc do MAKRO_I_MIKRO_BOT

To jest moim zdaniem obowiazkowe:

### A. Trzy osobne budzety

Nowy system tez powinien miec:
- `PRICE`
- `SYS`
- `ORDER`

### B. Udzialy per rodzina

Nie tylko per symbol, ale tez:
- `FX_ASIA`
- `FX_AM`
- `INDEX_EU`
- `METALS`
- `INDEX_US`

### C. Odblokowanie po postepie okna

Czyli grupa nie dostaje calego dziennego budzetu od razu.

### D. Kontrolowane pozyczanie

Jesli poprzednia grupa nie wykorzystala swojego odblokowanego budzetu:
- kolejna moze przejac czesc zapasu
- ale tylko w ograniczonym procencie

### E. Pacing w pierwszej i drugiej fazie okna

To bardzo dobrze pasuje do naszego stylu "pierwsza godzina obserwacji" i "nie panikuj po pierwszych minutach".

## 11. Najuczciwszy wniosek

Tak, dobrze pamietales.

W `OANDA_MT5_SYSTEM` dzialalo to mniej wiecej tak:
- kazda grupa miala swoj dzienny udzial budzetu,
- ten udzial odblokowywal sie stopniowo wraz z postepem jej okna,
- niewykorzystana czesc mogla byc pozyczona przez kolejne grupy,
- ale tylko w kontrolowanym procencie,
- z dodatkowymi guardami i pacingiem.

To jest bardzo dojrzaly model i zdecydowanie wart przeniesienia do nowego systemu jako czwartego filaru obok:
- latencji,
- ochrony kapitalu,
- zysku netto,
- zgodnosci z brokerem.

## Zrodla lokalne

- `C:\OANDA_MT5_SYSTEM\CONFIG\strategy.json`
- `C:\OANDA_MT5_SYSTEM\README\AUDIT_CONTRACT_V.txt`
- `C:\OANDA_MT5_SYSTEM\BIN\safetybot.py`
- `C:\OANDA_MT5_SYSTEM\DOCS\bridge\gh_to_oanda_behavior_contract.md`
