import json
import pathlib
import subprocess
import sys
import unittest


SCRIPT = pathlib.Path(__file__).with_name("morning_summary.py")


class MorningSummaryTest(unittest.TestCase):
    def test_default_excludes_health_values_and_provenance(self):
        self.assertTrue(SCRIPT.is_file(), "minimal morning adapter is not implemented")
        metric = {"status": "available", "value": 123456, "unit": "count", "stale": False, "raw_source_candidates": [{"private": "never-share-source"}]}
        sample = {"schema_version": 1, "source": "google_health_v4", "timezone": "Europe/London", "days": [{"date": "2026-10-12", "sleep": {"asleep_minutes": metric}, "hrv_rmssd_ms": metric, "resting_heart_rate_bpm": metric, "steps": metric, "exercise": {"coverage": metric, "workouts": [{"exercise_types": ["NEVER_SHARE_DEFAULT"], "start": "private", "sources": ["private"]}]}}]}
        result = subprocess.run([sys.executable, str(SCRIPT)], input=json.dumps(sample), capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("123456", result.stdout)
        self.assertNotIn("never-share", result.stdout)
        self.assertNotIn("NEVER_SHARE_DEFAULT", result.stdout)
        self.assertEqual(json.loads(result.stdout)["days"][0]["steps"], {"status": "available", "stale": False})


    def test_explicit_disclosure_only_includes_fresh_available_values(self):
        metric = {"status": "available", "value": 456, "unit": "count", "stale": False}
        missing = {"status": "missing", "value": 999, "unit": "ms", "stale": False}
        stale = {"status": "available", "value": 789, "unit": "bpm", "stale": True}
        sample = {"schema_version": 1, "source": "google_health_v4", "timezone": "Europe/London", "days": [{"date": "2026-10-12", "sleep": {"asleep_minutes": missing}, "hrv_rmssd_ms": missing, "resting_heart_rate_bpm": stale, "steps": metric, "exercise": {"coverage": metric, "workouts": []}}]}
        result = subprocess.run([sys.executable, str(SCRIPT), "--include-values"], input=json.dumps(sample), capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        day = json.loads(result.stdout)["days"][0]
        self.assertEqual(day["steps"].get("value"), 456)
        self.assertNotIn("value", day["sleep_minutes"])
        self.assertNotIn("value", day["resting_heart_rate_bpm"])
        self.assertNotIn("value", day["exercise"])

    def test_rejects_synthetic_or_wrong_schema_without_output(self):
        for changes in ({"synthetic_fixture": True}, {"schema_version": 2}, {"source": "unknown"}):
            with self.subTest(changes=changes):
                sample = {"schema_version": 1, "source": "google_health_v4", "timezone": "Europe/London", "days": [], **changes}
                result = subprocess.run([sys.executable, str(SCRIPT)], input=json.dumps(sample), capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
