"""CINESHOW metadata API: python -m backend.server (port 8080)."""
import json, os, sqlite3, threading, time
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs
from backend.catalog import DooplayAdapter, XonadosAdapter, Source, merge
DB = os.environ.get('CINESHOW_DB', 'catalog.sqlite3')
LOCK = threading.Lock()

def connection():
    db = sqlite3.connect(DB, timeout=30)
    db.execute('CREATE TABLE IF NOT EXISTS snapshots(provider TEXT PRIMARY KEY, payload TEXT, updated REAL)')
    db.execute('CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY AUTOINCREMENT, provider TEXT, source_id TEXT, title TEXT, created REAL)')
    return db

def adapter(provider):
    return XonadosAdapter() if provider == 'xonados' else DooplayAdapter(provider)

def sync_one(provider):
    from dataclasses import asdict
    a = adapter(provider)
    try:
        items = a.home()
        with connection() as db:
            old = db.execute('SELECT payload FROM snapshots WHERE provider=?', (provider,)).fetchone()
            if old:
                old_ids = {s['source_id'] for s in json.loads(old[0])}
                for item in items:
                    if item.source_id not in old_ids:
                        db.execute('INSERT INTO events(provider,source_id,title,created) VALUES(?,?,?,?)', (provider,item.source_id,item.title,time.time()))
            db.execute('INSERT OR REPLACE INTO snapshots VALUES(?,?,?)', (provider,json.dumps([asdict(i) for i in items]),time.time()))
        return provider, None
    except Exception as e:
        return provider, type(e).__name__
    finally:
        a.close()

def sync_loop():
    while True:
        with LOCK, ThreadPoolExecutor(max_workers=3) as pool:
            for provider, error in pool.map(sync_one, ['rtfilmes','tontons','xonados']):
                if error: print('Keeping last catalog for', provider, error, flush=True)
        time.sleep(max(300,int(os.environ.get('SYNC_SECONDS','600'))))

def catalog():
    items=[]; statuses=[]
    with connection() as db:
        for p,payload,updated in db.execute('SELECT * FROM snapshots'):
            items += [Source(**i) for i in json.loads(payload)]
            statuses.append({'provider':p,'updated_at':updated,'stale':time.time()-updated>1800})
    return {'items':merge(items),'sources':statuses}

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        route = urlsplit(self.path); q=parse_qs(route.query)
        try:
            if route.path == '/health': data={'ok':True}
            elif route.path == '/v1/catalog': data=catalog()
            elif route.path == '/v1/search':
                term=q.get('q',[''])[0][:100].strip()
                if len(term)<2: data={'items':[]}
                else:
                    def search(p):
                        a=adapter(p)
                        try:return a.search(term)
                        except Exception:return []
                        finally:a.close()
                    with ThreadPoolExecutor(max_workers=2) as pool:
                        items=sum(pool.map(search,['rtfilmes','tontons']),[])
                    data={'items':merge(items)}
            elif route.path == '/v1/events':
                since=max(0,int(q.get('after',['0'])[0]))
                with connection() as db:
                    rows=db.execute('SELECT * FROM events WHERE id>? ORDER BY id LIMIT 100',(since,)).fetchall()
                data={'events':[dict(zip(['id','provider','source_id','title','created'],r)) for r in rows]}
            elif route.path == '/v1/details':
                p=q.get('provider',[''])[0]; ident=q.get('id',[''])[0]
                rows=catalog()['items']; s=next(s for i in rows for s in i['sources'] if s['provider']==p and s['source_id']==ident)
                a=adapter(p)
                try:data=a.detail(Source(**s))
                finally:a.close()
            else:self.send_error(404);return
            body=json.dumps(data,ensure_ascii=False).encode()
            self.send_response(200);self.send_header('Content-Type','application/json; charset=utf-8');self.send_header('Content-Length',str(len(body)));self.send_header('Cache-Control','max-age=60');self.end_headers();self.wfile.write(body)
        except (ValueError,StopIteration):self.send_error(400,'Invalid request')
        except Exception:self.send_error(502,'Source temporarily unavailable')

if __name__=='__main__':
    connection().close()
    threading.Thread(target=sync_loop,daemon=True).start()
    ThreadingHTTPServer(('0.0.0.0',int(os.environ.get('PORT','8080'))),Handler).serve_forever()
