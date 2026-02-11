#!/usr/bin/env python3
from __future__ import annotations

import socket
from contextlib import ContextDecorator
from typing import Any, Callable, Optional

DEFAULT_REASON = "OFFLINE_NETWORK_BLOCKED: network calls are disabled in OFFLINE mode."


class OfflineNetworkGuard(ContextDecorator):
    def __init__(self, enabled: bool = True, reason: str = DEFAULT_REASON) -> None:
        self.enabled = bool(enabled)
        self.reason = str(reason)
        self._active = False
        self._orig_create_connection: Optional[Callable[..., Any]] = None
        self._orig_connect: Optional[Callable[..., Any]] = None
        self._orig_connect_ex: Optional[Callable[..., Any]] = None

    def _blocked(self, *args: Any, **kwargs: Any) -> Any:
        raise RuntimeError(self.reason)

    def __enter__(self) -> "OfflineNetworkGuard":
        if not self.enabled or self._active:
            return self

        self._orig_create_connection = socket.create_connection
        self._orig_connect = socket.socket.connect
        self._orig_connect_ex = socket.socket.connect_ex

        socket.create_connection = self._blocked  # type: ignore[assignment]
        socket.socket.connect = self._blocked  # type: ignore[assignment]
        socket.socket.connect_ex = self._blocked  # type: ignore[assignment]
        self._active = True
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> bool:
        if not self._active:
            return False

        if self._orig_create_connection is not None:
            socket.create_connection = self._orig_create_connection  # type: ignore[assignment]
        if self._orig_connect is not None:
            socket.socket.connect = self._orig_connect  # type: ignore[assignment]
        if self._orig_connect_ex is not None:
            socket.socket.connect_ex = self._orig_connect_ex  # type: ignore[assignment]
        self._active = False
        return False


def offline_network_guard(enabled: bool = True, reason: str = DEFAULT_REASON) -> OfflineNetworkGuard:
    return OfflineNetworkGuard(enabled=enabled, reason=reason)
