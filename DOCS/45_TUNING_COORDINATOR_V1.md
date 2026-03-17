# 45 Tuning Coordinator V1

## Cel

Koordynator strojenia stoi najwyzej, ale nie jest mozgiem handlu.

Jego zadanie:
- pilnowac porzadku zmian
- ograniczac chaos strojenia
- decydowac, ile lokalnych zmian wolno wykonywac
- w razie potrzeby zamrozic nowe zmiany, jesli park staje sie zbyt zdegradowany

## Co czyta

Koordynator nie patrzy juz na pojedyncze transakcje.
Patrzy na polityki rodzinne:
- czy sa wiarygodne
- ile rodzin jest zdegradowanych
- jakie sa rodzinne limity confidence i ryzyka
- czy rodziny same zaczynaja prosic o hamowanie zmian

## Co ustala

Koordynator buduje stan nadrzedny:
- `global_confidence_cap`
- `global_risk_cap`
- `max_local_changes_per_cycle`
- `freeze_new_changes`

## Czego nie robi

- nie wchodzi w ticki
- nie wykonuje zlecen
- nie stroi pojedynczego setupu konkretnej pary
- nie przepisuje lokalnych polityk sam z siebie

## Sens architektoniczny

To nie jest centralny bot handlowy.
To jest warstwa porzadku:
- ile zmian naraz
- czy rodziny sie nie rozjezdzaja
- czy system nie stroi sie zbyt agresywnie przy zbyt slabym obrazie danych

## Plik kodu

- [MbTuningCoordinator.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningCoordinator.mqh)
