from __future__ import annotations
import logging
from typing import Any, Dict, List, Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from .config_manager import ConfigManager

class RiskManager:
    """
    Encapsulates all logic related to trade risk assessment and portfolio heat management.
    """
    def __init__(self, config: ConfigManager | Any, db: Any):
        self.config = config
        self.db = db

    def daily_loss_guard(self, symbol: str, mode: str, dd_pct: float) -> bool:
        """
        Checks if the daily drawdown percentage exceeds soft or hard limits.
        Returns True if trading can continue, False otherwise.
        """
        risk_cfg = self.config.risk
        soft_loss_pct = float(risk_cfg['daily_loss_soft_pct'])
        hard_loss_pct = float(risk_cfg['daily_loss_hard_pct'])

        hard_loss = (dd_pct >= hard_loss_pct)
        if hard_loss:
            logging.info(f"SKIP_DAILY_LOSS_HARD {symbol} dd={dd_pct:.4f} lim={hard_loss_pct}")
            return False

        soft_loss = (dd_pct >= soft_loss_pct)
        if soft_loss and str(mode).upper() != "HOT":
            logging.info(f"SKIP_DAILY_LOSS_SOFT {symbol} mode={mode} dd={dd_pct:.4f} lim={soft_loss_pct}")
            return False
            
        return True

    def get_risk_pct(self, mode: str, is_soft_loss: bool) -> float:
        """
        Determines the risk percentage for a trade based on the current mode and daily loss status.
        """
        risk_cfg = self.config.risk
        m_upper = str(mode).upper()
        
        if m_upper == "HOT":
            risk_pct = float(risk_cfg['risk_scalp_pct'])
            risk_pct = max(float(risk_cfg['risk_scalp_min_pct']), min(float(risk_cfg['risk_scalp_max_pct']), risk_pct))
        else: # WARM or ECO
            risk_pct = float(risk_cfg['risk_swing_pct'])
            risk_pct = max(float(risk_cfg['risk_swing_min_pct']), min(float(risk_cfg['risk_swing_max_pct']), risk_pct))

        if is_soft_loss:
            risk_pct *= float(risk_cfg['daily_loss_soft_risk_factor'])
        
        risk_pct = min(float(risk_cfg['risk_per_trade_max_pct']), risk_pct)
        return risk_pct

    def get_sizing(
        self,
        eq_now: float,
        risk_pct: float,
        price: float,
        sl: float,
        tick_size: float,
        tick_value: float,
        vol_min: float,
        vol_max: float,
        vol_step: float,
        symbol: str,
        margin_free: Optional[float] = None,
    ) -> Optional[float]:
        """
        Calculates the trade volume based on risk percentage, stop loss distance, and instrument properties.
        Also considers available margin if provided to avoid TRADE_RETCODE_NO_MONEY.
        Returns the calculated volume or None if sizing is not possible or safe.
        """
        risk_money = eq_now * risk_pct
        if risk_money <= 0:
            return None

        if tick_size <= 0 or tick_value <= 0:
            logging.info(f"SKIP_RISK_NO_TICKVAL {symbol} tick_size={tick_size} tick_value={tick_value}")
            return None

        sl_dist = abs(price - sl)
        ticks = sl_dist / tick_size
        per_lot_risk = ticks * tick_value
        if per_lot_risk <= 0:
            return None

        vol_raw = risk_money / per_lot_risk
        
        # Margin safety buffer: do not use more than 80% of free margin for a single trade
        if margin_free is not None:
            # Conservative estimate: assume 1:30 leverage for FX if not known, 
            # but here we just cap the volume if we have very little margin left.
            # A better way is to use mt5.order_check in the caller.
            if margin_free <= 0:
                logging.warning(f"SKIP_RISK_NO_MARGIN {symbol} margin_free={margin_free}")
                return None

        if vol_min <= 0 or vol_max <= 0 or vol_step <= 0:
            return None

        # Floor to the nearest volume step
        vol = (int(vol_raw / vol_step) * vol_step)
        vol = max(vol_min, min(vol_max, vol))
        vol = float(round(vol, 8))

        if vol < vol_min:
            logging.info(f"SKIP_RISK_VOL_BELOW_MIN {symbol} vol_raw={vol_raw:.6f} vol_min={vol_min}")
            return None

        return vol

    def check_portfolio_heat(
        self,
        our_positions: List[Any],
        eq_now: float,
        symbol: str,
        new_trade_risk_money: float,
        mt_client, # Pass MT5 client to get symbol info
        db, # Pass db to get symbol info
        grp: str, # Pass group to get symbol info
    ) -> bool:
        """
        Checks if a new trade would exceed portfolio heat limits (max parallel positions, max open risk).
        Returns True if the trade is allowed.
        """
        risk_cfg = self.config.risk
        if len(our_positions) >= int(risk_cfg['max_positions_parallel']):
            logging.info(f"SKIP_MAX_POSITIONS {symbol} n={len(our_positions)} cap={risk_cfg['max_positions_parallel']}")
            return False

        if sum(1 for p in our_positions if str(getattr(p, "symbol", "")) == str(symbol)) >= int(risk_cfg['max_positions_per_symbol']):
            logging.info(f"SKIP_POS_PER_SYMBOL {symbol} cap={risk_cfg['max_positions_per_symbol']}")
            return False

        open_risk_money = 0.0
        for p in our_positions:
            sl_p = float(getattr(p, "sl", 0.0) or 0.0)
            if sl_p <= 0:
                continue
            p_sym = str(getattr(p, "symbol", ""))
            info_p = mt_client.symbol_info_cached(p_sym, grp, db)
            if info_p is None:
                continue
                
            ts = float(getattr(info_p, "trade_tick_size", 0.0) or 0.0)
            tv = float(getattr(info_p, "trade_tick_value", 0.0) or 0.0)
            if ts <= 0 or tv <= 0:
                continue
            
            price_open = float(getattr(p, "price_open", 0.0) or 0.0)
            vol_p = float(getattr(p, "volume", 0.0) or 0.0)
            if vol_p <= 0:
                continue
            
            open_risk_money += (abs(price_open - sl_p) / ts) * tv * vol_p

        max_open_risk_money = eq_now * float(risk_cfg['max_open_risk_pct'])
        if (open_risk_money + new_trade_risk_money) > max_open_risk_money:
            logging.info(f"SKIP_HEAT {symbol} open_risk={open_risk_money:.2f} new_risk={new_trade_risk_money:.2f} max={max_open_risk_money:.2f}")
            return False

        return True
