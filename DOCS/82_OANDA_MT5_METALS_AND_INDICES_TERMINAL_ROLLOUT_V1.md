# OANDA MT5 Metals And Indices Terminal Rollout v1

## Cel

Domknac rzeczywiste podpniecie `METALS` i `INDICES` do lokalnego terminala `OANDA MT5`, tak aby:

- pakiet instalacyjny byl samowystarczalny,
- terminal mial juz wgrane:
  - zrodla ekspertow,
  - binaria ekspertow,
  - presety bazowe,
  - presety aktywne,
  - konfiguracje runtime,
- profil wykresow obejmowal cala flote `17` mikro-botow,
- `MT5` uruchamial sie juz na profilu obejmujacym:
  - `FX`
  - `METALS`
  - `INDICES`

## Co zostalo domkniete

### 1. Pakiet montazowy

Pakiet serwerowy zostal poprawiony tak, aby przenosil nie tylko zrodla `mq5`, ale tez:

- `ex5`
- `ActiveLive` presets

Dzieki temu symulowana i rzeczywista instalacja opieraja sie juz na tym samym, kompletnym zestawie artefaktow.

### 2. Instalacja do realnego terminala

Pakiet zostal zainstalowany do danych terminala:

- `C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856`

Walidacja po instalacji zwrocila:

- `ok=true`

To potwierdzilo obecnosc:

- wszystkich `17` ekspertow `mq5`
- wszystkich `17` binariow `ex5`
- presetow bazowych
- presetow aktywnych
- konfiguracji projektu
- wspolnych plikow runtime

### 3. Profil wykresow

Zbudowano i uruchomiono profil:

- `MAKRO_I_MIKRO_BOT_AUTO`

Profil zawiera:

- `17` wykresow
- po jednym mikro-bocie na wykres
- pelne pokrycie:
  - `FX`
  - `METALS`
  - `INDICES`

Do profilu weszly:

- wszystkie pary walutowe
- cztery metale:
  - `GOLD`
  - `SILVER`
  - `COPPER-US`
- dwa indeksy:
  - `DE30`
  - `US500`

## Znaczenie operacyjne

To jest pierwszy moment, w ktorym:

- `METALS` i `INDICES` nie sa juz tylko przygotowane w projekcie,
- nie sa juz tylko obecne w `Common Files`,
- ale sa naprawde podpiete do `OANDA MT5`.

Od tego etapu caly organizm dnia ma juz pelny wymiar wykonawczy:

- `FX`
- `METALS`
- `INDICES`

w jednym terminalu, pod jednym profilem i pod wspolnym koordynatorem sesji oraz kapitalu.

## Uwagi bezpieczenstwa

Profil zostal zbudowany z presetow bazowych przewidzianych do kontrolowanego startu.

To oznacza, ze samo podpniecie do terminala nie znosi automatycznie:

- guardow kapitalowych,
- logiki `paper / defensive / reentry`,
- blokad rodzinnych,
- ochrony kontraktu ryzyka.

Czyli mamy juz gotowa scene wykonawcza, ale nadal w ramach calej architektury bezpieczenstwa zbudowanej w `MAKRO_I_MIKRO_BOT`.
