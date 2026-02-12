import sys
if __name__ == "__main__":
    print("[DEPRECATED] EntryPoint = DYRYGENT_EXTERNAL.py; użyj: python DYRYGENT_EXTERNAL.py --dry-run [--help]", file=sys.stderr)
    sys.exit(2)
print("--- STATUS REPORT ---")
print(external.status_report())
