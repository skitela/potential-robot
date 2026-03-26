from __future__ import annotations

import argparse
import csv
import json
from datetime import UTC, datetime
from pathlib import Path

import duckdb


def read_json(path: Path):
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8-sig"))


def normalize_symbol(value: str | None) -> str:
    if not value:
        return ""
    return value.strip().upper().replace(".PRO", "")


def iso_local(value) -> str | None:
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value.isoformat(sep=" ")
    return str(value)


def file_mtime_local(path: Path) -> str | None:
    if not path.exists():
        return None
    return datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")


def build_symbol_specs(profile: dict | None) -> tuple[list[str], dict[str, dict]]:
    order: list[str] = []
    specs: dict[str, dict] = {}

    if not profile:
        return order, specs

    for section in ("present", "missing", "blocked"):
        for entry in profile.get(section, []):
            alias = normalize_symbol(entry.get("symbol_alias"))
            if not alias:
                continue
            if alias not in order:
                order.append(alias)

            existing = specs.get(alias, {})
            merged = {
                "symbol_alias": alias,
                "broker_symbol": entry.get("broker_symbol"),
                "qdm_symbol": entry.get("qdm_symbol"),
                "datasource": entry.get("datasource"),
                "datatype": entry.get("datatype"),
                "date_from": entry.get("date_from"),
                "date_to": entry.get("date_to"),
                "notes": entry.get("notes"),
                "mt5_export_name": entry.get("mt5_export_name"),
                "history_ready": bool(entry.get("history_ready", section == "present")),
                "history_file": entry.get("history_file"),
                "history_size_mb": float(entry.get("history_size_mb", 0.0) or 0.0),
                "history_last_write_local": entry.get("history_last_write_local"),
                "export_present": bool(entry.get("export_present", section == "present")),
                "export_file": entry.get("export_file"),
                "export_path": entry.get("export_path"),
                "export_size_mb": float(entry.get("export_size_mb", 0.0) or 0.0),
                "export_last_write_local": entry.get("export_last_write_local"),
                "cache_present": bool(entry.get("cache_present", False)),
                "cache_minute_rows": int(float(entry.get("cache_minute_rows", 0) or 0)),
                "cache_minute_parquet_path": entry.get("cache_minute_parquet_path"),
                "blocked_reason": entry.get("reason") if section == "blocked" else None,
            }
            for key, value in merged.items():
                if value not in (None, "", 0, 0.0, False):
                    existing[key] = value
                elif key not in existing:
                    existing[key] = value
            specs[alias] = existing

    for alias, spec in specs.items():
        export_name = spec.get("mt5_export_name")
        if not export_name:
            export_file = str(spec.get("export_file") or "")
            if export_file:
                export_name = Path(export_file).stem
                spec["mt5_export_name"] = export_name

    return order, specs


def query_candidate_stats(con: duckdb.DuckDBPyConnection, parquet_path: Path) -> dict[str, dict]:
    if not parquet_path.exists():
        return {}
    rows = con.execute(
        f"""
        select
            upper(trim(symbol_alias)) as symbol_alias,
            count(*) as candidate_rows,
            min(date_trunc('minute', epoch_ms(cast(ts as bigint) * 1000))) as candidate_bar_min,
            max(date_trunc('minute', epoch_ms(cast(ts as bigint) * 1000))) as candidate_bar_max
        from read_parquet('{parquet_path.as_posix()}')
        where symbol_alias is not null and trim(symbol_alias) <> ''
        group by 1
        """
    ).fetchall()
    return {
        str(symbol): {
            "candidate_rows": int(rows_total),
            "candidate_bar_min": candidate_bar_min,
            "candidate_bar_max": candidate_bar_max,
        }
        for symbol, rows_total, candidate_bar_min, candidate_bar_max in rows
    }


def query_qdm_stats(con: duckdb.DuckDBPyConnection, parquet_path: Path) -> dict[str, dict]:
    if not parquet_path.exists():
        return {}
    rows = con.execute(
        f"""
        select
            upper(trim(symbol_alias)) as symbol_alias,
            count(*) as qdm_rows,
            min(bar_minute) as qdm_bar_min,
            max(bar_minute) as qdm_bar_max
        from read_parquet('{parquet_path.as_posix()}')
        where symbol_alias is not null and trim(symbol_alias) <> ''
        group by 1
        """
    ).fetchall()
    return {
        str(symbol): {
            "qdm_rows": int(rows_total),
            "qdm_bar_min": qdm_bar_min,
            "qdm_bar_max": qdm_bar_max,
        }
        for symbol, rows_total, qdm_bar_min, qdm_bar_max in rows
    }


def query_current_coverage(con: duckdb.DuckDBPyConnection, candidate_path: Path, qdm_path: Path) -> dict[str, dict]:
    if not candidate_path.exists() or not qdm_path.exists():
        return {}
    rows = con.execute(
        f"""
        with candidate as (
            select
                upper(trim(symbol_alias)) as symbol_alias,
                date_trunc('minute', epoch_ms(cast(ts as bigint) * 1000)) as bar_minute
            from read_parquet('{candidate_path.as_posix()}')
            where symbol_alias is not null and trim(symbol_alias) <> ''
        ),
        qdm as (
            select
                upper(trim(symbol_alias)) as symbol_alias,
                bar_minute
            from read_parquet('{qdm_path.as_posix()}')
            where symbol_alias is not null and trim(symbol_alias) <> ''
        )
        select
            candidate.symbol_alias,
            count(*) as candidate_rows,
            sum(case when qdm.symbol_alias is not null then 1 else 0 end) as matched_rows,
            round(sum(case when qdm.symbol_alias is not null then 1 else 0 end) * 1.0 / count(*), 4) as coverage_ratio
        from candidate
        left join qdm
            on candidate.symbol_alias = qdm.symbol_alias
           and candidate.bar_minute = qdm.bar_minute
        group by 1
        """
    ).fetchall()
    return {
        str(symbol): {
            "candidate_rows": int(candidate_rows),
            "matched_rows": int(matched_rows or 0),
            "coverage_ratio": float(coverage_ratio or 0.0),
        }
        for symbol, candidate_rows, matched_rows, coverage_ratio in rows
    }


def build_trained_coverage_map(metrics: dict | None) -> tuple[dict[str, float], list[str], float]:
    coverage_map: dict[str, float] = {}
    visible_symbols: list[str] = []
    row_ratio = 0.0
    if not metrics:
        return coverage_map, visible_symbols, row_ratio

    coverage = ((metrics.get("dataset") or {}).get("qdm_coverage") or {})
    visible_symbols = [normalize_symbol(symbol) for symbol in coverage.get("symbols_with_qdm", []) if normalize_symbol(symbol)]
    row_ratio = float(coverage.get("row_coverage_ratio", 0.0) or 0.0)
    for item in coverage.get("symbol_coverage", []):
        symbol = normalize_symbol(item.get("symbol"))
        if not symbol:
            continue
        coverage_map[symbol] = float(item.get("coverage_ratio", 0.0) or 0.0)
    return coverage_map, visible_symbols, row_ratio


def classify(spec: dict, candidate: dict, qdm: dict, current_cov: dict, trained_cov: float) -> tuple[str, bool, bool, str]:
    candidate_rows = int(candidate.get("candidate_rows", 0))
    qdm_rows = int(qdm.get("qdm_rows", 0))
    current_ratio = float(current_cov.get("coverage_ratio", 0.0))
    history_ready = bool(spec.get("history_ready", False))
    export_present = bool(spec.get("export_present", False))
    blocked_reason = spec.get("blocked_reason")
    candidate_bar_min = candidate.get("candidate_bar_min")
    candidate_bar_max = candidate.get("candidate_bar_max")
    qdm_bar_max = qdm.get("qdm_bar_max")

    refresh_required = False
    retrain_required = False

    if blocked_reason:
        return "BLOKADA_QDM", refresh_required, retrain_required, "symbol jest jawnie zablokowany w odzysku QDM"

    if candidate_rows <= 0:
        return "BRAK_KANDYDATOW", refresh_required, retrain_required, "symbol nie produkuje jeszcze kandydatow do globalnego treningu"

    if current_ratio >= 0.95:
        if trained_cov < 0.95:
            retrain_required = True
            return "GLOBALNY_TRENING_NIEAKTUALNY", refresh_required, retrain_required, "kontrakt widzi QDM, ale ostatni globalny trening lub jego metryki sa nieaktualne"
        return "QDM_WIDOCZNE", refresh_required, retrain_required, "QDM jest widoczne w aktualnym kontrakcie i nie widac luki joinu"

    if qdm_rows <= 0:
        if history_ready and not export_present:
            refresh_required = True
            return "BRAK_AKTYWNEGO_EKSPORTU_MT5", refresh_required, retrain_required, "historia raw jest gotowa, ale nie ma aktywnego eksportu MT5 dla QDM"
        if history_ready:
            refresh_required = True
            return "PUSTY_KONTRAKT_QDM", refresh_required, retrain_required, "eksport lub cache istnieje, ale kontrakt QDM jest pusty dla tego symbolu"
        return "BRAK_QDM", refresh_required, retrain_required, "brakuje gotowego toru QDM dla symbolu"

    if candidate_bar_min and qdm_bar_max and qdm_bar_max < candidate_bar_min:
        refresh_required = history_ready
        return "CACHE_QDM_STARSZY_NIZ_OKNO_KANDYDATOW", refresh_required, retrain_required, "QDM konczy sie przed pierwszym kandydatem i nie moze zasilic globalnego treningu"

    if candidate_bar_max and qdm_bar_max and qdm_bar_max < candidate_bar_max:
        refresh_required = history_ready
        return "QDM_NIE_SIEGA_DO_KONCA_OKNA_KANDYDATOW", refresh_required, retrain_required, "QDM nie dochodzi do konca okna kandydatow i daje zerowe lub zbyt niskie pokrycie"

    return "ROZJAZD_ALIASU_LUB_CZASU", refresh_required, retrain_required, "QDM istnieje, ale laczenie nadal nie widzi zgodnosci czasu lub aliasu"


def recommendation_for(root_cause: str) -> str:
    mapping = {
        "BRAK_KANDYDATOW": "szukac przyczyny w strategii, progach i filtrach budowy kandydatow",
        "BRAK_AKTYWNEGO_EKSPORTU_MT5": "odswiezyc eksport QDM do MT5 dla symbolu",
        "PUSTY_KONTRAKT_QDM": "przebudowac kontrakt QDM i sprawdzic cache oraz eksport",
        "CACHE_QDM_STARSZY_NIZ_OKNO_KANDYDATOW": "odswiezyc eksport QDM, bo cache jest starszy niz kandydaty",
        "QDM_NIE_SIEGA_DO_KONCA_OKNA_KANDYDATOW": "odswiezyc eksport QDM do swiezszego okna",
        "ROZJAZD_ALIASU_LUB_CZASU": "sprawdzic alias symbolu i sposob zaokraglania czasu do minuty",
        "GLOBALNY_TRENING_NIEAKTUALNY": "przetrenowac globalny model lub odswiezyc jego metryki po naprawie kontraktu",
        "QDM_WIDOCZNE": "utrzymac pod nadzorem; symbol ma juz poprawny sygnal QDM",
        "BLOKADA_QDM": "usunac blokade albo potwierdzic, ze symbol ma pozostac poza odzyskiem",
    }
    return mapping.get(root_cause, "utrzymac pod nadzorem i diagnozowac dalej")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--qdm-profile", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_missing_only_profile_latest.json")
    parser.add_argument("--candidate-contract", default=r"C:\TRADING_DATA\RESEARCH\datasets\contracts\candidate_signals_norm_latest.parquet")
    parser.add_argument("--qdm-minute-bars", default=r"C:\TRADING_DATA\RESEARCH\datasets\qdm_minute_bars_latest.parquet")
    parser.add_argument("--global-metrics", default=r"C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor\paper_gate_acceptor_metrics_latest.json")
    parser.add_argument("--output-json", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_visibility_refresh_profile_latest.json")
    parser.add_argument("--output-md", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_visibility_refresh_profile_latest.md")
    parser.add_argument("--output-csv", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_visibility_refresh_pack_latest.csv")
    args = parser.parse_args()

    qdm_profile = read_json(Path(args.qdm_profile))
    global_metrics_path = Path(args.global_metrics)
    global_metrics = read_json(global_metrics_path)

    order, specs = build_symbol_specs(qdm_profile)
    con = duckdb.connect()
    candidate_stats = query_candidate_stats(con, Path(args.candidate_contract))
    qdm_stats = query_qdm_stats(con, Path(args.qdm_minute_bars))
    current_coverage = query_current_coverage(con, Path(args.candidate_contract), Path(args.qdm_minute_bars))
    con.close()

    trained_coverage_map, trained_visible_symbols, trained_row_ratio = build_trained_coverage_map(global_metrics)

    items: list[dict] = []
    refresh_rows: list[dict] = []

    for alias in order:
        spec = specs.get(alias, {})
        candidate = candidate_stats.get(alias, {})
        qdm = qdm_stats.get(alias, {})
        current_cov = current_coverage.get(alias, {})
        trained_cov = float(trained_coverage_map.get(alias, 0.0) or 0.0)

        root_cause, refresh_required, retrain_required, why = classify(spec, candidate, qdm, current_cov, trained_cov)
        item = {
            "symbol_alias": alias,
            "qdm_symbol": spec.get("qdm_symbol"),
            "mt5_export_name": spec.get("mt5_export_name"),
            "history_ready": bool(spec.get("history_ready", False)),
            "export_present": bool(spec.get("export_present", False)),
            "cache_present": bool(spec.get("cache_present", False)),
            "candidate_rows": int(candidate.get("candidate_rows", 0)),
            "candidate_bar_min": iso_local(candidate.get("candidate_bar_min")),
            "candidate_bar_max": iso_local(candidate.get("candidate_bar_max")),
            "qdm_rows": int(qdm.get("qdm_rows", 0)),
            "qdm_bar_min": iso_local(qdm.get("qdm_bar_min")),
            "qdm_bar_max": iso_local(qdm.get("qdm_bar_max")),
            "current_contract_qdm_coverage_ratio": round(float(current_cov.get("coverage_ratio", 0.0) or 0.0), 4),
            "current_contract_matched_rows": int(current_cov.get("matched_rows", 0)),
            "trained_global_qdm_coverage_ratio": round(trained_cov, 4),
            "refresh_required": refresh_required,
            "retrain_required": retrain_required,
            "main_root_cause": root_cause,
            "dlatego_ze": why,
            "recommendation": recommendation_for(root_cause),
        }
        items.append(item)

        if refresh_required and spec.get("mt5_export_name") and spec.get("datasource") and spec.get("datatype"):
            refresh_rows.append(
                {
                    "enabled": "1",
                    "symbol": spec.get("qdm_symbol"),
                    "datasource": spec.get("datasource"),
                    "datatype": spec.get("datatype"),
                    "date_from": spec.get("date_from") or "",
                    "date_to": spec.get("date_to") or "",
                    "mt5_export_name": spec.get("mt5_export_name"),
                    "notes": f"{spec.get('notes') or 'registry'}|refresh_required|{root_cause}",
                }
            )

    refresh_rows.sort(key=lambda row: normalize_symbol(row.get("mt5_export_name")))
    items.sort(key=lambda row: (0 if row["refresh_required"] else 1, 0 if row["retrain_required"] else 1, row["symbol_alias"]))

    current_visible_symbols = [
        item["symbol_alias"]
        for item in items
        if item["candidate_rows"] > 0 and item["current_contract_qdm_coverage_ratio"] >= 0.95
    ]
    retrain_required_symbols = [item["symbol_alias"] for item in items if item["retrain_required"]]
    refresh_required_symbols = [item["symbol_alias"] for item in items if item["refresh_required"]]
    metrics_last_write_local = file_mtime_local(global_metrics_path)

    report = {
        "schema_version": "1.0",
        "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "summary": {
            "total_symbols": len(items),
            "candidate_symbols_count": sum(1 for item in items if item["candidate_rows"] > 0),
            "current_contract_qdm_visible_symbols_count": len(current_visible_symbols),
            "trained_global_qdm_visible_symbols_count": len(trained_visible_symbols),
            "refresh_required_count": len(refresh_required_symbols),
            "retrain_required_count": len(retrain_required_symbols),
            "no_candidate_count": sum(1 for item in items if item["main_root_cause"] == "BRAK_KANDYDATOW"),
            "manual_investigation_count": sum(1 for item in items if item["main_root_cause"] == "ROZJAZD_ALIASU_LUB_CZASU"),
            "trained_global_qdm_row_coverage_ratio": round(trained_row_ratio, 4),
            "metrics_last_write_local": metrics_last_write_local,
        },
        "current_contract_qdm_visible_symbols": current_visible_symbols,
        "trained_global_qdm_visible_symbols": trained_visible_symbols,
        "refresh_required": [item for item in items if item["refresh_required"]],
        "retrain_required": [item for item in items if item["retrain_required"]],
        "top_manual_investigation": [item for item in items if item["main_root_cause"] == "ROZJAZD_ALIASU_LUB_CZASU"][:8],
        "items": items,
    }

    output_json = Path(args.output_json)
    output_md = Path(args.output_md)
    output_csv = Path(args.output_csv)
    output_json.parent.mkdir(parents=True, exist_ok=True)

    output_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    with output_csv.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["enabled", "symbol", "datasource", "datatype", "date_from", "date_to", "mt5_export_name", "notes"],
        )
        writer.writeheader()
        writer.writerows(refresh_rows)

    lines = [
        "# QDM Visibility Refresh Profile",
        "",
        f"- generated_at_local: {report['generated_at_local']}",
        f"- current_contract_qdm_visible_symbols_count: {report['summary']['current_contract_qdm_visible_symbols_count']}",
        f"- trained_global_qdm_visible_symbols_count: {report['summary']['trained_global_qdm_visible_symbols_count']}",
        f"- refresh_required_count: {report['summary']['refresh_required_count']}",
        f"- retrain_required_count: {report['summary']['retrain_required_count']}",
        f"- metrics_last_write_local: {metrics_last_write_local}",
        "",
        "## Refresh Required",
        "",
    ]
    if not report["refresh_required"]:
        lines.append("- none")
    else:
        for item in report["refresh_required"]:
            lines.append(
                f"- {item['symbol_alias']}: cause={item['main_root_cause']}, candidate_max={item['candidate_bar_max']}, qdm_max={item['qdm_bar_max']}, export_present={item['export_present']}, coverage={item['current_contract_qdm_coverage_ratio']}"
            )
    lines.extend(["", "## Retrain Required", ""])
    if not report["retrain_required"]:
        lines.append("- none")
    else:
        for item in report["retrain_required"]:
            lines.append(
                f"- {item['symbol_alias']}: current_coverage={item['current_contract_qdm_coverage_ratio']}, trained_coverage={item['trained_global_qdm_coverage_ratio']}, cause={item['main_root_cause']}"
            )

    output_md.write_text("\r\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
