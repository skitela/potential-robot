"""Lightweight package marker for mb_ml_core.

Scripts import concrete modules such as mb_ml_core.registry or
mb_ml_core.trainer directly. Leaving __init__ empty keeps CLI startup
fast and avoids importing pandas/training code unless it is needed.
"""

__all__: list[str] = []
