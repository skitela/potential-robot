# 52. Tuning Language Extensions V1

## Cel

Weekendowa analiza `FX_MAIN` pokazala, ze sam system podatkow i capow nie wystarcza do dojrzalego strojenia. Potrzebowalismy kilku nowych pojec, ktore pozwalaja powiedziec nie tylko "przytnij ryzyko", ale tez "nie wpuszczaj tej klasy wejscia bez minimalnej jakosci potwierdzenia".

## Co zostalo dodane

Do lokalnej polityki strojenia dodano trzy nowe przelaczniki:

- `require_support_for_rejection`
- `require_non_poor_renko_for_breakout`
- `require_non_poor_candle_for_trend`

Sa one zapisane i ladowane razem z pozostala polityka strojenia, logowane w journalu akcji i przenoszone do skutecznej polityki instrumentu.

## Jak dzialaja

Nowe pojecia nie przepisuja strategii od nowa. One tylko zawezaja wejscie wtedy, gdy lokalny agent strojenia uzna, ze dana klasa strat jest juz wystarczajaco dobrze rozpoznana.

### Rejection

`require_support_for_rejection` blokuje wejscie typu rejection, jesli nie ma zgodnego wsparcia kierunkowego z warstwy pomocniczej. To odpowiada na przypadki, w ktorych sama idea odrzucenia wygladala atrakcyjnie, ale historycznie nie bronila sie bez potwierdzenia.

### Breakout

`require_non_poor_renko_for_breakout` blokuje breakout, gdy jakosc `Renko` jest `POOR` albo `UNKNOWN`. To jest odpowiedz na toksyczne klasy breakoutow, gdzie ruch formalnie istnial, ale nie mial czystosci potrzebnej do dalszej kontynuacji.

### Trend

`require_non_poor_candle_for_trend` blokuje wejscie trendowe, gdy jakosc swiecy jest `POOR`. To jest praktyczne zabezpieczenie przed trendem, ktory na papierze wyglada poprawnie, ale w rzeczywistosci jest slaby i czesto konczy sie `PAPER_TIMEOUT`.

## Gdzie to wdrozono

Nowe pojecia zostaly wdrozone dla:

- `EURUSD`
- `GBPUSD`
- `USDCAD`
- `USDCHF`

Czyli dla lokalnego wzorca oraz dojrzalej czworki `FX_MAIN`, na ktorej juz dziala most `lokalny -> rodzina -> flota`.

## Co to zmienia operacyjnie

Ta warstwa rozszerza jezyk strojenia bez naruszania hot-path.

- logika tickowa pozostaje lekka,
- strojenie dalej odbywa sie poza goracym szlakiem,
- nowe bramki sa tylko prostym warunkiem boolean opartym o juz policzony kontekst.

To jest zgodne z glownym zalozeniem projektu: poprawiac jakosc decyzji bez psucia latencji.

## Czego swiadomie nie dodano jeszcze teraz

Nie wdrozono jeszcze automatycznego skrocenia profilu timeoutu. Ten temat pozostaje odlozony, bo wymaga spokojnej obserwacji po otwarciu rynku i nie powinien byc mieszany z nowymi filtrami wejsc jednoczesnie.

## Uwaga o jakosci danych

Po rozszerzeniu schematu journala akcji stary `tuning_actions.csv` dla `EURUSD` zostal odlozony do archiwum, zeby nie mieszac starego i nowego ukladu kolumn w jednym pliku. To bylo celowe porzadkowanie, nie blad runtime.
