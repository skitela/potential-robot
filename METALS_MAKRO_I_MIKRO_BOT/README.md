# METALS_MAKRO_I_MIKRO_BOT

Ten katalog nie jest osobnym projektem i nie bedzie osobnym runtime tradingowym.

To jest katalog domenowy wewnatrz wspolnego organizmu `MAKRO_I_MIKRO_BOT`.
Jego rola to:
- porzadkowac przyszly rollout metali,
- trzymac lokalne artefakty domeny `METALS`,
- oddzielac metalowy swiat od `FX` i `INDICES`,
- ale bez zrywania wspolnego kontraktu kapitalowego, brokera i nadrzednego koordynatora dnia.

## Domena

Docelowa domena obejmuje:
- `GOLD.pro`
- `SILVER.pro`
- `COPPER-US.pro`

z podzialem na:
- `METALS_SPOT_PM`
- `METALS_FUTURES`

## Architektura

Wspolna zasada jest taka:
- mikro-boty metali beda wykonywac tylko lokalna logike instrumentu,
- rodziny metali beda pilnowane przez rodzinnych agentow,
- cala domena `METALS` dostanie wlasnego agenta domenowego,
- nad nia i tak pozostanie jeden globalny koordynator sesji i kapitalu dla calego `MAKRO_I_MIKRO_BOT`.

## Zrodla prawdy

Na teraz zrodlem prawdy sa:
- `C:\\MAKRO_I_MIKRO_BOT\\DOCS\\64_OANDA_MT5_METALS_FAMILY_RESEARCH_V1.md`
- `C:\\MAKRO_I_MIKRO_BOT\\DOCS\\65_METALS_SESSION_AND_TIME_ARCHITECTURE_V1.md`
- `C:\\MAKRO_I_MIKRO_BOT\\DOCS\\68_DOMAIN_ARCHITECTURE_FX_METALS_INDICES_V1.md`
- `C:\\MAKRO_I_MIKRO_BOT\\CONFIG\\metals_family_blueprint_v1.json`
- `C:\\MAKRO_I_MIKRO_BOT\\CONFIG\\domain_architecture_registry_v1.json`

## Kolejny etap

Kiedy przyjdzie moment na realny rollout, od tego katalogu zaczniemy:
- rejestr domeny `METALS`,
- profile instrumentow i presety,
- seed polityki rodzinnej i domenowej,
- rollout lokalnych mikro-botow metali,
- podpietcie do wspolnego koordynatora dnia i kapitalu.
