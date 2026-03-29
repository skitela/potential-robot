"""Lightweight package marker for mb_ml_supervision.

The operational entrypoints import concrete submodules directly.
Keeping __init__ side-effect free avoids paying the cost of importing
audits and runtime sync when a script only needs one helper.
"""

__all__: list[str] = []
