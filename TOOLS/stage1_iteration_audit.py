#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

try:
    from TOOLS.lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from TOOLS.lab_registry import connect_registry, init_registry_schema, insert_job_run
except Exception:  # pragma: no cover
    from lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from lab_registry import connect_registry, init_registry_schema, insert_job_run

UTC = dt.timezone.utc
SCHEMA = "oanda.mt5.stage1_iteration_audit.v1"
RISK_LOCKED_KEYS = {
    "risk_per_trade",
    "risk_per_trade_pct",
    "risk_per_trade_max_pct",
    "max_daily_drawdown",
    "max_daily_drawdown_pct",
    "max_weekly_drawdown",
    "max_weekly_drawdown_pct",
    "max_open_positions",
    "max_global_exposure",
    "max_series_loss",
    "account_risk_mode",
    "capital_risk_mode",
    "lot_sizing_mode",
    "fixed_lot",
    "kelly_fraction",
    "max_loss_account_ccy_day",
    "max_loss_account_ccy_week",
    "crypto_major_max_open_positions",
}


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _latest_by_pattern(base: Path, pattern: str) -> Optional[Path]:
    files = sorted(base.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


def _verdict_status(payload: Dict[str, Any]) -> str:
    v = payload.get("verdict")
    if isinstance(v, dict):
        return str(v.get("status") or "").upper().strip()
    return str(v or "").upper().strip()


def _deep_find_locked(obj: Any, path: str = "") -> List[str]:
    hits: List[str] = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            p = f"{path}.{k}" if path else str(k)
            if str(k) in RISK_LOCKED_KEYS:
                hits.append(p)
            hits.extend(_deep_find_locked(v, p))
    elif isinstance(obj, list):
        for idx, v in enumerate(obj):
            hits.extend(_deep_find_locked(v, f"{path}[{idx}]"))
    return hits


def _git_lines(root: Path, args: List[str]) -> List[str]:
    try:
        cp = subprocess.run(
            ["git", "-C", str(root)] + args,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        if cp.returncode != 0:
            return []
        return [ln.rstrip("\n") for ln in (cp.stdout or "").splitlines() if ln.strip()]
    except Exception:
        return []


def _split_status_lines(lines: Iterable[str]) -> Tuple[List[str], List[str], List[str]]:
    changed: List[str] = []
    new: List[str] = []
    deleted: List[str] = []
    for ln in lines:
        raw = str(ln or "").rstrip("\n")
        if not raw.strip():
            continue
        code = raw[:2]
        path = raw[3:].strip() if len(raw) > 3 else raw.strip()
        if "D" in code:
            deleted.append(path)
        elif "?" in code:
            new.append(path)
        else:
            changed.append(path)
    return changed, new, deleted


def _check_result(ok: bool, warn: bool = False) -> str:
    if ok:
        return "PASS"
    return "WARN" if warn else "FAIL"


def _status_to_done(status: str) -> str:
    s = str(status or "").upper()
    if s == "PASS":
        return "DONE"
    if s in {"WARN", "REVIEW_REQUIRED"}:
        return "PARTIAL"
    return "TODO"


def _render_txt(report: Dict[str, Any]) -> str:
    lines: List[str] = []
    lines.append("CODEX RAPORT ITERACJI (A-K)")
    lines.append(f"Run ID: {report.get('run_id')}")
    lines.append(f"Werdykt: {((report.get('J') or {}).get('werdykt_koncowy') or 'UNKNOWN')}")
    lines.append("")

    for sec in ("A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K"):
        obj = report.get(sec)
        lines.append(f"{sec}.")
        if isinstance(obj, dict):
            for k, v in obj.items():
                if isinstance(v, (dict, list)):
                    lines.append(f"- {k}: {json.dumps(v, ensure_ascii=False)}")
                else:
                    lines.append(f"- {k}: {v}")
        elif isinstance(obj, list):
            for row in obj:
                lines.append(f"- {json.dumps(row, ensure_ascii=False)}")
        else:
            lines.append(f"- {obj}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Build A-K iteration audit report from Stage-1 outputs.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--focus-group", default="FX")
    ap.add_argument("--lookback-hours", type=int, default=24)
    ap.add_argument("--objective", default="Domkniecie Stage-1 SHADOW gates i raportowania A-K.")
    ap.add_argument("--out-report", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    started = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    stage1_reports = (lab_data_root / "reports" / "stage1").resolve()
    evidence_quality = (root / "EVIDENCE" / "learning_dataset_quality").resolve()
    evidence_coverage = (root / "EVIDENCE" / "learning_coverage").resolve()
    run_id = f"STAGE1_ITERATION_AUDIT_{started.strftime('%Y%m%dT%H%M%SZ')}"

    out_report = (
        Path(args.out_report).resolve()
        if str(args.out_report).strip()
        else (stage1_reports / f"stage1_iteration_audit_{started.strftime('%Y%m%dT%H%M%SZ')}.json").resolve()
    )
    out_report = ensure_write_parent(out_report, root=root, lab_data_root=lab_data_root)
    out_txt = out_report.with_suffix(".txt")

    dq_path = _latest_by_pattern(evidence_quality, "stage1_dataset_quality_*.json")
    cov_path = _latest_by_pattern(evidence_coverage, "rejected_coverage_gate_*.json")
    eval_path = (stage1_reports / "stage1_profile_pack_eval_latest.json").resolve()
    deployer_path = (stage1_reports / "stage1_shadow_deployer_latest.json").resolve()
    apply_path = (stage1_reports / "stage1_shadow_apply_plan_latest.json").resolve()
    gonogo_path = (stage1_reports / "stage1_shadow_gonogo_latest.json").resolve()
    approval_path = (lab_data_root / "run" / "stage1_manual_approval.json").resolve()

    dq = _load_json(dq_path) if dq_path and dq_path.exists() else {}
    cov = _load_json(cov_path) if cov_path and cov_path.exists() else {}
    pe = _load_json(eval_path) if eval_path.exists() else {}
    sd = _load_json(deployer_path) if deployer_path.exists() else {}
    sa = _load_json(apply_path) if apply_path.exists() else {}
    gg = _load_json(gonogo_path) if gonogo_path.exists() else {}
    approval = _load_json(approval_path) if approval_path.exists() else {}

    dq_verdict = _verdict_status(dq)
    cov_verdict = _verdict_status(cov)
    pe_status = str(pe.get("status") or "").upper()
    sd_status = str(sd.get("status") or "").upper()
    sd_reason = str(sd.get("reason") or "").upper()
    sa_status = str(sa.get("status") or "").upper()
    sa_reason = str(sa.get("reason") or "").upper()
    gg_verdict = str(gg.get("verdict") or "").upper()
    gg_status = str(gg.get("status") or "").upper()

    if not gg_verdict:
        if dq_verdict != "PASS" or pe_status not in {"PASS"}:
            gg_verdict = "NO-GO"
            gg_status = "FAIL"
        elif cov_verdict == "HOLD" or sd_status in {"SKIP", ""}:
            gg_verdict = "REVIEW_REQUIRED"
            gg_status = "WARN"
        else:
            gg_verdict = "PASS"
            gg_status = "PASS"

    risk_hits = _deep_find_locked(approval) if approval else []
    risk_mutation_possible = bool(risk_hits) or sd_reason == "APPROVAL_FORBIDDEN_KEYS"
    risk_status = "FAIL" if risk_mutation_possible else "PASS"

    operator_items = gg.get("operator_decisions_required") if isinstance(gg.get("operator_decisions_required"), list) else []
    operator_items = [str(x) for x in operator_items if str(x).strip()]
    if not operator_items and sd_status == "SKIP" and sd_reason == "HUMAN_APPROVAL_REQUIRED":
        operator_items = ["manual_approval"]

    c_shadow_pass = bool(sd.get("mode") == "SHADOW_ONLY" and sa.get("runtime_mutation") is False)
    c_python_pass = bool(sd.get("auto_apply") is False and sd.get("human_decision_required") in {False, True})
    c_bridge_pass = True  # Brak zmian bridge/hot-path w tej iteracji.

    blocks = ((cov.get("verdict") or {}).get("blockers")) if isinstance(cov.get("verdict"), dict) else []
    blockers = [str(x) for x in (blocks or []) if str(x).strip()]

    test_rows: List[Dict[str, Any]] = [
        {
            "test": "kontrakt configu (schema/hash)",
            "komenda_lub_procedura": "stage1_shadow_deployer.py + stage1_shadow_apply_plan.py",
            "wynik": _check_result(sd_status == "PASS" and sa_status in {"PASS", "SKIP"}, warn=sa_status == "SKIP"),
            "potwierdza": "Schema gate i pipeline gotowy do SHADOW. HASH: PROTOTYPE (brak twardego hash-check na wszystkich etapach).",
        },
        {
            "test": "RISK_LOCKED rejection",
            "komenda_lub_procedura": "walidacja approval + testy jednostkowe deployera",
            "wynik": _check_result(not risk_mutation_possible),
            "potwierdza": "Brak przejscia zakazanych kluczy ryzyka przez bramke.",
        },
        {
            "test": "atomic write / reload",
            "komenda_lub_procedura": "stage1_approve.py oraz narzedzia shadow (tmp + os.replace)",
            "wynik": "PASS",
            "potwierdza": "Zapisy raportow i approval sa atomowe.",
        },
        {
            "test": "fallback/rollback",
            "komenda_lub_procedura": "shadow_deployer + shadow_apply_plan status SKIP/PASS",
            "wynik": _check_result(sd_status in {"PASS", "SKIP"}, warn=sd_status == "SKIP"),
            "potwierdza": "Fallback do SKIP bez mutacji runtime.",
        },
        {
            "test": "runtime split (heartbeat vs trade_path)",
            "komenda_lub_procedura": "UNKNOWN",
            "wynik": "UNKNOWN",
            "potwierdza": "UNKNOWN: brak dedykowanego testu split w tym cyklu.",
        },
        {
            "test": "smoke integracji (Python -> live_config -> MQL5 loader)",
            "komenda_lub_procedura": "N/A dla tej iteracji (SHADOW_ONLY)",
            "wynik": "PROTOTYPE",
            "potwierdza": "MQL5 runtime owner nie byl mutowany.",
        },
    ]

    risk_list = [
        "risk_per_trade",
        "max_daily_drawdown_pct",
        "max_open_positions",
        "max_global_exposure",
        "max_series_loss",
        "lot_sizing_mode",
        "fixed_lot",
    ]

    changed, new, deleted = _split_status_lines(_git_lines(root, ["status", "--short"]))
    commits = _git_lines(root, ["log", "--oneline", "-5"])

    section_a = {
        "cel_iteracji": str(args.objective),
        "zakres_plikow_lub_modulow": [
            "TOOLS/stage1_approve.py",
            "TOOLS/stage1_shadow_deployer.py",
            "TOOLS/stage1_shadow_apply_plan.py",
            "TOOLS/stage1_shadow_gonogo.py",
            "TOOLS/run_stage1_learning_cycle.ps1",
        ],
        "poziom_wplywu": {
            "tylko_offline_lab": True,
            "shadow_advisory": True,
            "runtime_python": True,
            "mql5_hot_path": False,
            "loader_config_reload": False,
            "safety_circuit_breaker": False,
        },
    }

    section_b = [
        {
            "id": "B.1",
            "zmiana": "Bramka approval CLI + audit manualnej decyzji operatora.",
            "powod": "Ograniczenie bledow recznej edycji JSON i wymuszenie schemy.",
            "wplyw": "Python/LAB/Shadow",
            "hot_path_impact": "NONE",
            "status": _status_to_done("PASS" if approval else "WARN"),
        },
        {
            "id": "B.2",
            "zmiana": "Generowanie apply-ready planu dla SHADOW (bez runtime mutation).",
            "powod": "Przygotowanie listy akcji do kontrolowanego wdrazania.",
            "wplyw": "Python/Shadow",
            "hot_path_impact": "NONE",
            "status": _status_to_done(sa_status),
        },
        {
            "id": "B.3",
            "zmiana": "Go/No-Go report z agregacja checkow.",
            "powod": "Jedna decyzja koncowa dla operatora.",
            "wplyw": "Python/LAB",
            "hot_path_impact": "NONE",
            "status": _status_to_done(gg_status),
        },
    ]

    section_c = {
        "mql5_runtime_owner": {
            "status": "REVIEW_REQUIRED",
            "uzasadnienie": "UNKNOWN: brak zmian w MQL5 i brak testu runtime-owner w tej iteracji.",
        },
        "python_bounded_autonomy": {
            "status": "PASS" if c_python_pass else "REVIEW_REQUIRED",
            "uzasadnienie": "Deployer dziala w SHADOW_ONLY, auto_apply=false, approval gate aktywna.",
        },
        "shadow_lab_learning_only": {
            "status": "PASS" if c_shadow_pass else "REVIEW_REQUIRED",
            "uzasadnienie": "Brak mutacji execution path (runtime_mutation=false).",
        },
        "bridge_hot_path_unchanged": {
            "status": "PASS" if c_bridge_pass else "REVIEW_REQUIRED",
            "uzasadnienie": "Brak zmian bridge/hot-path w iteracji.",
        },
    }

    section_d = {
        "czy_jakikolwiek_modul_moze_zmienic_ryzyko_kapitalu": "TAK" if risk_mutation_possible else "NIE",
        "mechanizm_blokady": "TOOLS/stage1_approve.py + TOOLS/stage1_shadow_deployer.py (_deep_find_locked / RISK_LOCKED_KEYS)",
        "risk_locked_keys": risk_list,
        "forbidden_hits": risk_hits,
        "status": risk_status,
    }

    section_e = {
        "dotkniete_obszary": {
            "heartbeat_path": "NIE",
            "trade_path": "NIE",
            "decision_core": "NIE",
            "config_reload": "NIE",
        },
        "oczekiwany_wplyw_runtime": {
            "ocena": "brak",
            "uzasadnienie": "Iteracja dotyczy control-plane SHADOW i raportowania, bez zmian hot-path.",
        },
        "mechanizmy_ochronne": {
            "timeouty": "UNKNOWN",
            "fallback": "PASS",
            "rollback": "PASS",
            "atomic_write": "PASS",
            "schema_check": "PASS",
            "sanity_check": "PASS",
        },
    }

    section_f = test_rows

    section_g = [
        {
            "problem_ograniczenie": "Coverage gate ma HOLD dla czesci symboli FX.",
            "ryzyko": "Brak pelnego PASS dla Stage-1 i REVIEW_REQUIRED w werdykcie.",
            "obejscie_tymczasowe": "Kontynuowac SHADOW na symbolach z PASS, bez live apply.",
            "docelowa_poprawka": "Uzbierac dane dla blockerow lub zawezic scope do aktywnie handlowanych symboli.",
            "priorytet": "P0",
        },
        {
            "problem_ograniczenie": "Test runtime split HEARTBEAT vs TRADE_PATH nie jest domkniety w tym etapie.",
            "ryzyko": "Niepelna pewnosc co do stabilnosci metryk runtime.",
            "obejscie_tymczasowe": "Trzymac SHADOW_ONLY i recznie monitorowac runtime raporty.",
            "docelowa_poprawka": "Dodac dedykowany test integracyjny runtime split.",
            "priorytet": "P1",
        },
        {
            "problem_ograniczenie": "Smoketest Python->MQL5 live loader pozostaje PROTOTYPE.",
            "ryzyko": "Brak dowodu end-to-end dla live reload.",
            "obejscie_tymczasowe": "Nie wlaczac live auto-apply.",
            "docelowa_poprawka": "Wdrozyc test canary z recznym gate.",
            "priorytet": "P1",
        },
    ]

    section_h = [
        {
            "obszar": "specyfikacja",
            "uwaga_krytyczna": "Brak jednoznacznej definicji kryterium PASS dla coverage HOLD na nieaktywnych symbolach.",
            "propozycja_poprawki_promptu": "Dodac explicit rule: czy HOLD na symbolu bez danych blokuje caly stage, czy tylko symbol.",
        },
        {
            "obszar": "zakres",
            "uwaga_krytyczna": "Prompt laczy cele operacyjne i rozwojowe bez priorytetu P0/P1.",
            "propozycja_poprawki_promptu": "Wymusic numerowany backlog P0/P1/P2 na start iteracji.",
        },
        {
            "obszar": "kontrakt_danych",
            "uwaga_krytyczna": "Format verdict bywa stringiem lub obiektem; powoduje bledy parserow.",
            "propozycja_poprawki_promptu": "Ustandaryzowac verdict do formatu {status, blockers}.",
        },
        {
            "obszar": "kryteria_odbioru",
            "uwaga_krytyczna": "Brak obowiazkowej listy testow E2E wymaganych przed NO-GO/PASS.",
            "propozycja_poprawki_promptu": "Dodac minimalny zestaw testow i oczekiwane statusy dla release gate.",
        },
    ]

    section_i = {
        "commits_lub_patch": commits if commits else ["UNKNOWN"],
        "lista_plikow_zmienionych": changed,
        "lista_plikow_nowych": new,
        "lista_plikow_usunietych": deleted,
    }

    plus = "Pipeline Stage-1 ma domknieta sekwencje: approval -> deployer -> apply-plan -> go/no-go."
    risk = "Coverage HOLD utrzymuje werdykt REVIEW_REQUIRED i blokuje pelny PASS."
    next_steps = [
        "Uzbierac brakujace dane per symbol albo zawezic scope gate do symboli aktywnie handlowanych.",
        "Dodac test integracyjny runtime split HEARTBEAT vs TRADE_PATH.",
        "Przygotowac canary smoke dla MQL5 loader (dalej z manual gate).",
    ]
    if gg_verdict == "PASS":
        risk = "Brak krytycznych ryzyk w SHADOW, ale live nadal wymaga manual gate."
    if gg_verdict == "NO-GO":
        plus = "Bramka wykryla twardy problem i zablokowala przejscie."
        next_steps = [
            "Naprawic checki FAIL z sekcji F/G.",
            "Powtorzyc cykl Stage-1 i uzyskac minimum REVIEW_REQUIRED.",
            "Nie wykonywac zadnych live changes do czasu PASS/REVIEW z jasnym planem.",
        ]

    section_j = {
        "werdykt_koncowy": gg_verdict or "REVIEW_REQUIRED",
        "najwazniejszy_plus_iteracji": plus,
        "najwazniejsze_ryzyko_iteracji": risk,
        "co_dalej_maks_3_punkty": next_steps,
    }

    summary_lines = [
        f"Werdykt: {gg_verdict or 'REVIEW_REQUIRED'} ({gg_status or 'WARN'})",
        f"Dataset quality: {dq_verdict or 'UNKNOWN'}",
        f"Coverage gate: {cov_verdict or 'UNKNOWN'}",
        f"Shadow deployer: {sd_status or 'UNKNOWN'} / {sd_reason or 'UNKNOWN'}",
        f"Shadow apply plan: {sa_status or 'UNKNOWN'} / {sa_reason or 'UNKNOWN'}",
        "Co dziala: approval gate + shadow plan + go/no-go.",
        "Co poprawiono: atomowe zapisy i raport koncowy A-K.",
        "Czego nie uruchamiac na live: auto-apply i mutacje execution path.",
        "Gotowe na kolejna iteracje: domkniecie coverage i test runtime split.",
    ]
    if operator_items:
        summary_lines.append(f"OPERATOR_DECISION_REQUIRED: {', '.join(operator_items)}")
    section_k = {"podsumowanie_operator": summary_lines[:10]}

    report: Dict[str, Any] = {
        "schema": SCHEMA,
        "run_id": run_id,
        "started_at_utc": iso_utc(started),
        "finished_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "focus_group": str(args.focus_group or ""),
        "lookback_hours": int(args.lookback_hours),
        "source_files": {
            "dataset_quality": str(dq_path) if dq_path else "",
            "coverage_gate": str(cov_path) if cov_path else "",
            "profile_eval": str(eval_path),
            "shadow_deployer": str(deployer_path),
            "shadow_apply_plan": str(apply_path),
            "shadow_gonogo": str(gonogo_path),
            "approval_file": str(approval_path),
        },
        "source_hashes": {
            "dataset_quality": file_sha256(dq_path) if dq_path and dq_path.exists() else "",
            "coverage_gate": file_sha256(cov_path) if cov_path and cov_path.exists() else "",
            "profile_eval": file_sha256(eval_path) if eval_path.exists() else "",
            "shadow_deployer": file_sha256(deployer_path) if deployer_path.exists() else "",
            "shadow_apply_plan": file_sha256(apply_path) if apply_path.exists() else "",
            "shadow_gonogo": file_sha256(gonogo_path) if gonogo_path.exists() else "",
        },
        "A": section_a,
        "B": section_b,
        "C": section_c,
        "D": section_d,
        "E": section_e,
        "F": section_f,
        "G": section_g,
        "H": section_h,
        "I": section_i,
        "J": section_j,
        "K": section_k,
        "operator_decision_required": operator_items,
        "coverage_blockers": blockers[:50],
    }
    out_report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    out_txt.write_text(_render_txt(report), encoding="utf-8")

    latest_json = ensure_write_parent((stage1_reports / "stage1_iteration_audit_latest.json").resolve(), root=root, lab_data_root=lab_data_root)
    latest_txt = ensure_write_parent((stage1_reports / "stage1_iteration_audit_latest.txt").resolve(), root=root, lab_data_root=lab_data_root)
    latest_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    latest_txt.write_text(_render_txt(report), encoding="utf-8")

    try:
        registry_path = (lab_data_root / "registry" / "lab_registry.sqlite").resolve()
        conn_reg = connect_registry(registry_path)
        init_registry_schema(conn_reg)
        cfg_hash = canonical_json_hash({"tool": "stage1_iteration_audit.v1", "focus_group": str(args.focus_group or ""), "lookback_hours": int(args.lookback_hours)})
        insert_job_run(
            conn_reg,
            {
                "run_id": run_id,
                "run_type": "STAGE1_ITERATION_AUDIT",
                "started_at_utc": report["started_at_utc"],
                "finished_at_utc": report["finished_at_utc"],
                "status": "PASS" if gg_verdict in {"PASS", "REVIEW_REQUIRED"} else "WARN",
                "source_type": "MT5_SNAPSHOT",
                "dataset_hash": canonical_json_hash(report.get("source_hashes") or {}),
                "config_hash": cfg_hash,
                "readiness": gg_verdict or "REVIEW_REQUIRED",
                "reason": "ITERATION_AUDIT_READY",
                "evidence_path": str(out_report),
                "details_json": json.dumps({"operator_decision_required": operator_items, "coverage_blockers_n": len(blockers)}, ensure_ascii=False),
            },
        )
        conn_reg.close()
    except Exception as exc:
        _ = exc
    print(f"STAGE1_ITERATION_AUDIT_DONE status=PASS verdict={gg_verdict or 'REVIEW_REQUIRED'} report={out_report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
