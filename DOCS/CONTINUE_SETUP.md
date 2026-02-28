# Continue Setup (Gemini primary + Perplexity fallback)

## Zakres
Ten dokument dotyczy tylko warstwy developerskiej VS Code/Continue dla repo `C:\OANDA_MT5_SYSTEM`.
Nie zmienia runtime tradingu, strategii, MQL5 ani guardów.

## Pliki konfiguracji
- Continue config: `.continue/config.json`
- VS Code rekomendacje rozszerzeń: `.vscode/extensions.json`

## Wymagane rozszerzenie
- `continue.continue` (zainstalowane lokalnie)

## Klucze API (bez zapisu do repo)
Używamy zmiennych środowiskowych użytkownika.

PowerShell (Windows, user scope):

```powershell
[Environment]::SetEnvironmentVariable("GEMINI_API_KEY", "<twoj_klucz_gemini>", "User")
[Environment]::SetEnvironmentVariable("PERPLEXITY_API_KEY", "<twoj_klucz_perplexity>", "User")
```

### Uwaga o Perplexity w Continue
Model `perplexity-fallback` jest skonfigurowany jako provider `openai` z `apiBase=https://api.perplexity.ai`.
W tym trybie Continue odczytuje klucz jak dla provider OpenAI. Ustaw alias:

```powershell
[Environment]::SetEnvironmentVariable("OPENAI_API_KEY", "<ten_sam_klucz_perplexity>", "User")
```

Po ustawieniu zmiennych zamknij i uruchom ponownie VS Code.

## Jak używać profili
W Continue (panel chat):
- domyślnie używaj modelu `gemini-primary`,
- gdy potrzebny fallback, ręcznie przełącz na `perplexity-fallback` w selektorze modelu.

Autouzupełnianie (tab autocomplete) jest ustawione na `gemini-fast`.

## Tryb podwójny w VS Code (Gemini + Perplexity)
- `Gemini Code Assist` działa niezależnie jako osobny panel/agent w VS Code.
- `Continue` działa równolegle:
  - `gemini-primary` (domyślnie),
  - `perplexity-fallback` (przełączany ręcznie).
- Dzięki temu możesz mieć oba narzędzia aktywne jednocześnie bez zmian w runtime tradingu.

## Checklista bezpieczeństwa
- Nigdy nie zapisuj kluczy w:
  - `.continue/config.json`
  - `.vscode/settings.json`
  - plikach repo
- Weryfikacja po zmianach:

```powershell
rg -n "API_KEY|GEMINI|PERPLEXITY|sk-" . --glob "!.venv/**" --glob "!.git/**"
git status --short
```

## Szybki smoke test
1. Otwórz panel Continue.
2. Wybierz `gemini-primary`, wyślij krótkie zapytanie.
3. Przełącz model na `perplexity-fallback`, wyślij zapytanie testowe.
4. Potwierdź brak zmian w runtime:
   - `TOOLS/SYSTEM_CONTROL.ps1 -Action status`
