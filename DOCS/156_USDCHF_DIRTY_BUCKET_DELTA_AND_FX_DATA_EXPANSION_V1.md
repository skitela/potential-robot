# USDCHF Dirty Bucket Delta And FX Data Expansion V1

## Co zrobiono

- dodano w `MicroBot_USDCHF.mq5` wąskie blokady dla dwóch toksycznych bucketow paper:
  - `SETUP_TREND / CHAOS / LOW / POOR candle / POOR renko`
  - `SETUP_REJECTION / CHAOS / LOW / POOR candle / POOR renko`
- podniesiono lokalnie paper gate dla `USDCHF` w trendzie i rejection, ale tylko dla slabych bucketow
- przygotowano pelny profil `QDM` dla calego FX:
  - `qdm_fx_full_pack.csv`
- dodano launcher pod pelny sync FX:
  - `START_QDM_FX_FULL_SYNC_BACKGROUND.ps1`
- oczyszczono `BUILD_TUNING_PRIORITY_REPORT.ps1`, zeby ignorowal puste summary po nieudanych batchach

## Dlaczego

Z biezacego sandboxu `USDCHF` wynikalo:
- `learning_sample_count = 12`
- `learning_win_count = 0`
- `learning_loss_count = 12`
- najgorsze buckety:
  - `SETUP_TREND / CHAOS` avg_pnl `-0.9125`
  - `SETUP_REJECTION / CHAOS` avg_pnl `-0.7375`
- kandydaci otwierali paper w bucketach `LOW / POOR / POOR`, ktore nie dawaly zadnej wygranej

To uzasadnia mala chirurgiczna blokade bucketu, a nie szerokie strojenie calej strategii.

## Co odczytano z live dla SILVER

Nie przyjeto zmiany sygnalu dla `SILVER` w tej rundzie, bo live pokazuje glownie:
- `PORTFOLIO_HEAT_BLOCK`
- `FREEZE_FAMILY`
- `FREEZE_FLEET`
- `RISK_CONTRACT_BLOCK`

Czyli najpierw trzeba uderzyc w kontrakt i pressure runtime, nie w sama logike setupu.

## Stan po rundzie

- `USDCHF` ma uruchomiony czysty retest po zmianie
- weakest-first raport jest czystszy i nie lapie pustych summary jako najnowszych wynikow
- tor danych jest przygotowany do rozszerzenia z core FX na cale okno FX
