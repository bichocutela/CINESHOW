"""Read-only adapters for publicly exposed catalogs. No video downloading."""
from __future__ import annotations
import hashlib
import html
import json
import re
import subprocess
import tempfile
import unicodedata
from dataclasses import dataclass, asdict
from urllib.parse import urlencode, urlsplit

ORIGINS = {'rtfilmes': 'https://rtfilmes.com', 'tontons': 'https://tontonsfilmeurs.com', 'xonados': 'https://www.xonados.com'}
SHOWS = {1: ('Além do Tempo', None), 2: ('Avenida Brasil', 'avenida-brasil-1'), 3: ('A Nobreza do Amor', 'a-nobreza-do-amor'), 4: ('Por Você', 'por-voce'), 5: ('Quem Ama Cuida', 'quem-ama-cuida'), 6: ('A Fazenda 18', 'a-fazenda-18')}

def normalized(text):
    return re.sub(r'\W+', ' ', unicodedata.normalize('NFKD', text).encode('ascii', 'ignore').decode().lower()).strip()

def text(value):
    return html.unescape(re.sub('<[^>]+>', '', value)).strip()

def attrs(tag):
    return dict((k, html.unescape(v)) for k, _, v in re.findall(r'([\w-]+)\s*=\s*([\"\x27])(.*?)\2', tag, re.S))

class Transport:
    def __init__(self, origin):
        self.origin = origin
        self.tmp = tempfile.TemporaryDirectory()
        self.jar = self.tmp.name + '/cookies'
    def close(self):
        self.tmp.cleanup()
    def request(self, path, body=None):
        url = path if path.startswith('https://') else self.origin + path
        if urlsplit(url).netloc != urlsplit(self.origin).netloc:
            raise ValueError('Adapter requests must remain on their configured origin')
        cmd = ['curl', '--fail', '--silent', '--show-error', '--location', '--max-redirs', '3', '--max-time', '20', '--max-filesize', '3000000', '--cookie', self.jar, '--cookie-jar', self.jar, '--user-agent', 'CINESHOW-Catalog/0.1']
        if body is not None:
            cmd += ['--data', body]
        result = subprocess.run(cmd + [url], capture_output=True, text=True, timeout=25)
        if result.returncode:
            raise RuntimeError('Source request failed')
        return result.stdout

@dataclass
class Source:
    provider: str
    source_id: str
    page_url: str
    title: str
    kind: str
    year: int = 0
    poster_url: str | None = None
    imdb_id: str | None = None
    modified_at: str | None = None

def parse_cards(markup, provider, origin):
    result = {}
    for block in re.findall(r'<article\b.*?</article>', markup, re.S):
        opening = attrs(block.split('>', 1)[0])
        match = re.search(r'(\d+)$', opening.get('id', ''))
        title_match = re.search(r'<h3[^>]*>\s*<a([^>]*)>(.*?)</a>', block, re.S)
        if not match or not title_match:
            continue
        link = attrs(title_match.group(1)).get('href', '')
        if urlsplit(link).netloc != urlsplit(origin).netloc or not any(p in link for p in ['/filme/', '/serie/']):
            continue
        title = text(title_match.group(2))
        images = re.findall(r'<img\b[^>]*>', block)
        image = attrs(images[0]) if images else {}
        date_match = re.search(r'<span[^>]*>(.*?)</span>', block, re.S)
        years = re.findall(r'\b(?:19|20)\d{2}\b', text(date_match.group(1)) if date_match else '')
        item = Source(provider, match.group(1), link, title, 'series' if '/serie/' in link else 'movie', int(years[-1]) if years else 0, image.get('data-src') or image.get('src'))
        result[item.source_id] = item
    return list(result.values())

class DooplayAdapter:
    def __init__(self, provider, transport=None):
        self.provider = provider
        self.origin = ORIGINS[provider]
        self.transport = transport or Transport(self.origin)
    def close(self):
        self.transport.close()
    def home(self):
        items = parse_cards(self.transport.request('/'), self.provider, self.origin)
        if not items:
            raise ValueError('Catalog structure changed or no cards returned')
        return items
    def search(self, query):
        root = self.transport.request('/')
        config = re.search(r'var dtGonza=(\{.*?\});', root)
        if not config:
            raise ValueError('Search configuration unavailable')
        nonce = json.loads(config.group(1))['nonce']
        data = json.loads(self.transport.request('/wp-json/dooplay/search/?' + urlencode({'keyword': query, 'nonce': nonce})))
        if not isinstance(data, dict) or 'error' in data:
            raise ValueError('Search did not return a catalog')
        result = []
        for ident, record in data.items():
            if not isinstance(record, dict) or not str(ident).isdigit():
                continue
            link = record.get('url', '')
            if urlsplit(link).netloc != urlsplit(self.origin).netloc:
                continue
            year = str(record.get('extra', {}).get('date', ''))
            result.append(Source(self.provider, str(ident), link, record['title'], 'series' if '/serie/' in link else 'movie', int(year) if year.isdigit() else 0, record.get('img')))
        return result
    def detail(self, source):
        markup = self.transport.request(source.page_url)
        imdb = re.search(r'\btt\d{7,10}\b', markup)
        episodes = []
        for link in re.findall(r'href=[\"\x27]([^\"\x27]+)', markup):
            link = html.unescape(link)
            if '/episodio/' not in link or urlsplit(link).netloc != urlsplit(self.origin).netloc:
                continue
            match = re.search(r'-(\d+)x(\d+)/?$', link)
            if match and link not in {e['page_url'] for e in episodes}:
                episodes.append({'id': link, 'title': f'Temporada {match[1]} · Episódio {match[2]}', 'season': int(match[1]), 'number': int(match[2]), 'page_url': link, 'availability': 'listed'})
        players = []
        for tag in re.findall(r'<li\b[^>]*>', markup):
            a = attrs(tag)
            if a.get('data-post') and a.get('data-nume') and a.get('data-type'):
                players.append({'post': a['data-post'], 'type': a['data-type'], 'source': a['data-nume']})
        synopsis = re.search(r'<div[^>]+class=[\"\x27][^\"\x27]*wp-content[^\"\x27]*[\"\x27][^>]*>(.*?)</div>', markup, re.S)
        return {'imdb_id': imdb.group() if imdb else None, 'description': text(synopsis.group(1)) if synopsis else '', 'episodes': episodes, 'players': players}
    def player(self, selection):
        if not re.fullmatch(r'\d+', selection['post']) or not all(re.fullmatch(r'[a-zA-Z0-9-]+', selection[k]) for k in ['type', 'source']):
            raise ValueError('Invalid player identifier')
        data = json.loads(self.transport.request('/wp-json/dooplayer/v2/{post}/{type}/{source}'.format(**selection)))
        if data.get('type') != 'iframe' or urlsplit(data.get('embed_url', '')).scheme != 'https':
            raise ValueError('Unsupported player response')
        return {'kind': 'external', 'url': data['embed_url'], 'availability': 'player_found'}

def parse_chapters(markup):
    chapters = {}
    for tag in re.findall(r'<iframe\b[^>]*>', markup):
        path = attrs(tag).get('src', '')
        match = re.search(r'(?:\?|&)date=(\d{8})(_\d+)?(?:&|$)', path)
        if not match:
            continue
        date, variant = match.group(1), match.group(2) or ''
        iso = f'{date[:4]}-{date[4:6]}-{date[6:]}'
        chapters[date + variant] = {'id': date + variant, 'title': iso + (f' · Variante {variant[1:]}' if variant else ''), 'date': iso, 'variant': variant, 'player_path': path, 'availability': 'player_found'}
    return list(chapters.values())

class XonadosAdapter:
    def __init__(self, transport=None):
        self.transport = transport or Transport(ORIGINS['xonados'])
    def close(self):
        self.transport.close()
    def home(self):
        root = self.transport.request('/')
        scripts = re.findall(r'<script[^>]+src=[\"\x27]([^\"\x27]+)', root)
        path = next((s for s in scripts if '/ast/WTyNK' in s), None)
        if not path:
            raise ValueError('Xonados catalog script unavailable')
        js = self.transport.request(html.unescape(path))
        endpoint = re.search(r"fetch\('([^']*ZXDSX[^']*)'", js)
        if not endpoint:
            raise ValueError('Xonados catalog endpoint unavailable')
        catalog = self.transport.request(endpoint.group(1), '"nuZ", nuZ')
        ids = set(int(v) for v in re.findall(r'data-wheel=[\"\x27](\d+)', catalog))
        if not ids:
            raise ValueError('Xonados returned no cards')
        return [Source('xonados', str(i), ORIGINS['xonados'] + ('/@novela/' + slug + '/' if slug else '/'), name, 'reality' if i == 6 else 'novela') for i, (name, slug) in SHOWS.items() if i in ids]
    def detail(self, source):
        self.transport.request('/')
        self.transport.request('/RTRT', source.source_id)
        selected = self.transport.request('/')
        script = next((html.unescape(v) for v in re.findall(r'<script[^>]+src=[\"\x27]([^\"\x27]+)', selected) if '/ast/YwZ' in v), None)
        if not script:
            raise ValueError('Selected player script unavailable')
        js = self.transport.request(script)
        frame = re.search(r"iframe.src\s*=\s*'([^']+)'", js)
        if not frame:
            raise ValueError('Player frame unavailable')
        chapters = parse_chapters(self.transport.request(html.unescape(frame.group(1))))
        if chapters:
            oldest = min(c['date'].replace('-', '') for c in chapters)
            token = self.transport.request('/G_sTw', '').strip()
            if not re.fullmatch(r'[a-zA-Z0-9]{1,128}', token):
                raise ValueError('Invalid history parameter')
            history = self.transport.request('/Y_sTw?' + urlencode({'y': token, 'zy': source.source_id}), urlencode({'vlum': oldest}))
            chapters += parse_chapters(history)
        return {'description': '', 'episodes': chapters, 'players': []}

def merge(items):
    groups = {}
    for item in items:
        # Unknown years never merge into a known year; kind keeps movies/series apart.
        key = f'{item.kind}:{normalized(item.title)}:{item.year}'
        ident = hashlib.sha256(key.encode()).hexdigest()[:20]
        if ident not in groups:
            groups[ident] = {'id': ident, 'title': item.title, 'kind': item.kind, 'year': item.year, 'poster_url': item.poster_url, 'description': '', 'sources': []}
        entry = groups[ident]
        entry['poster_url'] = entry['poster_url'] or item.poster_url
        if not any(s['provider'] == item.provider and s['source_id'] == item.source_id for s in entry['sources']):
            entry['sources'].append(asdict(item))
    return list(groups.values())
