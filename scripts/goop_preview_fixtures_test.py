import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class PreviewFixturesTest(unittest.TestCase):
    def test_week_previews_follow_the_rows_and_match_the_mockup(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            for name in ('snapshot_fresh.json', 'snapshot_stale.json', 'days_30.json'):
                (directory / name).write_text((ROOT / 'fixtures/v2/preview' / name).read_text())
            command = [sys.executable, '-I', str(ROOT / 'scripts/goop_preview_fixtures.py'), str(directory)]
            subprocess.run(command, check=True)
            for name in ('week_this.json', 'week_last.json'):
                self.assertEqual((directory / name).read_text(), (ROOT / 'fixtures/v2/preview' / name).read_text(), name)
            this = json.loads((directory / 'week_this.json').read_text())
            last = json.loads((directory / 'week_last.json').read_text())
        self.assertEqual((this['from'], this['to'], this['complete']), ('2026-03-09', '2026-03-10', False))
        self.assertEqual([this['targets'][k]['status'] for k in ('sleep', 'activity', 'strength')], ['open'] * 3)
        self.assertEqual((this['targets']['sleep']['met_nights'], this['targets']['activity']['credit_minutes'], this['targets']['strength']['met_days']), (1, 145, 0))
        self.assertEqual([last['targets'][k]['status'] for k in ('sleep', 'activity', 'strength')], ['no_data', 'met', 'not_met'])
        self.assertEqual((last['targets']['sleep']['missing_nights'], last['targets']['activity']['credit_minutes']), (1, 222))
        self.assertEqual((last['metrics']['recovery']['value'], last['metrics']['recovery']['last_week'], last['metrics']['steps']['value']), (57.3, 59, 73055))
        self.assertEqual([(s['display_name'], s['count']) for s in last['workouts']['by_sport']], [('Kickboxing', 2), ('Boxing', 1), ('Walking', 1)])

    def test_additions_preserve_existing_values_and_are_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            names = ('snapshot_fresh.json', 'snapshot_stale.json', 'days_30.json')
            for name in names:
                body = json.loads((ROOT / 'fixtures/v2/preview' / name).read_text())
                self.remove_parity(body)
                (directory / name).write_text(json.dumps(body))
            before = {name: json.loads((directory / name).read_text()) for name in names}
            command = [sys.executable, '-I', str(ROOT / 'scripts/goop_preview_fixtures.py'), str(directory)]
            subprocess.run(command, check=True)
            first = {name: (directory / name).read_bytes() for name in names}
            subprocess.run(command, check=True)
            for name in names:
                self.assertEqual(first[name], (directory / name).read_bytes())
                after = json.loads(first[name])
                self.assert_preserved(before[name], after)
                self.assertEqual(after['score_version'], '2.0.0')
                self.assert_configs(after)
                days = after['days']['days'] if after['kind'] == 'snapshot' else after['days']
                last = days[-1]
                self.assertEqual([last[k] for k in ('zones_1_3_minutes', 'zones_4_5_minutes', 'strength_minutes', 'restorative_minutes', 'sleep_consistency')], [27, 33, 0, 201, 87])
                if after['kind'] == 'snapshot':
                    status = json.loads((ROOT / 'fixtures/v2/status_full.json').read_text())
                    self.assertEqual(after['status']['edit_limits'], status['edit_limits'])
                    journal = json.loads((ROOT / 'fixtures/v2/journal/journal_basic.json').read_text())
                    self.assertEqual((after['journal']['kind'], after['journal']['generated_at']), ('journal', after['generated_at']))
                    self.assertEqual(after['journal']['entries'], journal['entries'])
                    full = json.loads((ROOT / 'fixtures/v2/day_full.json').read_text())
                    self.assertEqual(after['score_constants'], full['score_constants'])
                    self.assertEqual(after['day']['score_constants'], full['score_constants'])
                    self.assertEqual(after['day']['sleep']['efficiency_band'], 'high')
                    vitals = after['day']['vitals']
                    self.assertEqual(vitals.get('persistent'), [])
                    self.assertEqual(vitals.get('monitor_state'), 'outside')
                    self.assertEqual(vitals.get('hrv_trend'), full['vitals']['hrv_trend'])
                    self.assertEqual(after['day']['recovery']['components']['weights'], full['recovery']['components']['weights'])
                    self.assertEqual(after['day']['strain_target'], full['strain_target'])
                    self.assertEqual(after['day']['sleep_plan'], full['sleep_plan'])
                    comparison = after['day']['comparison']
                    self.assertEqual((comparison['from'], comparison['to']), ('2026-02-08', '2026-03-09'))
                    self.assertEqual(len(comparison['metrics']), 15)
                    self.assertEqual(after['sleep']['stage_typical']['light']['low_minutes'], 196)

    def test_monitor_fields_follow_preview_state(self):
        import copy
        import runpy
        add = runpy.run_path(str(ROOT / 'scripts/goop_preview_fixtures.py'))['add_engine_fields']
        full = json.loads((ROOT / 'fixtures/v2/day_full.json').read_text())
        for count, outside, state in ((0, [], 'building'), (5, [], 'within'), (5, ['resting_hr'], 'outside')):
            with self.subTest(state=state):
                body = copy.deepcopy(full)
                body['vitals'].update(metrics_with_range=count, outside_range=outside)
                body['vitals'].pop('monitor_state')
                body['vitals'].pop('persistent')
                body['score_constants'].pop('vitals')
                body['score_constants'].pop('hrv_trend')
                body['vitals'].pop('hrv_trend')
                add(body, full)
                self.assertEqual(body['vitals']['hrv_trend'], full['vitals']['hrv_trend'])
                self.assertEqual(list(body['score_constants']).index('hrv_trend'), list(body['score_constants']).index('vitals') + 1)
                self.assertEqual(body['vitals']['monitor_state'], state)
                self.assertEqual(body['vitals']['persistent'], [])
                self.assertEqual(body['score_constants']['vitals'], full['score_constants']['vitals'])
                body['vitals'].update(monitor_state='attention', persistent=['resting_hr', 'respiratory_rate'])
                add(body, full)
                self.assertEqual(body['vitals']['monitor_state'], 'attention')
                self.assertEqual(body['vitals']['persistent'], ['resting_hr', 'respiratory_rate'])

    def assert_configs(self, value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key == 'score_config':
                    self.assertEqual(child['strain_intent'], 'maintain')
                    self.assertIsNone(child['wake_target'])
                self.assert_configs(child)
        elif isinstance(value, list):
            for child in value:
                self.assert_configs(child)

    def remove_parity(self, value):
        if isinstance(value, dict):
            for key in ('journal', 'edit_limits', 'strain_target', 'sleep_plan', 'strain_intent', 'wake_target', 'weights', 'score_constants', 'values_needed', 'efficiency_band', 'nights_needed', 'low_percentile', 'high_percentile', 'persistent', 'monitor_state'):
                value.pop(key, None)
            for child in value.values():
                self.remove_parity(child)
        elif isinstance(value, list):
            for child in value:
                self.remove_parity(child)

    def assert_preserved(self, before, after):
        if isinstance(before, dict):
            for key, value in before.items():
                self.assertIn(key, after)
                self.assert_preserved(value, after[key])
        elif isinstance(before, list):
            self.assertEqual(len(before), len(after))
            for a, b in zip(before, after):
                self.assert_preserved(a, b)
        else:
            self.assertEqual(before, after)


if __name__ == '__main__':
    unittest.main()
