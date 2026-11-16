#!/usr/bin/env python3
"""Small LAN notes service. Python standard library only."""
import argparse
import json
import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

STATIC = Path(__file__).parent / 'static'
MAX_TEXT = 20000


@contextmanager
def connect(path):
    db = sqlite3.connect(path, timeout=10)
    db.row_factory = sqlite3.Row
    try:
        with db:
            yield db
    finally:
        db.close()


def initialize(path):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with connect(path) as db:
        db.execute('PRAGMA journal_mode=WAL')
        db.execute('''CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            highlighted INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL)''')


def note(row):
    return dict(row) | {'highlighted': bool(row['highlighted'])}


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, fmt, *args):
        # Never log note bodies or request URLs.
        pass

    def reply(self, status, data=None):
        body = b'' if data is None else json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlsplit(self.path)
        if parsed.path == '/api/notes':
            try:
                query = parse_qs(parsed.query)
                limit = int(query.get('limit', ['100'])[0])
                offset = int(query.get('offset', ['0'])[0])
                if not 1 <= limit <= 100 or offset < 0:
                    raise ValueError()
            except ValueError:
                return self.reply(400, {'error': 'Use limit 1–100 and offset 0 or greater.'})
            with connect(self.server.db_path) as db:
                rows = db.execute('SELECT * FROM notes ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?', (limit, offset)).fetchall()
                total = db.execute('SELECT count(*) FROM notes').fetchone()[0]
            return self.reply(200, {'notes': [note(row) for row in rows], 'total': total})
        if parsed.path == '/api/health':
            return self.reply(200, {'status': 'ok'})
        paths = {'/': ('index.html', 'text/html'), '/api-docs': ('api.html', 'text/html'),
                 '/style.css': ('style.css', 'text/css'), '/app.js': ('app.js', 'text/javascript')}
        if parsed.path not in paths:
            return self.reply(404, {'error': 'Not found.'})
        name, mime = paths[parsed.path]
        body = (STATIC / name).read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', mime + '; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
        self.end_headers()
        self.wfile.write(body)

    def mutate(self, method):
        # Reject browser cross-origin mutations; API clients without Origin work normally.
        origin = self.headers.get('Origin')
        if origin and (urlsplit(origin).netloc != self.headers.get('Host') or urlsplit(origin).scheme not in ('http', 'https')):
            self.close_connection = True
            return self.reply(403, {'error': 'Cross-origin writes are not allowed.'})
        if self.headers.get('Sec-Fetch-Site') == 'cross-site':
            self.close_connection = True
            return self.reply(403, {'error': 'Cross-origin writes are not allowed.'})
        try:
            if self.headers.get('Transfer-Encoding'):
                raise ValueError('Transfer encoding is unsupported.')
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 <= length <= 100000:
                self.close_connection = True
                return self.reply(413, {'error': 'Request too large.'})
            raw = self.rfile.read(length)
            if method != 'DELETE':
                if self.headers.get_content_type() != 'application/json':
                    return self.reply(415, {'error': 'Send Content-Type: application/json.'})
                data = json.loads(raw)
                if not isinstance(data, dict):
                    raise ValueError('Expected a JSON object.')
            path = urlsplit(self.path).path
            if method == 'POST' and path == '/api/notes':
                text = data.get('text')
                if not isinstance(text, str) or not text.strip() or len(text) > MAX_TEXT:
                    raise ValueError('Note text must contain 1–20,000 characters, not only whitespace.')
                if set(data) - {'text', 'highlighted'} or type(data.get('highlighted', False)) is not bool:
                    raise ValueError('Use text and an optional highlighted boolean.')
                with connect(self.server.db_path) as db:
                    cur = db.execute('INSERT INTO notes(text,highlighted,created_at) VALUES(?,?,?)',
                                     (text, data.get('highlighted', False), datetime.now(timezone.utc).isoformat(timespec='microseconds')))
                    row = db.execute('SELECT * FROM notes WHERE id=?', (cur.lastrowid,)).fetchone()
                return self.reply(201, note(row))
            parts = path.strip('/').split('/')
            if len(parts) != 3 or parts[:2] != ['api', 'notes'] or not parts[2].isdigit() or len(parts[2]) > 18:
                return self.reply(404, {'error': 'Not found.'})
            ident = int(parts[2])
            with connect(self.server.db_path) as db:
                if method == 'DELETE':
                    count = db.execute('DELETE FROM notes WHERE id=?', (ident,)).rowcount
                    if not count:
                        return self.reply(404, {'error': 'Note not found.'})
                    return self.reply(204)
                if method == 'PATCH':
                    if set(data) != {'highlighted'} or type(data['highlighted']) is not bool:
                        raise ValueError('Send only a highlighted boolean.')
                    count = db.execute('UPDATE notes SET highlighted=? WHERE id=?', (data['highlighted'], ident)).rowcount
                    if not count:
                        return self.reply(404, {'error': 'Note not found.'})
                    row = db.execute('SELECT * FROM notes WHERE id=?', (ident,)).fetchone()
                    return self.reply(200, note(row))
                return self.reply(404, {'error': 'Not found.'})
        except (ValueError, UnicodeError) as exc:
            self.close_connection = True
            self.reply(400, {'error': str(exc)})
        except sqlite3.Error:
            self.reply(503, {'error': 'Storage is temporarily unavailable. Please try again.'})

    def do_POST(self):
        self.mutate('POST')

    def do_PATCH(self):
        self.mutate('PATCH')

    def do_DELETE(self):
        self.mutate('DELETE')

    def setup(self):
        super().setup()
        self.connection.settimeout(15)


def make_server(host, port, db_path):
    initialize(db_path)
    server = ThreadingHTTPServer((host, port), Handler)
    server.db_path = db_path
    return server


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8787)
    parser.add_argument('--db', default=os.environ.get('NOTES_DB', 'notes.sqlite3'))
    args = parser.parse_args()
    make_server(args.host, args.port, args.db).serve_forever()
