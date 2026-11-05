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
