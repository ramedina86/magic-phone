import concurrent.futures
import http.client
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from server import make_server


class NotesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = str(Path(self.tmp.name) / 'notes.sqlite3')
        self.start()

    def start(self):
        self.server = make_server('127.0.0.1', 0, self.db)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.tmp.cleanup()

    def request(self, method, path='/api/notes', data=None, headers=None):
        conn = http.client.HTTPConnection(*self.server.server_address)
        body = json.dumps(data) if data is not None else None
        conn.request(method, path, body, headers or {'Content-Type': 'application/json'})
        response = conn.getresponse()
        payload = response.read()
        result = json.loads(payload) if payload else None
        conn.close()
        return response.status, result

    def test_lifecycle_order_and_restart(self):
        _, first = self.request('POST', data={'text': 'First\n<script>alert(1)</script>'})
        status, second = self.request('POST', data={'text': 'Second'})
        self.assertEqual(status, 201)
        self.assertEqual(self.request('GET')[1]['notes'][0]['id'], second['id'])
        status, changed = self.request('PATCH', f"/api/notes/{first['id']}", {'highlighted': True})
        self.assertEqual(status, 200)
        self.assertEqual(changed['created_at'], first['created_at'])
        self.assertTrue(changed['highlighted'])
        self.server.shutdown(); self.server.server_close(); self.thread.join(); self.start()
        self.assertEqual(self.request('GET')[1]['total'], 2)
        self.assertEqual(self.request('GET', '/api/notes?limit=1&offset=1')[1]['notes'][0]['text'], first['text'])
        self.assertEqual(self.request('DELETE', f"/api/notes/{first['id']}")[0], 204)
        self.assertEqual(self.request('DELETE', f"/api/notes/{first['id']}")[0], 404)

    def test_invalid_and_cross_origin(self):
        for data in ({'text': ' '}, {'text': 7}, {'text': 'x'*20001}, {'text': 'ok', 'highlighted': 1}, {'text': 'ok', 'title': 'no'}):
            self.assertEqual(self.request('POST', data=data)[0], 400)
        self.assertEqual(self.request('POST', data={'text': 'ok'}, headers={'Content-Type': 'text/plain'})[0], 415)
        self.assertEqual(self.request('POST', data={'text': 'ok'}, headers={'Content-Type': 'application/json', 'Origin': 'http://elsewhere.test'})[0], 403)
        self.assertEqual(self.request('GET', '/api/notes?limit=0')[0], 400)
        self.assertEqual(self.request('PATCH', '/api/notes/999', {'highlighted': True})[0], 404)
        self.assertEqual(self.request('GET', '/../../etc/passwd')[0], 404)

    def test_concurrent_writes(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda i: self.request('POST', data={'text': f'Note {i}'}), range(20)))
        self.assertTrue(all(status == 201 for status, _ in results))
        self.assertEqual(self.request('GET')[1]['total'], 20)


if __name__ == '__main__':
    unittest.main()
