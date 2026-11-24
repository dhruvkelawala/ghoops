import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = Path(__file__).with_name('parity_fixture_store.py')


class ParityFixtureStoreTest(unittest.TestCase):
    def test_only_three_synthetic_boxing_records_are_added(self):
        full = json.loads((ROOT / 'fixtures/v2/inputs/store_full.json').read_text())
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'store.json'
            command = [sys.executable, '-I', str(SCRIPT), '--output', str(output)]
            subprocess.run(command, check=True)
            first = output.read_bytes()
            subprocess.run(command, check=True)
            self.assertEqual(first, output.read_bytes())
            parity = json.loads(first)
        added = parity['records'][len(full['records']):]
        self.assertEqual(len(added), 3)
        template = next(r for r in full['records'] if r['data_type'] == 'exercise'
                        and r['data_point']['exercise']['exerciseType'] == 'KICKBOXING')
        for index, (record, day) in enumerate(zip(added, ('2026-02-16', '2026-02-23', '2026-03-02')), 1):
            expected = copy.deepcopy(template)
            expected.update(date=day, synthetic_fixture=True)
            point = expected['data_point']
            point['name'] = f'users/synthetic/dataTypes/exercise/dataPoints/{7400000000000000000 + index}'
            exercise = point['exercise']
            exercise.update(exerciseType='BOXING', displayName='Boxing', activeDuration='3600s')
            exercise['interval'].update(startTime=f'{day}T19:30:00Z', endTime=f'{day}T20:30:00Z')
            self.assertEqual(record, expected)
        parity['records'] = parity['records'][:-3]
        self.assertEqual(parity, full)


if __name__ == '__main__':
    unittest.main()
