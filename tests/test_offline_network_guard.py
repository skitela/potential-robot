import socket
import unittest

from TOOLS.offline_network_guard import DEFAULT_REASON, offline_network_guard


class TestOfflineNetworkGuard(unittest.TestCase):
    def test_socket_connect_is_blocked(self) -> None:
        with offline_network_guard(enabled=True):
            with self.assertRaisesRegex(RuntimeError, "OFFLINE_NETWORK_BLOCKED"):
                socket.create_connection(("example.com", 80), timeout=0.2)

    def test_socket_hooks_restore_after_exit(self) -> None:
        original = socket.create_connection
        with offline_network_guard(enabled=True):
            self.assertIsNot(socket.create_connection, original)
        self.assertIs(socket.create_connection, original)

    def test_disabled_guard_is_noop(self) -> None:
        original = socket.create_connection
        with offline_network_guard(enabled=False):
            self.assertIs(socket.create_connection, original)
        self.assertIs(socket.create_connection, original)

    def test_reason_constant_stable(self) -> None:
        self.assertIn("OFFLINE_NETWORK_BLOCKED", DEFAULT_REASON)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
