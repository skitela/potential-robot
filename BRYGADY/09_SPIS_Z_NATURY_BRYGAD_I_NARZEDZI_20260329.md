# SPIS Z NATURY BRYGAD I NARZEDZI - 2026-03-29

To jest operacyjny kontrakt Codexa do delegowania pracy.

Nie wymyslamy nowych lane'ow ani nowych nazw narzedzi. Korzystamy z tego, co juz istnieje w MAKRO_I_MIKRO_BOT.

## Cel nadrzedny

Kazda brygada jest podporzadkowana w tej kolejnosci:

1. zysk netto,
2. ochrona kapitalu,
3. nie psuc kodu i nie rozbudowywac systemu bez potrzeby,
4. redukowac zbedna zlozonosc,
5. utrzymac parity laptop <-> VPS <-> OANDA TMS MT5,
6. przyspieszac uczenie i przeplyw prawdy z runtime do badan.

## Jedno zrodlo prawdy

- jednym koordynatorem mostu jest `codex`,
- wszystkie brygady raportuja domyslnie do `codex`,
- brygady nie zadaja sobie pytan bezposrednio,
- pytania, watpliwosci, proby zmiany zakresu i konflikty ida tylko do `codex`,
- `brygada_nadzor_uczenia_rolloutu` wspiera Codexa w syntezie readiness, ale nie przejmuje koordynacji mostu.

## Co zostaje u Codexa

Codex zatrzymuje u siebie:

- najtrudniejsze kodowanie i finalna integracje zmian,
- decyzje przy sprzecznych wynikach brygad,
- decyzje o tym, co delegowac, a czego nie delegowac,
- ostatnie slowo w routingu i priorytecie,
- laczenie wynikow z wielu brygad w jedna sciezke wykonawcza.

Codex deleguje, gdy tylko to mozliwe:

- szerokie audyty,
- cleanup i residue,
- rollout, package i validate,
- research architektoniczny,
- synteze readiness i health,
- przygotowanie danych i kontraktow dla treningu.

## Aktywny kontekst instrumentow

Aktywna flota 13:

- `EURUSD`
- `AUDUSD`
- `GBPUSD`
- `USDJPY`
- `USDCAD`
- `USDCHF`
- `EURJPY`
- `EURAUD`
- `GOLD`
- `SILVER`
- `COPPER-US`
- `DE30`
- `US500`

Pierwsza fala paper/live:

- `US500`
- `EURJPY`
- `AUDUSD`
- `USDCAD`

Drugi rzut:

- `DE30`
- `GOLD`

Hold:

- `SILVER`

Global teacher only:

- `EURUSD`
- `GBPUSD`
- `USDJPY`
- `USDCHF`
- `EURAUD`
- `COPPER-US`

## Brygada ML i migracja MT5

- Actor: `brygada_ml_migracja_mt5`
- Priorytet: `CRITICAL`
- Pierwszy status: do `15` minut
- Kolejny heartbeat: co `30` minut

Narzędzia i zakres:

- `TOOLS/mb_ml_core`
- `TOOLS/mb_ml_supervision`
- `RUN/TRAIN_PAPER_GATE_ACCEPTOR_MODEL.ps1`
- `RUN/TRAIN_PAPER_GATE_ACCEPTOR_MODELS_PER_SYMBOL.ps1`
- `RUN/SYNC_MT5_ML_RUNTIME_STATE.ps1`
- `RUN/BUILD_LEARNING_HEALTH_REGISTRY.ps1`
- `RUN/BUILD_LOCAL_MODEL_READINESS_AUDIT.ps1`

Zlecaj tej brygadzie:

- trening,
- lokalna gotowosc modeli,
- ONNX,
- parity ML -> MT5,
- dane i kontrakty do uczenia,
- pytania o to, czy model ma sens po koszcie i po runtime truth.

Nie zlecaj tej brygadzie:

- sprzatania repo,
- rolloutu na serwer,
- szerokiego feature work w MQL5.

## Brygada audyt i cleanup

- Actor: `brygada_audyt_cleanup`
- Priorytet: `HIGH`
- Pierwszy status: do `20` minut
- Kolejny heartbeat: co `45` minut

Narzędzia i zakres:

- `EVIDENCE`
- `LOGS`
- `BACKUP`
- `RUN/CLEAN_RETIRED_SYMBOL_RESIDUE.ps1`
- `RUN/BUILD_REPO_HYGIENE_REPORT.ps1`
- `RUN/BUILD_RETIRED_SYMBOL_EXCLUSION_REPORT.ps1`

Zlecaj tej brygadzie:

- residue,
- stare artefakty,
- wycieki po wycofanych symbolach,
- higiena raportow i backupow,
- wszystko, co zamula obraz systemu i nie wymaga trudnego kodowania.

Nie zlecaj tej brygadzie:

- zmiany logiki strategii,
- treningu modeli,
- finalnego rolloutu.

## Brygada wdrozenia MT5

- Actor: `brygada_wdrozenia_mt5`
- Priorytet: `HIGH`
- Pierwszy status: do `15` minut
- Kolejny heartbeat: co `30` minut

Narzędzia i zakres:

- `SERVER_PROFILE`
- `RUN/PREPARE_MT5_ROLLOUT.ps1`
- `RUN/PREPARE_MT5_LAB_TERMINAL.ps1`
- `TOOLS/INSTALL_MT5_SERVER_PACKAGE.ps1`
- `TOOLS/VALIDATE_MT5_SERVER_INSTALL.ps1`
- `TOOLS/SIMULATE_MT5_SERVER_INSTALL.ps1`

Zlecaj tej brygadzie:

- package,
- install,
- validate,
- parity laptop-vps,
- test pierwszego zywego spool write,
- przygotowanie rolloutu dla aktywnej floty.

Nie zlecaj tej brygadzie:

- projektowania modeli,
- glownych zmian w MQL5,
- cleanupu jako pracy glownej.

## Brygada rozwoj kodu

- Actor: `brygada_rozwoj_kodu`
- Priorytet: `HIGH`
- Pierwszy status: do `20` minut
- Kolejny heartbeat: co `45` minut

Narzędzia i zakres:

- `MQL5/Experts`
- `MQL5/Include`
- `RUN/BUILD_MT5_PRETRADE_EXECUTION_TRUTH.ps1`
- `TOOLS/COMPILE_ALL_MICROBOTS.ps1`
- `TOOLS/COMPILE_MICROBOT.ps1`

Zlecaj tej brygadzie:

- konkretne poprawki w MQL5,
- helpery,
- hot-path runtime,
- integracje truth,
- kompilacje,
- bugfixy techniczne.

Nie zlecaj tej brygadzie:

- szerokich audytow,
- czyszczenia repo na szeroko,
- syntezy readiness,
- packagingu serwerowego jako glownej pracy.

## Brygada architektura i innowacje

- Actor: `brygada_architektura_innowacje`
- Priorytet: `HIGH`
- Pierwszy status: do `25` minut
- Kolejny heartbeat: co `60` minut

Narzędzia i zakres:

- `TOOLS/orchestrator`
- `CONFIG`
- `DOCS`
- `RUN/BUILD_CODEX_REQUEST_FROM_REPORT.ps1`
- `RUN/WRITE_ORCHESTRATOR_NOTE.ps1`

Zlecaj tej brygadzie:

- badanie MT5/OANDA/TMS,
- kontrakty architektoniczne,
- broker-mirror,
- parity research,
- nowe przeplywy pracy,
- wszystko, co ma dac lepszy model pracy, ale nie wymaga jeszcze trudnego kodu.

Nie zlecaj tej brygadzie:

- seryjnej implementacji,
- finalnego rolloutu,
- cleanupu jako glownego zadania.

## Brygada nadzor uczenia i rolloutow

- Actor: `brygada_nadzor_uczenia_rolloutu`
- Priorytet: `CRITICAL`
- Pierwszy status: do `15` minut
- Kolejny heartbeat: co `30` minut

Narzędzia i zakres:

- `RUN/BUILD_LEARNING_HEALTH_REGISTRY.ps1`
- `RUN/BUILD_LOCAL_MODEL_READINESS_AUDIT.ps1`
- `RUN/BUILD_ML_OVERLAY_AUDIT.ps1`
- `RUN/VALIDATE_PRELIVE_GONOGO.ps1`
- `RUN/BUILD_OUTCOME_CLOSURE_AUDIT.ps1`

Zlecaj tej brygadzie:

- readiness,
- go/no-go,
- overlay,
- learning health,
- ocene ryzyka,
- relacje zbiorcze dla Codexa.

Nie zlecaj tej brygadzie:

- glownego feature work,
- cleanupu,
- finalnej integracji kodu.

## Jak Codex ma delegowac

1. Najpierw wybierz brygade po jej realnym narzedziu i zakresie, nie po intuicji.
2. Uzywaj istniejącego nazewnictwa systemu:
   - nazwy brygad z registry,
   - nazwy aktywnych instrumentow,
   - istniejace skrypty `RUN/`,
   - istniejace kontrakty `CONFIG/`,
   - istniejace katalogi `MQL5/`, `TOOLS/`, `SERVER_PROFILE/`, `EVIDENCE/`.
3. Zlecaj task tak, by brygada wiedziala:
   - po czym poznac sukces,
   - gdzie jest scope,
   - jaki jest pierwszy status,
   - kiedy ma zrobic heartbeat,
   - i co ma oddac Codexowi.

## Jak informacje maja wracac do Codexa

Jedyny prawidlowy tor:

1. note od Codexa albo task od Codexa,
2. brygada czyta,
3. brygada bierze claim,
4. brygada publikuje wynik przez `RUN/WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1`,
5. wynik trafia do `codex`,
6. tylko Codex decyduje, czy:
   - odpowiedziec sam,
   - delegowac dalej,
   - zlecic poprawke kodowa,
   - albo zamknac temat.

## Czego brygady nie robia od teraz

- nie pytaja siebie nawzajem bezposrednio o dalsze decyzje,
- nie przejmują zadan poza lane bez zgody Codexa,
- nie wymyslaja nowego nazewnictwa dla istniejacych narzedzi i instrumentow,
- nie buduja dodatkowej zlozonosci bez poprawy zysku netto, ochrony kapitalu albo parity runtime.
