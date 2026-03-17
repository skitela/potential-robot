# 61. Immutable Capital Risk Contract V1

## Cel

Ten dokument przygotowuje jednolity, nienaruszalny kontrakt ryzyka kapitalu dla `MAKRO_I_MIKRO_BOT`.

To nie jest zwykly parametr strojenia. To jest warstwa ochrony kapitalu, ktorej nie wolno zmieniac:

- agentowi lokalnemu,
- agentowi rodzinnemu,
- koordynatorowi floty,
- ani zadnej adaptacji runtime.

Zmiana tego kontraktu ma byc mozliwa tylko po Twojej swiadomej decyzji i recznym wdrozeniu.

## Dlaczego ten kontrakt jest potrzebny

Obecny system ma juz:

- twarde limity dzienne i sesyjne w profilach symboli,
- adaptacyjny model ryzyka wejscia,
- ograniczenia rodzinne i flotowe,
- agenta strojenia, ktory potrafi sciskac ryzyko.

Ale to jeszcze nie daje jednego, zamrozonego kontraktu kapitalowego tak wyraznego, jak w starym `OANDA_MT5_SYSTEM`.

W praktyce widzielismy juz na `paper`, ze dzien moze skonczyc sie strata rzedu `20%` kapitalu testowego. To jest do zaakceptowania jako material diagnostyczny tylko dlatego, ze to nie bylo `live`. Dla prawdziwego kapitalu to jest nie do przyjecia.

## Co mowia wzorce zewnetrzne

Przeglad zewnetrznych zrodel pokazal kilka wspolnych punktow:

- profesjonalni i aktywni traderzy czesto schodza do `0.25% - 0.50%` ryzyka na trade,
- wielu edukatorow i brokerow traktuje `1%` jako gorna bezpieczniejsza strefe, a nie jako wartosc do codziennego dociskania,
- prop-firmowe `5% max daily loss` to model evaluacyjny, nie wzorzec dla prywatnego kapitalu zyciowego.

## Punkt odniesienia ze starego systemu

Stary `OANDA_MT5_SYSTEM` mial bardzo czytelna filozofie:

- `risk_per_trade_max_pct = 1.2%`
- `daily_loss_soft_pct = 1.5%`
- `daily_loss_hard_pct = 2.5%`
- dodatkowo `max_daily_loss_account = 2.0%`
- oraz `max_daily_loss_per_module = 0.8%`

To nie bylo idealnie identyczne we wszystkich plikach domyslnych, ale w aktywnym configu tworzylo jasny kontrakt ochrony kapitalu.

## Co jest dzis w makro i mikro bocie

Aktualny system ma juz twarde profile:

- `hard_daily_loss_pct = 2.0%`
- `hard_session_loss_pct = 1.0%`

oraz lokalne geny ryzyka symboli, na przyklad dla `EURUSD`:

- `base_risk_pct = 0.35`
- `min_risk_pct = 0.20`
- `max_risk_pct = 0.50`

To sa wartosci uzywane przez lokalny sizing pozycji, a pozniej modulowane przez:

- `adaptive_risk_scale`
- `signal_risk_multiplier`
- `risk_cap`
- polityke rodziny
- polityke floty

To daje elastycznosc, ale bez osobnego kontraktu oznacza tez, ze system jest bardziej zlozony i trudniej od razu zobaczyc, gdzie lezy absolutny sufit ryzyka.

## Decyzja projektowa

Kontrakt kapitalowy ma siedziec wyzej niz:

- lokalne geny symbolu,
- agent strojenia,
- rodzina,
- flota.

To oznacza:

- lokalne strategie nadal zachowuja osobowosc,
- agenci nadal moga obnizac ryzyko,
- ale nie moga go podnosic ponad ten kontrakt.

## Proponowany kontrakt PAPER

### Ryzyko na trade

- `risk_per_trade_base_pct = 0.50%`
- `risk_per_trade_min_pct = 0.20%`
- `risk_per_trade_max_pct = 0.75%`

### Limity strat

- `account_soft_daily_loss_pct = 2.00%`
- `account_hard_daily_loss_pct = 4.00%`
- `account_hard_session_loss_pct = 1.50%`
- `family_hard_daily_loss_pct = 1.20%`
- `symbol_hard_daily_loss_pct = 0.80%`

### Limit ryzyka otwartego

- `max_open_risk_pct = 2.00%`

### Reakcja po wejsciu w soft loss

- `soft_loss_risk_factor = 0.60`

## Proponowany kontrakt LIVE

### Ryzyko na trade

- `risk_per_trade_base_pct = 0.25%`
- `risk_per_trade_min_pct = 0.10%`
- `risk_per_trade_max_pct = 0.50%`

### Limity strat

- `account_soft_daily_loss_pct = 1.00%`
- `account_hard_daily_loss_pct = 1.50%`
- `account_hard_session_loss_pct = 0.75%`
- `family_hard_daily_loss_pct = 0.60%`
- `symbol_hard_daily_loss_pct = 0.40%`

### Limit ryzyka otwartego

- `max_open_risk_pct = 1.25%`

### Reakcja po wejsciu w soft loss

- `soft_loss_risk_factor = 0.50`

## Najwazniejsza roznica PAPER vs LIVE

`paper` ma pozostac wystarczajaco luźny, zeby boty i agent strojenia mogly widziec krew, bledy i brak przewagi.

`live` ma byc wyraznie bardziej zachowawczy. Tam priorytetem nie jest szybkie uczenie sie za wszelka cene, tylko:

- przetrwanie,
- ochrona kapitalu,
- i powolne budowanie zaufania.

## Aktualizacja: rdzen kapitalu i bufor zysku

Kontrakt zostal rozszerzony o dodatkowa zasade dla `live`:

- ryzyko nie liczy sie od calego chwilowego equity,
- tylko od `capital_core_anchor + 0.5 * realized_profit_buffer`.

To oznacza, ze system moze oddychac zyskiem, ale nie dostaje prawa do pelnego rozpędzenia ryzyka 1:1 razem z rachunkiem.

## Co jest nienaruszalne

Agentom i runtime nie wolno zmieniac:

- bazowego ryzyka na trade,
- minimalnego i maksymalnego ryzyka na trade,
- soft i hard daily loss,
- hard session loss,
- limitu dziennej straty rodziny,
- limitu dziennej straty symbolu,
- limitu maksymalnego ryzyka otwartego,
- wspolczynnika redukcji ryzyka po soft loss.

Agenci moga tylko:

- obniżac skuteczne ryzyko,
- zawezac confidence,
- zawezac setupy,
- zamrazac toksyczne klasy,
- przechodzic w `close_only` albo `halt`.

## Co trzeba wdrozyc pozniej w kodzie

## Status po wdrozeniu runtime v1

Na ten moment kontrakt nie jest juz tylko propozycja.

Zostal wdrozony w runtime w nastepujacym zakresie:

- osobna warstwa `paper/live` z immutable wartosciami kontraktu,
- twardy clamp ryzyka przed sizingiem pozycji,
- redukcja ryzyka po wejsciu w `soft daily loss`,
- osobne kotwice strat dla `paper` i `live` na poziomie symbolu,
- twardy `symbol_hard_daily_loss_pct` w guardach wejscia,
- agregacja dziennej straty rodziny i zatrzymanie rodziny po przekroczeniu limitu,
- agregacja dziennej straty floty i zatrzymanie floty po przekroczeniu limitu,
- zablokowanie wzmacniania ryzyka przez mnoznik sygnalu ponad kontrakt,
- wymuszenie stanu `paper/live` w runtime kazdego mikro-bota.

To oznacza, ze lokalny agent, rodzina i flota moga dalej tylko:

- sciskac ryzyko,
- zamrazac zmiany,
- lub zredukowac skuteczna polityke do zera.

Nie moga juz przepchnac wejscia ponad kontrakt kapitalowy.

## Co pozostaje na kolejny etap

Jedna rzecz zostala swiadomie odlozona, zeby nie rozepchac tego wdrozenia ponad bezpieczny zakres:

- pelne egzekwowanie `max_open_risk_pct` w skali calej floty na podstawie juz otwartych pozycji.

To wymaga jeszcze osobnej, bardzo precyzyjnej warstwy zliczania otwartego ryzyka portfela i nie powinno byc robione pospiesznie.

### 1. Osobny kontrakt runtime

Wdrozone jako `MbCapitalRiskContract`, ktory:

- laduje tryb `paper` albo `live`,
- trzyma wartosci immutable,
- udostepnia tylko odczyt do hot-path.

### 2. Osobne kotwice strat dla PAPER i LIVE

Wdrozone.

Dzisiejszy guard dzienny patrzy na realne `equity` z terminala. Dla `paper` to za malo, bo paper strata nie obniża prawdziwego equity konta.

Runtime robi teraz:

- dla `paper` liczyc limity od paperowego equity / paperowego PnL,
- dla `live` liczyc limity od realnego equity konta.

### 3. Clamp ryzyka przed sizingiem

Wdrozone.

### 4. Hierarchia strojenia tylko w dol

Most:

- lokalny,
- rodzinny,
- flotowy

ma moc tylko do sciskania ryzyka i confidence, nigdy do przebicia kontraktu.

To jest wdrozone dla:

- symbolu,
- rodziny,
- floty.

## Relacja do lokalnych genow

Ten kontrakt nie unifikuje symboli do jednej osobowosci.

To nie jest atak na lokalne geny:

- `EURUSD`
- `USDJPY`
- `GBPJPY`
- `GBPAUD`

dalej maja zachowac wlasne modele wejscia, filtry i tempo.

Kontrakt kapitalowy ma tylko powiedziec:

`nawet najlepszy kapitan nie moze ryzykowac wiecej niz pozwala konstytucja statku`

## Plik maszynowy

Kandydat kontraktu zostal zapisany w:

- [capital_risk_contract_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\capital_risk_contract_v1.json)

## Najuczciwszy wniosek

To jest moment, w ktorym system powinien przestac byc tylko sprytny, a zaczac byc tez twardo odpowiedzialny.

Jesli ten kontrakt zostanie pozniej wdrozony do runtime, to agent strojenia nadal bedzie mogl nas prowadzic do przewagi, ale juz nie kosztem tego, ze pojedynczy zly dzien moze zachowywac sie jak powolna katastrofa kapitalowa.
