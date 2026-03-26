from __future__ import annotations

import argparse
import csv
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_PROJECT_ROOT = Path(r"C:\MAKRO_I_MIKRO_BOT")
DEFAULT_COMMON_ROOT = Path(
    r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
)


def read_json_safe(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8-sig", errors="ignore"))
    except Exception:
        return None


def read_key_value_table(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    if not path.exists():
        return result
    for raw_line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw_line.strip()
        if not line or "\t" not in line:
            continue
        key, value = line.split("\t", 1)
        result[key] = value
    return result


def normalize_symbol_alias(symbol: str | None) -> str:
    if not symbol:
        return ""
    return symbol.strip().upper().replace(".PRO", "")


def to_int(value, default: int = 0) -> int:
    try:
        if value is None or value == "":
            return default
        return int(float(value))
    except Exception:
        return default


def to_float(value, default: float = 0.0) -> float:
    try:
        if value is None or value == "":
            return default
        return float(value)
    except Exception:
        return default


def load_tab_rows(path: Path, min_ts: int = 0) -> list[dict]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8-sig", errors="ignore", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        rows: list[dict] = []
        for raw in reader:
            if not raw:
                continue
            row = {str(key): (value or "").strip() for key, value in raw.items() if key is not None}
            ts = to_int(row.get("ts"))
            if min_ts and ts < min_ts:
                continue
            row["ts"] = ts
            row["pnl"] = to_float(row.get("pnl"))
            row["spread_points"] = to_float(row.get("spread_points"))
            row["score"] = to_float(row.get("score"))
            rows.append(row)
    return rows


def summarize_buckets(rows: list[dict]) -> list[dict]:
    grouped: dict[str, dict[str, float | int]] = defaultdict(lambda: {"count": 0, "pnl_sum": 0.0})
    for row in rows:
        bucket = "{}/{}/{}".format(
            row.get("setup_type") or "BRAK",
            row.get("market_regime") or "BRAK",
            row.get("spread_regime") or "BRAK",
        )
        grouped[bucket]["count"] += 1
        grouped[bucket]["pnl_sum"] += to_float(row.get("pnl"))
    items = []
    for bucket, stats in grouped.items():
        count = int(stats["count"])
        pnl_sum = float(stats["pnl_sum"])
        items.append(
            {
                "koszyk": bucket,
                "liczba": count,
                "suma_pnl": round(pnl_sum, 4),
                "sredni_pnl": round(pnl_sum / count, 4) if count else 0.0,
            }
        )
    items.sort(key=lambda item: (item["suma_pnl"], item["sredni_pnl"]))
    return items


def build_timeout_share(negative_rows: list[dict]) -> tuple[str, float]:
    if not negative_rows:
        return "", 0.0
    reasons = Counter((row.get("close_reason") or "BRAK") for row in negative_rows)
    reason, count = reasons.most_common(1)[0]
    return reason, round(count / len(negative_rows), 4)


def build_decision_reason(decision_rows: list[dict]) -> tuple[str, int]:
    if not decision_rows:
        return "", 0
    reasons = Counter((row.get("reason") or "BRAK") for row in decision_rows)
    reason, count = reasons.most_common(1)[0]
    return reason, int(count)


def choose_primary_source(
    net_today: float,
    opens_today: int,
    closes_today: int,
    trust_reason: str,
    market_regime: str,
    spread_regime: str,
    confidence_bucket: str,
    candle_quality: str,
    renko_quality: str,
    loss_streak: int,
    timeout_reason: str,
    timeout_share: float,
    cost_state: str,
    cost_to_move: float,
    cost_to_mfe: float,
) -> tuple[str, list[str]]:
    if opens_today <= 0 and closes_today <= 0:
        return "BRAK_TRANSAKCJI", []
    if net_today >= 0:
        return "BRAK_AKTYWNEJ_STRATY", []

    reasons: list[str] = []

    cost_flag = (
        "LOW_RATIO" in trust_reason
        or cost_state in {"HIGH", "NON_REPRESENTATIVE"}
        or cost_to_move >= 0.8
        or cost_to_mfe >= 0.5
        or spread_regime == "BAD"
    )
    quality_flag = (
        "FOREFIELD_DIRTY" in trust_reason
        or market_regime in {"CHAOS", "RANGE"}
        or confidence_bucket == "LOW"
        or candle_quality == "POOR"
        or renko_quality == "POOR"
    )
    timeout_flag = timeout_reason == "PAPER_TIMEOUT" and timeout_share >= 0.5
    streak_flag = loss_streak >= 3

    if cost_flag:
        reasons.append("KOSZT_I_RELACJA_RUCHU")
    if quality_flag:
        reasons.append("JAKOSC_RYNKU_I_SELEKCJI")
    if timeout_flag:
        reasons.append("WYJSCIE_CZASOWE")
    if streak_flag:
        reasons.append("SERIA_STRAT")

    if cost_flag and (cost_to_move >= 1.0 or cost_to_mfe >= 0.8 or "LOW_RATIO" in trust_reason):
        primary = "KOSZT_I_RELACJA_RUCHU"
    elif quality_flag and ("FOREFIELD_DIRTY" in trust_reason or market_regime == "CHAOS"):
        primary = "JAKOSC_RYNKU_I_SELEKCJI"
    elif timeout_flag:
        primary = "WYJSCIE_CZASOWE"
    elif streak_flag:
        primary = "SERIA_STRAT"
    elif reasons:
        primary = reasons[0]
    else:
        primary = "MIESZANE"

    return primary, reasons


def build_why_and_recommendation(
    primary_source: str,
    symbol: str,
    trust_reason: str,
    market_regime: str,
    spread_regime: str,
    cost_to_move: float,
    cost_to_mfe: float,
    timeout_reason: str,
    timeout_share: float,
    dominant_decision_reason: str,
    dominant_bucket: dict | None,
) -> tuple[str, str]:
    if primary_source == "KOSZT_I_RELACJA_RUCHU":
        why = (
            f"{symbol} traci glownie dlatego, ze koszt wejscia jest za duzy wobec ruchu rynku; "
            f"relacja kosztu do typowego ruchu wynosi {cost_to_move:.2f}, a do maksymalnego zysku {cost_to_mfe:.2f}."
        )
        recommendation = (
            "zaostrzyc filtr kosztu i nie wpuszczac wejsc, gdy koszt zjada wiekszosc potencjalnego ruchu; "
            "w tle utrzymac obserwacje, ale bez agresywnego luzowania"
        )
        return why, recommendation

    if primary_source == "JAKOSC_RYNKU_I_SELEKCJI":
        why = (
            f"{symbol} traci glownie dlatego, ze obraz rynku i selekcja wejsc sa slabe; "
            f"powod zaufania to {trust_reason or 'BRAK'}, reżim rynku {market_regime}, reżim spreadu {spread_regime}."
        )
        recommendation = (
            "zaostrzyc filtr jakosci sygnalu, foregroundu i pewnosci swiecy; "
            "nie zwiekszac agresji, dopoki nie poprawi sie jakosc wyboru wejsc"
        )
        return why, recommendation

    if primary_source == "WYJSCIE_CZASOWE":
        why = (
            f"{symbol} traci glownie dlatego, ze ujemne zamkniecia dominuja przez {timeout_reason}; "
            f"udzial tego powodu wsrod ujemnych zamkniec wynosi {timeout_share:.2%}."
        )
        recommendation = (
            "przejrzec logike wyjsc czasowych, bo pozycje zbyt czesto koncza sie timeoutem zamiast sensownym domknieciem"
        )
        return why, recommendation

    if primary_source == "SERIA_STRAT":
        why = (
            f"{symbol} traci glownie dlatego, ze wszedl w serie strat i powinien byc prowadzony bardziej zachowawczo."
        )
        recommendation = (
            "utrzymac obronny tryb ryzyka i szukac przyczyny serii strat w koszykach setupow oraz warunkach rynku"
        )
        return why, recommendation

    if primary_source == "BRAK_TRANSAKCJI":
        why = f"{symbol} nie pokazal dzis aktywnej straty, bo nie wchodzil w transakcje."
        recommendation = "pozostawic w obserwacji; nie ma tu dzis aktywnej szkody do rozliczenia"
        return why, recommendation

    if primary_source == "BRAK_AKTYWNEJ_STRATY":
        why = f"{symbol} nie pokazuje dzis aktywnej straty handlowej."
        recommendation = "utrzymac obserwacje i nie zmieniac nic tylko dlatego, ze raport jest pusty"
        return why, recommendation

    bucket_text = dominant_bucket["koszyk"] if dominant_bucket else "BRAK"
    why = (
        f"{symbol} ma mieszane zrodla szkody; dominujacy powod decyzji to {dominant_decision_reason or 'BRAK'}, "
        f"a najbardziej toksyczny koszyk to {bucket_text}."
    )
    recommendation = "rozbijac strate dalej na koszt, selekcje i wyjscie, zamiast luzowac blokady w ciemno"
    return why, recommendation


def build_symbol_report(
    instrument_entry: dict,
    runtime_state: dict[str, str],
    execution_summary: dict | None,
    learning_rows: list[dict],
    decision_rows: list[dict],
) -> dict:
    symbol_alias = normalize_symbol_alias(instrument_entry.get("instrument"))
    net_today = to_float(instrument_entry.get("netto_dzis"))
    opens_today = to_int(instrument_entry.get("otwarcia_dzis"))
    closes_today = to_int(instrument_entry.get("zamkniecia_dzis"))
    wins_today = to_int(instrument_entry.get("wygrane_dzis"))
    losses_today = to_int(instrument_entry.get("przegrane_dzis"))

    trust_state = str((execution_summary or {}).get("trust_state") or instrument_entry.get("trust_state") or "")
    trust_reason = str((execution_summary or {}).get("trust_reason") or "")
    cost_state = str((execution_summary or {}).get("cost_pressure_state") or instrument_entry.get("cost_pressure") or "")
    execution_quality = str((execution_summary or {}).get("execution_quality_state") or instrument_entry.get("execution_quality") or "")
    market_regime = str((execution_summary or {}).get("market_regime") or runtime_state.get("market_regime") or "")
    spread_regime = str((execution_summary or {}).get("spread_regime") or runtime_state.get("spread_regime") or "")
    execution_regime = str((execution_summary or {}).get("execution_regime") or runtime_state.get("execution_regime") or "")
    confidence_bucket = str((execution_summary or {}).get("confidence_bucket") or runtime_state.get("confidence_bucket") or "")
    candle_quality = str((execution_summary or {}).get("candle_quality_grade") or runtime_state.get("candle_quality_grade") or "")
    renko_quality = str((execution_summary or {}).get("renko_quality_grade") or runtime_state.get("renko_quality_grade") or "")

    loss_streak = to_int((execution_summary or {}).get("loss_streak") or runtime_state.get("loss_streak"))
    learning_samples = to_int(runtime_state.get("learning_sample_count"))
    learning_wins = to_int(runtime_state.get("learning_win_count"))
    learning_losses = to_int(runtime_state.get("learning_loss_count"))
    spread_points = to_float((execution_summary or {}).get("spread_points"))
    cost_to_move = to_float((execution_summary or {}).get("cost_spread_vs_typical_move"))
    cost_to_mfe = to_float((execution_summary or {}).get("cost_spread_vs_mfe"))

    negative_rows = [row for row in learning_rows if to_float(row.get("pnl")) < 0.0]
    timeout_reason, timeout_share = build_timeout_share(negative_rows)
    dominant_decision_reason, dominant_decision_count = build_decision_reason(decision_rows)
    toxic_buckets = summarize_buckets(negative_rows)

    primary_source, supporting_sources = choose_primary_source(
        net_today=net_today,
        opens_today=opens_today,
        closes_today=closes_today,
        trust_reason=trust_reason,
        market_regime=market_regime,
        spread_regime=spread_regime,
        confidence_bucket=confidence_bucket,
        candle_quality=candle_quality,
        renko_quality=renko_quality,
        loss_streak=loss_streak,
        timeout_reason=timeout_reason,
        timeout_share=timeout_share,
        cost_state=cost_state,
        cost_to_move=cost_to_move,
        cost_to_mfe=cost_to_mfe,
    )

    why, recommendation = build_why_and_recommendation(
        primary_source=primary_source,
        symbol=symbol_alias,
        trust_reason=trust_reason,
        market_regime=market_regime,
        spread_regime=spread_regime,
        cost_to_move=cost_to_move,
        cost_to_mfe=cost_to_mfe,
        timeout_reason=timeout_reason,
        timeout_share=timeout_share,
        dominant_decision_reason=dominant_decision_reason,
        dominant_bucket=toxic_buckets[0] if toxic_buckets else None,
    )

    return {
        "symbol_alias": symbol_alias,
        "aktywny_handlowo": bool(opens_today > 0 or closes_today > 0),
        "czy_symbol_aktywnie_traci": bool(net_today < 0.0 and (opens_today > 0 or closes_today > 0)),
        "otwarcia_dzis": opens_today,
        "zamkniecia_dzis": closes_today,
        "wygrane_dzis": wins_today,
        "przegrane_dzis": losses_today,
        "netto_dzis": round(net_today, 4),
        "zaufanie": trust_state,
        "powod_zaufania": trust_reason,
        "nacisk_kosztowy": cost_state,
        "jakosc_wykonania": execution_quality,
        "rezim_rynku": market_regime,
        "rezim_spreadu": spread_regime,
        "rezim_wykonania": execution_regime,
        "koszt_spread_punkty": round(spread_points, 4),
        "koszt_do_typowego_ruchu": round(cost_to_move, 4),
        "koszt_do_maks_zysku": round(cost_to_mfe, 4),
        "liczba_prob_uczenia": learning_samples,
        "wygrane_uczenia": learning_wins,
        "przegrane_uczenia": learning_losses,
        "seria_strat": loss_streak,
        "liczba_wierszy_uczenia_dzien": len(learning_rows),
        "liczba_wierszy_ujemnych_dzien": len(negative_rows),
        "dominujacy_powod_zamkniecia_ujemnych": timeout_reason,
        "udzial_dominujacego_powodu_zamkniecia_ujemnych": timeout_share,
        "dominujacy_powod_decyzji": dominant_decision_reason,
        "liczba_dominujacego_powodu_decyzji": dominant_decision_count,
        "toksyczne_koszyki": toxic_buckets[:3],
        "glowne_zrodlo_straty": primary_source,
        "powody_wspolwystepujace": supporting_sources,
        "czy_obecna_obrona_wyglada_sensownie": primary_source in {
            "KOSZT_I_RELACJA_RUCHU",
            "JAKOSC_RYNKU_I_SELEKCJI",
            "WYJSCIE_CZASOWE",
            "SERIA_STRAT",
        },
        "dlatego_ze": why,
        "rekomendacja": recommendation,
    }


def render_markdown(report: dict, output_path: Path) -> None:
    lines: list[str] = []
    lines.append("# Audyt Zrodel Strat Paper")
    lines.append("")
    lines.append(f"- wygenerowano_utc: `{report['generated_at_utc']}`")
    lines.append(f"- liczba_symboli: `{report['summary']['symbols_count']}`")
    lines.append(f"- aktywnie_handlujace: `{report['summary']['active_trade_symbols_count']}`")
    lines.append(f"- aktywnie_tracace: `{report['summary']['active_negative_symbols_count']}`")
    lines.append(f"- strata_aktywnych_symboli: `{report['summary']['active_negative_net_total']}`")
    lines.append("")
    lines.append("## Zrodla")
    lines.append("")
    lines.append(f"- koszt_i_relacja_ruchu: `{report['summary']['cost_driven_count']}`")
    lines.append(f"- jakosc_rynku_i_selekcji: `{report['summary']['quality_driven_count']}`")
    lines.append(f"- wyjscie_czasowe: `{report['summary']['timeout_driven_count']}`")
    lines.append(f"- seria_strat: `{report['summary']['streak_driven_count']}`")
    lines.append(f"- mieszane: `{report['summary']['mixed_count']}`")
    lines.append("")
    lines.append("## Najbardziej Ujemne")
    lines.append("")
    for item in report["top_negative_symbols"]:
        lines.append(
            f"- {item['symbol_alias']}: netto={item['netto_dzis']}, zrodlo={item['glowne_zrodlo_straty']}, dlaczego={item['dlatego_ze']}"
        )
    lines.append("")
    lines.append("## Instrumenty")
    lines.append("")
    for item in report["symbol_reports"]:
        lines.append(f"### {item['symbol_alias']}")
        lines.append("")
        lines.append(
            f"- handel_dzis: otwarcia={item['otwarcia_dzis']}, zamkniecia={item['zamkniecia_dzis']}, wynik={item['netto_dzis']}"
        )
        lines.append(
            f"- stan: zaufanie={item['zaufanie']}, koszt={item['nacisk_kosztowy']}, wykonanie={item['jakosc_wykonania']}, reżim={item['rezim_rynku']}/{item['rezim_spreadu']}"
        )
        lines.append(f"- zrodlo_straty: {item['glowne_zrodlo_straty']}")
        lines.append(f"- dlatego_ze: {item['dlatego_ze']}")
        lines.append(f"- rekomendacja: {item['rekomendacja']}")
        if item["toksyczne_koszyki"]:
            buckets = ", ".join(
                f"{bucket['koszyk']}={bucket['suma_pnl']}" for bucket in item["toksyczne_koszyki"]
            )
            lines.append(f"- toksyczne_koszyki: {buckets}")
        lines.append("")
    output_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=str(DEFAULT_PROJECT_ROOT))
    parser.add_argument("--common-root", default=str(DEFAULT_COMMON_ROOT))
    parser.add_argument("--daily-report", default=None)
    parser.add_argument("--output-json", default=None)
    parser.add_argument("--output-md", default=None)
    args = parser.parse_args()

    project_root = Path(args.project_root)
    common_root = Path(args.common_root)
    daily_report_path = Path(args.daily_report) if args.daily_report else project_root / "EVIDENCE" / "DAILY" / "raport_dzienny_latest.json"
    output_json = Path(args.output_json) if args.output_json else project_root / "EVIDENCE" / "OPS" / "paper_loss_source_audit_latest.json"
    output_md = Path(args.output_md) if args.output_md else project_root / "EVIDENCE" / "OPS" / "paper_loss_source_audit_latest.md"

    daily_report = read_json_safe(daily_report_path)
    if not daily_report:
        raise SystemExit(f"Brakuje raportu dziennego: {daily_report_path}")

    instrument_entries = daily_report.get("instrumenty") or []
    logs_root = common_root / "logs"
    state_root = common_root / "state"

    symbol_reports: list[dict] = []
    for entry in instrument_entries:
        symbol_alias = normalize_symbol_alias(entry.get("instrument"))
        runtime_state = read_key_value_table(state_root / symbol_alias / "runtime_state.csv")
        execution_summary = read_json_safe(state_root / symbol_alias / "execution_summary.json")
        day_anchor = to_int(runtime_state.get("day_anchor"))
        learning_rows = load_tab_rows(logs_root / symbol_alias / "learning_observations_v2.csv", min_ts=day_anchor)
        decision_rows = load_tab_rows(logs_root / symbol_alias / "decision_events.csv", min_ts=day_anchor)
        symbol_reports.append(
            build_symbol_report(
                instrument_entry=entry,
                runtime_state=runtime_state,
                execution_summary=execution_summary,
                learning_rows=learning_rows,
                decision_rows=decision_rows,
            )
        )

    active_negative_symbols = [
        item for item in symbol_reports if item["czy_symbol_aktywnie_traci"]
    ]
    top_negative_symbols = sorted(active_negative_symbols, key=lambda item: item["netto_dzis"])[:5]

    summary = {
        "symbols_count": len(symbol_reports),
        "active_trade_symbols_count": sum(1 for item in symbol_reports if item["aktywny_handlowo"]),
        "active_negative_symbols_count": len(active_negative_symbols),
        "active_negative_net_total": round(sum(item["netto_dzis"] for item in active_negative_symbols), 4),
        "cost_driven_count": sum(1 for item in active_negative_symbols if item["glowne_zrodlo_straty"] == "KOSZT_I_RELACJA_RUCHU"),
        "quality_driven_count": sum(1 for item in active_negative_symbols if item["glowne_zrodlo_straty"] == "JAKOSC_RYNKU_I_SELEKCJI"),
        "timeout_driven_count": sum(1 for item in active_negative_symbols if item["glowne_zrodlo_straty"] == "WYJSCIE_CZASOWE"),
        "streak_driven_count": sum(1 for item in active_negative_symbols if item["glowne_zrodlo_straty"] == "SERIA_STRAT"),
        "mixed_count": sum(1 for item in active_negative_symbols if item["glowne_zrodlo_straty"] == "MIESZANE"),
        "no_active_loss_count": sum(1 for item in symbol_reports if item["glowne_zrodlo_straty"] in {"BRAK_TRANSAKCJI", "BRAK_AKTYWNEJ_STRATY"}),
    }

    report = {
        "schema_version": "1.0",
        "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "summary": summary,
        "top_negative_symbols": top_negative_symbols,
        "symbol_reports": sorted(symbol_reports, key=lambda item: (item["netto_dzis"], item["symbol_alias"])),
    }

    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_md.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    render_markdown(report, output_md)


if __name__ == "__main__":
    main()
