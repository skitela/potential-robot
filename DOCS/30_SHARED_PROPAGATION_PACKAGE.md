# Shared Propagation Package

## Cel

Ten etap dodaje praktyczna warstwe pomiedzy:

- planowaniem propagacji,
- a pozniejszym wdrazaniem zmian wspolnych na inne mikro-boty.

Pakiet propagacji ma sluzyc do bezpiecznego przygotowania wspolnych zmian z bota wzorcowego, bez automatycznego nadpisywania lokalnych genow innych symboli.

## Zasada

Pakiet zawiera tylko to, co jest naprawde wspolne:

- wspolne pliki `Core`,
- wspolne helpery strategii,
- wybrane narzedzia i dokumentacje wspierajace propagacje.

Pakiet nie zawiera:

- lokalnych strategii symbolowych,
- lokalnych profili symbolowych,
- ekspertow `MicroBot_*`,
- prywatnej warstwy eksperymentalnej `EURUSD`, dopoki nie zostanie zatwierdzona do rozlania.

## Narzedzia

- `TOOLS/PREPARE_SHARED_PROPAGATION_PACKAGE.ps1`
- `TOOLS/VALIDATE_PROPAGATION_PACKAGE.ps1`

## Typowy workflow

1. Rozwijamy wzorzec lokalnie, np. `EURUSD`.
2. Generujemy plan propagacji.
3. Przygotowujemy pakiet wspolnej propagacji.
4. Walidujemy pakiet.
5. Dopiero potem uzywamy go jako kontrolowanego zrodla wspolnych zmian dla rodziny.

## Domyslny przyklad

Pakiet dla rodziny `FX_MAIN` z `EURUSD`:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\PREPARE_SHARED_PROPAGATION_PACKAGE.ps1
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\VALIDATE_PROPAGATION_PACKAGE.ps1
```

## Co chronimy

Najwazniejsza zasada pozostaje bez zmian:

- wspolne rzeczy mozna rozlewac,
- genotypu pary nie wolno nadpisywac automatycznie.

Dotyczy to szczegolnie:

- okien handlu,
- scoringu,
- setup labels,
- trigger thresholds,
- lokalnych wartosci ryzyka,
- `SL/TP/trail`.

## Obecny zakres

Na tym etapie pakiet jest przygotowany glownie pod:

- rodzine `FX_MAIN`,
- wzorzec `EURUSD`,
- rozlewanie bezpiecznych zmian wspolnych,
- bez rozlewania eksperymentalnej warstwy kontekstowej `EURUSD`.
