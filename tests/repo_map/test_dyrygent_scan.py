import os
import json
import tempfile
from pathlib import Path
from dyrygent_scan import scan_repo_map

def test_scan_repo_map_basic():
    # Tworzymy tymczasowy katalog z kilkoma plikami
    with tempfile.TemporaryDirectory() as tmpdir:
        root = Path(tmpdir)
        (root / "a.py").write_text("""def foo(): pass\nclass Bar: pass\nimport os\n""")
        (root / "b.txt").write_text("hello")
        (root / "sub").mkdir()
        (root / "sub" / "c.py").write_text("""# test\nif __name__ == '__main__': pass\n""")
        repo_map = scan_repo_map(str(root))
        # Sprawdzamy czy pliki są wykryte
        rels = {x['rel_path'] for x in repo_map}
        assert "a.py" in rels
        assert "b.txt" in rels
        assert "sub/c.py" in rels
        # Sprawdzamy symbole i entrypoint
        a = next(x for x in repo_map if x['rel_path'] == "a.py")
        assert "foo" in a['symbols']
        assert "Bar" in a['symbols']
        assert "os" in a['imports']
        c = next(x for x in repo_map if x['rel_path'] == "sub/c.py")
        assert c['entrypoint']

def test_scan_repo_map_denylist():
    with tempfile.TemporaryDirectory() as tmpdir:
        root = Path(tmpdir)
        (root / "EVIDENCE").mkdir()
        (root / "EVIDENCE" / "secret.py").write_text("token = 'x'")
        (root / "main.py").write_text("pass")
        repo_map = scan_repo_map(str(root))
        rels = {x['rel_path'] for x in repo_map}
        assert "main.py" in rels
        assert not any("EVIDENCE/" in x for x in rels)
