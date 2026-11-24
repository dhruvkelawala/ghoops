import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('sleep_fixture_store.py')
INPUT = SCRIPT.parent.parent / 'fixtures/v2/inputs/store_full.json'


class SleepFixtureStoreTest(unittest.TestCase):
    def test_only_the_edited_night_changes_and_output_is_repeatable(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'store.json'
            command = [sys.executable, '-I', str(SCRIPT), '--output', str(output)]
            subprocess.run(command, check=True)
            first = output.read_bytes()
            subprocess.run(command, check=True)
            self.assertEqual(first, output.read_bytes())
            before = json.loads(INPUT.read_text())
            after = json.loads(first)
            self.assertEqual(len(after['records']), len(before['records']))
            changed = [(a, b) for a, b in zip(before['records'], after['records']) if a != b]
            self.assertEqual(len(changed), 1)
            original, edited = changed[0]
            self.assertEqual((edited['data_type'], edited['stream'], edited['date']), ('sleep', 'reconciled', '2026-03-10'))
            expected = copy.deepcopy(original)
            sleep = expected['data_point']['sleep']
            sleep['interval']['endTime'] = '2026-03-10T07:41:00Z'
            sleep['metadata']['stagesStatus'] = None
            sleep['summary']['minutesAwake'] = '94'
            sleep['summary']['minutesInSleepPeriod'] = '509'
            self.assertEqual(edited, expected)
            after['records'] = before['records']
            self.assertEqual(after, before)

    def test_neighbours_adds_only_one_nap(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'store.json'
            command = [sys.executable, '-I', str(SCRIPT), '--variant', 'neighbours', '--output', str(output)]
            subprocess.run(command, check=True)
            first = output.read_bytes()
            subprocess.run(command, check=True)
            self.assertEqual(first, output.read_bytes())
            before, after = json.loads(INPUT.read_text()), json.loads(first)
            added = after['records'].pop()
            self.assertEqual(after, before)
            sleep = added['data_point']['sleep']
            self.assertTrue(sleep['metadata']['nap'])
            self.assertEqual(sleep['type'], 'CLASSIC')
            self.assertEqual(sleep['interval']['startTime'], '2026-03-09T21:30:00Z')
            self.assertEqual(sleep['interval']['endTime'], '2026-03-09T22:30:00Z')
            self.assertEqual(sleep['summary']['minutesAsleep'], '50')


if __name__ == '__main__':
    unittest.main()
