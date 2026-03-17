# Dodatkowe wsparcie konwersji breakoutow dla GBPUSD

Data: 2026-03-16

## Cel
- usunac waskie gardlo `GBPUSD`, gdzie papierowe lekcje konczyly sie na `RISK_CONTRACT_BLOCK`
- nie rozluzniac calego bota, tylko dopuscic tylko najmocniejsze breakouty, ktore maja sens poznawczy

## Co zostalo zmienione
- dodano dodatkowy papierowy ratunek dla `GBPUSD`, ale tylko dla breakoutow:
  - z wynikiem co najmniej `1.00`
  - poza `CHAOS`
  - bez zlego spreadu
  - z dobra egzekucja
  - z bucketem lepszym niz `LOW`
  - z co najmniej jednym mocnym potwierdzeniem swieca / Renko
- nie zmieniono ogolnej filozofii bota:
  - slabe breakouty dalej maja byc odrzucane
  - brudny trend w chaosie dalej nie ma dostawac papierowego ratunku

## Dlaczego
- analiza historii `GBPUSD` pokazala, ze glowny zator nie lezal juz w trendzie, tylko w breakoutach
- w logach byly widoczne breakouty o wysokim wyniku i przyzwoitym tle rynkowym, ale nadal ucinane na planie ryzyka
- poprzedni ratunek byl zbyt waski, bo dotykal glownie trendu/pullbacku

## Weryfikacja techniczna
- `MicroBot_GBPUSD` skompilowany poprawnie
- lokalny `OANDA MT5` zrestartowany
- log terminala potwierdza ponowne zaladowanie `MicroBot_GBPUSD`

## Uczciwy stan po wdrozeniu
- poprawka jest aktywna w runtime
- rynek po restarcie nie zostawil jeszcze nowego, swiezego sladu `GBPUSD` po tej wersji
- czyli:
  - kod jest gotowy
  - terminal go zaladowal
  - ale potwierdzenie skutku z rynku wymaga jeszcze kolejnej swiecy / kolejnego cyklu
