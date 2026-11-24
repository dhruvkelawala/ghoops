#!/usr/bin/env python3
"""Write the synthetic night whose Google window ends after its stages."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--variant', choices=['unstaged','neighbours'], default='unstaged')
    parser.add_argument('--output', type=Path, default=None)
    args = parser.parse_args()
    state = json.loads((ROOT / 'fixtures/v2/inputs/store_full.json').read_text())
    if args.variant == 'neighbours':
        state['records'].append({
            'data_type':'sleep', 'stream':'reconciled', 'date':'2026-03-09', 'synthetic_fixture':True,
            'data_point':{'sleep':{
                'interval':{'startTime':'2026-03-09T21:30:00Z','endTime':'2026-03-09T22:30:00Z','startUtcOffset':'0s','endUtcOffset':'0s'},
                'type':'CLASSIC','metadata':{'mainSleep':False,'processed':True,'nap':True},
                'summary':{'minutesAsleep':'50','minutesAwake':'10'},'stages':[],'shortAwakenings':[]}}})
    for record in state['records'] if args.variant == 'unstaged' else []:
        if record['data_type'] == 'sleep' and record['stream'] == 'reconciled' and record['date'] == '2026-03-10':
            sleep = record['data_point']['sleep']
            if not sleep['metadata']['mainSleep']:
                continue
            sleep['interval']['endTime'] = '2026-03-10T07:41:00Z'
            sleep['metadata']['stagesStatus'] = None
            sleep['summary']['minutesAwake'] = '94'
            sleep['summary']['minutesInSleepPeriod'] = '509'
    args.output = args.output or ROOT / f'fixtures/v2/inputs/store_sleep_{args.variant}.json'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(state, indent=2) + '\n')


if __name__ == '__main__':
    main()
