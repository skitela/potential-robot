import tempfile
import json
from pathlib import Path
from dyrygent_trace import TraceLogger

def test_trace_logger_basic():
    with tempfile.TemporaryDirectory() as tmpdir:
        trace_path = Path(tmpdir) / "trace.jsonl"
        logger = TraceLogger(trace_path)
        logger.log("scan_repo", rel_path="main.py", result="ok")
        logger.log("redact", rel_path="main.py", result="redacted")
        lines = trace_path.read_text(encoding="utf-8").splitlines()
        assert len(lines) == 2
        rec1 = json.loads(lines[0])
        rec2 = json.loads(lines[1])
        assert rec1["event"] == "scan_repo"
        assert rec2["event"] == "redact"
        assert rec1["rel_path"] == "main.py"
        assert rec2["result"] == "redacted"
