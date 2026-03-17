# 95_TUNING_EXPERIMENT_MEMORY_AND_ROLLBACK_V1

## Cel

Przesunac lokalnego agenta strojenia z roli samego regulatora parametrow do roli ostroznego eksperymentatora, ktory:

- pamieta, jaka zmiane wdrozyl,
- ocenia skutki tej zmiany na swiezych lekcjach paper,
- potrafi utrzymac skuteczna zmiane,
- potrafi cofnac nieudana zmiane,
- i przez pewien czas nie wraca do tej samej, swiezo obalonej sciezki.

## Co zostalo wdrozone

### 1. Pamiec eksperymentu w polityce lokalnej

Do `MbTuningLocalPolicy` dodano trwały stan eksperymentu:

- `experiment_active`
- `experiment_revision`
- `experiment_review_count`
- `experiment_started_at`
- bazowy stan probki, wygranych, przegranych, papierowych otwarc i `realized_pnl_lifetime`
- kod akcji eksperymentu
- fokus eksperymentu: `setup_type` i `market_regime`
- status eksperymentu
- ostatnio obalona sciezke oraz czas blokady powrotu

### 2. Trwale pliki i logi

Dodano:

- stabilny snapshot polityki: `tuning_policy_stable.csv`
- dziennik eksperymentow: `tuning_experiments.csv`

Agent zapisuje teraz:

- start eksperymentu,
- oczekiwanie na wynik,
- utrzymanie skutecznej zmiany,
- cofniecie nieudanej zmiany.

### 3. Ocena skutku zmiany

Przy aktywnym eksperymencie agent porownuje stan biezacy z baza eksperymentu:

- przyrost probki uczenia,
- przyrost wygranych i przegranych,
- przyrost `paper_open`,
- zmiane `realized_pnl_lifetime`.

Na tej podstawie:

- utrzymuje eksperyment jako `PENDING`,
- zatwierdza go jako `ACCEPTED`,
- albo cofa jako `ROLLED_BACK`.

### 4. Cofniecie i blokada powrotu

Jesli eksperyment pogarsza obraz:

- agent laduje ostatnia stabilna polityke,
- wykonuje `ROLLBACK`,
- zapisuje obalona sciezke,
- ustawia czas `avoid_repeat_until`,
- i nie wraca od razu do tej samej akcji na tym samym fokusie.

To ma zatrzymac zapetlenie typu:

- ta sama strata,
- ta sama odpowiedz,
- ten sam blad jeszcze raz.

### 5. Ciagla praca zamiast ciaglego przestawiania

Agent nadal pracuje stale, ale nie musi stale przestawiac parametrow.

Nowy model jest taki:

- wprowadza zmiane,
- daje jej oddech,
- mierzy skutki,
- dopiero potem decyduje: zostawic czy cofnac.

To jest bezpieczniejsze i blizej dojrzalego strojenia niz nerwowe, czeste przelaczanie polityki.

## Co zostalo potwierdzone

- Kompilacja calej floty przeszla `17/17`.
- Lokalny MT5 zostal odswiezony i zaladowal ponownie wszystkie `17` mikro-botow.
- `tuning_reasoning.csv` zaczal juz zapisywac zywy tok myslenia agenta po restarcie.

## Czego jeszcze uczciwie nie ma

W chwili wdrozenia nie pojawil sie jeszcze swiezy wpis `tuning_experiments.csv`, bo po restarcie nie zaszedl nowy cykl zmiany polityki wykraczajacy poza cooldown.

To nie jest brak kodu. To oznacza tylko, ze:

- mechanizm eksperymentu jest gotowy,
- ale rynek i kolejny cykl strojenia musza zostawic pierwszy zywy sladowy wpis `START/ACCEPT/ROLLBACK`.
