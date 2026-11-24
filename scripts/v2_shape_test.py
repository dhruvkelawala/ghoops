"""Exercise the redaction boundary using synthetic bodies only."""
import importlib.util
import json
import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("v2_shape", ROOT / "scripts/v2_shape.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ShapeTest(unittest.TestCase):
    def test_full_day_has_no_numeric_leaves(self):
        body = (ROOT / "fixtures/v2/day_full.json").read_text()
        result = subprocess.run([sys.executable, "-I", str(ROOT / "scripts/v2_shape.py")],
                                input=body, capture_output=True, text=True, check=True)
        redacted = json.loads(result.stdout)

        def check(original, masked, field=""):
            if isinstance(original, dict):
                self.assertEqual(original.keys(), masked.keys())
                for key in original:
                    check(original[key], masked[key], key)
            elif isinstance(original, list):
                self.assertEqual(masked["array"], f"<array len={len(original)}>")
                if original:
                    check(original[0], masked["first"], field)
            elif original is None or isinstance(original, bool):
                self.assertEqual(original, masked)
            elif isinstance(original, (int, float)):
                self.assertEqual(masked, "<num>")
                self.assertFalse(any(character.isdigit() for character in masked))
            elif field in MODULE.ENUM_FIELDS:
                self.assertEqual(original, masked)
            else:
                self.assertIn(masked, ("<date>", "<time>", "<str>"))

        check(json.loads(body), redacted)

    def test_strings_identifiers_dates_and_numeric_strings_are_redacted(self):
        body = {"schema_version": 2, "kind": "day", "value": "918273.4", "name": "Private tracker",
                "date": "2026-03-10", "at": "2026-03-10T12:34:56Z", "nullable": None,
                "ok": True, "empty": [], "series": [918273.4, 918274.5]}
        self.assertEqual(MODULE.shape(body), {
            "schema_version": "<num>", "kind": "day", "value": "<str>", "name": "<str>",
            "date": "<date>", "at": "<time>", "nullable": None, "ok": True,
            "empty": {"array": "<array len=0>"}, "series": {"array": "<array len=2>", "first": "<num>"},
        })


if __name__ == "__main__":
    unittest.main()
