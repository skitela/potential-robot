from __future__ import annotations


# Explicit denylist for runtime-trading imports.
FORBIDDEN_RUNTIME_IMPORT_PREFIXES: tuple[str, ...] = (
    "MetaTrader5",
    "safetybot",
    "zeromq_bridge",
    "BIN.safetybot",
    "BIN.zeromq_bridge",
    "MQL5",
)

# Explicit denylist for execution-adjacent write paths (relative to workspace root).
FORBIDDEN_WRITE_ROOTS: tuple[str, ...] = (
    "BIN",
    "CONFIG",
    "MQL5",
    "CORE",
    "META",
    "RUN",
    "DB",
    "LOGS",
)

