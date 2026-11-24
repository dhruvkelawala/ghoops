import datetime as dt
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('edit_fixture_store.py')


class EditFixtureStoreTest(unittest.TestCase):
    def test_deterministic_reference_and_london_anchor(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'store.json'
            def build(now):
                subprocess.run([sys.executable, '-I', str(SCRIPT), '--now', now, '--output', str(output)], check=True)
                return output.read_bytes()
            first = build('2026-03-12T20:30:00Z')
            self.assertEqual(first, build('2026-03-12T22:00:00Z'))
            state = json.loads(first)
            self.assertTrue(state['synthetic_fixture'])
            ids = [r['data_point']['name'].rsplit('/', 1)[-1] for r in state['records'] if r['data_type'] == 'exercise']
            self.assertEqual(ids, ['7300000000000000100', '7300000000000000101', '7300000000000000102', '7300000000000000103'])
            for now, sync in [('2026-03-12T20:29:59Z', '2026-03-11T20:08:00Z'), ('2026-07-12T19:29:59Z', '2026-07-11T19:08:00Z'), ('2026-07-12T19:30:00Z', '2026-07-12T19:08:00Z'), ('2026-03-29T19:30:00Z', '2026-03-29T19:08:00Z')]:
                state = json.loads(build(now))
                self.assertEqual(state['user']['paired_devices']['body']['pairedDevices'][0]['lastSyncTime'], sync)
                self.assertLess(dt.datetime.fromtimestamp(state['hr_minutes'][-1]['windows'][-1][0], dt.timezone.utc), dt.datetime.fromisoformat(now.replace('Z', '+00:00')))


if __name__ == '__main__':
    unittest.main()
