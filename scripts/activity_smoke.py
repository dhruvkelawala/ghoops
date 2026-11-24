"""Exercise the activity API on an isolated verify-ghealth fixture server."""
import datetime as dt
import json
from pathlib import Path
import sys
import urllib.error
import urllib.request

run = Path(sys.argv[1])
port = int(sys.argv[2])
assert run.name.startswith('ghealth-verify-') and port != 8787
header = (run / 'token.header').read_text().strip().split(': ', 1)[1]
now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
body = json.loads(Path('fixtures/v2/activities/valid.json').read_text())
body.update(start=(now - dt.timedelta(hours=2)).isoformat(), end=(now - dt.timedelta(hours=1)).isoformat())


def request(method, path, payload, expected):
    req = urllib.request.Request(f'http://127.0.0.1:{port}/v2/{path}', data=payload, method=method,
                                 headers={'Authorization': header, 'Content-Type': 'application/json'})
    try:
        response = urllib.request.urlopen(req)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        result = json.load(response)
        assert response.status == expected, (method, response.status, expected)
        print(method, path.split('/')[0], response.status)
        return result


raw = json.dumps(body).encode()
request('POST', 'activities', raw, 201)
request('POST', 'activities', raw, 200)
request('POST', 'activities', json.dumps({**body, 'display_name': 'Changed'}).encode(), 409)
request('POST', 'activities', b'{}', 400)
request('POST', 'activities', b' ' * 65537, 413)
rows = request('GET', 'workouts?days=1', None, 200)['workouts']
assert sum(w['kind'] == 'goop' for w in rows) == 1
assert all(b'Boxing' not in p.read_bytes() for p in (run / 'state').iterdir() if p.is_file())
print('goop_workouts=1 plaintext_matches=0')
request('DELETE', 'activities/' + body['id'], None, 200)
request('DELETE', 'activities/' + body['id'], None, 404)
