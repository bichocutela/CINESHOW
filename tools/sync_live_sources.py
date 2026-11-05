"""Public live directory mirror. No media files, credentials or expiring media URLs."""
import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from urllib.parse import urlsplit

ORIGIN = 'https://superflixapi.fun'
FIELDS = {'id', 'name', 'title', 'description', 'logo_url', 'embed_url', 'category',
          'is_active', 'is_nsfw', 'poster', 'sport_key', 'start_time', 'status',
          'competition', 'page_url', 'play_event_url'}

def clean_rows(raw, events=False):
    if not isinstance(raw, dict) or raw.get('success') is not True or not isinstance(raw.get('data'), list):
        raise ValueError('Invalid live directory response')
    rows = []
    for item in raw['data']:
        if not isinstance(item, dict):
            continue
        if item.get('is_active') is False or item.get('is_nsfw') is True:
            continue
        if str(item.get('category', '')).lower() in ('adulto', 'adultos', 'xxx'):
            continue
        url = urlsplit(str(item.get('play_event_url' if events else 'embed_url', '')))
        if url.scheme != 'https' or url.netloc != 'superflixapi.fun' or not url.path.startswith('/eventos/' if events else '/canal/'):
            continue
        rows.append({k: v for k, v in item.items() if k in FIELDS})
    if not rows:
        raise ValueError('Empty directory must not replace a valid snapshot')
    return rows

def request_json(url, data=None, method='GET', token=None):
    headers = {'User-Agent': 'CINESHOW/0.6.1', 'Accept': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    body = None if data is None else json.dumps(data).encode()
    if body is not None:
        headers['Content-Type'] = 'application/json'
    with urlopen(Request(url, data=body, headers=headers, method=method), timeout=25) as response:
        content = response.read(3000001)
        if len(content) > 3000000:
            raise ValueError('Directory response too large')
        return json.loads(content)

def snapshots():
    result = {}
    for category, events in [('canais', False), ('eventos', True)]:
        raw = request_json(ORIGIN + '/lista?category=' + category + '&format=json&limit=500')
        result['superflix_' + ('events' if events else 'channels') + '.json'] = {
            'source': ORIGIN, 'fetchedAt': datetime.now(timezone.utc).isoformat(),
            'items': clean_rows(raw, events)}
    return result

def publish(files):
    token = os.environ['GH_TOKEN']
    repo = os.environ['GITHUB_REPOSITORY']
    base = 'https://api.github.com/repos/' + repo
    call = lambda path, data=None, method='GET': request_json(base + path, data, method, token)
    exists = True
    try:
        parent = call('/git/ref/heads/live-data')['object']['sha']
    except HTTPError as error:
        if error.code != 404:
            raise
        exists = False
        parent = call('/git/ref/heads/main')['object']['sha']
    tree = call('/git/trees', {'tree': [
        {'path': name, 'mode': '100644', 'type': 'blob', 'content': json.dumps(data, ensure_ascii=False)}
        for name, data in files.items()]}, 'POST')['sha']
    commit = call('/git/commits', {'message': 'data: refresh verified public live directories',
                                  'tree': tree, 'parents': [parent]}, 'POST')['sha']
    if exists:
        call('/git/refs/heads/live-data', {'sha': commit}, 'PATCH')
    else:
        call('/git/refs', {'ref': 'refs/heads/live-data', 'sha': commit}, 'POST')
    print('Updated public directories:', ', '.join(files))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default='assets')
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    files = snapshots()
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        (output / name).write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
        print(name, len(data['items']), data['fetchedAt'])
    if args.publish:
        publish(files)
