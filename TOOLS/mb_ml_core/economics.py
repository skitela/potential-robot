from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .io_utils import safe_float


@dataclass(slots=True)
class BrokerEconomics:
    symbol_alias: str
    broker_symbol: str
    broker_name: str
    account_currency: str
    contract_size: float
    tick_size: float
    tick_value_account_ccy: float
    spread_points_modeled: float = 0.0
    slippage_points_modeled: float = 0.0
    commission_per_lot_account_ccy: float = 0.0
    swap_long_account_ccy: float = 0.0
    swap_short_account_ccy: float = 0.0
    extra_fee_account_ccy: float = 0.0
    fx_to_pln_default: float = 1.0


@dataclass(slots=True)
class BrokerNetResult:
    gross_pln: float
    spread_cost_pln: float
    slippage_cost_pln: float
    commission_pln: float
    swap_pln: float
    extra_fee_pln: float
    net_pln: float
    edge_after_cost_pln: float
    edge_after_cost_bps: float


def make_broker_economics(row: dict[str, Any] | Any) -> BrokerEconomics:
    get = row.get if hasattr(row, "get") else lambda k, default=None: getattr(row, k, default)
    return BrokerEconomics(
        symbol_alias=str(get("symbol_alias", "UNKNOWN")),
        broker_symbol=str(get("broker_symbol", get("symbol_alias", "UNKNOWN"))),
        broker_name=str(get("broker_name", "OANDA_MT5")),
        account_currency=str(get("account_currency", "PLN")),
        contract_size=safe_float(get("contract_size", 1.0), 1.0),
        tick_size=max(safe_float(get("tick_size", 0.0001), 0.0001), 1e-12),
        tick_value_account_ccy=safe_float(get("tick_value_account_ccy", 1.0), 1.0),
        spread_points_modeled=safe_float(get("spread_points_modeled", 0.0), 0.0),
        slippage_points_modeled=safe_float(get("slippage_points_modeled", 0.0), 0.0),
        commission_per_lot_account_ccy=safe_float(get("commission_per_lot_account_ccy", 0.0), 0.0),
        swap_long_account_ccy=safe_float(get("swap_long_account_ccy", 0.0), 0.0),
        swap_short_account_ccy=safe_float(get("swap_short_account_ccy", 0.0), 0.0),
        extra_fee_account_ccy=safe_float(get("extra_fee_account_ccy", 0.0), 0.0),
        fx_to_pln_default=max(safe_float(get("fx_to_pln_default", 1.0), 1.0), 1e-12),
    )


def compute_trade_result(
    economics: BrokerEconomics,
    lots: float,
    side: str,
    pnl_account_ccy: float | None = None,
    entry_price: float | None = None,
    exit_price: float | None = None,
    held_minutes: int = 1,
    spread_points_entry: float | None = None,
    spread_points_exit: float | None = None,
    slippage_points_actual: float | None = None,
    commission_account_ccy: float | None = None,
    swap_account_ccy: float | None = None,
    extra_fee_account_ccy: float | None = None,
    fx_to_pln: float | None = None,
) -> BrokerNetResult:
    fx = economics.fx_to_pln_default if fx_to_pln in (None, 0, 0.0) else float(fx_to_pln)
    if pnl_account_ccy is None:
        if entry_price is not None and exit_price is not None:
            delta = (float(exit_price) - float(entry_price)) if str(side).upper() == "BUY" else (float(entry_price) - float(exit_price))
            pnl_account_ccy = (delta / economics.tick_size) * economics.tick_value_account_ccy * lots
        else:
            pnl_account_ccy = 0.0

    spread_entry = economics.spread_points_modeled if spread_points_entry is None else float(spread_points_entry)
    spread_exit = 0.0 if spread_points_exit is None else float(spread_points_exit)
    slippage_points = economics.slippage_points_modeled if slippage_points_actual is None else float(slippage_points_actual)
    commission_account_ccy = economics.commission_per_lot_account_ccy * lots if commission_account_ccy is None else float(commission_account_ccy)
    swap_account_ccy = (
        (economics.swap_long_account_ccy if str(side).upper() == "BUY" else economics.swap_short_account_ccy)
        * max(1.0, held_minutes / 1440.0)
        if swap_account_ccy is None else float(swap_account_ccy)
    )
    extra_fee_account_ccy = economics.extra_fee_account_ccy * lots if extra_fee_account_ccy is None else float(extra_fee_account_ccy)

    gross_pln = float(pnl_account_ccy) * fx
    spread_cost_pln = (spread_entry + spread_exit) * economics.tick_value_account_ccy * lots * fx
    slippage_cost_pln = slippage_points * economics.tick_value_account_ccy * lots * fx
    commission_pln = commission_account_ccy * fx
    swap_pln = swap_account_ccy * fx
    extra_fee_pln = extra_fee_account_ccy * fx

    total_cost_pln = spread_cost_pln + slippage_cost_pln + commission_pln + swap_pln + extra_fee_pln
    net_pln = gross_pln - total_cost_pln
    denom = max(1.0, abs(gross_pln) + total_cost_pln)
    return BrokerNetResult(
        gross_pln=gross_pln,
        spread_cost_pln=spread_cost_pln,
        slippage_cost_pln=slippage_cost_pln,
        commission_pln=commission_pln,
        swap_pln=swap_pln,
        extra_fee_pln=extra_fee_pln,
        net_pln=net_pln,
        edge_after_cost_pln=net_pln,
        edge_after_cost_bps=(net_pln / denom) * 10000.0,
    )
