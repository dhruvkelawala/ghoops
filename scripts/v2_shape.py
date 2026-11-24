"""Print a v2 body's structure without its measurements or identifiers."""
import json
import re
import sys

ENUM_FIELDS = frozenset((
    "status", "reason", "band", "kind", "start_source", "end_source",
    "confidence", "position", "device_sync_source", "last_collect_status",
    "max_hr_source", "resting_hr_source", "category", "stage", "code",
    "severity", "disclosure", "efficiency_band", "monitor_state",
))


def shape(value, field=""):
    if value is None or isinstance(value, bool):
        return value
    if isinstance(value, dict):
        return {key: shape(item, key) for key, item in value.items()}
    if isinstance(value, list):
        result = {"array": f"<array len={len(value)}>"}
        if value:
            result["first"] = shape(value[0], field)
        return result
    if isinstance(value, (int, float)):
        return "<num>"
    if isinstance(value, str):
        if field in ENUM_FIELDS:
            return value
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
            return "<date>"
        if re.match(r"\d{4}-\d{2}-\d{2}T", value):
            return "<time>"
    return "<str>"


def main():
    try:
        value = json.load(sys.stdin)
        if not isinstance(value, dict) or value.get("schema_version") != 2:
            raise ValueError("unsupported schema")
        print(json.dumps(shape(value), indent=2))
        return 0
    except (ValueError, TypeError):
        print("v2 shape requires a schema 2 JSON object", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
