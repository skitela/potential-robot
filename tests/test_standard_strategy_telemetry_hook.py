import ast
from pathlib import Path


def _load_module_ast() -> ast.Module:
    src = Path("BIN/safetybot.py").read_text(encoding="utf-8")
    return ast.parse(src)


def _find_class(module: ast.Module, name: str) -> ast.ClassDef:
    for node in module.body:
        if isinstance(node, ast.ClassDef) and node.name == name:
            return node
    raise AssertionError(f"Class not found: {name}")


def test_standard_strategy_exposes_execution_telemetry_method() -> None:
    module = _load_module_ast()
    strategy_cls = _find_class(module, "StandardStrategy")
    method_names = {
        node.name for node in strategy_cls.body if isinstance(node, ast.FunctionDef)
    }
    assert "_append_execution_telemetry" in method_names


def test_safetybot_wires_strategy_execution_telemetry_hook() -> None:
    module = _load_module_ast()
    safety_cls = _find_class(module, "SafetyBot")
    init_fn = None
    for node in safety_cls.body:
        if isinstance(node, ast.FunctionDef) and node.name == "__init__":
            init_fn = node
            break
    assert init_fn is not None, "SafetyBot.__init__ not found"

    wired = False
    for node in ast.walk(init_fn):
        if not isinstance(node, ast.Assign):
            continue
        if len(node.targets) != 1:
            continue
        target = node.targets[0]
        if not isinstance(target, ast.Attribute):
            continue
        if target.attr != "execution_telemetry_hook":
            continue
        if not isinstance(target.value, ast.Attribute):
            continue
        if not isinstance(target.value.value, ast.Name):
            continue
        if target.value.value.id != "self" or target.value.attr != "strategy":
            continue
        value = node.value
        if not isinstance(value, ast.Attribute):
            continue
        if not isinstance(value.value, ast.Name):
            continue
        if value.value.id == "self" and value.attr == "_append_execution_telemetry":
            wired = True
            break

    assert wired, "SafetyBot must wire strategy execution telemetry hook"
