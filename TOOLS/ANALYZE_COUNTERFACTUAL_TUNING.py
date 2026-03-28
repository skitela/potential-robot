from __future__ import annotations

import argparse
import csv
import json
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable


DEFAULT_COMMON_ROOT = Path(
    r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
)
DEFAULT_PROJECT_ROOT = Path(r"C:\MAKRO_I_MIKRO_BOT")

FAMILY_SYMBOLS = {
    "FX_MAIN": ["EURUSD", "GBPUSD", "USDCAD", "USDCHF"],
    "FX_ASIA": ["AUDUSD", "USDJPY"],
    "FX_CROSS": ["EURJPY", "EURAUD"],
    "METALS_SPOT_PM": ["GOLD.pro", "SILVER.pro"],
    "METALS_FUTURES": ["COPPER-US.pro"],
}


@dataclass(frozen=True)
class Rule:
    code: str
    label: str
    suggestion: str
    applies: Callable[[dict], bool]


def load_rows(path: Path) -> list[dict]:
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8-sig", errors="ignore")
    if not text.strip():
        return []
    dialect = csv.Sniffer().sniff(text[:2048], delimiters="\t,;")
    reader = csv.DictReader(text.splitlines(), dialect=dialect)
    rows: list[dict] = []
    for raw in reader:
        row = {k: (v or "").strip() for k, v in raw.items() if k is not None}
        if not row:
            continue
        row["confidence_score"] = float(row.get("confidence_score") or 0.0)
        row["candle_score"] = float(row.get("candle_score") or 0.0)
        row["renko_score"] = float(row.get("renko_score") or 0.0)
        row["pnl"] = float(row.get("pnl") or 0.0)
        row["ts"] = int(float(row.get("ts") or 0))
        row["side"] = int(float(row.get("side") or 0))
        row["expected_bias"] = "UP" if row["side"] > 0 else "DOWN"
        row["candle_support"] = row.get("candle_bias") == row["expected_bias"]
        row["renko_support"] = row.get("renko_bias") == row["expected_bias"]
        row["any_support"] = row["candle_support"] or row["renko_support"]
        row["strong_support"] = row["candle_support"] and row["renko_support"]
        rows.append(row)
    return rows


def build_rules(rows: Iterable[dict]) -> list[Rule]:
    rows = list(rows)
    setups = sorted({r["setup_type"] for r in rows if r["setup_type"]})
    regimes = sorted({r["market_regime"] for r in rows if r["market_regime"]})
    spreads = sorted({r["spread_regime"] for r in rows if r["spread_regime"]})
    thresholds = [0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75]

    rules: list[Rule] = []

    for setup in setups:
        rules.append(
            Rule(
                code=f"block:{setup}",
                label=f"Blokuj {setup}",
                suggestion=f"czasowo zamrozic lub mocno opodatkowac {setup}",
                applies=lambda row, setup=setup: row["setup_type"] == setup,
            )
        )
        rules.append(
            Rule(
                code=f"need_support:{setup}",
                label=f"Wymagaj wsparcia dla {setup}",
                suggestion=f"wymagac przynajmniej jednego zgodnego wsparcia dla {setup}",
                applies=lambda row, setup=setup: row["setup_type"] == setup and not row["any_support"],
            )
        )
        rules.append(
            Rule(
                code=f"renko_not_poor:{setup}",
                label=f"Nie wpuszczaj {setup} przy slabym Renko",
                suggestion=f"zaostrzyc filtr Renko dla {setup}",
                applies=lambda row, setup=setup: row["setup_type"] == setup and row["renko_quality_grade"] in {"UNKNOWN", "POOR"},
            )
        )
        rules.append(
            Rule(
                code=f"candle_not_poor:{setup}",
                label=f"Nie wpuszczaj {setup} przy slabiej swiecy",
                suggestion=f"zaostrzyc filtr swiec dla {setup}",
                applies=lambda row, setup=setup: row["setup_type"] == setup and row["candle_quality_grade"] == "POOR",
            )
        )
        for threshold in thresholds:
            threshold_code = str(threshold).replace(".", "")
            rules.append(
                Rule(
                    code=f"confidence:{setup}:{threshold_code}",
                    label=f"Confidence gate {setup} >= {threshold:.2f}",
                    suggestion=f"podniesc minimalny confidence dla {setup} do {threshold:.2f}",
                    applies=lambda row, setup=setup, threshold=threshold: row["setup_type"] == setup and row["confidence_score"] < threshold,
                )
            )
        for regime in regimes:
            rules.append(
                Rule(
                    code=f"block:{setup}:{regime}",
                    label=f"Blokuj {setup} w {regime}",
                    suggestion=f"zamrozic {setup} w reżimie {regime}",
                    applies=lambda row, setup=setup, regime=regime: row["setup_type"] == setup and row["market_regime"] == regime,
                )
            )
            rules.append(
                Rule(
                    code=f"need_support:{setup}:{regime}",
                    label=f"Wymagaj wsparcia dla {setup} w {regime}",
                    suggestion=f"w {regime} wymagac wsparcia dla {setup}",
                    applies=lambda row, setup=setup, regime=regime: row["setup_type"] == setup
                    and row["market_regime"] == regime
                    and not row["any_support"],
                )
            )
            for spread in spreads:
                rules.append(
                    Rule(
                        code=f"block:{setup}:{regime}:{spread}",
                        label=f"Blokuj {setup} w {regime} przy {spread}",
                        suggestion=f"zablokowac {setup} w {regime} przy spreadzie {spread}",
                        applies=lambda row, setup=setup, regime=regime, spread=spread: row["setup_type"] == setup
                        and row["market_regime"] == regime
                        and row["spread_regime"] == spread,
                    )
                )
            for threshold in thresholds:
                threshold_code = str(threshold).replace(".", "")
                rules.append(
                    Rule(
                        code=f"confidence:{setup}:{regime}:{threshold_code}",
                        label=f"Confidence gate {setup} {regime} >= {threshold:.2f}",
                        suggestion=f"w {regime} podniesc confidence dla {setup} do {threshold:.2f}",
                        applies=lambda row, setup=setup, regime=regime, threshold=threshold: row["setup_type"] == setup
                        and row["market_regime"] == regime
                        and row["confidence_score"] < threshold,
                    )
                )
    return rules


def evaluate_rule(rows: list[dict], rule: Rule) -> dict | None:
    blocked = [r for r in rows if rule.applies(r)]
    if not blocked:
        return None
    blocked_pnl = sum(r["pnl"] for r in blocked)
    blocked_neg = sum(r["pnl"] for r in blocked if r["pnl"] < 0.0)
    blocked_pos = sum(r["pnl"] for r in blocked if r["pnl"] > 0.0)
    blocked_losses = sum(1 for r in blocked if r["pnl"] < 0.0)
    blocked_wins = sum(1 for r in blocked if r["pnl"] > 0.0)
    baseline_pnl = sum(r["pnl"] for r in rows)
    new_pnl = baseline_pnl - blocked_pnl
    improvement = new_pnl - baseline_pnl
    return {
        "code": rule.code,
        "label": rule.label,
        "suggestion": rule.suggestion,
        "blocked_count": len(blocked),
        "blocked_losses": blocked_losses,
        "blocked_wins": blocked_wins,
        "blocked_pnl_sum": round(blocked_pnl, 4),
        "avoided_loss_sum": round(-blocked_neg, 4),
        "sacrificed_win_sum": round(blocked_pos, 4),
        "baseline_pnl": round(baseline_pnl, 4),
        "counterfactual_pnl": round(new_pnl, 4),
        "net_improvement": round(improvement, 4),
        "avg_blocked_pnl": round(blocked_pnl / len(blocked), 4),
    }


def evaluate_half_risk(rows: list[dict], rule: Rule) -> dict | None:
    matched = [r for r in rows if rule.applies(r)]
    if not matched:
        return None
    baseline = sum(r["pnl"] for r in rows)
    adjusted = baseline
    match_sum = 0.0
    for row in matched:
        match_sum += row["pnl"]
        adjusted -= row["pnl"] * 0.5
    return {
        "code": rule.code,
        "label": rule.label,
        "suggestion": f"zamiast blokowac: scisnac ryzyko o 50% gdy {rule.label.lower()}",
        "matched_count": len(matched),
        "matched_pnl_sum": round(match_sum, 4),
        "baseline_pnl": round(baseline, 4),
        "counterfactual_pnl": round(adjusted, 4),
        "net_improvement": round(adjusted - baseline, 4),
    }


def summarize_rows(rows: list[dict]) -> dict:
    close_reasons = Counter(r["close_reason"] for r in rows)
    setup_regime = defaultdict(lambda: {"count": 0, "pnl": 0.0})
    for row in rows:
        key = f'{row["setup_type"]}/{row["market_regime"]}'
        setup_regime[key]["count"] += 1
        setup_regime[key]["pnl"] += row["pnl"]
    toxic = sorted(
        (
            {
                "bucket": key,
                "count": value["count"],
                "pnl_sum": round(value["pnl"], 4),
                "avg_pnl": round(value["pnl"] / value["count"], 4),
            }
            for key, value in setup_regime.items()
            if value["count"] > 0
        ),
        key=lambda item: (item["pnl_sum"], item["avg_pnl"]),
    )
    return {
        "rows": len(rows),
        "wins": sum(1 for r in rows if r["pnl"] > 0.0),
        "losses": sum(1 for r in rows if r["pnl"] < 0.0),
        "pnl_sum": round(sum(r["pnl"] for r in rows), 4),
        "close_reasons": dict(close_reasons.most_common()),
        "toxic_buckets": toxic[:8],
    }


def analyze_symbol(symbol: str, common_root: Path) -> dict:
    rows = load_rows(common_root / "logs" / symbol / "learning_observations_v2.csv")
    summary = summarize_rows(rows)
    rules = build_rules(rows)
    block_results = [evaluate_rule(rows, rule) for rule in rules]
    block_results = [r for r in block_results if r is not None and r["net_improvement"] > 0.0]
    block_results.sort(
        key=lambda r: (
            r["net_improvement"],
            r["blocked_losses"] - r["blocked_wins"],
            r["blocked_count"],
        ),
        reverse=True,
    )
    risk_results = [evaluate_half_risk(rows, rule) for rule in rules]
    risk_results = [r for r in risk_results if r is not None and r["net_improvement"] > 0.0]
    risk_results.sort(key=lambda r: (r["net_improvement"], r["matched_count"]), reverse=True)
    return {
        "symbol": symbol,
        "summary": summary,
        "top_block_rules": block_results[:8],
        "top_half_risk_rules": risk_results[:5],
    }


def build_markdown(results: dict, out_path: Path) -> None:
    lines: list[str] = []
    lines.append("# Counterfactual Tuning Analysis")
    lines.append("")
    lines.append(f"- generated_at_utc: `{results['generated_at_utc']}`")
    lines.append(f"- family: `{results['family']}`")
    lines.append(f"- symbols: `{', '.join(results['symbols'])}`")
    lines.append("")
    lines.append("## Wniosek")
    lines.append("")
    lines.append(
        "Ten raport nie probuje udawac, ze da sie zamienic kazda strate w wygrana. "
        "Szuka za to takich filtrow i takich ograniczen ryzyka, ktore na danych z ostatniej aktywnej sesji "
        "najmocniej poprawilyby wynik przez niewpuszczenie najbardziej toksycznych klas wejsc albo przez ich scisniecie."
    )
    lines.append("")
    for symbol_result in results["symbols_results"]:
        summary = symbol_result["summary"]
        lines.append(f"## {symbol_result['symbol']}")
        lines.append("")
        lines.append(
            f"- bazowy wynik: `{summary['pnl_sum']}` przy `{summary['rows']}` obserwacjach, "
            f"`{summary['wins']}` wygranych i `{summary['losses']}` przegranych"
        )
        if summary["close_reasons"]:
            top_reasons = ", ".join(f"`{k}={v}`" for k, v in list(summary["close_reasons"].items())[:4])
            lines.append(f"- dominujace powody zamkniec: {top_reasons}")
        if summary["toxic_buckets"]:
            toxic = ", ".join(
                f"`{item['bucket']} ({item['pnl_sum']})`" for item in summary["toxic_buckets"][:4]
            )
            lines.append(f"- najbardziej toksyczne buckety: {toxic}")
        lines.append("")
        lines.append("Najlepsze kontrfaktyczne filtry blokujace:")
        lines.append("")
        for rule in symbol_result["top_block_rules"][:5]:
            lines.append(
                f"- `{rule['label']}` -> poprawa `{rule['net_improvement']}`, zablokowane `{rule['blocked_count']}` wejsc, "
                f"uratowana strata `{rule['avoided_loss_sum']}`, oddane wygrane `{rule['sacrificed_win_sum']}`"
            )
            lines.append(f"  sugestia: {rule['suggestion']}")
        lines.append("")
        lines.append("Najlepsze kontrfaktyczne scisniecia ryzyka:")
        lines.append("")
        for rule in symbol_result["top_half_risk_rules"][:3]:
            lines.append(
                f"- `{rule['label']}` -> poprawa `{rule['net_improvement']}` przy polowie ryzyka dla `{rule['matched_count']}` wejsc"
            )
            lines.append(f"  sugestia: {rule['suggestion']}")
        lines.append("")

    family = results["family_rollup"]
    lines.append("## Rodzina")
    lines.append("")
    lines.append(
        f"- wynik laczny rodziny: `{family['summary']['pnl_sum']}` przy `{family['summary']['rows']}` obserwacjach"
    )
    lines.append("- wspolne filtry, ktore wygladaja najmocniej dla calej rodziny:")
    for rule in family["top_block_rules"][:6]:
        lines.append(
            f"- `{rule['label']}` -> poprawa `{rule['net_improvement']}`, zablokowane `{rule['blocked_count']}` wejsc"
        )
        lines.append(f"  sugestia: {rule['suggestion']}")
    lines.append("")
    lines.append("## Uczciwe ograniczenia")
    lines.append("")
    lines.append(
        "- to jest analiza kontrfaktyczna typu 'gdybysmy nie wpuscili tego typu wejsc albo scisneli im ryzyko', "
        "a nie dowod, ze rynek stalby sie dodatni po jednej zmianie"
    )
    lines.append(
        "- najlepsze reguly trzeba traktowac jako kandydatow do sekwencyjnego testu po otwarciu rynku, "
        "a nie jako prawo do wdrozenia wszystkiego naraz"
    )
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--family", default="FX_MAIN", choices=sorted(FAMILY_SYMBOLS))
    parser.add_argument("--common-root", default=str(DEFAULT_COMMON_ROOT))
    parser.add_argument("--project-root", default=str(DEFAULT_PROJECT_ROOT))
    args = parser.parse_args()

    common_root = Path(args.common_root)
    project_root = Path(args.project_root)
    symbols = FAMILY_SYMBOLS[args.family]

    symbol_results = [analyze_symbol(symbol, common_root) for symbol in symbols]
    family_rows: list[dict] = []
    for symbol in symbols:
        family_rows.extend(load_rows(common_root / "logs" / symbol / "learning_observations_v2.csv"))
    family_rollup = {
        "summary": summarize_rows(family_rows),
        "top_block_rules": [],
        "top_half_risk_rules": [],
    }
    family_rules = build_rules(family_rows)
    family_block = [evaluate_rule(family_rows, rule) for rule in family_rules]
    family_block = [r for r in family_block if r is not None and r["net_improvement"] > 0.0]
    family_block.sort(
        key=lambda r: (
            r["net_improvement"],
            r["blocked_losses"] - r["blocked_wins"],
            r["blocked_count"],
        ),
        reverse=True,
    )
    family_half = [evaluate_half_risk(family_rows, rule) for rule in family_rules]
    family_half = [r for r in family_half if r is not None and r["net_improvement"] > 0.0]
    family_half.sort(key=lambda r: (r["net_improvement"], r["matched_count"]), reverse=True)
    family_rollup["top_block_rules"] = family_block[:8]
    family_rollup["top_half_risk_rules"] = family_half[:5]

    generated_at = datetime.now(timezone.utc).isoformat()
    results = {
        "generated_at_utc": generated_at,
        "family": args.family,
        "symbols": symbols,
        "symbols_results": symbol_results,
        "family_rollup": family_rollup,
    }

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_json = project_root / "EVIDENCE" / f"COUNTERFACTUAL_TUNING_{args.family}_{stamp}.json"
    out_md = project_root / "EVIDENCE" / f"COUNTERFACTUAL_TUNING_{args.family}_{stamp}.md"
    out_json.write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")
    build_markdown(results, out_md)
    print(
        json.dumps(
            {
                "status": "OK",
                "family": args.family,
                "json_path": str(out_json),
                "md_path": str(out_md),
            },
            indent=2,
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
