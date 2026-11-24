#!/usr/bin/env python3
"""Build the synthetic Edit Activity store."""
import argparse
import copy
import datetime as dt
import json
import math
from pathlib import Path
from zoneinfo import ZoneInfo

LONDON = ZoneInfo('Europe/London')
REFERENCE = dt.date(2026, 3, 12)
ROOT = Path(__file__).resolve().parents[1]


def noise0(minute):
    seed = (math.floor(minute) * 7919) % 233280
    return ((seed * 9301 + 49297) % 233280) / 233280


def noise(minute):
    return sum(noise0(minute + offset) for offset in (0, 1, -1)) / 3


def hr_a(minute):
    t = minute - 17 * 60 - 30
    n = noise(minute)
    if t < 26:
        return 84 + math.sin(t / 3) * 2 + n * 4
    if t < 35:
        return 92 + (t - 26) * 5.2 + n * 5
    if t < 92:
        return 146 + math.sin(t / 2.3) * 12 + math.sin(t / 7.1) * 5 + n * 9
    if t < 102:
        return 146 - (t - 92) * 4.6 + n * 5
    if t < 106:
        return 98 + n * 6
    if t < 128:
        return 136 + math.sin(t / 2.2) * 10 + math.sin(t / 6.3) * 4 + n * 8
    return 100 - (t - 128) * 1.2 + n * 4


def hr_b(minute):
    t = minute - 17 * 60 - 30
    n = noise(minute)
    if t < 30:
        return 82 + math.sin(t / 3) * 2 + n * 4
    if t < 34:
        return 90 + (t - 30) * 12 + n * 5
    if t < 90:
        return 146 + math.sin(t / 6) * 6 + (t - 34) * .08 + n * 7
    if t < 96:
        return 150 - (t - 90) * 9 + n * 5
    return 88 + math.sin(t / 3) * 2 + n * 4


def hr_e(minute):
    t = minute - 7 * 60 - 10
    if t < 0:
        return 96
    if t < 4:
        return 100 + t * 7 + noise(minute) * 4
    if t < 27:
        return 128 + math.sin(t / 2.1) * 7 + noise(minute) * 7
    return 134 - (t - 27) * 7 + noise(minute) * 4


def iso(value):
    return value.astimezone(dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')


def anchor(now):
    local = now.astimezone(LONDON)
    day = local.date()
    candidate = dt.datetime.combine(day, dt.time(20, 30), LONDON)
    if candidate > local:
        candidate = dt.datetime.combine(day - dt.timedelta(days=1), dt.time(20, 30), LONDON)
    return candidate


def generate(now):
    latest = anchor(now)
    shift = latest.date() - REFERENCE

    def at(day, hour, minute):
        return dt.datetime.combine(REFERENCE + dt.timedelta(days=day) + shift, dt.time(hour, minute), LONDON)

    def shifted(value):
        if isinstance(value, dict):
            if set(value) == {'year', 'month', 'day'}:
                day = dt.date(value['year'], value['month'], value['day']) + dt.timedelta(days=2) + shift
                return {'year': day.year, 'month': day.month, 'day': day.day}
            return {key: shifted(item) for key, item in value.items()}
        if isinstance(value, list):
            return [shifted(item) for item in value]
        if isinstance(value, str):
            try:
                if len(value) == 10:
                    return (dt.date.fromisoformat(value) + dt.timedelta(days=2) + shift).isoformat()
                if value.endswith('Z') and 'T' in value:
                    old = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
                    day = old.date() + dt.timedelta(days=2) + shift
                    return iso(dt.datetime.combine(day, old.time().replace(tzinfo=None), LONDON))
            except ValueError:
                pass
        return value

    state = shifted(json.loads((ROOT / 'fixtures/v2/inputs/store_full.json').read_text()))
    first_baseline = (latest.date() - dt.timedelta(days=41)).isoformat()
    state['records'] = [r for r in state['records'] if r['data_type'] != 'exercise' and r['date'] >= first_baseline]
    for record in state['records']:
        point = record['data_point']
        if record['data_type'] == 'daily-resting-heart-rate' and record['date'] >= at(-5, 0, 0).date().isoformat():
            point['dailyRestingHeartRate']['beatsPerMinute'] = '54'
        if record['data_type'] == 'sleep' and record['date'] == latest.date().isoformat():
            sleep = point['sleep']
            sleep['interval'].update(startTime=iso(at(-1, 23, 14)), endTime=iso(at(0, 6, 52)))
            sleep.pop('stages', None)
            sleep.pop('shortAwakenings', None)
            sleep['summary'].update(minutesAsleep='438', minutesAwake='20', minutesInSleepPeriod='458', stagesSummary=[{'type': kind, 'minutes': str(minutes), 'count': '4'} for kind, minutes in [('LIGHT', 250), ('DEEP', 90), ('REM', 98), ('AWAKE', 20)]])
    template = next(r for r in json.loads((ROOT / 'fixtures/v2/inputs/store_full.json').read_text())['records'] if r['data_type'] == 'exercise')
    for day, kind, sh, sm, eh, em, suffix in [(-5, 'BOXING', 18, 30, 19, 30, '0100'), (-2, 'KICKBOXING', 18, 5, 19, 2, '0101'), (-2, 'KICKBOXING', 19, 16, 19, 38, '0102'), (0, 'WALKING', 12, 31, 13, 4, '0103')]:
        record = copy.deepcopy(template)
        record['date'] = at(day, sh, sm).date().isoformat()
        point = record['data_point']
        point['name'] = 'users/synthetic/dataTypes/exercise/dataPoints/730000000000000' + suffix
        exercise = point['exercise']
        exercise.update(exerciseType=kind, displayName={'BOXING': 'Boxing', 'KICKBOXING': 'Kickboxing', 'WALKING': 'Walking'}[kind])
        exercise['interval'].update(startTime=iso(at(day, sh, sm)), endTime=iso(at(day, eh, em)))
        exercise['activeDuration'] = str(int((at(day, eh, em) - at(day, sh, sm)).total_seconds())) + 's'
        state['records'].append(record)
    state['hr_minutes'] = []
    minute = at(-5, 0, 0).astimezone(dt.timezone.utc)
    stop = at(0, 20, 8).astimezone(dt.timezone.utc)
    by_day = {}
    while minute < stop:
        local = minute.astimezone(LONDON)
        day = (local.date() - latest.date()).days
        m = local.hour * 60 + local.minute
        avg = 61 + math.sin(m / 83) * 5 + noise(m) * 4
        if m < 6 * 60:
            avg = 53 + math.sin(m / 31) * 3 + noise(m) * 2
        if day == -5 and 18 * 60 + 30 <= m < 19 * 60 + 30:
            avg = 145 + math.sin(m / 3) * 8 + noise(m) * 6
        if day == -2 and 17 * 60 + 30 <= m < 19 * 60 + 50:
            avg = hr_a(m)
        if day == -1 and 17 * 60 + 30 <= m < 19 * 60 + 40:
            avg = hr_b(m)
            avg = max(120.1, avg) if 18 * 60 + 4 <= m < 19 * 60 + 4 else min(119.9, avg)
        if day == 0 and 6 * 60 + 40 <= m < 8 * 60:
            avg = hr_e(m)
            avg = max(120.1, avg) if 7 * 60 + 10 <= m < 7 * 60 + 41 else min(119.9, avg)
        avg = round(avg, 2)
        by_day.setdefault(local.date().isoformat(), []).append([int(minute.timestamp()), round(avg - 3, 2), avg, round(avg + 4, 2)])
        minute += dt.timedelta(minutes=1)
    state['hr_minutes'] = [{'date': day, 'windows': rows} for day, rows in sorted(by_day.items())]
    state['user']['profile']['body']['age'] = 31
    for device in state['user']['paired_devices']['body']['pairedDevices']:
        device['lastSyncTime'] = iso(stop)
    for resource in state['user'].values():
        resource['fetched_at'] = iso(at(0, 20, 15))
    state['runs'][-1].update(started_at=iso(at(0, 20, 15)), finished_at=iso(at(0, 20, 16)))
    return state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--now', default='2026-03-12T20:30:00Z')
    parser.add_argument('--output', type=Path, default=ROOT / 'fixtures/v2/inputs/store_edit.json')
    args = parser.parse_args()
    now = dt.datetime.fromisoformat(args.now.replace('Z', '+00:00'))
    if now.tzinfo is None:
        parser.error('--now must include a timezone')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(generate(now), separators=(',', ':')) + '\n')


if __name__ == '__main__':
    main()
