# Git workflow v1

Ten projekt ma juz lokalne repo `git` i od tego momentu pracujemy tak:

## Zasady
- male commity, jeden logiczny temat na commit
- najpierw zmiana i sprawdzenie, potem commit
- duze etapy oznaczamy tagiem
- backup zip dalej zostaje jako dodatkowa warstwa bezpieczenstwa, ale podstawowa historia zmian siedzi juz w `git`

## Co trafia do repo
- kod `MQL5`
- skrypty `TOOLS` i `RUN`
- konfiguracja `CONFIG`
- dokumentacja `DOCS`
- lekkie assety i pliki projektowe

## Czego nie wrzucamy do repo
- `BACKUP`
- `EVIDENCE`
- `LOGS`
- `STATE`
- wygenerowane pliki testera
- paczki wdrozeniowe i lokalne pliki pomocnicze

## Prosty rytm pracy
1. robimy mala zmiane
2. sprawdzamy wynik
3. zapisujemy punkt kontrolny w `git`
4. przy duzym etapie dodajemy tag

## Narzedzia
- szybki status: `git -C C:\MAKRO_I_MIKRO_BOT st`
- krotka historia: `git -C C:\MAKRO_I_MIKRO_BOT lg`
- ostatni commit: `git -C C:\MAKRO_I_MIKRO_BOT last`
- zapis punktu kontrolnego: [ZAPISZ_PUNKT_GIT.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\ZAPISZ_PUNKT_GIT.ps1)

## Zdalne repo
Lokalne repo jest gotowe do podpienia zdalnego `origin`, ale adres repo trzeba wskazac jawnie. Nie podpinamy w ciemno przypadkowego URL-a.
