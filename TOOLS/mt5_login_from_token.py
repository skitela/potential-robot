# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from BIN.safetybot import load_env


def utc_id() -> str:
    return time.strftime("%Y%m%d_%H%M%S", time.gmtime())


def main() -> int:
    ap = argparse.ArgumentParser(description="Logowanie MT5 z lokalnego TOKEN/BotKey.env")
    ap.add_argument("--token-root", required=True, help="Katalog główny woluminu OANDAKEY, np. K:\\")
    ap.add_argument("--mt5-path", required=True, help="Ścieżka do terminal64.exe")
    ap.add_argument("--out-dir", default=str(ROOT / "RUN" / "DIAG_REPORTS"), help="Katalog raportów")
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_json = out_dir / f"MT5_LOGIN_FROM_TOKEN_{utc_id()}.json"

    report = {
        "schema_version": 1,
        "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "token_root": args.token_root,
        "mt5_path": args.mt5_path,
        "initialize": False,
        "login": False,
        "last_error": None,
        "account": None,
        "terminal": None,
        "error": None,
        "result": "FAIL",
    }

    try:
        import MetaTrader5 as mt5
    except Exception as e:
        report["error"] = f"import MetaTrader5 failed: {e}"
        out_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"MT5_LOGIN_FROM_TOKEN_FAIL report={out_json}")
        return 2

    try:
        cfg = load_env(Path(args.token_root))
        login = int(str(cfg["MT5_LOGIN"]).strip())
        password = str(cfg["MT5_PASSWORD"]).strip()
        server = str(cfg.get("MT5_SERVER", "OANDATMS-MT5")).strip() or "OANDATMS-MT5"

        ok = mt5.initialize(args.mt5_path)
        report["initialize"] = bool(ok)
        report["last_error"] = mt5.last_error()
        if not ok:
            report["error"] = "mt5.initialize returned False"
            out_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
            print(f"MT5_LOGIN_FROM_TOKEN_FAIL report={out_json}")
            return 3

        logged = mt5.login(login=login, password=password, server=server)
        report["login"] = bool(logged)
        report["last_error"] = mt5.last_error()

        acc = mt5.account_info()
        if acc is not None:
            report["account"] = {
                "login": getattr(acc, "login", None),
                "server": getattr(acc, "server", None),
                "trade_allowed": bool(getattr(acc, "trade_allowed", False)),
                "trade_expert": bool(getattr(acc, "trade_expert", False)),
            }
        ti = mt5.terminal_info()
        if ti is not None:
            report["terminal"] = {
                "connected": bool(getattr(ti, "connected", False)),
                "trade_allowed": bool(getattr(ti, "trade_allowed", False)),
                "tradeapi_disabled": bool(getattr(ti, "tradeapi_disabled", False)),
                "name": getattr(ti, "name", None),
                "company": getattr(ti, "company", None),
            }

        report["result"] = "PASS" if logged else "FAIL"
        out_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        if logged:
            print(f"MT5_LOGIN_FROM_TOKEN_OK report={out_json}")
            return 0
        print(f"MT5_LOGIN_FROM_TOKEN_FAIL report={out_json}")
        return 4
    except Exception as e:
        report["error"] = str(e)
        out_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"MT5_LOGIN_FROM_TOKEN_FAIL report={out_json}")
        return 5
    finally:
        try:
            import MetaTrader5 as mt5
            mt5.shutdown()
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
