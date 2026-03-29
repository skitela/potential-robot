# BRYGADY

Tu masz wszystkie brygady opisane normalnie, bez szukania po nazwach plikow.

## BRYGADA ML I MIGRACJA MT5

[Otworz brygade 01](BRYGADY/01_BRYGADA_ML_MT5__ONNX_QDM_GOTOWOSC_MIGRACJA.md)

Ta brygada zajmuje sie treningiem modeli, ONNX, QDM, gotowoscia lokalnych modeli i migracja modelu albo state do terminali MT5.

To jest brygada od ciaglego uczenia aktywnych instrumentow i przygotowania materialu modelowego dla runtime.

## BRYGADA AUDYT I CLEANUP

[Otworz brygade 02](BRYGADY/02_BRYGADA_AUDYT_CLEANUP__RESIDUE_ARTEFAKTY_HIGIENA.md)

Ta brygada zajmuje sie sprzataniem residue, starych artefaktow, backupow, logow i problemow parity w repo oraz runtime.

To jest brygada od higieny repo, wykrywania starych bledow i usuwania wszystkiego, co przeszkadza uczeniu, raportom albo wdrozeniom.

## BRYGADA WDROZENIA MT5

[Otworz brygade 03](BRYGADY/03_BRYGADA_WDROZENIA_MT5__PACKAGE_INSTALL_VALIDATE.md)

Ta brygada zajmuje sie package, install, validate, handoff i bezpiecznym rolloutem zmian do MT5.

To jest brygada od fizycznego wejscia zmian na terminal, serwer i profil MT5 bez rozjechania parity laptop-VPS.

## BRYGADA ROZWOJ KODU

[Otworz brygade 04](BRYGADY/04_BRYGADA_ROZWOJ_KODU__MQL5_HELPERY_BUGFIXY_KOMPILACJA.md)

Ta brygada zajmuje sie pisaniem kodu, bugfixami, helperami MQL5, kompilacja i wdrazaniem zmian technicznych w systemie.

To jest brygada od implementacji: kod, poprawki, helpery, kompilacja i techniczne domykanie funkcji wskazanych przez pozostale brygady.

## BRYGADA ARCHITEKTURA I INNOWACJE

[Otworz brygade 05](BRYGADY/05_BRYGADA_ARCH_INNOWACJE__KONCEPCJE_KONTRAKTY_PRZEPLYWY.md)

Ta brygada zajmuje sie architektura, nowymi koncepcjami, kontraktami, przeplywami pracy i usprawnieniami miedzy brygadami.

To jest brygada od projektowania kierunku systemu: nowe pomysly, kontrakty architektoniczne, przeplywy pracy i usprawnienia calego modelu brygad.

## BRYGADA NADZOR UCZENIA I GO-NO-GO

[Otworz brygade 06](BRYGADY/06_BRYGADA_NADZOR_UCZENIA__HEALTH_OVERLAY_GONOGO.md)

Ta brygada zajmuje sie learning health, readiness, overlay audit, go-no-go i kontrola ryzyka przed rolloutem.

To jest brygada od nadzoru: pilnuje czy uczenie, readiness i rollout sa bezpieczne, oraz czy system jest gotowy do przejscia dalej.

## PLIKI STERUJACE

[Panel sterowania brygad](BRYGADY/00_PANEL_STEROWANIA_BRYGAD.md)

To jest glowny panel operatorski do wejscia w brygady, status, raport dzienny i wspolna liste notatek.

[Start brygad](BRYGADY/00_START_BRYGADY.md)

To jest tablica startowa z ukladem lane i glownymi wejsciami do pracy.

[Handoff brygad](BRYGADY/07_HANDOFF_BRYGAD.md)

To jest plik przekazywania pracy miedzy brygadami.

[Plan brygad](BRYGADY/08_PLAN_BRYGAD_20260329.md)

To jest aktualny plan pracy brygad.

## Regula nowych wiadomosci

- wszystkie brygady czytaja nowe notatki z mostu,
- ale wykonuje tylko brygada jednoznacznie wskazana jako adresat albo wlasciciel tasku,
- adresat najpierw robi review bezpieczenstwa i zgodnosci z kontraktami,
- jezeli polecenie jest sprzeczne albo destrukcyjne, nie wykonuje go slepo tylko eskaluje.

## SESJE COPILOT DLA BRYGAD

[Wejdz: BRYGADA ML I MIGRACJA MT5](.github/prompts/wejdz-brygada-ml-migracja-mt5.prompt.md)

Uruchamia osobna sesje Copilot dla brygady ML i migracji MT5.

[Wejdz: BRYGADA AUDYT I CLEANUP](.github/prompts/wejdz-brygada-audyt-cleanup.prompt.md)

Uruchamia osobna sesje Copilot dla brygady audytowej i cleanup.

[Wejdz: BRYGADA WDROZENIA MT5](.github/prompts/wejdz-brygada-wdrozenia-mt5.prompt.md)

Uruchamia osobna sesje Copilot dla brygady wdrozeniowej MT5.

[Wejdz: BRYGADA ROZWOJ KODU](.github/prompts/wejdz-brygada-rozwoj-kodu.prompt.md)

Uruchamia osobna sesje Copilot dla brygady rozwoju kodu.

[Wejdz: BRYGADA ARCHITEKTURA I INNOWACJE](.github/prompts/wejdz-brygada-architektura-innowacje.prompt.md)

Uruchamia osobna sesje Copilot dla brygady architektury i innowacji.

[Wejdz: BRYGADA NADZOR UCZENIA I GO-NO-GO](.github/prompts/wejdz-brygada-nadzor-uczenia-gonogo.prompt.md)

Uruchamia osobna sesje Copilot dla brygady nadzoru uczenia i decyzji go-no-go.
