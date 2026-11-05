"""Optional OMDb metadata proxy. Credentials stay on the server, never in APK."""
import json
import os
import re
import threading
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen

_CACHE = {}
_LOCK = threading.Lock()

def request_json(url, timeout=10):
    request = Request(url, headers={'User-Agent': 'CINESHOW-Metadata/0.6.0', 'Accept': 'application/json'})
    with urlopen(request, timeout=timeout) as response:
        body = response.read(500001)
        if len(body) > 500000:
            raise ValueError('Metadata response too large')
        return json.loads(body)

def rotten_url(imdb_id, fetch=request_json):
    query = 'SELECT ?rt WHERE { ?item wdt:P345 "' + imdb_id + '"; wdt:P1258 ?rt. } LIMIT 2'
    try:
        raw = fetch('https://query.wikidata.org/sparql?' + urlencode({'query': query, 'format': 'json'}), timeout=6)
        ids = {row['rt']['value'] for row in raw.get('results', {}).get('bindings', [])}
        if len(ids) != 1:
            return None
        ident = ids.pop()
        if not re.fullmatch(r'(?:m|tv)/[A-Za-z0-9_-]+(?:/s\d+)?', ident):
            return None
        return 'https://www.rottentomatoes.com/' + ident
    except Exception:
        return None

def normalize(imdb_id, raw, rt_url=None):
    if not isinstance(rt_url, str) or not re.fullmatch(r'https://www\.rottentomatoes\.com/(?:m|tv)/[A-Za-z0-9_-]+(?:/s\d+)?', rt_url):
        rt_url = None
    if raw.get('Response') != 'True' or raw.get('imdbID') != imdb_id:
        return {'verified': False, 'imdbId': imdb_id}
    if raw.get('Type') not in ('movie', 'series'):
        return {'verified': False, 'imdbId': imdb_id}
    def clean(value):
        return value if isinstance(value, str) and value != 'N/A' else ''
    score = None
    try:
        value = float(raw.get('imdbRating', ''))
        if 0 <= value <= 10:
            score = value
    except (ValueError, TypeError):
        pass
    votes = None
    value = str(raw.get('imdbVotes', '')).replace(',', '')
    if value.isdigit():
        votes = int(value)
    rt = None
    for rating in raw.get('Ratings') or []:
        if not isinstance(rating, dict) or rating.get('Source') != 'Rotten Tomatoes':
            continue
        match = re.fullmatch(r'(\d{1,3})%', str(rating.get('Value', '')))
        if match and int(match[1]) <= 100:
            rt = int(match[1])
    year = re.match(r'\d{4}', str(raw.get('Year', '')))
    return {'verified': True, 'imdbId': imdb_id, 'title': clean(raw.get('Title')),
        'year': int(year[0]) if year else 0, 'type': raw.get('Type'),
        'plot': clean(raw.get('Plot')), 'imdbRating': score, 'imdbVotes': votes,
        'cast': [v.strip() for v in clean(raw.get('Actors')).split(',') if v.strip()],
        'director': clean(raw.get('Director')), 'released': clean(raw.get('Released')),
        'runtime': clean(raw.get('Runtime')), 'genres': clean(raw.get('Genre')),
        'rtRating': rt if rt_url else None, 'rtUrl': rt_url,
        'source': 'OMDb', 'updatedAt': int(time.time())}

def metadata(imdb_id):
    if not re.fullmatch(r'tt\d{7,10}', imdb_id):
        raise ValueError('Invalid IMDb ID')
    key = os.environ.get('OMDB_API_KEY', '').strip()
    if not key:
        return {'configured': False, 'verified': False, 'imdbId': imdb_id}
    with _LOCK:
        cached = _CACHE.get(imdb_id)
        if cached and time.time() - cached[0] < 86400:
            return cached[1]
        raw = request_json('https://www.omdbapi.com/?' + urlencode({
            'apikey': key, 'i': imdb_id, 'plot': 'full', 'r': 'json'}))
        rt = None
        if any(isinstance(v, dict) and v.get('Source') == 'Rotten Tomatoes'
               for v in raw.get('Ratings') or []):
            rt = rotten_url(imdb_id)
        data = normalize(imdb_id, raw, rt)
        data['configured'] = True
        if len(_CACHE) >= 500:
            _CACHE.clear()
        _CACHE[imdb_id] = (time.time(), data)
        return data
