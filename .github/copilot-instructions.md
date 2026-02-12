# DYRYGENT — stałe instrukcje dla GitHub Copilot (VS Code)
**System:** OANDA MT5 System (Windows)  
**TWARDY ROOT:** `C:\OANDA_MT5_SYSTEM`  
**Cel:** Egzekwować limity operacyjne OANDA TMS (PL) + jakość techniczną, **bez zmiany strategii**.

> Te instrukcje mają działać automatycznie w VS Code/Copilot dla całego workspace.  
> Jeśli odpowiedź nie spełnia wymaganego formatu (META + unified diff + TESTPLAN) → traktuj jako `INVALID_OUTPUT`.

---

## 0) HARD CONSTRAINTS (NON-NEGOTIABLE)
- **Nie wolno** modyfikować strategii/polityki tradingowej: reguł wejść/wyjść, generowania sygnałów, modelu ryzyka, sizingu/volume/lot, SL/TP, logiki decyzyjnych “godzin”, ani parametrów wpływających na decyzje transakcyjne.
- Dozwolone zmiany: guardrails techniczne, throttling, caching, instrumentacja, logi, obsługa błędów/timeouty, stałe limitów, testy, tooling release/audytu, repo hygiene (§8).
- „PASS” tylko z artefaktami **EVIDENCE + VERDICT** (§7). Inaczej: **NOT VERIFIED**.
- Repo hygiene: zawsze **SCAN→CLEANUP**, zawsze **PASS/rollback**, **nigdy w LIVE** (§8).

## 1) QUALITY TARGETS — 16 PRZYMIOTNIKÓW (MAJĄ BYĆ “ZAKODOWANE” JAKO CHECKI)
Stable; Unhangable; Deterministic (release); Auditable; Broker-compliant; Secure; Predictable; Resilient; Frugal; Fast; Readable; Modular; Repairable; Observable; Profit-friendly (operational-loss reduction only); Not-overloaded (repo hygiene).

**Definicja “Profit-friendly”:** redukcja strat operacyjnych (awarie, błędy egzekucji, blokady limitów, zbędne requesty), **nie tuning strategii**.

## 2) OFFICIAL LIMITS — AUTHORITATIVE FACTS (POLAND / OANDA TMS / MT5)
2.1 Daily price-request limits (Doc 14 “Terms and Conditions…”, identifier: REGUM20260206)  
- Appendix 3 “Limits on the number of requests for price submitted”, Page 60/63.  
- Verbatim excerpt:  
  "Warning level 1000 requests per calendar day"  
  "Cut-off level 5000 requests per calendar day"

2.2 Consequence of exceeding thresholds (Doc 14, REGUM20260206)  
- §18 “Manner and conditions of placing Orders online”, Page 15/63 (clauses 4–5).  
- Meaning:  
  - After warning: broker can require reviewing/modifying algorithmic mechanisms OR limiting number of queries.  
  - After cut-off: broker can block electronic access to the Trading System; revocation only exceptional.

2.3 Execution-time rule for CFDs (Doc 31 “Best Execution Policy”, identifier: BEPL20250331)  
- Clause 5.16, PDF page 7/18.  
- Verbatim excerpt:  
  "executes orders within 180 seconds (after that time, orders are rejected)"

2.4 Operational limits on orders and positions (Doc 14, REGUM20260206)  
- Appendix 4 “Limits on the number of Orders placed and Positions held”, Page 61/63.  
- Extracted constraints (values MUST match):  
  - Max market orders submission rate: **50 orders per second** (market orders).  
  - Max simultaneous “Positions + pending orders” aggregated: **500 total** (TP/SL excluded).

## 3) REQUIRED HOUSE SAFETY MARGINS (DO NOT LOOSEN)
- SOFT_WARN_REQUESTS_DAY = 1000  
- HARD_STOP_REQUESTS_DAY = 4500 (house stop before broker 5000)  
- HARD_STOP_ORDERS_SEC = 45 (house stop before broker 50)  
- HARD_STOP_SIMULTANEOUS = 450 (house stop before broker 500)

## 4) DEFINITIONS FOR THIS AUDIT (IMPLEMENT EXACTLY)
4.1 “Price request”  
+1 dla każdego wywołania pobierającego ceny/rynek z MT5/brokera, np.:  
- symbol_info_tick, symbol_info, copy_ticks_*, copy_rates_*, market_book_get, ticks/quotes getters,  
- każde repo-wrapper, które finalnie pobiera BID/ASK/OHLC z MT5.  
Nie liczyć obliczeń lokalnych na danych już pobranych.

4.2 “Order submission”  
+1 dla każdej próby złożenia zlecenia rynkowego (oraz pending, jeśli repo je składa).  
Wymuś house stop **<=45/s** (market orders), a pozostałe submissions throttluj konserwatywnie.

4.3 “Simultaneous positions + pending”  
W każdym momencie: PositionsTotal + OrdersTotal **<= 450** (house stop; TP/SL excluded).

4.4 Calendar-day ambiguity  
Dwa liczniki; egzekwuj surowszy wynik:  
- Counter A: UTC calendar day (00:00–23:59 UTC)  
- Counter B: rolling 24-hour window  
Jeśli którykolwiek osiągnie stop: SAFE MODE + stop nowych requestów.

## 5) STRATEGY DEFINITION (STOP SCOPE FIGHTS)
Plik/funkcja jest STRATEGIC, jeśli:  
- definiuje sygnały wejść/wyjść lub bramki decyzyjne trade,  
- liczy/ustawia SL/TP, volume/lot sizing, risk budgets,  
- decyduje KIEDY/CO/ILE/JAK handlować,  
- zmienia parametry używane w decyzjach tradingowych.

Mechanizm: utrzymuj `STRATEGY_FILES.txt` i `STRATEGY_SYMBOLS.txt`.  
Jeśli dotykasz strategii → `STRATEGY_TOUCH=YES` → `NEEDS_REVIEW` → STOP auto-merge.

## 6) REQUIRED IMPLEMENTATION (ALLOWED CHANGE)
Centralny guard (np. `CORE/oanda_limits_guard.py`) musi zapewniać:  
- thread-safe counters dla price requests (UTC day + rolling 24h) + **persist to disk** (restart-safe),  
- rate limiter dla order submissions (sliding window per second),  
- exposure guard: positions+pending przed każdą próbą zlecenia,  
- SAFE MODE: po hard stop → read-only (no new orders; minimal price requests; logs + alert).

## 7) EVIDENCE + VERDICT (MANDATORY)
Każdy patch kończy się artefaktami:  
- `EVIDENCE/oanda_limits_audit_report.md` (stałe + call-sites file+lines + reproduce)  
- `EVIDENCE/oanda_limits_state.json` (utc_day_id/count; rolling window; orders/sec; last_safe_mode_reason)  
- `VERDICT.json` zawierający:
  - status PASS|WARN|FAIL|FAIL_APPLY|NEEDS_REVIEW|BLOCKED
  - reasons, files_touched, strategy_touch, limits_touch, cleanup_touch

## 8) “NOT-OVERLOADED” REPO HYGIENE (CRITICAL)
8.1 SCAN→CLEANUP  
- SCAN: tylko raporty (EVIDENCE/repo_hygiene_scan.json + .md), **zero kasowania**.  
- CLEANUP: usuwa **tylko** SAFE_TO_REMOVE, które są też na `CLEANUP_ALLOWLIST.txt`.  
- Jeśli CLEANUP nie przejdzie testów → rollback.

8.2 Ruff/Vulture = pomocnicze, mogą dawać false-positive  
- Obowiązkowe listy:  
  - `CLEANUP_ALLOWLIST.txt`  
  - `CLEANUP_DENYLIST.txt` (musi obejmować: EVIDENCE/, DIAG/, runbooki/policies, entrypointy bez ręcznego review)

8.3 git clean bezpieczeństwo  
- Zakaz: `git clean -fd` na repo-root bez whitelist.  
- Dozwolone: `git clean -n` (dry-run) → zapis do EVIDENCE → potem ograniczone czyszczenie tylko cache/build.

## 9) FORMAT ODPOWIEDZI (DLA PATCHY / ZMIAN)
Zawsze zwracaj:
META:
  STRATEGY_TOUCH=NO|YES
  LIMITS_TOUCH=NO|YES
  CLEANUP_TOUCH=NO|YES
  FILES_TOUCHED=<int>
  RISK=LOW|MED|HIGH
PATCH:
  ```diff
  (unified diff, git-style a/... b/...)
  ```
TESTPLAN:
  (max 10 linii; py_compile/compileall + guard harness + verify_evidence)

---
