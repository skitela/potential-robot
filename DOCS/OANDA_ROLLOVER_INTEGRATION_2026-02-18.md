# OANDA Rollover Integration (MT5)

Date: 2026-02-18

## Confirmed from OANDA pages

1. OANDA FAQ (PL): rollover is a periodic switch to the next futures contract and happens after end of trading day for the instrument.  
   Source: https://help.oanda.com/pl/pl/faqs/indices-rollover.htm

2. OANDA rollover list page contains dated entries by symbol.  
   Source: https://www.oanda.com/eu-en/rollover-lists

3. Confirmed row observed on the list page:
   - 2026-03-18 | US30.pro

## Practical implementation in this repo

1. Keep existing daily protection window around 17:00 New York time.
2. Add quarterly index rollover guard:
   - default months: 3, 6, 9, 12
   - default roll day: third Friday minus 2 days (Wednesday)
   - default anchor time: 17:00 New York time
3. Add `CONFIG/rollover_events.json` to:
   - override quarterly defaults,
   - define explicit event dates/hours per symbol group.

## 2026 quarterly dates from the implemented rule

- 2026-03-18
- 2026-06-17
- 2026-09-16
- 2026-12-16

Note: explicit broker timetable should still be checked each quarter on OANDA rollover list.
