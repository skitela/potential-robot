# 85. Tuning Guard Matrix Runtime Integration V1

## Cel

Matryca kosztu i okna przestaje byc tylko dokumentem.

Od tej wersji staje sie lekka warstwa runtime dla strojenia:

- lokalny agent strojenia respektuje rodzinne limity ostroznosci,
- agent rodzinny nie wypycha juz dominujacych capow ponad rodzinny sufit kosztowo-okienny,
- most hierarchii pilnuje, aby finalna polityka skuteczna nie zgubila tego ograniczenia,
- indeksy wchodza do wspolnej listy rodzin strojenia tak samo jak `FX` i `METALS`.

## Co zostalo wdrozone

Dodano wspolny helper guardow rodzinnych:

- `MbTuningGuardMatrix.mqh`

Helper rozpoznaje rodzine po:

- nazwie rodziny,
- albo po symbolu.

Na tej podstawie rozklada lekkie sufity ostroznosci dla:

- `confidence_cap`
- `risk_cap`

## Sufity runtime v1

- `FX_MAIN`
  - `confidence_cap <= 0.92`
  - `risk_cap <= 0.88`
- `FX_ASIA`
  - `confidence_cap <= 0.88`
  - `risk_cap <= 0.80`
- `FX_CROSS`
  - `confidence_cap <= 0.82`
  - `risk_cap <= 0.65`
- `METALS_SPOT_PM`
  - `confidence_cap <= 0.84`
  - `risk_cap <= 0.72`
- `METALS_FUTURES`
  - `confidence_cap <= 0.80`
  - `risk_cap <= 0.65`
- `INDEX_EU`
  - `confidence_cap <= 0.78`
  - `risk_cap <= 0.70`
- `INDEX_US`
  - `confidence_cap <= 0.82`
  - `risk_cap <= 0.72`

## Gdzie to dziala

### Lokalny agent

Po policzeniu lokalnych kar i blokad:

- loss ratio
- loss streak
- breakout i trend bucket taxes

na koncu nakladany jest rodzinny sufit z guard matrix.

To znaczy:

- lokalny agent dalej moze sie stroic,
- ale nie moze przepchnac symbolu ponad rodzinna ostroznosc.

### Agent rodzinny

Po agregacji snapshotow symboli:

- srednie `confidence_cap`
- srednie `risk_cap`
- breakout i trend votes

polityka rodzinna jest jeszcze raz przycinana przez guard matrix.

To stabilizuje rodzine nawet wtedy, gdy lokalne polityki sa chwilowo zbyt optymistyczne.

### Most hierarchii

Po nalozeniu:

- polityki rodzinnej
- polityki koordynatora

finalna polityka skuteczna dostaje jeszcze ostatni clamp guard matrix.

To daje prosty kontrakt:

- lokalny agent nie przepchnie guardu,
- rodzina nie przepchnie guardu,
- most skuteczny tez nie przepchnie guardu.

## Indeksy

Do listy rodzin strojenia zostaly formalnie dolaczone:

- `INDEX_EU`
- `INDEX_US`

oraz ich mapowanie symboli:

- `DE30.pro`
- `US500.pro`

To domyka niespojnosc, w ktorej indeksy istnialy juz w runtime i rejestrach, ale nie byly jeszcze pelnoprawnie widoczne dla calej hierarchii strojenia.

## Czego jeszcze nie robi ta wersja

To jest swiadomie lekka wersja `v1`.

Jeszcze nie ma tu:

- dynamicznego odcinania nowych live w ostatnich minutach okna przez sam lokalny agent,
- bezposredniego przechodzenia do `paper` tylko z powodu guard matrix,
- czytania JSON w runtime.

Te rzeczy sa odlozone celowo:

- zeby nie dociązac hot-path,
- i zeby najpierw wejsc z bezpiecznym, prostym clampem.

## Wynik techniczny

- `17/17` mikro-botow kompiluje sie poprawnie
- walidacja hierarchii strojenia przechodzi z `ok=true`
- walidacja layoutu projektu przechodzi z `ok=true`

## Wniosek

To jest dobry pierwszy krok.

Matryca nie jest juz tylko mapa do czytania przez czlowieka.
Jest juz realna warstwa ostroznosci runtime:

- lekka,
- wspolna,
- i trudna do obejscia przez lokalne strojenie.
