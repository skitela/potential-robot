import sys
import json
import time
from pathlib import Path
from threading import Lock

class TraceLogger:
    def __init__(self, trace_path):
        self.trace_path = Path(trace_path)
        self.lock = Lock()
        self.trace_path.parent.mkdir(parents=True, exist_ok=True)

    def log(self, event, **kwargs):
        record = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()),
            "event": event,
            **kwargs
        }
        line = json.dumps(record, ensure_ascii=False)
        with self.lock:
            with open(self.trace_path, "a", encoding="utf-8") as f:
                f.write(line + "\n")

if __name__ == "__main__":
    # CLI: dyrygent_trace.py <trace_path> <event> <key1=val1> <key2=val2> ...
    if len(sys.argv) < 3:
        print("Usage: dyrygent_trace.py <trace_path> <event> [key=val ...]")
        sys.exit(1)
    trace_path = sys.argv[1]
    event = sys.argv[2]
    kwargs = {}
    for arg in sys.argv[3:]:
        if '=' in arg:
            k, v = arg.split('=', 1)
            kwargs[k] = v
    logger = TraceLogger(trace_path)
    logger.log(event, **kwargs)
    print(f"Logged event '{event}' to {trace_path}")
