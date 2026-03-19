# 150 Local Autonomy And Token Reduction V1

## Cel

Zmniejszyc zuzycie tokenow przez Codex/ChatGPT i przeniesc jak najwiecej rutynowej pracy na lokalne skrypty, `QDM`, `MT5` i offline ML.

## Zasada glowna

AI ma wchodzic tylko wtedy, gdy potrzebna jest:

- decyzja inzynierska
- interpretacja wyniku
- korekta logiki
- review ryzyka

Nie warto zuzywac tokenow na:

- rutynowe statusy procesow
- listy aktywnych wrapperow
- proste podglady metryk
- sprawdzenie, czy batch dalej biegnie

## Co wdrozono

### 1. Lokalny summary zamiast pytania do AI

Skrypt:

- `RUN\GET_LOCAL_OPERATOR_SUMMARY.ps1`

Ma dawac szybki obraz:

- aktywnych procesow labu
- ostatnich metryk ML
- ostatniego batchu testera

### 2. Czyszczenie nieuzywanych dodatkow AI w VS Code

Skrypt:

- `RUN\UNINSTALL_UNUSED_VSCODE_AI_EXTENSIONS.ps1`

Usuwa nieuzywane rozszerzenia:

- Gemini
- Claude Dev

Zostawia nasz glowny tor pracy.

### 3. Czyszczenie desktopowych procesow pobocznych

Skrypt:

- `RUN\CLEAN_IDLE_DESKTOP_APPS.ps1`

Zamyka niepotrzebne procesy typu:

- `PhoneExperienceHost`
- `CrossDeviceService`
- `M365Copilot`

## Jak realnie zmniejszac tokeny

1. Najpierw odpalac lokalny summary.
2. Do AI wracac dopiero z:
   - anomalia
   - delta
   - decyzja o zmianie
3. Nie pytac AI o to, co juz mamy jako lokalny raport.
4. Trzymac uczenie w:
   - `MT5 tester`
   - `QDM`
   - `offline ML`
5. Nie uzywac AI do ciaglego nadzoru procesu minuta po minucie.

## Kierunek docelowy

Najwiecej pracy ma sie dziac lokalnie:

- dane: `QDM`
- testy: `MT5`
- uczenie pomocnicze: `offline ML`
- runtime i tuning lokalny: mikroboty i agenci strojenia

AI ma byc warstwa decyzji, a nie warstwa obslugi rutyny.
