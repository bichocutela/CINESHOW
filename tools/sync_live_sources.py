"""Mirror public directories, retaining verified data during source outages."""
import argparse
import base64
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from urllib.parse import urlsplit

ORIGIN = 'https://superflixapi.fun'
DIRECTORIES = [('superflix_channels.json', 'canais', False),
               ('superflix_events.json', 'eventos', True)]
FIELDS = {'id', 'name', 'title', 'description', 'logo_url', 'embed_url', 'category',
          'is_active', 'is_nsfw', 'poster', 'sport_key', 'start_time', 'status',
          'competition', 'page_url', 'play_event_url'}


def clean_rows(raw, events=False):
    if not isinstance(raw, dict) or raw.get('success') is not True or not isinstance(raw.get('data'), list):
        raise ValueError('Invalid live directory response')
    # An explicitly empty agenda is valid. An empty channel list or a nonempty
    # response whose entries all fail validation must never erase verified data.
    if events and raw['data'] == []:
        return []
    rows = []
    for item in raw['data']:
        if not isinstance(item, dict):
            continue
        if item.get('is_active') in (False, 0, '0') or item.get('is_nsfw') in (True, 1, '1'):
            continue
        if str(item.get('category', '')).strip().lower() in ('adulto', 'adultos', 'xxx'):
            continue
        url = urlsplit(str(item.get('play_event_url' if events else 'embed_url', '')))
        if (url.scheme != 'https' or url.netloc != 'superflixapi.fun'
                or not url.path.startswith('/eventos/' if events else '/canal/')):
            continue
        name = item.get('title' if events else 'name')
        if not isinstance(name, str) or not name.strip():
            continue
        rows.append({k: v for k, v in item.items() if k in FIELDS})
    if not rows:
        raise ValueError('Empty or incompatible directory must not replace a valid snapshot')
    return rows


def request_json(url, data=None, method='GET', token=None):
    headers = {'User-Agent': 'CINESHOW/0.6.4', 'Accept': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    body = None if data is None else json.dumps(data).encode()
    if body is not None:
        headers['Content-Type'] = 'application/json'
    with urlopen(Request(url, data=body, headers=headers, method=method), timeout=20) as response:
        content = response.read(3000001)
        if len(content) > 3000000:
            raise ValueError('Directory response too large')
        return json.loads(content)


def validated_snapshot(data, events=False):
    if not isinstance(data, dict) or data.get('source') != ORIGIN:
        raise ValueError('Invalid snapshot source')
    at = datetime.fromisoformat(data['fetchedAt'])
    if at.tzinfo is None:
        raise ValueError('Snapshot timestamp requires a timezone')
    rows = clean_rows({'success': True, 'data': data.get('items')}, events)
    return {'source': ORIGIN, 'fetchedAt': data['fetchedAt'], 'items': rows}


def read_previous(call=None, assets=Path('assets')):
    result = {}
    for name, _, events in DIRECTORIES:
        if call is not None:
            try:
                blob = call('/contents/' + name + '?ref=live-data')
                data = json.loads(base64.b64decode(blob['content']))
                result[name] = validated_snapshot(data, events)
                continue
            except HTTPError as error:
                if error.code != 404:
                    raise  # GitHub authentication/permission errors remain failures.
            except (KeyError, ValueError, TypeError):
                pass
        try:
            result[name] = validated_snapshot(json.loads((assets / name).read_text()), events)
        except (OSError, KeyError, ValueError, TypeError):
            pass
    return result


def snapshots(previous=None, fetch=request_json, sleep=time.sleep, report=None):
    previous = previous or {}
    report = report if report is not None else {}
    result = {}
    for name, category, events in DIRECTORIES:
        error = None
        attempts = 0
        for attempt in range(3):
            attempts += 1
            try:
                raw = fetch(ORIGIN + '/lista?category=' + category + '&format=json&limit=500')
                result[name] = {'source': ORIGIN,
                                'fetchedAt': datetime.now(timezone.utc).isoformat(),
                                'items': clean_rows(raw, events)}
                report[name] = {'status': 'updated', 'attempts': attempts,
                                'items': len(result[name]['items'])}
                break
            except (URLError, TimeoutError, OSError, ValueError) as failure:
                error = type(failure).__name__
                if attempt < 2:
                    sleep(2 ** attempt)
        if name not in result:
            try:
                result[name] = validated_snapshot(previous[name], events)
                report[name] = {'status': 'retained', 'attempts': attempts,
                                'items': len(result[name]['items']), 'reason': error}
            except (KeyError, ValueError, TypeError):
                report[name] = {'status': 'unavailable', 'attempts': attempts, 'reason': error}
    return result


def github_call():
    token = os.environ['GH_TOKEN']
    base = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
    return lambda path, data=None, method='GET': request_json(base + path, data, method, token)


def publish(files, call=None):
    if not files:
        return False
    call = call or github_call()
    exists = True
    try:
        parent = call('/git/ref/heads/live-data')['object']['sha']
    except HTTPError as error:
        if error.code != 404:
            raise
        exists = False
        parent = call('/git/ref/heads/main')['object']['sha']
    parent_tree = call('/git/commits/' + parent)['tree']['sha']
    # Keep other directories/files when only one source refreshed successfully.
    tree = call('/git/trees', {'base_tree': parent_tree, 'tree': [
        {'path': name, 'mode': '100644', 'type': 'blob', 'content': json.dumps(data, ensure_ascii=False)}
        for name, data in files.items()]}, 'POST')['sha']
    if tree == parent_tree:
        print('Verified snapshots unchanged; no commit needed.')
        return False
    commit = call('/git/commits', {'message': 'data: refresh verified public live directories',
                                  'tree': tree, 'parents': [parent]}, 'POST')['sha']
    if exists:
        call('/git/refs/heads/live-data', {'sha': commit, 'force': False}, 'PATCH')
    else:
        call('/git/refs', {'ref': 'refs/heads/live-data', 'sha': commit}, 'POST')
    print('Updated public directories:', ', '.join(files))
    return True


def run(output, should_publish=False, summary_path=None, fetch=request_json, sleep=time.sleep, call=None):
    if should_publish:
        call = call or github_call()
    report = {}
    files = snapshots(read_previous(call), fetch=fetch, sleep=sleep, report=report)
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        (output / name).write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
    (output / 'sync-status.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    lines = ['## Public live directory sync', '', '| Directory | Result | Entries | Attempts | Verified at |',
             '|---|---|---:|---:|---|']
    for name, state in report.items():
        at = files.get(name, {}).get('fetchedAt', 'unavailable')
        lines.append(f"| {name} | {state['status']} | {state.get('items', 0)} | {state['attempts']} | {at} |")
        if state['status'] != 'updated':
            print(f"::warning::{name}: {state['status']} after {state['attempts']} attempts ({state['reason']}).")
        else:
            print(name, state['items'], 'entries verified')
    if summary_path:
        Path(summary_path).write_text('\n'.join(lines) + '\n', encoding='utf-8')
    # Retained data is an explicitly reported degraded state, not fresh data.
    # Retained snapshots keep their original verification time and contents.
    if should_publish:
        publish(files, call)
    if any(state['status'] == 'unavailable' for state in report.values()):
        raise RuntimeError('No verified snapshot available for one or more directories')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default='assets')
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    run(args.output, args.publish, os.environ.get('GITHUB_STEP_SUMMARY'))
