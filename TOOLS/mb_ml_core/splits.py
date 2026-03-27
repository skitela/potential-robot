from __future__ import annotations

from dataclasses import dataclass

import pandas as pd


@dataclass(slots=True)
class SplitWindow:
    fold_id: int
    train_index: list[int]
    valid_index: list[int]
    train_start: pd.Timestamp
    train_end: pd.Timestamp
    valid_start: pd.Timestamp
    valid_end: pd.Timestamp


def make_walk_forward_splits(
    df: pd.DataFrame,
    time_col: str = "ts",
    train_days: int = 45,
    valid_days: int = 5,
    step_days: int = 5,
    embargo_minutes: int = 10,
    min_train_rows: int = 250,
    min_valid_rows: int = 50,
) -> list[SplitWindow]:
    if df.empty:
        return []
    tmp = df.reset_index(drop=False).rename(columns={"index": "_row_id"}).copy()
    tmp[time_col] = pd.to_datetime(tmp[time_col], utc=True)

    start = tmp[time_col].min().floor("D")
    end = tmp[time_col].max().ceil("D")
    train_delta = pd.Timedelta(days=train_days)
    valid_delta = pd.Timedelta(days=valid_days)
    step_delta = pd.Timedelta(days=step_days)
    embargo_delta = pd.Timedelta(minutes=embargo_minutes)

    cursor_train_end = start + train_delta
    fold_id = 0
    windows = []

    while cursor_train_end + valid_delta <= end:
        train_end = cursor_train_end
        valid_start = cursor_train_end + embargo_delta
        valid_end = cursor_train_end + valid_delta

        train_idx = tmp.loc[tmp[time_col] < train_end, "_row_id"].tolist()
        valid_idx = tmp.loc[(tmp[time_col] >= valid_start) & (tmp[time_col] < valid_end), "_row_id"].tolist()

        if len(train_idx) >= min_train_rows and len(valid_idx) >= min_valid_rows:
            windows.append(
                SplitWindow(
                    fold_id=fold_id,
                    train_index=train_idx,
                    valid_index=valid_idx,
                    train_start=start,
                    train_end=train_end,
                    valid_start=valid_start,
                    valid_end=valid_end,
                )
            )
            fold_id += 1
        cursor_train_end += step_delta

    return windows
