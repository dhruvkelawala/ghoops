import datetime as dt
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('load_fixture_store.py')


class LoadFixtureStoreTest(unittest.TestCase):
    def test_days_end_today_in_london_and_stop_at_now(self):
        now = '2026-07-12T23:30:00Z'
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'store.json'
            subprocess.run([sys.executable, '-I', str(SCRIPT), '--days', '50', '--now', now, '--output', str(output)], check=True, capture_output=True)
            state = json.loads(output.read_bytes())
        self.assertTrue(state['synthetic_fixture'])
        dates = [d['date'] for d in state['hr_minutes']]
        self.assertEqual(len(dates), 50)
        self.assertEqual(dates[-1], '2026-07-13')
        self.assertEqual(dates[0], '2026-05-25')
        cutoff = dt.datetime.fromisoformat(now.replace('Z', '+00:00')).timestamp()
        self.assertLessEqual(max(w[0] for d in state['hr_minutes'] for w in d['windows']), cutoff)
        self.assertEqual({r['date'] for r in state['records']} - set(dates), set())
        names = [r['data_point'].get('name') or r['data_point'].get('dataPointName') for r in state['records']]
        named = [n for n in names if n]
        self.assertEqual(len(named), len(set(named)))
        self.assertEqual(sum(r['data_type'] == 'exercise' for r in state['records']), 26)


if __name__ == '__main__':
    unittest.main()
