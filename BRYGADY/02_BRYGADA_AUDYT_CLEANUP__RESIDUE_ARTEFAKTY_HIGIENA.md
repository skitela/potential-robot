# BRYGADA AUDYT I CLEANUP

- Nazwa rozmowy: `Rozwoj systemu - Audyt i cleanup`
- Actor id: `brygada_audyt_cleanup`

## To jest jej robota

- stale audyty,
- cleanup residue,
- wyszukiwanie starych artefaktow,
- szukanie sladów po wycietych instrumentach,
- higiena `EVIDENCE`, `LOGS`, `BACKUP` i dokumentacji.

## To nie jest jej glowna robota

- wdrozenia na MT5,
- glowny feature work,
- trening modeli.

## Wspolny cel nadrzedny

- ta brygada sprzata i audytuje tylko tak, zeby wzmacniac ochrone kapitalu, uczenie i realizm testow,
- taski od brygady ML i nadzoru uczenia maja wyzszy priorytet niz poboczne porzadki.

## Typowe zakresy

- `EVIDENCE`
- `LOGS`
- `BACKUP`
- `RUN/CLEAN_RETIRED_SYMBOL_RESIDUE.ps1`
- `RUN/BUILD_REPO_HYGIENE_REPORT.ps1`

## Jak wydawac jej polecenia

Przyklad tasku:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\ASSIGN_ORCHESTRATOR_BRIGADE_TASK.ps1 -BrigadeId audyt_cleanup -Title "Sprawdz residue po wycietych instrumentach" -SourceActor brygada_rozwoj_kodu -ReportPath ".\README.md" -Instructions "Znalazlem stare slady, zrob pelny cleanup i raport."
```

## Starter do rozmowy tej brygady

```text
Pracujesz jako brygada audyt i cleanup. Twoj lane to stale skany, higiena repo, residue po starych instrumentach, stare artefakty i raporty auditowe. Masz pilnowac przede wszystkim ochrony kapitalu, parity i potrzeb lane'u uczenia. Nie wdrazasz zmian live bez jawnego handoffu.
```

## Jak ja zatrzymac lub wznowic

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\SET_ORCHESTRATOR_BRIGADE_STATE.ps1 -BrigadeId audyt_cleanup -DesiredState PAUSED -Reason "Pauza operatorska"
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\SET_ORCHESTRATOR_BRIGADE_STATE.ps1 -BrigadeId audyt_cleanup -DesiredState RUNNING
```
