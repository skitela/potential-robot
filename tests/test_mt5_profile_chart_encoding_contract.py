from __future__ import annotations

import importlib.util
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


def test_write_chart_text_writes_single_bom(tmp_path: Path) -> None:
    mod = _load_setup_module()
    chart_path = tmp_path / "chart01.chr"
    text_with_duplicated_bom = "\ufeff\ufeff<chart>\r\nsymbol=EURUSD.pro\r\n</chart>\r\n"

    mod._write_chart_text(chart_path, text_with_duplicated_bom)

    raw = chart_path.read_bytes()
    assert raw.startswith(b"\xff\xfe"), "UTF-16LE BOM missing"
    # Ensure we do not write duplicated BOM bytes at file start.
    assert not raw.startswith(b"\xff\xfe\xff\xfe"), "Duplicated BOM written"
    decoded = raw.decode("utf-16")
    assert decoded.startswith("<chart>"), "Leading BOM character leaked into CHR payload"
