# Runtime Priority And Weakest-First V1

## Cel

Zamienic reczne wybieranie kolejnych instrumentow na automatyczny porzadek oparty o:
- aktualny runtime z VPS
- stan trust/cost/sample z execution summary
- ostatni wynik testera

## Co dodano

- automatyczny raport kolejkowania:
  - `RUN\BUILD_TUNING_PRIORITY_REPORT.ps1`
- pakiet danych QDM dla najslabszych:
  - `TOOLS\qdm_weakest_pack.csv`
- batch testera dla najslabszych:
  - `RUN\RUN_WEAKEST_MT5_BATCH.ps1`
  - `RUN\START_WEAKEST_MT5_BATCH_BACKGROUND.ps1`
- launcher weakest-first:
  - `RUN\START_WEAKEST_FIRST_LAB.ps1`
- lokalny summary pokazuje juz top kolejki weakest-first

## Zasada kolejkowania

Najwyzszy priorytet dostaja instrumenty, ktore lacza:
- slaby trust state
- slaby cost state
- mala probke lub bardzo zly bias
- ujemny runtime 24h przy realnej aktywnosci

To daje porzadek:
- najpierw naprawa najgorszych miejsc
- potem live-active przegrani
- na koncu instrumenty juz czesciowo dostrojone

## Granice

- raport priorytetow nie zmienia sam kodu strategii
- nadal tylko czlowiek akceptuje delty do MQL5
- QDM i ML zostaja warstwami pomocniczymi, a MT5/OANDA zostaje glownym testerem i prawda brokerska
