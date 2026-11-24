#!/usr/bin/env python3
"""Build a large synthetic v2 store for load and performance runs.

Copies store_full's synthetic days, shifted so the last day is today in London,
until the store holds --days days (default 400, the retention limit), with a
minute heart-rate day for every day and a workout every other day. The output is
plaintext like fixtures/v2/inputs; fixture-ghealth encrypts it with an in-memory key.
No value comes from a real account.
"""
import argparse
import copy
import datetime as dt
import json
import re
from pathlib import Path
from zoneinfo import ZoneInfo

LONDON = ZoneInfo('Europe/London')
ROOT = Path(__file__).resolve().parents[1]
STAMP = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$')


def shift(value, days):
    """Return value with every date and timestamp moved by whole days."""
    if isinstance(value, dict):
        if set(value) == {'year', 'month', 'day'}:
            d = dt.date(value['year'], value['month'], value['day']) + dt.timedelta(days=days)
            return {'year': d.year, 'month': d.month, 'day': d.day}
        return {k: shift(v, days) for k, v in value.items()}
    if isinstance(value, list):
        return [shift(v, days) for v in value]
    if isinstance(value, str):
        if STAMP.match(value):
            at = dt.datetime.fromisoformat(value.replace('Z', '+00:00')) + dt.timedelta(days=days)
            return at.strftime('%Y-%m-%dT%H:%M:%S') + ('.' + value.split('.')[1] if '.' in value else 'Z')
        if re.fullmatch(r'\d{4}-\d{2}-\d{2}', value):
            return (dt.date.fromisoformat(value) + dt.timedelta(days=days)).isoformat()
    return value


def rename(record, suffix):
    point = record['data_point']
    for key in ('name', 'dataPointName'):
        if key in point:
            point[key] = point[key] + suffix
    return record


def build(days, now):
    with open(ROOT / 'fixtures' / 'v2' / 'inputs' / 'store_full.json') as f:
        template = json.load(f)
    today = now.astimezone(LONDON).date()
    first = today - dt.timedelta(days=days - 1)
    template_days = sorted({r['date'] for r in template['records']})
    by_date = {}
    for r in template['records']:
        if r['data_type'] != 'exercise':
            by_date.setdefault(r['date'], []).append(r)
    exercises = [r for r in template['records'] if r['data_type'] == 'exercise']
    coverage = {}
    for row in template['coverage']:
        coverage.setdefault(row['date'], []).append(row)
    rollups = {}
    for row in template['daily_rollups']:
        rollups.setdefault(row['date'], []).append(row)
    hr_day = next(d for d in template['hr_minutes'] if d['date'] == '2026-03-09')
    hr_today = next(d for d in template['hr_minutes'] if d['date'] == '2026-03-10')

    out = copy.deepcopy(template)
    out['records'], out['coverage'], out['daily_rollups'], out['hr_minutes'] = [], [], [], []
    cutoff = int(now.timestamp())
    for i in range(days):
        date = first + dt.timedelta(days=i)
        source = template_days[i % len(template_days)] if date != today else template_days[-1]
        delta = (date - dt.date.fromisoformat(source)).days
        for r in by_date.get(source, []):
            out['records'].append(rename(shift(copy.deepcopy(r), delta), '-%d' % i))
        if i % 2 == 0 or date == today:
            ex = exercises[i % len(exercises)]
            delta_ex = (date - dt.date.fromisoformat(ex['date'])).days
            out['records'].append(rename(shift(copy.deepcopy(ex), delta_ex), '-%d' % i))
        for row in coverage.get(source, []):
            out['coverage'].append(shift(copy.deepcopy(row), delta))
        rollup_source = '2026-03-10' if date == today else '2026-03-09'
        for row in rollups.get(rollup_source, []):
            out['daily_rollups'].append(shift(copy.deepcopy(row), (date - dt.date.fromisoformat(rollup_source)).days))
        minutes = hr_today if date == today else hr_day
        seconds = (date - dt.date.fromisoformat(minutes['date'])).days * 86400
        windows = [[w[0] + seconds] + w[1:] for w in minutes['windows'] if w[0] + seconds <= cutoff]
        out['hr_minutes'].append({'date': date.isoformat(), 'windows': windows})
    last = today - dt.date(2026, 3, 10)
    out['runs'] = shift(template['runs'], last.days)
    out['user'] = shift(template['user'], last.days)
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--days', type=int, default=400)
    parser.add_argument('--now', help='RFC 3339 UTC; default is now')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    now = dt.datetime.fromisoformat(args.now.replace('Z', '+00:00')) if args.now else dt.datetime.now(dt.timezone.utc)
    store = build(args.days, now)
    with open(args.output, 'w') as f:
        f.write(json.dumps(store, separators=(',', ':')))
    print(json.dumps({'days': args.days, 'records': len(store['records']), 'hr_days': len(store['hr_minutes']),
                      'hr_windows': sum(len(d['windows']) for d in store['hr_minutes']),
                      'exercises': sum(r['data_type'] == 'exercise' for r in store['records']),
                      'bytes': Path(args.output).stat().st_size}))


if __name__ == '__main__':
    main()
