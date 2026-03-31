# Dzisiejszy Stan Pierwsza Fala i Druga Partia

Data: 2026-03-31

## Cel

Zachować w repo najważniejsze ustalenia z dzisiejszej pracy tak, żeby nie zginęły w historii rozmowy i mogły być użyte przy:
- dalszym dociąganiu pierwszej fali,
- uruchomieniu drugiej partii na laptopie z globalnym nauczycielem,
- późniejszym wdrożeniu na serwer.

## Pierwsza fala: co już zostało osiągnięte

Pierwsza fala:
- US500
- EURJPY
- AUDUSD
- USDCAD

Najważniejsze domknięte elementy:
- naprawiono pełny paperowy łańcuch nauki: open -> close -> execution truth close -> lesson write -> knowledge write,
- dopisano jawne etapy końca łańcucha w logice botów,
- doprowadzono do lokalnego, zwykłego toru poza laboratorium, w którym 4 z 4 potrafią dojść do realnej nauki,
- zachowano osobne materiały operacyjne i pakiety analityczne na pulpicie:
  - `lekcja lekcja`
  - `próba`
  - `2 z 4`

Wniosek praktyczny:
- wzorzec odblokowania pierwszej fali jest już znany i nadaje się do przeniesienia na kolejne partie.

## Co najbardziej pomogło w odblokowaniu pierwszej fali

Najważniejsze elementy naprawy:
- poszerzenie ścieżki diagnostycznej w botach,
- niewycinanie `setup_type == "NONE"` tam, gdzie trzeba było zachować widoczność,
- odblokowanie bootstrapowych stanów typu `LOW_SAMPLE` i `BUCKETS_EMPTY`,
- domknięcie paper close truth,
- jawne `LESSON_WRITE` i `KNOWLEDGE_WRITE`,
- poprawki w ograniczniku żądań i lokalnych bypassach diagnostycznych,
- ustawienie właściwego trybu paper-learning dla skupionego uczenia.

## Druga partia: symbole do uruchomienia na globalnym nauczycielu

Symbole:
- DE30
- GOLD
- SILVER
- USDJPY
- USDCHF
- COPPER-US
- EURAUD
- EURUSD
- GBPUSD

Rzeczywisty podział z planu wszechświata:
- `paper_live_second_wave`: DE30, GOLD
- `paper_live_hold`: SILVER
- `global_teacher_only`: USDJPY, USDCHF, COPPER-US, EURAUD, EURUSD, GBPUSD

## Co zostało przygotowane dla drugiej partii

Dodane narzędzia:
- `TOOLS\GENERATE_MT5_SYMBOL_GROUP_CHART_PLAN.ps1`
- `RUN\BUILD_GLOBAL_TEACHER_COHORT_ACTIVITY_AUDIT.ps1`
- `RUN\FOCUS_GLOBAL_TEACHER_COHORT_LEARNING.ps1`

Cel tych narzędzi:
- wygenerować plan wykresów dla dowolnej grupy symboli,
- uruchomić skupione uczenie dziewięciu symboli,
- potwierdzić, czy grupa naprawdę żyje na laptopie:
  - decyzje,
  - obserwacje ONNX,
  - lekcje,
  - wiedza,
  - stan gate.

## Najważniejsze odkrycie infrastrukturalne dnia

Pierwsza próba uruchomienia drugiej partii nie zawiodła przez logikę strategii, tylko przez infrastrukturę profilu MT5.

Objaw:
- plan wykresów był generowany poprawnie,
- pliki `chart*.chr` były budowane poprawnie,
- terminal startował,
- ale eksperci nowej grupy nie byli faktycznie ładowani.

Root cause:
- terminal nie przełączał aktywnego profilu na nowy profil grupy,
- w `common.ini` było stare `ProfileLast`,
- eksperci mogli pozostawać wyłączeni.

Naprawa:
- `TOOLS\setup_mt5_microbots_profile.py` zostało rozszerzone o primowanie `Config\common.ini`,
- przed startem ustawia:
  - `[Charts] ProfileLast=<docelowy_profil>`
  - `[Experts] Enabled=1`

To jest kluczowa poprawka, bo bez niej druga partia mogła wyglądać na uruchomioną, choć w praktyce nie miała załadowanych botów.

## Stan po tej poprawce

Po poprawce:
- nowy profil globalnego nauczyciela jest ustawiany jako aktywny,
- eksperci są włączani przed uruchomieniem terminala,
- można uczciwie ponowić rozruch grupy i sprawdzić, czy druga partia rzeczywiście zaczyna pracować.

## Ślady i dowody

Najważniejsze ścieżki:
- `EVIDENCE\OPS\global_teacher_cohort_focus_latest.json`
- `EVIDENCE\OPS\global_teacher_cohort_activity_latest.json`
- `EVIDENCE\OPS\global_teacher_cohort_activity_latest.md`
- `EVIDENCE\OPS\global_teacher_cohort_chart_plan_latest.json`
- `EVIDENCE\mt5_microbots_profile_setup_report.json`

Dane terminala:
- `C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856\Config\common.ini`
- `C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856\Logs\20260331.log`

## Następny krok

Następny ruch po tym zapisie:
- ponowić uruchomienie drugiej partii przez `RUN\FOCUS_GLOBAL_TEACHER_COHORT_LEARNING.ps1`,
- potwierdzić w logach terminala, że eksperci tej dziewiątki są faktycznie ładowani,
- dopiero potem ocenić, czy trzeba wzmacniać preset lub logikę uczenia.
