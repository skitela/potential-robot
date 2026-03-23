from __future__ import annotations

import argparse
import csv
import json
import math
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_COMMON_ROOT = Path(
    r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
)
DEFAULT_PROJECT_ROOT = Path(r"C:\MAKRO_I_MIKRO_BOT")

FAMILY_SYMBOLS = {
    "FX_MAIN": ["EURUSD", "GBPUSD", "USDCAD", "USDCHF"],
    "FX_ASIA": ["AUDUSD", "USDJPY", "NZDUSD"],
    "FX_CROSS": ["EURJPY", "GBPJPY", "EURAUD"],
    "METALS_SPOT_PM": ["GOLD.pro", "SILVER.pro"],
    "METALS_FUTURES": ["COPPER-US.pro"],
}


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
        row["winner"] = row["pnl"] > 0.0
        row["loser"] = row["pnl"] < 0.0
        rows.append(row)
    return rows


def safe_avg(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def rate(rows: list[dict], predicate) -> float:
    if not rows:
        return 0.0
    return sum(1 for row in rows if predicate(row)) / len(rows)


def quantile(values: list[float], q: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    pos = (len(ordered) - 1) * q
    lo = math.floor(pos)
    hi = math.ceil(pos)
    if lo == hi:
        return ordered[lo]
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (pos - lo)


def setup_profiles(rows: list[dict]) -> list[dict]:
    grouped: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        grouped[row["setup_type"]].append(row)
    profiles: list[dict] = []
    for setup, items in grouped.items():
        winners = [r for r in items if r["winner"]]
        losers = [r for r in items if r["loser"]]
        winner_conf = [r["confidence_score"] for r in winners]
        loser_conf = [r["confidence_score"] for r in losers]
        profiles.append(
            {
                "setup_type": setup,
                "samples": len(items),
                "wins": len(winners),
                "losses": len(losers),
                "pnl_sum": round(sum(r["pnl"] for r in items), 4),
                "avg_pnl": round(safe_avg([r["pnl"] for r in items]), 4),
                "winner_conf_avg": round(safe_avg(winner_conf), 4),
                "loser_conf_avg": round(safe_avg(loser_conf), 4),
                "winner_conf_q25": round(quantile(winner_conf, 0.25), 4),
                "winner_support_rate": round(rate(winners, lambda r: r["any_support"]), 4),
                "loser_support_rate": round(rate(losers, lambda r: r["any_support"]), 4),
                "winner_strong_support_rate": round(rate(winners, lambda r: r["strong_support"]), 4),
                "loser_strong_support_rate": round(rate(losers, lambda r: r["strong_support"]), 4),
                "winner_poor_candle_rate": round(rate(winners, lambda r: r["candle_quality_grade"] == "POOR"), 4),
                "loser_poor_candle_rate": round(rate(losers, lambda r: r["candle_quality_grade"] == "POOR"), 4),
                "winner_poor_renko_rate": round(rate(winners, lambda r: r["renko_quality_grade"] in {"POOR", "UNKNOWN"}), 4),
                "loser_poor_renko_rate": round(rate(losers, lambda r: r["renko_quality_grade"] in {"POOR", "UNKNOWN"}), 4),
            }
        )
    profiles.sort(key=lambda item: item["pnl_sum"])
    return profiles


def bucket_profiles(rows: list[dict]) -> list[dict]:
    grouped: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for row in rows:
        grouped[(row["setup_type"], row["market_regime"])].append(row)
    profiles: list[dict] = []
    for (setup, regime), items in grouped.items():
        wins = sum(1 for r in items if r["winner"])
        losses = sum(1 for r in items if r["loser"])
        profiles.append(
            {
                "bucket": f"{setup}/{regime}",
                "setup_type": setup,
                "market_regime": regime,
                "samples": len(items),
                "wins": wins,
                "losses": losses,
                "pnl_sum": round(sum(r["pnl"] for r in items), 4),
                "avg_pnl": round(safe_avg([r["pnl"] for r in items]), 4),
                "win_rate": round(wins / len(items), 4) if items else 0.0,
            }
        )
    profiles.sort(key=lambda item: (item["pnl_sum"], item["avg_pnl"]))
    return profiles


def build_recommendations(setup_stats: list[dict], bucket_stats: list[dict]) -> dict:
    keep: list[str] = []
    tighten: list[str] = []
    strengthen: list[str] = []
    remove: list[str] = []

    for bucket in bucket_stats:
        if bucket["samples"] >= 3 and bucket["pnl_sum"] > 0.0 and bucket["win_rate"] >= 0.5:
            keep.append(
                f"utrzymac `{bucket['bucket']}` jako kandydat dodatni ({bucket['pnl_sum']}, win_rate={bucket['win_rate']})"
            )
        if bucket["samples"] >= 5 and bucket["pnl_sum"] <= -5.0:
            tighten.append(
                f"mocno scisnac albo czasowo zamrozic `{bucket['bucket']}` ({bucket['pnl_sum']})"
            )

    for setup in setup_stats:
        if setup["wins"] >= 3 and setup["losses"] >= 3:
            if (setup["winner_support_rate"] - setup["loser_support_rate"]) >= 0.25:
                strengthen.append(
                    f"dla `{setup['setup_type']}` wymagac przynajmniej jednego zgodnego wsparcia"
                )
            if (setup["winner_strong_support_rate"] - setup["loser_strong_support_rate"]) >= 0.25:
                strengthen.append(
                    f"dla `{setup['setup_type']}` premiowac silne wsparcie swieca+Renko"
                )
            if (setup["loser_poor_candle_rate"] - setup["winner_poor_candle_rate"]) >= 0.20:
                tighten.append(
                    f"dla `{setup['setup_type']}` odciac wejscia przy `POOR candle`"
                )
            if (setup["loser_poor_renko_rate"] - setup["winner_poor_renko_rate"]) >= 0.20:
                tighten.append(
                    f"dla `{setup['setup_type']}` odciac wejscia przy `POOR/UNKNOWN Renko`"
                )
            if (setup["winner_conf_q25"] - setup["loser_conf_avg"]) >= 0.10 and setup["winner_conf_q25"] > 0.0:
                gate = round(setup["winner_conf_q25"] / 0.05) * 0.05
                strengthen.append(
                    f"dla `{setup['setup_type']}` rozważyć confidence gate w okolicy `{gate:.2f}`"
                )

        if setup["samples"] >= 8 and setup["pnl_sum"] < 0.0 and setup["wins"] <= 1:
            remove.append(
                f"`{setup['setup_type']}` nie pokazal przewagi i powinien byc traktowany bardzo defensywnie"
            )

    return {
        "keep": list(dict.fromkeys(keep))[:6],
        "tighten": list(dict.fromkeys(tighten))[:8],
        "strengthen": list(dict.fromkeys(strengthen))[:8],
        "remove": list(dict.fromkeys(remove))[:6],
    }


def symbol_analysis(symbol: str, rows: list[dict]) -> dict:
    setups = setup_profiles(rows)
    buckets = bucket_profiles(rows)
    reasons = Counter(r["close_reason"] for r in rows)
    return {
        "symbol": symbol,
        "rows": len(rows),
        "wins": sum(1 for r in rows if r["winner"]),
        "losses": sum(1 for r in rows if r["loser"]),
        "pnl_sum": round(sum(r["pnl"] for r in rows), 4),
        "close_reasons": dict(reasons.most_common()),
        "setup_profiles": setups,
        "bucket_profiles": buckets,
        "recommendations": build_recommendations(setups, buckets),
    }


def render_markdown(result: dict, out_path: Path) -> None:
    lines: list[str] = []
    lines.append("# Win / Loss Profile Analysis")
    lines.append("")
    lines.append(f"- generated_at_utc: `{result['generated_at_utc']}`")
    lines.append(f"- family: `{result['family']}`")
    lines.append(f"- symbols: `{', '.join(result['symbols'])}`")
    lines.append("")
    lines.append("## Sens")
    lines.append("")
    lines.append(
        "Ten raport patrzy nie tylko na to, co bylo toksyczne, ale tez na to, "
        "jak wygladaly zwycieskie wejscia. Chodzi o odroznienie rzeczy, ktore trzeba odciac, "
        "od rzeczy, ktore warto chronic albo delikatnie wzmacniac."
    )
    lines.append("")
    for symbol in result["symbols_results"]:
        lines.append(f"## {symbol['symbol']}")
        lines.append("")
        lines.append(
            f"- wynik: `{symbol['pnl_sum']}` przy `{symbol['rows']}` obserwacjach, "
            f"`{symbol['wins']}` wygranych i `{symbol['losses']}` przegranych"
        )
        if symbol["close_reasons"]:
            reasons = ", ".join(f"`{k}={v}`" for k, v in list(symbol["close_reasons"].items())[:4])
            lines.append(f"- dominujace powody zamkniec: {reasons}")
        lines.append("")
        lines.append("Co warto zachowac:")
        if symbol["recommendations"]["keep"]:
            for item in symbol["recommendations"]["keep"]:
                lines.append(f"- {item}")
        else:
            lines.append("- brak jeszcze mocnych dodatnich bucketow do obrony")
        lines.append("")
        lines.append("Co warto scisnac:")
        if symbol["recommendations"]["tighten"]:
            for item in symbol["recommendations"]["tighten"]:
                lines.append(f"- {item}")
        else:
            lines.append("- brak jednoznacznych kandydatow do twardego docisku")
        lines.append("")
        lines.append("Co warto wzmacniac lub wymagac:")
        if symbol["recommendations"]["strengthen"]:
            for item in symbol["recommendations"]["strengthen"]:
                lines.append(f"- {item}")
        else:
            lines.append("- brak jeszcze mocnych wzorcow do wzmacniania")
        lines.append("")
        lines.append("Co wyglada jak kandydat do ograniczenia lub usuniecia:")
        if symbol["recommendations"]["remove"]:
            for item in symbol["recommendations"]["remove"]:
                lines.append(f"- {item}")
        else:
            lines.append("- nic nie kwalifikuje sie jeszcze do jednoznacznego wyciecia na podstawie samej tej probki")
        lines.append("")

    family = result["family_rollup"]
    lines.append("## Rodzina")
    lines.append("")
    for section, title in (
        ("keep", "Co bronic w rodzinie"),
        ("tighten", "Co dociskac w rodzinie"),
        ("strengthen", "Co wzmacniac w rodzinie"),
        ("remove", "Co traktowac bardzo defensywnie"),
    ):
        lines.append(title)
        if family["recommendations"][section]:
            for item in family["recommendations"][section]:
                lines.append(f"- {item}")
        else:
            lines.append("- brak wspolnego wzorca na tym poziomie")
        lines.append("")
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

    symbol_results = []
    family_rows: list[dict] = []
    for symbol in symbols:
        rows = load_rows(common_root / "logs" / symbol / "learning_observations_v2.csv")
        family_rows.extend(rows)
        symbol_results.append(symbol_analysis(symbol, rows))

    family_rollup = symbol_analysis(args.family, family_rows)
    generated_at = datetime.now(timezone.utc).isoformat()
    payload = {
        "generated_at_utc": generated_at,
        "family": args.family,
        "symbols": symbols,
        "symbols_results": symbol_results,
        "family_rollup": family_rollup,
    }

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_json = project_root / "EVIDENCE" / f"WIN_LOSS_PROFILE_{args.family}_{stamp}.json"
    out_md = project_root / "EVIDENCE" / f"WIN_LOSS_PROFILE_{args.family}_{stamp}.md"
    out_json.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    render_markdown(payload, out_md)
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
