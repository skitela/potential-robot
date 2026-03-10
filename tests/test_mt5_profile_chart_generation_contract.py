from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path


def _load_setup_module():
    src = Path("TOOLS/setup_mt5_hybrid_profile.py").resolve()
    spec = importlib.util.spec_from_file_location("setup_mt5_hybrid_profile", src)
    assert spec and spec.loader, "Cannot load setup_mt5_hybrid_profile.py"
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)  # type: ignore[attr-defined]
    return mod


def _valid_template(chart_id: str, extra: str = "") -> str:
    return (
        "<chart>\r\n"
        f"id={chart_id}\r\n"
        "symbol=EURUSD.pro\r\n"
        "description=EUR/USD\r\n"
        "period_type=0\r\n"
        "period_size=5\r\n"
        "<expert>\r\n"
        "name=HybridAgent\r\n"
        "path=Experts\\HybridAgent.ex5\r\n"
        "expertmode=5\r\n"
        "<inputs>\r\n"
        "InpPolicyRuntimeReloadSec=15\r\n"
        "</inputs>\r\n"
        "</expert>\r\n"
        "<window>\r\n"
        "height=100\r\n"
        "</window>\r\n"
        f"{extra}"
        "</chart>\r\n"
    )


def _base_template_without_expert(chart_id: str) -> str:
    return (
        "<chart>\r\n"
        f"id={chart_id}\r\n"
        "symbol=EURUSD\r\n"
        "description=EUR/USD\r\n"
        "period_type=1\r\n"
        "period_size=1\r\n"
        "<window>\r\n"
        "height=100\r\n"
        "</window>\r\n"
        "</chart>\r\n"
    )


def test_write_profile_assigns_unique_chart_ids(tmp_path: Path) -> None:
    mod = _load_setup_module()
    data_dir = tmp_path / "data"
    template_path = tmp_path / "template.chr"
    template_path.write_text(_valid_template("111111111111111111"), encoding="utf-16le")

    profile_dir = mod._write_profile(
        data_dir=data_dir,
        profile_name="OANDA_HYBRID_AUTO",
        symbols=["EURUSD.pro", "GBPUSD.pro", "USDJPY.pro"],
        template_path=template_path,
    )

    ids = []
    for chart in sorted(profile_dir.glob("*.chr")):
        txt = chart.read_text(encoding="utf-16le")
        m = re.search(r"(?m)^id=(\d+)$", txt)
        assert m, f"Missing id in {chart.name}"
        ids.append(m.group(1))
    assert len(ids) == 3
    assert len(set(ids)) == 3, "Chart IDs must be unique per profile"


def test_pick_source_chart_prefers_stable_profiles_over_backups(tmp_path: Path) -> None:
    mod = _load_setup_module()
    data_dir = tmp_path / "data"
    charts_root = data_dir / "MQL5" / "Profiles" / "Charts"
    stable_dir = charts_root / "Default"
    backup_dir = charts_root / "OANDA_HYBRID_AUTO_backup_1700000000"
    preferred_dir = charts_root / "OANDA_HYBRID_AUTO"
    stable_dir.mkdir(parents=True, exist_ok=True)
    backup_dir.mkdir(parents=True, exist_ok=True)
    preferred_dir.mkdir(parents=True, exist_ok=True)

    (stable_dir / "chart01.chr").write_text(
        _valid_template("123", extra="comment=stable_template_payload_longer\r\n"),
        encoding="utf-16le",
    )
    (backup_dir / "chart01.chr").write_text(
        _valid_template("456"),
        encoding="utf-16le",
    )
    (preferred_dir / "chart01.chr").write_text(
        _valid_template("789"),
        encoding="utf-16le",
    )

    picked = mod._pick_source_chart(data_dir=data_dir, profile_name="OANDA_HYBRID_AUTO")
    assert picked is not None
    assert picked.parent.name == "Default"


def test_pick_source_chart_prefers_backup_over_generated_profile(tmp_path: Path) -> None:
    mod = _load_setup_module()
    data_dir = tmp_path / "data"
    charts_root = data_dir / "MQL5" / "Profiles" / "Charts"
    backup_dir = charts_root / "OANDA_HYBRID_AUTO_backup_1700000000"
    preferred_dir = charts_root / "OANDA_HYBRID_AUTO"
    backup_dir.mkdir(parents=True, exist_ok=True)
    preferred_dir.mkdir(parents=True, exist_ok=True)

    # Prefer lean backup chart instead of reusing generated profile as source template.
    (backup_dir / "chart01.chr").write_text(
        _valid_template("456", extra="objects=0\r\n"),
        encoding="utf-16le",
    )
    (preferred_dir / "chart01.chr").write_text(
        _valid_template("789", extra=("objects=300\r\n" + ("<object>\r\nname=x\r\n</object>\r\n" * 3))),
        encoding="utf-16le",
    )

    picked = mod._pick_source_chart(data_dir=data_dir, profile_name="OANDA_HYBRID_AUTO")
    assert picked is not None
    assert "backup" in picked.parent.name.lower()


def test_pick_source_chart_falls_back_to_plain_chart_template_when_hybrid_missing(tmp_path: Path) -> None:
    mod = _load_setup_module()
    data_dir = tmp_path / "data"
    charts_root = data_dir / "MQL5" / "Profiles" / "Charts"
    stable_dir = charts_root / "Default"
    stable_dir.mkdir(parents=True, exist_ok=True)
    (stable_dir / "chart01.chr").write_text(_base_template_without_expert("101"), encoding="utf-16le")

    picked = mod._pick_source_chart(data_dir=data_dir, profile_name="OANDA_HYBRID_AUTO")
    assert picked is not None
    assert picked.parent.name == "Default"

    built = mod._build_chart_text(
        template_text=(stable_dir / "chart01.chr").read_text(encoding="utf-16le"),
        symbol="EURUSD.pro",
        description="EUR/USD",
        chart_id="999",
    )
    assert "name=HybridAgent" in built
    assert r"path=Experts\HybridAgent.ex5" in built
    assert "InpPolicyRuntimeRequireFile=true" in built


def test_build_chart_text_strips_ui_objects_noise(tmp_path: Path) -> None:
    mod = _load_setup_module()
    template = _valid_template(
        "111",
        extra=(
            "objects=3\r\n"
            "<object>\r\nname=a\r\n</object>\r\n"
            "<object>\r\nname=b\r\n</object>\r\n"
            "<object>\r\nname=c\r\n</object>\r\n"
        ),
    )
    built = mod._build_chart_text(
        template_text=template,
        symbol="EURUSD.pro",
        description="EUR/USD",
        chart_id="222",
    )
    assert "objects=0" in built
    assert "<object>" not in built
    assert built.count("<window>") == 1
    assert "name=Main" in built
    assert "path=" in built


def test_build_chart_text_normalizes_window_geometry() -> None:
    mod = _load_setup_module()
    template = _valid_template("333")
    built = mod._build_chart_text(
        template_text=template,
        symbol="GBPUSD.pro",
        description="GBP/USD",
        chart_id="444",
    )
    assert "window_left=20" in built
    assert "window_top=20" in built
    assert "window_right=1280" in built
    assert "window_bottom=760" in built
    assert "windows_total=1" in built
