import unittest
from tools.sync_live_sources import clean_rows

class LiveSnapshotTests(unittest.TestCase):
    def test_snapshot_removes_private_media_tokens_and_inactive_rows(self):
        rows = clean_rows({'success': True, 'data': [
            {'id': 'band', 'name': 'Band', 'embed_url': 'https://superflixapi.fun/canal/band',
             'token': 'temporary', 'play_event_direct_url': 'https://media.test?token=temporary'},
            {'id': 'off', 'name': 'Off', 'is_active': False, 'embed_url': 'https://superflixapi.fun/canal/off'}]})
        self.assertEqual(len(rows), 1)
        self.assertNotIn('token', rows[0])
        self.assertNotIn('play_event_direct_url', rows[0])
    def test_invalid_or_empty_snapshot_cannot_overwrite_last_valid_directory(self):
        for raw in ({'success': False, 'data': []}, {'success': True, 'data': []}):
            with self.assertRaises(ValueError):
                clean_rows(raw)

class LiveSyncRecoveryTests(unittest.TestCase):
    def snapshot(self, events=False):
        from tools.sync_live_sources import ORIGIN
        row = ({'id': 'match', 'title': 'Match', 'play_event_url': ORIGIN + '/eventos/match'} if events else
               {'id': 'band', 'name': 'Band', 'embed_url': ORIGIN + '/canal/band'})
        return {'source': ORIGIN, 'fetchedAt': '2026-11-05T14:30:17+00:00', 'items': [row]}

    def previous(self):
        return {'superflix_channels.json': self.snapshot(), 'superflix_events.json': self.snapshot(True)}

    def test_empty_agenda_valid_but_invalid_entries_rejected(self):
        self.assertEqual(clean_rows({'success': True, 'data': []}, events=True), [])
        with self.assertRaises(ValueError):
            clean_rows({'success': True, 'data': [{'title': 'Bad', 'play_event_url': 'https://other.test/eventos/x'}]}, events=True)

    def test_string_flags_and_blank_names_are_not_published(self):
        for extra in ({'is_active': '0'}, {'is_nsfw': '1'}, {'name': ' '}):
            with self.assertRaises(ValueError):
                clean_rows({'success': True, 'data': [{**self.snapshot()['items'][0], **extra}]})

    def test_empty_channels_do_not_block_empty_agenda(self):
        from tools.sync_live_sources import snapshots
        report = {}
        previous = self.previous()
        result = snapshots(previous, fetch=lambda _: {'success': True, 'data': []}, sleep=lambda _: None, report=report)
        self.assertEqual(result['superflix_channels.json'], previous['superflix_channels.json'])
        self.assertEqual(result['superflix_events.json']['items'], [])
        self.assertEqual(report['superflix_channels.json']['status'], 'retained')
        self.assertEqual(report['superflix_channels.json']['attempts'], 3)
        self.assertEqual(report['superflix_events.json']['status'], 'updated')

    def test_transient_network_failure_is_retried(self):
        from tools.sync_live_sources import snapshots
        from urllib.error import URLError
        calls = {}
        def fetch(url):
            events = 'category=eventos' in url
            calls[events] = calls.get(events, 0) + 1
            if calls[events] == 1:
                raise URLError('temporary')
            return {'success': True, 'data': self.snapshot(events)['items']}
        report = {}
        result = snapshots(fetch=fetch, sleep=lambda _: None, report=report)
        self.assertEqual(len(result), 2)
        self.assertEqual(calls, {False: 2, True: 2})
        self.assertTrue(all(v['status'] == 'updated' for v in report.values()))

    def test_partial_failure_preserves_timestamp_and_other_refresh(self):
        from tools.sync_live_sources import snapshots
        from urllib.error import URLError
        previous = self.previous()
        def fetch(url):
            if 'category=eventos' in url:
                raise URLError('source offline')
            return {'success': True, 'data': self.snapshot()['items']}
        report = {}
        result = snapshots(previous, fetch=fetch, sleep=lambda _: None, report=report)
        self.assertEqual(report['superflix_channels.json']['status'], 'updated')
        self.assertEqual(report['superflix_events.json']['status'], 'retained')
        self.assertEqual(result['superflix_events.json']['fetchedAt'], previous['superflix_events.json']['fetchedAt'])

    def test_invalid_backup_is_not_a_successful_sync(self):
        from tools.sync_live_sources import snapshots
        report = {}
        result = snapshots({'superflix_channels.json': {'source': 'wrong'}},
                           fetch=lambda _: {'success': False, 'data': []}, sleep=lambda _: None, report=report)
        self.assertEqual(result, {})
        self.assertTrue(all(v['status'] == 'unavailable' for v in report.values()))

    def test_previous_branch_snapshot_has_priority(self):
        import base64
        import json
        from tempfile import TemporaryDirectory
        from pathlib import Path
        from tools.sync_live_sources import read_previous
        previous = self.previous()
        def call(path):
            name = path.split('/contents/')[1].split('?')[0]
            return {'content': base64.b64encode(json.dumps(previous[name]).encode()).decode()}
        with TemporaryDirectory() as tmp:
            self.assertEqual(read_previous(call, assets=Path(tmp)), previous)

    def test_github_permission_error_is_not_hidden(self):
        from tools.sync_live_sources import read_previous, publish
        from urllib.error import HTTPError
        def call(*args):
            raise HTTPError('https://api.github.com', 403, 'Forbidden', {}, None)
        with self.assertRaises(HTTPError):
            read_previous(call)
        with self.assertRaises(HTTPError):
            publish(self.previous(), call=call)

    def test_publish_keeps_parent_tree_and_does_not_force_branch(self):
        from tools.sync_live_sources import publish
        calls = []
        def call(path, data=None, method='GET'):
            calls.append((path, data, method))
            return {'/git/ref/heads/live-data': {'object': {'sha': 'parent'}},
                    '/git/commits/parent': {'tree': {'sha': 'parent-tree'}},
                    '/git/trees': {'sha': 'new-tree'},
                    '/git/commits': {'sha': 'new-commit'},
                    '/git/refs/heads/live-data': {}}[path]
        self.assertTrue(publish({'superflix_channels.json': self.snapshot()}, call=call))
        tree = next(data for path, data, _ in calls if path == '/git/trees')
        self.assertEqual(tree['base_tree'], 'parent-tree')
        self.assertEqual(len(tree['tree']), 1)
        self.assertEqual(calls[-1][1], {'sha': 'new-commit', 'force': False})

    def test_unchanged_snapshots_skip_commit(self):
        from tools.sync_live_sources import publish
        paths = []
        def call(path, data=None, method='GET'):
            paths.append(path)
            return {'/git/ref/heads/live-data': {'object': {'sha': 'parent'}},
                    '/git/commits/parent': {'tree': {'sha': 'same-tree'}},
                    '/git/trees': {'sha': 'same-tree'}}[path]
        self.assertFalse(publish(self.previous(), call=call))
        self.assertNotIn('/git/commits', paths)

    def test_run_reports_retained_data_without_claiming_it_is_fresh(self):
        import json
        from pathlib import Path
        from tempfile import TemporaryDirectory
        from unittest.mock import patch
        from tools.sync_live_sources import run
        previous = self.previous()
        with TemporaryDirectory() as tmp, patch('tools.sync_live_sources.read_previous', return_value=previous):
            summary = Path(tmp) / 'summary.md'
            report = run(Path(tmp) / 'out', summary_path=summary,
                         fetch=lambda _: {'success': False, 'data': []}, sleep=lambda _: None)
            self.assertTrue(all(v['status'] == 'retained' for v in report.values()))
            data = json.loads((Path(tmp) / 'out/superflix_channels.json').read_text())
            self.assertEqual(data['fetchedAt'], previous['superflix_channels.json']['fetchedAt'])
            self.assertIn('retained', summary.read_text())
            self.assertTrue((Path(tmp) / 'out/sync-status.json').exists())

    def test_run_fails_if_no_verified_snapshot_is_available(self):
        from pathlib import Path
        from tempfile import TemporaryDirectory
        from unittest.mock import patch
        from tools.sync_live_sources import run
        with TemporaryDirectory() as tmp, patch('tools.sync_live_sources.read_previous', return_value={}):
            with self.assertRaises(RuntimeError):
                run(tmp, fetch=lambda _: {'success': False, 'data': []}, sleep=lambda _: None)
            self.assertTrue((Path(tmp) / 'sync-status.json').exists())
