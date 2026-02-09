from pathlib import Path
import PyPDF2


def main() -> int:
    root = Path(r"C:\OANDA_MT5_SYSTEM\DOCS\OANDA")
    out_dir = root / "_extract"
    out_dir.mkdir(parents=True, exist_ok=True)

    for pdf in sorted(root.glob("*.pdf")):
        reader = PyPDF2.PdfReader(str(pdf))
        out_lines = []
        for i, page in enumerate(reader.pages, start=1):
            try:
                text = page.extract_text() or ""
            except Exception as exc:
                text = f"[EXTRACT_ERROR:{type(exc).__name__}]"
            out_lines.append(f"\n=== PAGE {i} / {pdf.name} ===\n")
            out_lines.append(text)
        (out_dir / f"{pdf.stem}.txt").write_text(
            "\n".join(out_lines), encoding="utf-8", errors="ignore"
        )

    print(f"OK {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
