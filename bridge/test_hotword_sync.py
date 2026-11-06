import contextlib
import hashlib
import io
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys
import tempfile
import threading
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from sync_hotwords import HotFile, HotwordHTTPClient, HotwordSynchronizer, SyncError, main, normalized
from hotwords import HotwordStore
from engine import DemoEngine
from server import make_handler


class FakeRemote:
    endpoint = 'https://hotwords.example.invalid'
    def __init__(self, raw=b'CapsWriter\n'):
        self.raw = raw; self.writable = True; self.before_save = None; self.after_save = None
        self.save_calls = 0

    def read(self):
        return HotFile(normalized(self.raw.decode('utf-8-sig')), hashlib.sha256(self.raw).hexdigest(), self.writable)

    def save(self, revision, text):
        self.save_calls += 1
        if self.before_save: self.before_save()
        if revision != self.read().revision: raise SyncError('remote_http_409', status=409)
        self.raw = normalized(text).encode('utf-8')
        result = self.read()
        if self.after_save: self.after_save()
        return result


class HotwordSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.desktop = self.root / 'desktop'; self.desktop.mkdir()
        self.file = self.desktop / 'hot.txt'; self.file.write_bytes(b'CapsWriter\n')
        self.state = self.root / 'private-state'
        self.remote = FakeRemote()
        self.sync = HotwordSynchronizer(self.file, self.state, self.remote, enable_desktop_save=True)

    def tearDown(self): self.temp.cleanup()
    def baseline(self): self.assertEqual(self.sync.step(), 'baseline')
    def assert_error(self, code, callback):
        with self.assertRaises(SyncError) as error: callback()
        self.assertEqual(error.exception.code, code)

    def test_matching_first_poll_establishes_only_hashes(self):
        self.baseline()
        state = json.loads(self.sync.state_file.read_text())
        self.assertNotIn('CapsWriter', self.sync.state_file.read_text())
        self.assertEqual(state['local_revision'], hashlib.sha256(self.file.read_bytes()).hexdigest())
        self.assertEqual(self.sync.step(), 'unchanged')
        self.assertEqual(self.remote.save_calls, 0)

    def test_initial_mismatch_never_overwrites_either_side(self):
        self.remote.raw = '云端不同\n'.encode()
        self.assertEqual(self.sync.step(), 'conflict')
        self.assertEqual(self.file.read_bytes(), b'CapsWriter\n')
        self.assertEqual(self.remote.raw, '云端不同\n'.encode())
        self.assertFalse(self.sync.state_file.exists())
        self.assertEqual(len(list((self.state / 'conflicts').glob('*/desktop.txt'))), 1)
        self.assertEqual(self.sync.step(), 'conflict')
        self.assertEqual(len(list((self.state / 'conflicts').iterdir())), 1)

    def test_local_only_change_pushes_with_current_remote_revision(self):
        self.baseline(); self.file.write_text('电脑新词\n', encoding='utf-8')
        self.assertEqual(self.sync.step(), 'pushed')
        self.assertEqual(self.remote.read().text, '电脑新词\n')
        self.assertEqual(self.sync.step(), 'unchanged')

    def test_remote_only_change_pulls_and_backs_up_desktop(self):
        self.baseline(); self.remote.raw = '手机新词\n'.encode()
        self.assertEqual(self.sync.step(), 'pulled')
        self.assertEqual(self.file.read_text(encoding='utf-8'), '手机新词\n')
        self.assertEqual(next((self.state / 'backups').glob('hot.*.txt')).read_bytes(), b'CapsWriter\n')
        self.assertEqual(self.sync.step(), 'unchanged')

    def test_desktop_save_requires_explicit_flag(self):
        sync = HotwordSynchronizer(self.file, self.state, self.remote)
        self.assertEqual(sync.step(), 'baseline')
        self.remote.raw = '手机词\n'.encode()
        self.assert_error('desktop_save_disabled', sync.step)
        self.assertEqual(self.file.read_bytes(), b'CapsWriter\n')
        self.assertFalse((self.state / 'backups').exists())

    def test_both_changed_differently_keep_old_baseline_and_private_snapshots(self):
        self.baseline(); previous = self.sync.state_file.read_bytes()
        self.file.write_text('电脑编辑\n', encoding='utf-8'); self.remote.raw = '手机编辑\n'.encode()
        self.assertEqual(self.sync.step(), 'conflict')
        self.assertEqual(self.sync.state_file.read_bytes(), previous)
        folder = next((self.state / 'conflicts').iterdir())
        self.assertEqual((folder / 'desktop.txt').read_bytes(), self.file.read_bytes())
        self.assertEqual((folder / 'cloud.txt').read_text(encoding='utf-8'), '手机编辑\n')

    def test_both_changed_to_same_text_adopt_metadata_without_writes(self):
        self.baseline()
        self.file.write_bytes('相同\r\n'.encode()); self.remote.raw = '相同\n'.encode()
        self.assertEqual(self.sync.step(), 'aligned')
        self.assertEqual(self.remote.save_calls, 0)
        self.assertEqual(self.file.read_bytes(), '相同\r\n'.encode())
        self.assertFalse((self.state / 'backups').exists())

    def test_crlf_and_bom_semantics_do_not_cause_rewrites(self):
        self.file.write_bytes(b'\xef\xbb\xbfCapsWriter\r\n')
        self.baseline()
        self.file.write_bytes(b'CapsWriter\n')
        self.assertEqual(self.sync.step(), 'aligned')
        self.remote.raw = b'CapsWriter\r\n'
        self.assertEqual(self.sync.step(), 'aligned')
        self.assertEqual(self.remote.save_calls, 0)
        self.assertFalse((self.state / 'backups').exists())

    def test_remote_409_captures_conflict_without_retrying_over_new_words(self):
        self.baseline(); previous = self.sync.state_file.read_bytes()
        self.file.write_text('电脑编辑\n', encoding='utf-8')
        self.remote.before_save = lambda: setattr(self.remote, 'raw', '手机抢先编辑\n'.encode())
        self.assertEqual(self.sync.step(), 'conflict')
        self.assertEqual(self.remote.read().text, '手机抢先编辑\n')
        self.assertEqual(self.remote.save_calls, 1)
        self.assertEqual(self.sync.state_file.read_bytes(), previous)

    def test_remote_409_for_identical_concurrent_save_can_align(self):
        self.baseline(); self.file.write_text('双方相同\n', encoding='utf-8')
        self.remote.before_save = lambda: setattr(self.remote, 'raw', '双方相同\n'.encode())
        self.assertEqual(self.sync.step(), 'aligned')
        self.assertFalse((self.state / 'conflicts').exists())

    def test_local_concurrent_edit_during_pull_is_preserved(self):
        self.baseline(); self.remote.raw = '手机编辑\n'.encode()
        self.sync.local_store.validate = lambda _: self.file.write_text('电脑刚编辑\n', encoding='utf-8')
        self.assertEqual(self.sync.step(), 'conflict')
        self.assertEqual(self.file.read_text(encoding='utf-8'), '电脑刚编辑\n')

    def test_new_local_edit_during_push_is_detected_next_poll(self):
        self.baseline(); self.file.write_text('第一版\n', encoding='utf-8')
        self.remote.after_save = lambda: self.file.write_text('第二版\n', encoding='utf-8')
        self.assertEqual(self.sync.step(), 'pushed')
        self.assertEqual(self.remote.read().text, '第一版\n')
        self.remote.after_save = None
        self.assertEqual(self.sync.step(), 'pushed')
        self.assertEqual(self.remote.read().text, '第二版\n')

    def test_state_is_bound_to_configured_local_file_and_endpoint(self):
        self.baseline()
        remote = FakeRemote(); remote.endpoint = 'https://another.example.invalid'
        other = HotwordSynchronizer(self.file, self.state, remote, enable_desktop_save=True)
        self.assert_error('state_configuration_mismatch', other.step)

    def test_other_desktop_file_name_rejected(self):
        self.assert_error('desktop_filename_must_be_hot_txt',
            lambda: HotwordSynchronizer(self.desktop / 'config_client.py', self.state, self.remote))
        self.assert_error('state_directory_must_be_separate',
            lambda: HotwordSynchronizer(self.file, self.desktop / 'state', self.remote))

    def test_bad_state_does_not_get_replaced(self):
        self.sync.state_file.write_text('not-json', encoding='utf-8')
        self.assert_error('invalid_state', self.sync.step)
        self.assertEqual(self.sync.state_file.read_text(), 'not-json')

    def test_process_lock_rejects_second_worker(self):
        other = HotwordSynchronizer(self.file, self.state, self.remote)
        with self.sync.process_lock():
            self.assert_error('another_sync_is_running', lambda: other.process_lock().__enter__())
        with other.process_lock(): pass


@contextlib.contextmanager
def serve(handler):
    server = ThreadingHTTPServer(('127.0.0.1', 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    try: yield 'http://127.0.0.1:' + str(server.server_port)
    finally: server.shutdown(); server.server_close(); thread.join()


class HotwordSyncHTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        self.token = 'test-only-hotword-token-1234567890'
        self.token_file = self.root / 'token.txt'; self.token_file.write_text(self.token)

    def tearDown(self): self.temp.cleanup()

    def test_https_required_and_credential_urls_rejected(self):
        for url in ['http://127.0.0.1:1', 'http://8.8.8.8', 'https://user:secret@example.com',
                    'https://example.com?token=secret', 'https://example.com#secret']:
            with self.assertRaises(SyncError): HotwordHTTPClient(url, self.token_file)
        with self.assertRaises(SyncError): HotwordHTTPClient('http://8.8.8.8', self.token_file, allow_lan_http=True)

    def test_expired_temporary_address_sends_no_request(self):
        class NeverOpen:
            def open(self, *args, **kwargs): raise AssertionError('Expired address contacted')
        client = HotwordHTTPClient('https://192.0.2.1', self.token_file, expires_at=1)
        client.opener = NeverOpen()
        for operation in [client.read, lambda: client.save('0' * 64, 'example')]:
            with self.assertRaises(SyncError) as error: operation()
            self.assertEqual(error.exception.code, 'temporary_endpoint_expired')
        for invalid in [float('nan'), float('inf'), 0, -1]:
            with self.assertRaises(SyncError):
                HotwordHTTPClient('https://192.0.2.1', self.token_file, expires_at=invalid)

    def test_real_backend_get_and_revision_checked_save(self):
        source = self.root / 'server'; source.mkdir(); (source / 'hot.txt').write_text('原词\n', encoding='utf-8')
        store = HotwordStore(source, self.root / 'server-backups', writable=True)
        with serve(make_handler(DemoEngine(), self.token, hotwords=store)) as endpoint:
            client = HotwordHTTPClient(endpoint, self.token_file, allow_lan_http=True)
            original = client.read()
            saved = client.save(original.revision, '新词\n')
            self.assertEqual(saved.text, '新词\n')
            with self.assertRaises(SyncError) as error: client.save(original.revision, '过期版本')
            self.assertEqual(error.exception.status, 409)

    def test_cross_origin_redirect_never_forwards_token(self):
        received = []
        class Sink(BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_GET(self):
                received.append(self.headers.get('Authorization')); self.send_response(200); self.end_headers()
        with serve(Sink) as other:
            class Redirect(BaseHTTPRequestHandler):
                def log_message(self, *_): pass
                def do_GET(self):
                    self.send_response(302); self.send_header('Location', other + '/v1/hotwords'); self.end_headers()
            with serve(Redirect) as endpoint:
                client = HotwordHTTPClient(endpoint, self.token_file, allow_lan_http=True)
                with self.assertRaises(SyncError) as error: client.read()
                self.assertEqual(error.exception.code, 'remote_redirect_rejected')
        self.assertEqual(received, [])

    def test_error_output_contains_no_words_or_credentials(self):
        secret_word = '测试私有词条不能出现在日志'
        token = self.token
        class Failure(BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_GET(self):
                self.send_response(503); self.end_headers(); self.wfile.write((secret_word + token).encode())
        desktop = self.root / 'desktop'; desktop.mkdir(); file = desktop / 'hot.txt'; file.write_text(secret_word, encoding='utf-8')
        out, err = io.StringIO(), io.StringIO()
        with serve(Failure) as endpoint, contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            result = main(['--endpoint', endpoint, '--token-file', str(self.token_file),
                           '--desktop-hot-file', str(file), '--state-dir', str(self.root / 'private-state'),
                           '--allow-lan-http', '--once'])
        self.assertEqual(result, 1)
        self.assertNotIn(token, out.getvalue() + err.getvalue())
        self.assertNotIn(secret_word, out.getvalue() + err.getvalue())
        self.assertIn('remote_http_503', err.getvalue())


if __name__ == '__main__': unittest.main()
