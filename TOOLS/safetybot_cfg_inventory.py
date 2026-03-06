#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import json
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List, Tuple


def _category_for(name: str) -> Tuple[str, str, bool]:
    n = str(name or "").strip().lower()

    if any(
        key in n
        for key in (
            "risk_per_trade",
            "risk_scalp",
            "risk_swing",
            "max_open_risk",
            "max_risk_cap",
            "friday_risk",
            "borrow_block",
            "kill_switch",
            "black_swan",
            "manual_kill_switch",
        )
    ):
        return (
            "NIENARUSZALNE_KAPITAL_I_BEZPIECZENSTWO",
            "Twarde zabezpieczenie kapitału albo awaryjne odcięcie handlu.",
            False,
        )

    if any(
        key in n
        for key in (
            "self_heal",
            "canary",
            "drift_",
            "learner_qa",
            "unified_learning",
            "warn_degrade",
            "snapshot_health",
            "eco_probe",
            "spenddown",
        )
    ):
        return (
            "ADAPTACYJNE_RUNTIME",
            "Bieżąca adaptacja pracy runtime, ochrona trybu pracy i ograniczanie aktywności.",
            False,
        )

    if any(
        key in n
        for key in (
            "spread_cap",
            "signal_score",
            "quality",
            "tradeability",
            "hot_relaxed",
            "score_threshold",
        )
    ):
        return (
            "MIEKKIE_PROGI_DO_UCZENIA",
            "Miękki próg dopuszczenia do handlu albo punktacji sygnału. Nadaje się do strojenia przez naukę.",
            True,
        )

    if any(
        key in n
        for key in (
            "trade_window",
            "window_",
            "rotation",
            "carryover",
            "prefetch",
            "symbol_intents",
            "group_priority",
            "policy_windows",
            "policy_group",
            "policy_overlap",
            "policy_shadow",
            "policy_risk_windows",
            "asia_wave1",
            "jpy_basket",
        )
    ):
        return (
            "OKNA_ROUTING_I_ORKIESTRACJA",
            "Dobór okna czasowego, grupy instrumentów i kolejności skanowania.",
            False,
        )

    if any(
        key in n
        for key in (
            "renko",
            "candle",
            "sma_",
            "adx",
            "atr",
            "regime",
            "mean_reversion",
            "structure_filter",
            "trend_",
            "session_",
        )
    ):
        return (
            "PARAMETRY_LOGIKI_SYGNALU",
            "Parametry budowy i oceny sygnału. Część może być później uczona, ale tylko po osobnym audycie.",
            False,
        )

    return (
        "OPERACYJNE_I_INFRASTRUKTURALNE",
        "Parametr pracy technicznej, telemetrii albo infrastruktury systemu.",
        False,
    )


def _literal_text(source: str, node: ast.AST | None) -> str:
    if node is None:
        return ""
    seg = ast.get_source_segment(source, node)
    if seg is not None:
        return str(seg).strip()
    try:
        return ast.unparse(node).strip()
    except Exception:
        return ""


def _extract_cfg_fields(path: Path) -> List[Dict[str, Any]]:
    source = path.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(path))
    items: List[Dict[str, Any]] = []
    for node in tree.body:
        if not isinstance(node, ast.ClassDef) or node.name != "CFG":
            continue
        for stmt in node.body:
            if isinstance(stmt, ast.AnnAssign) and isinstance(stmt.target, ast.Name):
                field_name = stmt.target.id
                category, rationale, learnable = _category_for(field_name)
                items.append(
                    {
                        "name": field_name,
                        "annotation": _literal_text(source, stmt.annotation),
                        "default": _literal_text(source, stmt.value),
                        "line": int(stmt.lineno),
                        "category": category,
                        "category_reason": rationale,
                        "eligible_for_learning": bool(learnable),
                    }
                )
        break
    return items


def _render_markdown(payload: Dict[str, Any]) -> str:
    lines: List[str] = []
    lines.append("# SafetyBot - spis parametrów sterujących")
    lines.append("")
    lines.append(f"- Źródło: `{payload['source']}`")
    lines.append(f"- Liczba parametrów: `{payload['summary']['fields_n']}`")
    lines.append("")
    lines.append("## Podsumowanie kategorii")
    lines.append("")
    for row in payload["summary"]["categories"]:
        lines.append(f"- `{row['category']}`: `{row['count']}`")
    lines.append("")
    lines.append("## Parametry")
    lines.append("")
    for item in payload["fields"]:
        lines.append(f"### `{item['name']}`")
        lines.append(f"- Kategoria: `{item['category']}`")
        lines.append(f"- Typ: `{item['annotation'] or 'UNKNOWN'}`")
        lines.append(f"- Domyślna wartość: `{item['default'] or 'UNKNOWN'}`")
        lines.append(f"- Linia: `{item['line']}`")
        lines.append(f"- Nadaje się do uczenia: `{str(bool(item['eligible_for_learning'])).lower()}`")
        lines.append(f"- Uzasadnienie: {item['category_reason']}")
        lines.append("")
    return "\n".join(lines) + "\n"


def build_inventory(root: Path) -> Dict[str, Any]:
    source = (root / "BIN" / "safetybot.py").resolve()
    fields = _extract_cfg_fields(source)
    counts = Counter([str(x["category"]) for x in fields])
    summary = {
        "fields_n": int(len(fields)),
        "categories": [
            {"category": category, "count": int(count)}
            for category, count in sorted(counts.items(), key=lambda kv: kv[0])
        ],
    }
    return {
        "schema": "oanda.mt5.safetybot_cfg_inventory.v1",
        "source": str(source),
        "summary": summary,
        "fields": fields,
    }


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Generate SafetyBot CFG inventory and category map.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--out-dir", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    out_dir = Path(args.out_dir).resolve() if str(args.out_dir).strip() else (root / "EVIDENCE" / "safetybot_cfg_inventory").resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    payload = build_inventory(root)
    out_json = out_dir / "safetybot_cfg_inventory_latest.json"
    out_md = out_dir / "safetybot_cfg_inventory_latest.md"
    out_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    out_md.write_text(_render_markdown(payload), encoding="utf-8")
    print(
        "SAFETYBOT_CFG_INVENTORY_OK "
        + json.dumps(
            {
                "fields_n": payload["summary"]["fields_n"],
                "categories_n": len(payload["summary"]["categories"]),
                "out_json": str(out_json),
                "out_md": str(out_md),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
