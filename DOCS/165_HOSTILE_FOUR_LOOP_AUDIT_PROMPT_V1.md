# 165 Hostile Four Loop Audit Prompt V1

Cel:
- uruchomic nieprzyjemny dla bledow audyt krzyzowy,
- wyciagnac na wierzch rozjazdy, stare slady, martwe artefakty i niespojnosci miedzy warstwami,
- traktowac pojedynczy zielony status jako niewystarczajacy dowod.

Zasada przewodnia:
- "panskie oko konia tuczy"
- "mala lyzka, ale ciegiem"
- nie ufaj jednemu raportowi, jesli nie potwierdza go co najmniej drugi i trzeci slad.

## Petla 1: Synchronizacja Krzyzowa

Sprawdzaj:
- aktywny rejestr floty kontra rodziny,
- aktywny rejestr floty kontra plan wykresow,
- aktywny rejestr floty kontra gotowosc techniczna,
- plan badawczy kontra kolejka testera,
- kolejka testera kontra realny stan testera,
- symbole wycofane kontra aktywne raporty, kolejki i hosting.

Szukaj:
- brakujacych symboli,
- dodatkowych symboli,
- roznych nazw dla tego samego instrumentu,
- symboli wycofanych, ktore wracaja boczna droga,
- niezgodnosci liczebnosci i kolejnosci.

## Petla 2: Higiena i Smieci Systemowe

Sprawdzaj:
- brudny git,
- stare wygenerowane artefakty rolloutowe,
- przeterminowane snapshoty,
- stare logi i dzienniki ponad prog rozsadku,
- osierocone katalogi state/logs,
- niepotrzebne stare pliki stagingowe i eksportowe.

Szukaj:
- przegrzanych csv i jsonl,
- nadmiarowych warstw danych,
- sladow po wycofanych symbolach,
- plikow, ktore juz nie powinny byc aktywne.

## Petla 3: Archeologia Kodu i Nazw

Sprawdzaj:
- pozostale odniesienia do symboli wycofanych w aktywnej orkiestracji,
- dryf nazw symboli miedzy aliasem, broker_symbol, code_symbol i nazwami rodzin,
- stare nazwy i historyczne obejscia,
- pozostale krytyczne odniesienia do zlej metryki pingu lub latencji w rdzeniu decyzyjnym.

Szukaj:
- `GBPAUD`, `PLATIN` w aktywnych skryptach i konfiguracji,
- symboli z sufiksem `.pro` tam, gdzie warstwa logiczna powinna pracowac na aliasie kanonicznym,
- starych odniesien do `terminal_ping` w sciezce wykonawczej,
- rozjazdow rodzin i referencji.

## Petla 4: Uczenie, ONNX i Sprzezenie Zwrotne

Sprawdzaj:
- czy mikroboty oddaja wiedze do laptopa,
- czy male ONNX rzeczywiscie zapisaly obserwacje,
- czy kabel `paper/live -> laptop` dziala,
- czy male ONNX sa tylko technicznie podpiete czy juz realnie zyja,
- czy warstwa ML jest swieza i czy pracuje.

Szukaj:
- `onnx_observations = 0`,
- fallbackow globalnych bez progresu,
- modeli slabego lub ostroznego kalibru bez planu poprawy,
- niskiego pokrycia QDM w uczeniu,
- rozjazdu miedzy tym, co raportuje runtime, a tym, co widzi research.

## Progi ostrosci

- `critical`
  - realny blocker,
  - rozjazd prawdy operacyjnej,
  - symbol wycofany wraca do aktywnej warstwy,
  - krytyczny komponent raportuje stan sprzeczny z rzeczywistoscia,
  - uczenie lub runtime jest logicznie uszkodzone.

- `high`
  - silna niespojnosc, ktora jeszcze nie blokuje wszystkiego,
  - stary lub mylacy sygnal w warstwie krytycznej,
  - przegrzane logi i artefakty,
  - brak sprzezenia zwrotnego tam, gdzie kabel mial juz dzialac.

- `medium`
  - slady dlugu technicznego,
  - dryf nazw,
  - martwe lub podejrzane artefakty,
  - raporty wymagajace domkniecia.

- `low`
  - rzeczy porzadkowe,
  - slady historyczne, ktore jeszcze nie szkodza bezposrednio,
  - rzeczy do spokojnego czyszczenia.

## Wynik koncowy

Audyt ma zwrocic:
- werdykt globalny,
- liczbe problemow per petla,
- liczbe problemow per poziom ostrosci,
- liste najgorszych znalezisk,
- liste szybkich napraw,
- liste dlugu porzadkowego.
