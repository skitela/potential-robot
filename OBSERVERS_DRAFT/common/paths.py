from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .boundaries import FORBIDDEN_WRITE_ROOTS


DEFAULT_READ_ROOTS = ("DB", "LOGS", "META", "EVIDENCE", "RUN")
DEFAULT_EXECUTION_ADJACENT_DENY_WRITES = FORBIDDEN_WRITE_ROOTS


@dataclass(frozen=True)
class Paths:
    workspace_root: Path
    observers_root: Path
    outputs_root: Path
    reports_root: Path
    alerts_root: Path
    tickets_root: Path
    cache_root: Path
    read_roots: tuple[Path, ...]
    deny_write_roots: tuple[Path, ...]

    @classmethod
    def from_workspace(cls, workspace_root: Path) -> "Paths":
        ws = workspace_root.resolve()
        observers = ws / "OBSERVERS_DRAFT"
        outputs = observers / "outputs"
        read_roots = tuple((ws / rel).resolve() for rel in DEFAULT_READ_ROOTS)
        deny_write_roots = tuple(
            (ws / rel).resolve() for rel in DEFAULT_EXECUTION_ADJACENT_DENY_WRITES
        )
        return cls(
            workspace_root=ws,
            observers_root=observers,
            outputs_root=outputs,
            reports_root=outputs / "reports",
            alerts_root=outputs / "alerts",
            tickets_root=outputs / "tickets",
            cache_root=outputs / "cache",
            read_roots=read_roots,
            deny_write_roots=deny_write_roots,
        )

    def ensure_roots_exist(self) -> None:
        for path in (self.outputs_root, self.reports_root, self.alerts_root, self.tickets_root, self.cache_root):
            path.mkdir(parents=True, exist_ok=True)

    def is_allowed_read_path(self, path: Path) -> bool:
        rp = path.resolve()
        return any(_is_relative_to(rp, root) for root in self.read_roots)

    def is_allowed_write_path(self, path: Path) -> bool:
        rp = path.resolve()
        if not _is_relative_to(rp, self.outputs_root):
            return False
        if any(_is_relative_to(rp, deny_root) for deny_root in self.deny_write_roots):
            return False
        return True

    def ensure_write_allowed(self, path: Path) -> None:
        if not self.is_allowed_write_path(path):
            raise PermissionError(f"Write outside observers outputs is forbidden: {path}")


def _is_relative_to(path: Path, base: Path) -> bool:
    try:
        path.relative_to(base)
        return True
    except ValueError:
        return False
