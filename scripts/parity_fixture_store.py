#!/usr/bin/env python3
"""Build the synthetic parity store from store_full."""
import argparse
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def generate():
    state = json.loads((ROOT / 'fixtures/v2/inputs/store_full.json').read_text())
    template = next(r for r in state['records'] if r['data_type'] == 'exercise'
                    and r['data_point']['exercise']['exerciseType'] == 'KICKBOXING')
    for index, day in enumerate(('2026-02-16', '2026-02-23', '2026-03-02'), 1):
        record = copy.deepcopy(template)
        record['date'] = day
        record['synthetic_fixture'] = True
        point = record['data_point']
        point['name'] = f'users/synthetic/dataTypes/exercise/dataPoints/{7400000000000000000 + index}'
        exercise = point['exercise']
        exercise.update(exerciseType='BOXING', displayName='Boxing', activeDuration='3600s')
        exercise['interval'].update(startTime=f'{day}T19:30:00Z', endTime=f'{day}T20:30:00Z')
        state['records'].append(record)
    return state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=ROOT / 'fixtures/v2/inputs/store_parity.json')
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(generate(), separators=(',', ':')) + '\n')


if __name__ == '__main__':
    main()
