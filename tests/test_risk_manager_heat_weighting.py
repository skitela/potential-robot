import sys
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from BIN.risk_manager import RiskManager


def _mk_pos(symbol: str, price_open: float, sl: float, volume: float):
    return SimpleNamespace(symbol=symbol, price_open=price_open, sl=sl, volume=volume)


def _mk_engine():
    info = SimpleNamespace(trade_tick_size=1.0, trade_tick_value=1.0)
    return SimpleNamespace(symbol_info_cached=lambda *_args, **_kwargs: info)


def _mk_cfg(cross_weight: float):
    return SimpleNamespace(
        risk={
            "max_positions_parallel": 5,
            "max_positions_per_symbol": 1,
            "max_open_risk_pct": 0.02,
            "portfolio_heat_same_group_weight": 1.0,
            "portfolio_heat_cross_group_weight": float(cross_weight),
        }
    )


def test_cross_group_weight_allows_active_group_entry():
    rm = RiskManager(_mk_cfg(cross_weight=0.55), db=None)
    positions = [
        _mk_pos("EU50.pro", price_open=100.0, sl=94.0, volume=1.0),   # risk=6
        _mk_pos("US30.pro", price_open=100.0, sl=94.0, volume=1.0),   # risk=6
    ]
    allowed = rm.check_portfolio_heat(
        our_positions=positions,
        eq_now=1000.0,                 # max_open_risk_money = 20
        symbol="GOLD.pro",             # new group=METAL
        new_trade_risk_money=12.5,     # weighted open = 12 * 0.55 = 6.6 ; total=19.1 <= 20
        mt_client=_mk_engine(),
        db=None,
        grp="METAL",
    )
    assert allowed is True


def test_without_cross_group_discount_entry_is_blocked():
    rm = RiskManager(_mk_cfg(cross_weight=1.0), db=None)
    positions = [
        _mk_pos("EU50.pro", price_open=100.0, sl=94.0, volume=1.0),   # risk=6
        _mk_pos("US30.pro", price_open=100.0, sl=94.0, volume=1.0),   # risk=6
    ]
    blocked = rm.check_portfolio_heat(
        our_positions=positions,
        eq_now=1000.0,                 # max=20
        symbol="GOLD.pro",
        new_trade_risk_money=12.5,     # raw open=12 ; total=24.5 > 20
        mt_client=_mk_engine(),
        db=None,
        grp="METAL",
    )
    assert blocked is False

