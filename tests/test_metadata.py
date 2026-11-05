import os
import unittest
from unittest.mock import patch
from backend.metadata import metadata, normalize, rotten_url

class MetadataTests(unittest.TestCase):
    def test_unconfigured_does_not_request_external_api(self):
        with patch.dict(os.environ, {'OMDB_API_KEY': ''}), patch('backend.metadata.request_json') as fetch:
            self.assertFalse(metadata('tt28534120')['configured'])
            fetch.assert_not_called()
    def test_exact_identity_and_scores(self):
        raw = {'Response': 'True', 'imdbID': 'tt28534120', 'Type': 'movie',
               'imdbRating': '11', 'Ratings': [{'Source': 'Rotten Tomatoes', 'Value': '99%'}]}
        self.assertFalse(normalize('tt1234567', raw)['verified'])
        result = normalize('tt28534120', raw, 'https://evil.test/m/movie')
        self.assertIsNone(result['imdbRating'])
        self.assertIsNone(result['rtRating'])
        result = normalize('tt28534120', raw, 'https://www.rottentomatoes.com/m/movie')
        self.assertEqual(result['rtRating'], 99)
    def test_invalid_id_rejected(self):
        with self.assertRaises(ValueError):
            metadata('tt28534120&apikey=bad')
    def test_ambiguous_rotten_id_not_linked(self):
        self.assertIsNone(rotten_url('tt28534120', fetch=lambda *a, **k: {
            'results': {'bindings': [{'rt': {'value': 'm/first'}}, {'rt': {'value': 'm/second'}}]}}))
