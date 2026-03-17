# 63. Monday 2026-03-16 Session Master Playbook

## Cel

Ten dokument jest jednym wspolnym planem operacyjnym dla calego `MAKRO_I_MIKRO_BOT` na poniedzialek `16 marca 2026`.

Ma zastapic skakanie miedzy osobnymi playbookami rodzin w pierwszym waznym oknie po weekendowym wznowieniu rynku.

Najwazniejszy cel poniedzialku nie brzmi:

- `zarobic za wszelka cene`

tylko:

- wejsc w rynek z czysta telemetria,
- potwierdzic, ze nowa hierarchia strojenia dziala spokojnie i logicznie,
- pozwolic botom zbierac wartosciowy material,
- ograniczyc liczbe glupich porazek,
- nie naruszyc kontraktu ochrony kapitalu.

To ma byc dzien dyscypliny, nie improwizacji.

## Kontekst na start

Na wejscie w ten dzien system ma juz:

- lokalnych agentow strojenia,
- technicznych pomocnikow czyszczacych dane,
- most `lokalny -> rodzina -> flota`,
- dzienniki kandydatow wejscia,
- kontrakt kapitalowy `paper/live`,
- osobne playbooki dla:
  - `FX_MAIN`
  - `FX_ASIA`
  - `FX_CROSS`
  - `INDICES`

To oznacza, ze w poniedzialek nie zaczynamy od budowy czegos nowego. Zaczynamy od odpowiedzialnego wejscia w rynek z tym, co juz zostalo przygotowane.

## Zasada nadrzedna dnia

W poniedzialek `16 marca 2026` nie wygrywa ten, kto zrobi najwiecej ruchow, tylko ten, kto wykona najmniej zbednych ruchow.

To znaczy:

- nie spieszymy sie ze zmianami,
- nie odblokowujemy niczego po jednej wygranej,
- nie panikujemy po jednej stracie,
- patrzymy na wzorzec, nie na emocje.

## Harmonogram dnia

### Faza 0 - przed wejsciem w obserwacje

Zanim zaczniemy interpretowac rynek, sprawdzamy tylko stan techniczny:

- czy wszystkie eksperty sa zaladowane,
- czy runtime dla symboli odswieza sie normalnie,
- czy `candidate_signals.csv` i `learning_observations_v2.csv` maja poprawny schemat,
- czy `tuning_policy_effective.csv` istnieje dla rodzin, ktore maja byc obserwowane,
- czy nie ma ewidentnej korupcji logow lub martwych snapshotow.

Jesli wszystko jest czyste, nie robimy nic wiecej.

### Faza 1 - pierwsze 15 minut

To nie jest jeszcze okno do wnioskowania o przewadze.

W tych pierwszych minutach patrzymy tylko:

- czy pojawiaja sie kandydaci,
- czy pojawiaja sie pierwsze decyzje `PAPER_OPEN` lub `PAPER_CLOSE`,
- czy klasy rejestrowane jako toksyczne nie wracaja natychmiast jako dominujace,
- czy rodzina i flota nie tworza szumu w skutecznej polityce,
- czy nie ma regresji latencji i execution.

Jesli w tych 15 minutach nie ma zadnej transakcji, to samo w sobie nie jest problemem. Problemem bylby brak zycia runtime przy aktywnym rynku.

### Faza 2 - 15 do 60 minut

To jest glowna faza interpretacyjna.

W tym oknie patrzymy juz:

- czy przeplyw kandydatow ma sens,
- czy nowe filtry rzeczywiscie cos odsiewaja,
- czy liczba strat przez `PAPER_TIMEOUT` i `PAPER_SL` zaczyna wygladac lepiej niz w ostatnich raportach,
- czy rodziny zachowuja sie zgodnie ze swoim genotypem,
- czy agenci strojenia pozostaja spokojni i nie zaczynaja generowac nerwowych zmian.

Dopiero po tej godzinie wolno wyciagac pierwsze ostrozne wnioski.

## Co zostawiamy nieruszone przez pierwsza godzine

W pierwszej godzinie po rozpoczeciu obserwacji nie robimy:

- zmian w kodzie,
- recznego luzowania polityki rodzinnej,
- recznego ruszania koordynatora floty,
- recznego podnoszenia `risk_cap`,
- recznego podnoszenia `confidence_cap`,
- recznego wzmacniania `SETUP_BREAKOUT`, `SETUP_TREND` albo `SETUP_RANGE`,
- nowych resetow journali i nowych porzadkow runtime, jesli nie ma realnej korupcji,
- recznego odblokowywania botow po pojedynczym zysku.

Pierwsza godzina ma byc diagnostyczna.

## Co obserwujemy globalnie

Na poziomie calego systemu obserwujemy:

- `candidate_signals.csv`
- `learning_observations_v2.csv`
- `learning_bucket_summary_v1.csv`
- `decision_events.csv`
- `tuning_policy_effective.csv`
- `tuning_actions.csv`
- `tuning_deckhand.csv`
- `execution_summary.json`
- `informational_policy.json`
- `runtime_state.csv`

Interesuje nas przede wszystkim:

- czy kandydaci w ogole pojawiaja sie logicznie,
- czy wejscia nie wracaja natychmiast do najbardziej toksycznych bucketow,
- czy runtime nadal pozostaje czysty,
- czy kontrakt ryzyka zaczyna dzialac zgodnie z intencja.

## Priorytety rodzin

### FX_MAIN

To jest rodzina najwazniejsza operacyjnie.

Tu w centrum uwagi sa:

- `EURUSD` jako wzorzec,
- `GBPUSD`,
- `USDCAD`,
- `USDCHF`.

Patrzymy glownie na:

- czy `EURUSD` dalej unika toksycznego `TREND` w `BREAKOUT/CHAOS`,
- czy `GBPUSD` ogranicza zbyt szeroki `TREND`,
- czy `USDCAD` nie wraca do nadmiernego breakoutu bez wsparcia,
- czy `USDCHF` nie probuje znow handlowac zbyt pewnym siebie breakoutem.

To jest rodzina, w ktorej najszybciej chcemy zobaczyc, czy weekendowa praca daje mniej glupich porazek.

### FX_ASIA

To jest rodzina, ktora ma pokazywac przede wszystkim dyscypline, a nie agresje.

Patrzymy glownie na:

- czy `USDJPY` pokazuje mniej toksycznego breakoutu,
- czy `AUDUSD` nie wraca do slepego range bez jakosci,
- czy `NZDUSD` pozostaje pod spokojna obserwacja zamiast dostac zbyt szybkie lokalne strojenie.

Dla tej rodziny dobrym wynikiem nie musi byc szybki zysk. Dobrym wynikiem jest mniejsza toksycznosc i czystszy material.

### FX_CROSS

To jest rodzina najtrudniejsza kosztowo i najbardziej zdradliwa.

Patrzymy glownie na:

- czy `GBPJPY` nie wraca natychmiast do rany `SETUP_RANGE/CHAOS`,
- czy `EURJPY`, `EURAUD` i `GBPAUD` zaczynaja dostarczac w ogole nowy material,
- czy crossy pozostaja mierzalne, a nie rozjezdzaja sie natychmiast we wlasne skrajne zachowania.

Tu najwazniejszy sygnal sukcesu to nie eksplozja zyskow, tylko brak regresji i wzrost czytelnosci.

### INDICES

To jest nowa domena runtime i dlatego jej poniedzialek ma byc jeszcze bardziej
obserwacyjny niz w przypadku dojrzalszych rodzin `FX`.

Patrzymy glownie na:

- czy `DE30.pro` zbiera czysty material w `INDEX_EU`,
- czy `US500.pro` nie wraca natychmiast do agresywnego breakoutu przy `INDEX_US`,
- czy domena `INDICES` jest poprawnie budzona i usypiana przez koordynator sesji,
- czy lokalne rodziny pozostaja zamrozone strojenia dopoki nie pojawi sie prawdziwa probka.

Dla `INDICES` dobrym wynikiem nie musi byc zysk. Dobrym wynikiem jest:

- czysty runtime,
- logika domeny bez szumu,
- oraz pierwsze wartosciowe dane do przyszlego strojenia.

## Co bedzie oznaka dobrego startu

Dobry start poniedzialku to:

- czyste logi,
- odswiezajacy sie runtime,
- sensowny przeplyw kandydatow,
- mniej wejsc w klasy oznaczone w weekend jako toksyczne,
- brak regresji latencji,
- brak histerii w `tuning_actions.csv`,
- brak obchodzenia kontraktu ryzyka,
- pierwsze transakcje zgodne z nowa polityka, nawet jesli nie wszystkie beda zyskowne.

## Co bedzie oznaka zlego startu

Zly start to:

- martwy runtime przy aktywnym rynku,
- zepsuty schemat journali,
- natychmiastowy powrot najbardziej toksycznych klas jako dominujacego zachowania,
- wyrazny wzrost `PAPER_SL` i `PAPER_TIMEOUT` bez zadnej poprawy selekcji,
- brak zgodnosci miedzy polityka skuteczna a zachowaniem strategii,
- oznaki, ze rodzina albo flota przestaly trzymac dyscypline.

## Kiedy wolno interweniowac

Interwencja w pierwszej godzinie jest uzasadniona tylko wtedy, gdy pojawi sie jeden z nastepujacych problemow:

- runtime nie aktualizuje sie mimo aktywnego rynku,
- journale lub stany sa uszkodzone,
- skuteczna polityka strojenia ma ewidentnie bledny stan,
- jest techniczna seria awarii execution,
- kontrakt kapitalowy nie zachowuje sie zgodnie z oczekiwaniem.

Zwykla strata `paper` nie jest sama w sobie powodem do interwencji.

## Jak czytamy wynik po pierwszej godzinie

Po pierwszej godzinie nie zadajemy pytania:

- `czy system juz zarabia`

tylko pytamy:

- czy system podejmuje madrzejsze decyzje niz wczoraj,
- czy ogranicza najgorsze klasy porazek,
- czy daje czystszy material dla dalszego strojenia,
- czy kontrakt ryzyka trzyma cala flote blizej bezpieczenstwa.

Jesli odpowiedz na te pytania jest twierdzaca, to nawet przy mieszanym PnL godzina jest wartosciowa.

## Co robimy po pierwszej godzinie

Po zakonczeniu pierwszej godziny robimy tylko trzy rzeczy:

1. zestawiamy nowe rekordy z raportami weekendowymi,
2. oceniamy, czy rodziny zachowaly dyscypline,
3. decydujemy, czy:
   - dalej tylko obserwujemy,
   - czy przygotowujemy jedna kolejna mala zmiane dla wybranej rodziny.

Nie przechodzimy od razu do wielu zmian naraz.

## Dokumenty pomocnicze

Ten dokument opiera sie na i porzadkuje:

- [53_FIRST_HOUR_REOPEN_PLAYBOOK_FX_MAIN.md](C:\MAKRO_I_MIKRO_BOT\DOCS\53_FIRST_HOUR_REOPEN_PLAYBOOK_FX_MAIN.md)
- [56_FIRST_HOUR_REOPEN_PLAYBOOK_FX_ASIA.md](C:\MAKRO_I_MIKRO_BOT\DOCS\56_FIRST_HOUR_REOPEN_PLAYBOOK_FX_ASIA.md)
- [59_FIRST_HOUR_REOPEN_PLAYBOOK_FX_CROSS.md](C:\MAKRO_I_MIKRO_BOT\DOCS\59_FIRST_HOUR_REOPEN_PLAYBOOK_FX_CROSS.md)
- [76_FIRST_HOUR_REOPEN_PLAYBOOK_INDICES.md](C:\MAKRO_I_MIKRO_BOT\DOCS\76_FIRST_HOUR_REOPEN_PLAYBOOK_INDICES.md)
- [61_IMMUTABLE_CAPITAL_RISK_CONTRACT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\61_IMMUTABLE_CAPITAL_RISK_CONTRACT_V1.md)
- [62_CAPITAL_RISK_CONTRACT_ENFORCEMENT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\62_CAPITAL_RISK_CONTRACT_ENFORCEMENT_V1.md)

## Najkrotszy sens tego dnia

Poniedzialek `16 marca 2026` nie ma byc dniem popisu.

Ma byc dniem, w ktorym:

- boty nie wracaja do dawnych glupich ran,
- agenci strojenia nie panikuja,
- majtkowie techniczni utrzymuja czysty poklad,
- a cala flota pokazuje, ze potrafi plynac spokojniej, madrzej i bezpieczniej niz do tej pory.
