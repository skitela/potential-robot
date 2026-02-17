from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict

# In a real scenario, you would use a library like jsonschema to validate
# the config against the schema, but to avoid adding dependencies, we'll
# just load the file. The schema exists for documentation and future use.

class ConfigManager:
    """
    Simple configuration manager to load settings from JSON files.
    """
    def __init__(self, config_dir: Path):
        self.config_dir = config_dir
        self.risk: Dict[str, Any] = self._load_config("risk.json")
        self.limits: Dict[str, Any] = self._load_config("limits.json")
        self.scheduler: Dict[str, Any] = self._load_config("scheduler.json")
        self.strategy: Dict[str, Any] = self._load_optional_config("strategy.json")
        # In the future, other configs would be loaded here:
        # self.strategy: Dict[str, Any] = self._load_config("strategy.json")

    def _load_config(self, filename: str) -> Dict[str, Any]:
        """Loads a single JSON configuration file."""
        config_path = self.config_dir / filename
        if not config_path.exists():
            raise FileNotFoundError(f"Configuration file not found: {config_path}")
        with config_path.open("r", encoding="utf-8") as f:
            return json.load(f)

    def _load_optional_config(self, filename: str) -> Dict[str, Any]:
        """Loads optional JSON config. Missing file returns empty dict."""
        config_path = self.config_dir / filename
        if not config_path.exists():
            return {}
        with config_path.open("r", encoding="utf-8") as f:
            return json.load(f)

    def get(self, key: str, default: Any = None) -> Any:
        """
        A generic getter to access config values, e.g., config.get("risk.risk_per_trade_max_pct")
        This is a placeholder for a more robust implementation.
        """
        parts = key.split('.')
        if len(parts) == 2:
            section_name, key_name = parts
            section = getattr(self, section_name, None)
            if section and isinstance(section, dict):
                return section.get(key_name, default)
        return default

# A global instance can be created if needed, but dependency injection is preferred.
# For this refactoring, we will instantiate it inside the SafetyBot.
