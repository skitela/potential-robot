#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import tkinter as tk
except Exception:  # pragma: no cover
    tk = None

try:
    from TOOLS.lab_guardrails import ensure_write_parent, resolve_lab_data_root
except Exception:  # pragma: no cover
    from lab_guardrails import ensure_write_parent, resolve_lab_data_root

UTC = dt.timezone.utc
SCHEMA = "oanda.mt5.stage1_operator_decision.v1"


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _read_optional(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return _load_json(path)
    except Exception:
        return {}


def _build_message(
    gonogo: Dict[str, Any],
    iteration: Dict[str, Any],
    coverage: Dict[str, Any],
) -> Tuple[str, str, List[Tuple[str, str]], str]:
    verdict = str(gonogo.get("verdict") or "").upper()
    status = str(gonogo.get("status") or "").upper()
    reason = str(gonogo.get("reason") or "")
    coverage_status = str(coverage.get("status") or "")
    coverage_reason = str(coverage.get("reason") or "")
    blockers = coverage.get("actions_by_symbol") if isinstance(coverage.get("actions_by_symbol"), list) else []
    blockers_n = len(blockers)

    title = "Decyzja operatora - etap 1"
    report_path = str((gonogo.get("checks") or [{}])[-1].get("source") or "") if isinstance(gonogo.get("checks"), list) and gonogo.get("checks") else ""

    if verdict == "NO-GO":
        body = (
            "Wdrozenie zostalo zatrzymane przez warunek bezpieczenstwa.\n\n"
            "Co to oznacza:\n"
            "- Nie wolno wdrazac nowych ustawien.\n"
            "- Handel pozostaje na poprzednich stabilnych ustawieniach.\n"
            "- Ochrona kapitalu dziala i nie pozwala na ryzykowne zmiany.\n\n"
            "Konsekwencja decyzji:\n"
            "- Potwierdz wstrzymanie: utrzymujemy obecny stan i analizujemy blad.\n"
            "- Otworz raport: przechodzisz od razu do szczegolow blokady.\n\n"
            f"Status: {status or 'BRAK'} | Powod: {reason or 'BRAK'}"
        )
        actions = [
            ("POTWIERDZ_WSTRZYMANIE", "Potwierdz wstrzymanie"),
            ("OTWORZ_RAPORT", "Otworz raport"),
        ]
        return title, body, actions, report_path

    if verdict == "PASS":
        body = (
            "Analiza zakonczona poprawnie.\n\n"
            "Co to oznacza:\n"
            "- Proponowane ustawienia sa gotowe do dalszego kroku.\n"
            "- Ochrona kapitalu pozostaje aktywna bez zmian.\n"
            "- Handel i skalping moga dzialac dalej.\n\n"
            "Konsekwencja decyzji:\n"
            "- Zatwierdz: przechodzimy do kontrolowanego wdrozenia.\n"
            "- Wstrzymaj: zostajemy przy obecnych ustawieniach.\n"
        )
        actions = [
            ("ZATWIERDZ", "Zatwierdz"),
            ("WSTRZYMAJ", "Wstrzymaj"),
        ]
        return title, body, actions, report_path

    # REVIEW_REQUIRED / brak jasnego PASS
    body = (
        "Potrzebna decyzja operatora, bo dane sa niepelne.\n\n"
        "Co to oznacza:\n"
        "- To nie jest awaria.\n"
        "- Automatyczna zmiana ustawien moze byc przedwczesna.\n"
        "- Ochrona kapitalu dziala: niedozwolone zmiany sa blokowane.\n\n"
        f"Stan pokrycia danych: {coverage_status or 'BRAK'} ({coverage_reason or 'BRAK'}).\n"
        f"Liczba instrumentow z brakami: {blockers_n}.\n\n"
        "Konsekwencja decyzji:\n"
        "- Zatwierdz warunkowo: zmiany tylko tam, gdzie dane sa wystarczajace.\n"
        "- Wstrzymaj i dozbieraj dane: brak zmian profili teraz, zbieramy dane.\n"
        "- Odrzuc: nie wdrazamy zmian.\n"
    )
    actions = [
        ("ZATWIERDZ_WARUNKOWO", "Zatwierdz warunkowo"),
        ("WSTRZYMAJ_I_DOZBIERAJ_DANE", "Wstrzymaj i dozbieraj dane"),
        ("ODRZUC", "Odrzuc"),
    ]
    return title, body, actions, report_path


def _show_popup(title: str, body: str, actions: List[Tuple[str, str]], auto_action: str = "") -> str:
    if auto_action:
        return auto_action

    if tk is None:
        return actions[0][0]

    chosen = {"value": actions[0][0]}
    root = tk.Tk()
    root.title(title)
    root.geometry("780x520")
    root.resizable(False, False)

    lbl = tk.Label(root, text=title, font=("Segoe UI", 14, "bold"), anchor="w", justify="left")
    lbl.pack(fill="x", padx=16, pady=(12, 6))

    msg = tk.Message(root, text=body, width=740, font=("Segoe UI", 11), justify="left")
    msg.pack(fill="both", expand=True, padx=16, pady=(4, 8))

    frame = tk.Frame(root)
    frame.pack(fill="x", padx=16, pady=(0, 14))
    for code, label in actions:
        def _pick(c: str = code) -> None:
            chosen["value"] = c
            root.destroy()
        b = tk.Button(frame, text=label, width=24, command=_pick)
        b.pack(side="left", padx=6)

    root.mainloop()
    return chosen["value"]


def _append_jsonl(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")


def _decision_consequence(action: str) -> str:
    mapping = {
        "ZATWIERDZ": "System przechodzi do kontrolowanego wdrozenia.",
        "WSTRZYMAJ": "System pozostaje na obecnych ustawieniach.",
        "POTWIERDZ_WSTRZYMANIE": "Wdrozenie zmian pozostaje zablokowane do czasu naprawy problemu.",
        "OTWORZ_RAPORT": "Otwieram raport i pozostawiam system bez zmian.",
        "ZATWIERDZ_WARUNKOWO": "Zmiany tylko dla instrumentow z wystarczajacymi danymi.",
        "WSTRZYMAJ_I_DOZBIERAJ_DANE": "Brak zmian teraz, priorytet to zebranie brakujacych danych.",
        "ODRZUC": "Brak wdrozenia, pozostaje poprzednia konfiguracja.",
    }
    return mapping.get(action, "Brak zmiany konfiguracji do czasu kolejnej decyzji operatora.")


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Okno decyzji operatora dla etapu 1 (komunikaty po polsku).")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--no-gui", action="store_true")
    ap.add_argument("--auto-action", default="", help="Kod decyzji do testow/automatyki, np. WSTRZYMAJ_I_DOZBIERAJ_DANE")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    now = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    stage1_reports = (lab_data_root / "reports" / "stage1").resolve()
    run_dir = (lab_data_root / "run").resolve()

    gonogo = _read_optional((stage1_reports / "stage1_shadow_gonogo_latest.json").resolve())
    iteration = _read_optional((stage1_reports / "stage1_iteration_audit_latest.json").resolve())
    coverage = _read_optional((stage1_reports / "stage1_coverage_recovery_latest.json").resolve())

    title, body, actions, report_path = _build_message(gonogo, iteration, coverage)
    action_codes = [x[0] for x in actions]
    auto_action = str(args.auto_action or "").strip().upper()
    if auto_action and auto_action not in action_codes:
        print(f"STAGE1_OPERATOR_POPUP_DONE status=FAIL reason=INVALID_AUTO_ACTION action={auto_action}")
        return 2

    chosen = action_codes[0]
    if args.no_gui:
        chosen = auto_action or action_codes[0]
        print(title)
        print(body)
        print(f"Wybrana decyzja: {chosen}")
    else:
        chosen = _show_popup(title, body, actions, auto_action=auto_action)

    if chosen == "OTWORZ_RAPORT" and report_path:
        try:
            if os.name == "nt":
                os.startfile(report_path)  # type: ignore[attr-defined]
        except Exception as exc:
            _ = exc
    record = {
        "schema": SCHEMA,
        "generated_at_utc": iso_utc(now),
        "title": title,
        "selected_action": chosen,
        "consequence": _decision_consequence(chosen),
        "stage1_shadow_gonogo_verdict": str(gonogo.get("verdict") or ""),
        "stage1_shadow_gonogo_status": str(gonogo.get("status") or ""),
        "coverage_status": str(coverage.get("status") or ""),
        "coverage_reason": str(coverage.get("reason") or ""),
        "report_path": report_path,
    }

    out_dir = ensure_write_parent((run_dir / "operator_decisions" / "stage1_operator_decision_latest.json").resolve(), root=root, lab_data_root=lab_data_root).parent
    out_dir.mkdir(parents=True, exist_ok=True)
    stamped = out_dir / f"stage1_operator_decision_{now.strftime('%Y%m%dT%H%M%SZ')}.json"
    latest = out_dir / "stage1_operator_decision_latest.json"
    audit_jsonl = ensure_write_parent((run_dir / "operator_decisions" / "stage1_operator_decision_audit.jsonl").resolve(), root=root, lab_data_root=lab_data_root)

    stamped.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    latest.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    _append_jsonl(audit_jsonl, record)

    print(f"STAGE1_OPERATOR_POPUP_DONE status=PASS action={chosen} latest={latest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
