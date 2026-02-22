"""
Module for system integrity checks and enforcing architectural constraints.
"""
import socket
import pytest

# P0 Constraint: Python service MUST NOT perform any network calls.
# This fixture monkey-patches the socket module to prevent any outbound network connections.
@pytest.fixture(autouse=True)
def disable_network_calls(monkeypatch):
    """
    Fixture to disable network calls for the duration of a test session.
    It will raise a RuntimeError if any code attempts to create a socket.
    """
    def disabled_socket(*args, **kwargs):
        raise RuntimeError(f"AUDIT FAIL: Network call attempted via socket.socket({args}, {kwargs}). This is forbidden.")

    monkeypatch.setattr(socket, "socket", disabled_socket)
    yield

def test_network_calls_are_disabled():
    """
    This test verifies that the `disable_network_calls` fixture is active
    and correctly prevents socket creation.
    """
    with pytest.raises(RuntimeError) as e:
        # This line should trigger the monkey-patched socket.socket and raise an error.
        socket.socket(socket.AF_INET, socket.SOCK_STREAM)

    assert "AUDIT FAIL: Network call attempted" in str(e.value)

def test_importing_modules_does_not_trigger_network():
    """
    This is a sanity check to ensure that simply importing the main application
    modules doesn't trigger a network call on its own. The `disable_network_calls`
    fixture is active automatically. If any module tried to open a socket on
    import, this test would fail.
    """
    try:
        # Import main modules that could potentially (but shouldn't) open sockets.
        from BIN import zeromq_bridge
        from BIN import risk_manager
        from BIN import learner_offline
    except RuntimeError:
        pytest.fail("AUDIT FAIL: A module attempted a network call upon import.")
    except ImportError as e:
        pytest.fail(f"Could not import a required module: {e}")

