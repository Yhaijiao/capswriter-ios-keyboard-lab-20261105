import json
from pathlib import Path
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from engine import DemoEngine
from server import make_handler


class BridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), make_handler(DemoEngine(), 'test-pairing-token'))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = 'http://127.0.0.1:' + str(cls.server.server_port)

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join()

    def request(self, path, data=None, token='test-pairing-token', extra=None):
        headers = {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}
        headers.update(extra or {})
        raw = json.dumps(data).encode() if data is not None else None
        req = urllib.request.Request(self.url + path, raw, headers)
        try:
            with urllib.request.urlopen(req, timeout=5) as res:
                return res.status, json.load(res), dict(res.headers)
        except urllib.error.HTTPError as res:
            return res.code, json.load(res), dict(res.headers)

    def test_status_is_versioned_and_no_store(self):
        code, data, headers = self.request('/v1/status')
        self.assertEqual(code, 200)
        self.assertEqual(data['mode'], 'demo-exact-aliases')
        self.assertEqual(headers['Cache-Control'], 'no-store')

    def test_pairing_required(self):
        self.assertEqual(self.request('/v1/status', token='wrong')[0], 401)

    def test_correction_explicit_demo(self):
        code, data, _ = self.request('/v1/correct', {'text': '测试：卡普斯赖特'})
        self.assertEqual(code, 200)
        self.assertEqual(data['text'], '测试：CapsWriter')
        self.assertEqual(data['mode'], 'demo-exact-aliases')

    def test_browser_origin_denied(self):
        self.assertEqual(self.request('/v1/status', extra={'Origin': 'https://example.com'})[0], 403)

    def test_invalid_input(self):
        for value in ({'text': 123}, {'text': 'a' * 2001}, ['hello']):
            self.assertEqual(self.request('/v1/correct', value)[0], 400)

    def test_unknown_endpoint(self):
        self.assertEqual(self.request('/v1/secrets')[0], 404)


if __name__ == '__main__': unittest.main()
