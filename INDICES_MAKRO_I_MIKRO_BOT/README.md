# INDICES_MAKRO_I_MIKRO_BOT

Ten katalog jest domenowym runtime katalogiem indeksow
wewnatrz wspolnego organizmu `MAKRO_I_MIKRO_BOT`.

To nie jest osobny projekt i nie jest osobny runtime tradingowy.

## Rola katalogu

Katalog sluzy do:
- wydzielenia domeny `INDICES` od `FX` i `METALS`,
- przygotowania rollout-u europejskich i amerykanskich indeksow,
- zachowania wspolnego kontraktu kapitalowego, brokera i nadrzednego koordynatora dnia.

## Domena

Na poziomie architektury przyjmujemy dwie rodziny:
- `INDEX_EU`
- `INDEX_US`

Aktualny seed runtime:
- `DE30.pro` dla `INDEX_EU`
- `US500.pro` dla `INDEX_US`

## Zrodla prawdy

Na teraz zrodlem prawdy sa:
- `C:\\MAKRO_I_MIKRO_BOT\\DOCS\\66_SESSION_WINDOW_MATRIX_V1.md`
- `C:\\MAKRO_I_MIKRO_BOT\\DOCS\\68_DOMAIN_ARCHITECTURE_FX_METALS_INDICES_V1.md`
- `C:\\MAKRO_I_MIKRO_BOT\\CONFIG\\indices_family_blueprint_v1.json`
- `C:\\MAKRO_I_MIKRO_BOT\\CONFIG\\domain_architecture_registry_v1.json`

## Stan domeny

`INDICES` zostaly juz podpiete do:
- wspolnego kontraktu kapitalowego,
- koordynatora sesji i kapitalu,
- hierarchii strojenia rodzin,
- runtime `DE30.pro` i `US500.pro`.

Najblizszy etap to dojrzewanie genotypu indeksowego i playbookow reentry / reserve.
