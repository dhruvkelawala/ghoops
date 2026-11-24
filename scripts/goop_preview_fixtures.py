#!/usr/bin/env python3
"""Add GOOP display fields to the synthetic preview bodies, and write the two week previews from them."""
import argparse
import copy
import datetime as dt
import json
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

METRICS = (
    'recovery', 'strain', 'sleep_performance', 'asleep_minutes',
    'efficiency_pct', 'restorative_minutes', 'hrv_rmssd_ms', 'resting_hr_bpm',
    'respiratory_rate_bpm', 'spo2_pct', 'skin_temp_deviation_c', 'steps',
    'zones_1_3_minutes', 'zones_4_5_minutes', 'strength_minutes',
)
STAGE_TYPICAL = {
    'window_nights': 30, 'nights_used': 27,
    **{key: {'low_minutes': low, 'high_minutes': high, 'nights_used': 27}
       for key, low, high in (
           ('light', 196, 232), ('deep', 74, 96), ('rem', 92, 121),
           ('awake', 18, 34), ('restorative', 170, 214))},
}


def rounded(value, places=0):
    return float(Decimal(str(value)).quantize(Decimal(10) ** -places, rounding=ROUND_HALF_UP))


def insert_after(obj, key, additions):
    result = {}
    for name, value in obj.items():
        if name not in additions:
            result[name] = value
        if name == key:
            result.update(additions)
    return result


def add_recovery_weights(value, weights):
    if isinstance(value, dict):
        components = value.get('components')
        if isinstance(components, dict) and 'weighted_base' in components and 'weights' not in components:
            value['components'] = insert_after(components, 'weighted_base', {'weights': copy.deepcopy(weights)})
        for child in value.values():
            add_recovery_weights(child, weights)
    elif isinstance(value, list):
        for child in value:
            add_recovery_weights(child, weights)


def add_engine_fields(body, full):
    if isinstance(body, dict):
        if 'score_config' in body and 'score_constants' not in body:
            updated = insert_after(body, 'score_config', {'score_constants': copy.deepcopy(full['score_constants'])})
            body.clear()
            body.update(updated)
        constants = body.get('score_constants')
        if isinstance(constants, dict) and 'vitals' not in constants:
            body['score_constants'] = insert_after(constants, 'workouts', {'vitals': copy.deepcopy(full['score_constants']['vitals'])})
        constants = body.get('score_constants')
        if isinstance(constants, dict) and 'hrv_trend' not in constants:
            body['score_constants'] = insert_after(constants, 'vitals', {'hrv_trend': copy.deepcopy(full['score_constants']['hrv_trend'])})
        constants = body.get('score_constants')
        if isinstance(constants, dict) and 'journal' not in constants:
            constants['journal'] = copy.deepcopy(full['score_constants']['journal'])
        additions = {}
        key = None
        if 'metrics_with_range' in body and 'values_needed' not in body:
            key, additions = 'metrics_with_range', {'values_needed': full['vitals']['values_needed']}
        elif 'efficiency_pct' in body and 'consistency' in body and 'efficiency_band' not in body:
            pct = body['efficiency_pct']
            bands = full['score_constants']['sleep']['efficiency_bands']
            band = None if pct is None else 'high' if pct >= bands['high'] else 'medium' if pct >= bands['medium'] else 'low'
            key, additions = 'efficiency_pct', {'efficiency_band': band}
        if additions:
            updated = insert_after(body, key, additions)
            body.clear()
            body.update(updated)
        if 'metrics_with_range' in body and 'monitor_state' not in body:
            state = 'building' if body['metrics_with_range'] == 0 else 'outside' if body['outside_range'] else 'within'
            updated = insert_after(body, 'adverse', {'persistent': []})
            updated = insert_after(updated, 'values_needed', {'monitor_state': state})
            body.clear()
            body.update(updated)
        if 'monitor_state' in body and 'metrics_with_range' in body and 'hrv_trend' not in body:
            updated = insert_after(body, 'monitor_state', {'hrv_trend': copy.deepcopy(full['vitals']['hrv_trend'])})
            body.clear()
            body.update(updated)
        for name, source, keys in (
                ('sleep_plan', full['sleep_plan'], ('nights_needed', 'window_nights')),
                ('stage_typical', full['sleep']['stage_typical'], ('nights_needed', 'low_percentile', 'high_percentile'))):
            value = body.get(name)
            if isinstance(value, dict) and 'nights_needed' not in value:
                body[name] = insert_after(value, 'nights_used', {k: source[k] for k in keys})
        for child in body.values():
            add_engine_fields(child, full)
    elif isinstance(body, list):
        for child in body:
            add_engine_fields(child, full)


def add_edit_limits(body, status):
    if isinstance(body, dict):
        if body.get('kind') == 'status' and 'edit_limits' not in body:
            updated = insert_after(body, 'server', {'edit_limits': copy.deepcopy(status['edit_limits'])})
            body.clear()
            body.update(updated)
        if isinstance(body.get('edit_limits'), dict):
            body['edit_limits'].setdefault('sleep_min_minutes', status['edit_limits']['sleep_min_minutes'])
            body['edit_limits'].setdefault('rpe_scale', status['edit_limits']['rpe_scale'])
        for child in body.values():
            add_edit_limits(child, status)
    elif isinstance(body, list):
        for child in body:
            add_edit_limits(child, status)


def add_journal(body, journal):
    if body.get('kind') == 'snapshot' and 'impact' not in body.get('journal', {}):
        entry = copy.deepcopy(journal)
        entry['score_version'] = body['score_version']
        entry['generated_at'] = body['generated_at']
        body['journal'] = entry


def extend_rows(body, day):
    for i, row in enumerate(body['days']):
        strain, asleep, performance = (row[key] for key in ('strain', 'asleep_minutes', 'sleep_performance'))
        additions = {
            'zones_1_3_minutes': None if strain is None else round(strain * 2.2),
            'zones_4_5_minutes': None if strain is None else round(max(0, strain - 6) * 2.4),
            'strength_minutes': 45 if row['date'] in ('2026-02-12', '2026-02-19') else 0,
            'restorative_minutes': None if asleep is None else round(asleep * .46),
            'sleep_consistency': None if performance is None else 70 + (i * 7) % 25,
        }
        if row['date'] == day['date']:
            zones = day['strain']['zones_minutes']
            stages = day['sleep']['stages']
            additions.update({
                'zones_1_3_minutes': None if zones is None else sum(zones[k] for k in ('z1', 'z2', 'z3')),
                'zones_4_5_minutes': None if zones is None else sum(zones[k] for k in ('z4', 'z5')),
                'strength_minutes': 0,
                'restorative_minutes': stages['deep']['minutes'] + stages['rem']['minutes'],
                'sleep_consistency': day['sleep']['consistency']['value'],
            })
        body['days'][i] = insert_after(row, 'calories_kcal', additions)


def comparison(day, rows):
    end = dt.date.fromisoformat(day['date'])
    start, last = ((end - dt.timedelta(days=n)).isoformat() for n in (30, 1))
    metrics = {}
    for key in METRICS:
        values = [r[key] for r in rows if start <= r['date'] <= last and r[key] is not None]
        places = 0 if key == 'steps' else 2 if key == 'skin_temp_deviation_c' else 1
        metrics[key] = {'mean': rounded(sum(values) / len(values), places) if len(values) >= 7 else None,
                        'available_days': len(values)}
    return {'window_days': 30, 'from': start, 'to': last, 'min_days': 7, 'metrics': metrics}


WEEK_TARGETS = {'sleep_minutes': 420, 'sleep_nights': 5, 'activity_minutes': 150, 'strength_days': 2}
WEEK_VIGOROUS_WEIGHT = 2
WEEK_MEANS = ('recovery', 'strain', 'sleep_performance', 'asleep_minutes', 'sleep_consistency', 'hrv_rmssd_ms', 'resting_hr_bpm')
WEEK_TOTALS = ('zones_1_3_minutes', 'zones_4_5_minutes', 'strength_minutes', 'steps')


def number(value):
    """Whole numbers as integers, as Go's encoder writes them."""
    return int(value) if value is not None and value == int(value) else value


def week_preview(snapshot, date):
    """The `week` body for the preview store, by week-review-spec.md section 3 and the default targets."""
    rows = {row['date']: row for row in snapshot['days']['days']}
    default, day = dt.date.fromisoformat(snapshot['default_date']), dt.date.fromisoformat(date)
    monday = day - dt.timedelta(days=day.weekday())
    sunday, to = monday + dt.timedelta(days=6), min(monday + dt.timedelta(days=6), default)
    span = lambda a, b: [(a + dt.timedelta(days=i)).isoformat() for i in range((b - a).days + 1)]
    current, last = span(monday, to), span(monday - dt.timedelta(days=7), to - dt.timedelta(days=7))
    usual = span(monday - dt.timedelta(days=28), monday - dt.timedelta(days=1))
    values = lambda dates, key: [rows[d][key] for d in dates if d in rows and rows[d].get(key) is not None]

    def aggregate(dates, key, total):
        found = values(dates, key)
        if not found:
            return None
        return rounded(sum(found)) if total else rounded(sum(found) / len(found), 1)

    metrics = {}
    for key in WEEK_MEANS + WEEK_TOTALS:
        total = key in WEEK_TOTALS
        value, prior, typical = aggregate(current, key, total), aggregate(last, key, total), values(usual, key)
        usual_value = None
        if len(typical) >= 7:
            mean = sum(typical) / len(typical)
            usual_value = rounded(mean * len(current)) if total else rounded(mean, 1)
        change = None if value is None or prior is None else rounded(value - prior, 1)
        metrics[key] = {'value': number(value), 'available_days': len(values(current, key)), 'last_week': number(prior),
                        'change': number(change), 'usual': number(usual_value)}

    sports, total, detected = {}, 0, 0
    for workout in snapshot['workouts']['workouts']:
        if workout['cycle_date'] not in current:
            continue
        if workout['kind'] not in ('recorded', 'goop'):
            detected += 1
            continue
        total += 1
        sport = sports.setdefault(workout['exercise_type'], {'exercise_type': workout['exercise_type'], 'display_name': workout['display_name'], 'category': workout['category'], 'count': 0})
        sport['count'] += 1

    week = [rows.get(d, {}) for d in current]
    complete = sunday < default

    def counted(count, missing, target):
        return 'met' if count >= target else 'open' if not complete else 'not_met' if count + missing < target else 'no_data'

    asleep = [row.get('asleep_minutes') for row in week]
    zone_days = [row for row in week if row.get('zones_1_3_minutes') is not None and row.get('zones_4_5_minutes') is not None]
    credit = sum(row['zones_1_3_minutes'] + WEEK_VIGOROUS_WEIGHT * row['zones_4_5_minutes'] for row in zone_days) if zone_days else None
    strength = [row.get('strength_minutes') for row in week]
    sleep_met = sum(1 for v in asleep if v is not None and v >= WEEK_TARGETS['sleep_minutes'])
    strength_met = sum(1 for v in strength if v is not None and v > 0)
    activity_missing = len(week) - len(zone_days)
    activity = 'met' if credit is not None and credit >= WEEK_TARGETS['activity_minutes'] else 'open' if not complete else 'not_met' if activity_missing == 0 else 'no_data'
    return {
        'schema_version': 2, 'kind': 'week', 'source': snapshot['source'], 'score_version': snapshot['score_version'],
        'generated_at': snapshot['generated_at'], 'timezone': snapshot['timezone'], 'synthetic_fixture': True,
        'freshness': copy.deepcopy(snapshot['freshness']), 'date': date,
        'from': current[0], 'to': current[-1], 'week_end': sunday.isoformat(), 'days_counted': len(current), 'complete': complete,
        'last_week': {'from': last[0], 'to': last[-1]}, 'usual': {'from': usual[0], 'to': usual[-1], 'min_days': 7},
        'metrics': metrics,
        'workouts': {'total': total, 'last_week_total': sum(rows[d]['workouts'] for d in last if d in rows), 'detected_efforts': detected,
                     'by_sport': sorted(sports.values(), key=lambda s: (-s['count'], s['display_name']))},
        'targets': {
            'sleep': {'status': counted(sleep_met, asleep.count(None), WEEK_TARGETS['sleep_nights']), 'min_minutes': WEEK_TARGETS['sleep_minutes'],
                      'nights': WEEK_TARGETS['sleep_nights'], 'met_nights': sleep_met, 'missing_nights': asleep.count(None)},
            'activity': {'status': activity, 'minutes': WEEK_TARGETS['activity_minutes'], 'vigorous_weight': WEEK_VIGOROUS_WEIGHT,
                         'credit_minutes': credit, 'missing_days': activity_missing},
            'strength': {'status': counted(strength_met, strength.count(None), WEEK_TARGETS['strength_days']), 'days': WEEK_TARGETS['strength_days'],
                         'met_days': strength_met, 'missing_days': strength.count(None)},
        },
    }


def update(directory):
    paths = [directory / name for name in ('snapshot_fresh.json', 'snapshot_stale.json', 'days_30.json')]
    bodies = [json.loads(path.read_text()) for path in paths]
    full = json.loads((Path(__file__).resolve().parents[1] / 'fixtures/v2/day_full.json').read_text())
    status = json.loads((Path(__file__).resolve().parents[1] / 'fixtures/v2/status_full.json').read_text())
    journal = json.loads((Path(__file__).resolve().parents[1] / 'fixtures/v2/journal/journal_basic.json').read_text())
    def config_keys(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key == 'score_config':
                    child.update(strain_intent='maintain', wake_target=None)
                config_keys(child)
        elif isinstance(value, list):
            for child in value:
                config_keys(child)
    for body in bodies:
        add_recovery_weights(body, full['recovery']['components']['weights'])
        config_keys(body)
        day = body['day'] if body['kind'] == 'snapshot' else bodies[0]['day']
        days = body['days'] if body['kind'] == 'snapshot' else body
        extend_rows(days, day)
        if body['kind'] == 'snapshot':
            day = insert_after(day, 'strain', {'strain_target': copy.deepcopy(full['strain_target'])})
            day = insert_after(day, 'sleep', {'sleep_plan': copy.deepcopy(day.get('sleep_plan', full['sleep_plan']))})
            day['sleep'] = insert_after(day['sleep'], 'consistency', {'stage_typical': copy.deepcopy(STAGE_TYPICAL)})
            body['sleep'] = insert_after(body['sleep'], 'consistency', {'stage_typical': copy.deepcopy(STAGE_TYPICAL)})
            body['day'] = insert_after(day, 'workouts', {'strength_minutes': 0})
            body['day'] = insert_after(body['day'], 'health_flags', {'comparison': comparison(day, days['days'])})
    sleep = json.loads((Path(__file__).resolve().parents[1] / 'fixtures/v2/sleep_full.json').read_text())
    for body in bodies:
        if body['kind'] == 'snapshot':
            for key in ('google', 'edit', 'edit_range'):
                body['sleep']['session'].setdefault(key, copy.deepcopy(sleep['session'][key]))
            body['sleep']['hypnogram'].setdefault('outside', [])
    fresh = bodies[0]
    for body in bodies:
        if body['kind'] == 'snapshot':
            for workout in body['day']['workouts'] + body['workouts']['workouts']:
                workout['paused_minutes'] = 0
                workout.setdefault('rpe', None)
    if not any(w['kind'] == 'goop' for w in fresh['workouts']['workouts']):
        for i, workout in enumerate(fresh['workouts']['workouts']):
            if workout['kind'] == 'detected':
                goop = copy.deepcopy(workout)
                goop.update(kind='goop', id='goop-3f0c0000-0000-4000-8000-000000000001',
                            exercise_type='BOXING', display_name='Boxing', category='combat',
                            source='goop', provider=None, paused_minutes=0)
                fresh['workouts']['workouts'][i] = goop
                for row in fresh['days']['days']:
                    if row['date'] == goop['cycle_date']:
                        row['workouts'] += 1
                        row['detected_efforts'] -= 1
                break
    for path, body in zip(paths, bodies):
        add_engine_fields(body, full)
        add_edit_limits(body, status)
        add_journal(body, journal)
        path.write_text(json.dumps(body, indent=2, ensure_ascii=False) + '\n')
    for name, date in (('week_this.json', fresh['default_date']), ('week_last.json', '2026-03-02')):
        (directory / name).write_text(json.dumps(week_preview(fresh, date), indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, nargs='?', default=Path(__file__).resolve().parents[1] / 'fixtures/v2/preview')
    update(parser.parse_args().directory)
