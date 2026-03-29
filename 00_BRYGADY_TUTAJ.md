# BRYGADY

Tu masz wszystkie brygady opisane normalnie, bez szukania po nazwach plikow.

## ZASADA WIADOMOSCI I WYKONANIA

Kazda nowa wiadomosc albo note na wspolnej liscie ma byc przeczytana przez wszystkie brygady.

Wykonanie nalezy tylko do brygady jawnie wskazanej jako target albo do brygady, ktorej operator albo Codex jawnie przypisal task.

Domyslnym administratorem informacji i koordynatorem calego mostu jest Codex.

Kazda note, handoff, task i raport wyniku ma jawnie wskazywac trzy rzeczy: kto przetwarza informacje, kto jest wlascicielem zlecenia oraz gdzie wraca raport po wykonaniu.

Wlascicielem zlecenia pozostaje chat albo aktor, ktory wydal polecenie albo handoff, ale domyslny raport zwrotny wraca do Codexa. To Codex trzyma jedna wersje prawdy dla calego mostu i koordynuje dalsze kroki.

Dyspozycje inzyniera naczelnego powinny byc domyslnie rozglaszane do wszystkich brygad i do Codexa, zeby caly system znal kierunek pracy. Sama widocznosc nie oznacza obowiazku odpowiedzi; odpowiada albo dziala tylko jawnie wskazany adresat albo wlasciciel tasku.

Brygady niewskazane czytaja, obserwuja i eskaluja tylko wtedy, gdy widza ryzyko albo sprzecznosc. Nie przejmuja samodzielnie wykonania i nie przechwytuja routingu od Codexa.

Brygady nie zadaja sobie pytan operacyjnych bezposrednio. Wszystkie pytania, watpliwosci, konflikty zakresu i prosby o doprecyzowanie ida do Codexa, a Codex decyduje, czy odpowiedziec sam, czy wydac nowy task albo note.

Jesli brygada wykonawcza potrzebuje pracy od innej brygady, zleca to tylko przez note plus task handoff, nigdy nie tylko przez rozmowe.

Po wykonaniu, blokadzie albo delegacji brygada wykonawcza raportuje wynik na wspolna liste dla wszystkich brygad i dla Codexa, a domyslnym odbiorca raportu pozostaje Codex, chyba ze operator wskaze inaczej.

Szybki start lane'u:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_BRIGADE_START_CONTEXT.ps1 -BrigadeId rozwoj_kodu
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\READ_ORCHESTRATOR_BRIGADE_NOTES.ps1 -BrigadeId rozwoj_kodu -Limit 10 -ShowContent
```

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

[Spis z natury brygad i narzedzi](BRYGADY/09_SPIS_Z_NATURY_BRYGAD_I_NARZEDZI_20260329.md)

To jest operacyjna instrukcja Codexa: kto od czego jest, jakimi narzedziami pracuje, kiedy ma raportowac i czego nie pytac poza Codexem.

[Manifest spiecia brygad](EVIDENCE/OPS/brigade_sync_manifest_latest.md)

To jest jeden jawny punkt kontroli dla Codexa: pokazuje czy kazda brygada ma kontrakt ogolny, task, note i aktualne spiecie lane.

[Automatyczna publikacja raportow](RUN/PUBLISH_BRIGADE_AUTOMATIC_REPORTS.ps1)

Ten wrapper jednym poleceniem buduje i publikuje na most raport dzienny brygad oraz manifest spiecia brygad.

[Raport doreczenia informacji z mostu](EVIDENCE/OPS/bridge_note_delivery_latest.md)

Ten raport pokazuje czy latest note z mostu zostala odebrana przez kazda brygade i czy receipts sa zsynchronizowane.

## Regula nowych wiadomosci

- wszystkie brygady czytaja nowe notatki z mostu,
- preferowana komenda odczytu to `RUN/READ_ORCHESTRATOR_BRIGADE_NOTES.ps1`, bo zapisuje tez slad odczytu brygady,
- ale wykonuje tylko brygada jednoznacznie wskazana jako adresat albo wlasciciel tasku,
- kazda note, handoff, task i wynik musza wskazac adres przetwarzania, wlasciciela zlecenia oraz adres raportowania,
- domyslnie raport wraca do Codexa, a brygada nadzoru pilnuje readiness, syntezy ryzyka i czyta wszystko,
- dyspozycje inzyniera naczelnego sa broadcastem do wszystkich do wiadomosci, chyba ze w tej samej nocie pada jawne zlecenie wykonania,
- adresat najpierw robi review bezpieczenstwa i zgodnosci z kontraktami,
- jezeli polecenie jest sprzeczne albo destrukcyjne, nie wykonuje go slepo tylko eskaluje.

## Gdzie brygady czytaja i gdzie zapisuja

- czytanie notatek: `C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox\notes\inbox`
- slad odczytu notatek: `C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox\status\brigade_note_receipts.json`
- taski pending: `C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox\coordination\tasks\pending`
- taski active: `C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox\coordination\tasks\active`
- claimy: `C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox\coordination\claims\active`
- raport wyniku brygady wraca znow do `notes\inbox` przez `RUN/WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1`

## SESJE COPILOT DLA BRYGAD

Te wejscia startuja sesje Copilot dla konkretnej brygady i dziedzicza wspolne zasady pracy z [.github/copilot-instructions.md](.github/copilot-instructions.md).

Najprostszy tryb pracy jest taki: kliknij prompt brygady, wejdz do sesji, a potem w razie potrzeby otworz jej karte operacyjna z katalogu BRYGADY.

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
