import base64
import json
import struct
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.error import HTTPError

from engine import DemoEngine
from server import make_handler
from voice import VoiceRelay, VoiceError, DesktopASR


class FakeASR:
    def available(self): return True
    def transcribe(self, pcm, task_id):
        self.pcm, self.task_id = pcm, task_id
        return '卡普斯赖特'


class VoiceTests(unittest.TestCase):
    def setUp(self):
        self.now = 100
        self.asr = FakeASR()
        self.relay = VoiceRelay(DemoEngine(), self.asr, clock=lambda: self.now)
        self.agent = 'test-phone-agent-id'
        self.audio = struct.pack('<f', .1) * 4000

    def begin(self):
        self.relay.agent(self.agent)
        job = self.relay.start()
        self.relay.ack(job['id'], self.agent)
        return job['id']

    def payload(self, job_id, audio=None):
        return dict(id=job_id, agent_id=self.agent, encoding='f32le', sample_rate=16000,
                    audio=base64.b64encode(self.audio if audio is None else audio).decode())

    def test_full_record_stop_recognize_correct_consume(self):
        job_id = self.begin()
        self.assertEqual(self.relay.stop(job_id)['state'], 'stopping')
        result = self.relay.upload(self.payload(job_id))
        self.assertEqual(result['state'], 'done')
        self.assertEqual(result['text'], 'CapsWriter')
        self.assertEqual(self.asr.pcm, self.audio)
        self.assertEqual(self.asr.task_id, job_id)
        self.assertEqual(self.relay.consume(job_id)['text'], '')
        with self.assertRaises(VoiceError): self.relay.upload(self.payload(job_id))

    def test_cold_or_dead_agent_cannot_record(self):
        with self.assertRaisesRegex(VoiceError, '主 App'): self.relay.start()
        job_id = self.begin(); self.now += 9
        self.assertEqual(self.relay.result(job_id)['state'], 'error')
        with self.assertRaises(VoiceError): self.relay.upload(self.payload(job_id))

    def test_isolation_and_no_parallel_capture(self):
        job_id = self.begin()
        with self.assertRaises(VoiceError): self.relay.start()
        with self.assertRaises(VoiceError): self.relay.agent('other-phone-agent-id')
        with self.assertRaises(VoiceError): self.relay.ack(job_id, 'wrong')
        with self.assertRaises(VoiceError): self.relay.result('wrong')

    def test_cancel_clears_and_rejects_audio(self):
        job_id = self.begin()
        self.assertEqual(self.relay.cancel(job_id)['text'], '')
        with self.assertRaises(VoiceError): self.relay.upload(self.payload(job_id))
        self.relay.start()

    def test_audio_bounds_finite_encoding(self):
        job_id = self.begin()
        for audio in (b'', b'x', struct.pack('<f', float('nan')) * 4000,
                      struct.pack('<f', 3.0) * 4000):
            with self.assertRaises(VoiceError): self.relay.upload(self.payload(job_id, audio))
        payload = self.payload(job_id); payload['audio'] = 'not-base64'
        with self.assertRaises(VoiceError): self.relay.upload(payload)
        payload = self.payload(job_id); payload['sample_rate'] = 48000
        with self.assertRaises(VoiceError): self.relay.upload(payload)

    def test_expiry_and_agent_closed(self):
        job_id = self.begin(); self.relay.agent(self.agent, False)
        self.assertEqual(self.relay.result(job_id)['state'], 'error')
        self.now += 241
        with self.assertRaises(VoiceError): self.relay.result(job_id)

    def test_stale_recognition_cannot_overwrite_cancellation(self):
        job_id = self.begin()
        def transcribe(pcm, task_id):
            self.relay.cancel(task_id)
            return 'late result'
        self.asr.transcribe = transcribe
        result = self.relay.upload(self.payload(job_id))
        self.assertEqual(result['state'], 'cancelled')
        self.assertEqual(result['text'], '')

    def test_asr_failure_is_recoverable(self):
        job_id = self.begin()
        def fail(*args): raise ConnectionError('private implementation detail')
        self.asr.transcribe = fail
        result = self.relay.upload(self.payload(job_id))
        self.assertEqual(result['state'], 'error')
        self.assertNotIn('private', result['error'])


class VoiceHTTPTests(unittest.TestCase):
    def test_authenticated_phone_to_desktop_roundtrip(self):
        relay = VoiceRelay(DemoEngine(), FakeASR())
        server = ThreadingHTTPServer(('127.0.0.1', 0), make_handler(DemoEngine(), 'test-token', relay))
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        def request(path, value=None, token='test-token'):
            req = Request(f'http://127.0.0.1:{server.server_port}' + path,
                          json.dumps(value).encode() if value is not None else None,
                          {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
            try:
                with urlopen(req, timeout=5) as response: return response.status, json.load(response)
            except HTTPError as response: return response.code, json.load(response)
        try:
            self.assertEqual(request('/v1/voice/start', {}, 'wrong')[0], 401)
            self.assertEqual(request('/v1/voice/agent', {'agent_id': 'http-test-phone-id'})[0], 200)
            code, job = request('/v1/voice/start', {}); self.assertEqual(code, 200)
            job_id = job['id']
            self.assertEqual(request('/v1/voice/ack', {'id': job_id, 'agent_id': 'http-test-phone-id'})[1]['state'], 'recording')
            request('/v1/voice/stop', {'id': job_id})
            result = request('/v1/voice/audio', dict(id=job_id, agent_id='http-test-phone-id',
                sample_rate=16000, encoding='f32le', audio=base64.b64encode(struct.pack('<f', 0) * 4000).decode()))
            self.assertEqual(result[1]['text'], 'CapsWriter')
            self.assertEqual(request('/v1/voice/result?id=' + job_id)[1]['state'], 'done')
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_real_websocket_wire_protocol_with_loopback_fixture(self):
        try:
            from websockets.sync.server import serve
        except ImportError:
            self.skipTest('Install bridge/requirements.txt to check the WebSocket transport')
        seen = {}
        def handler(connection):
            value = json.loads(connection.recv()); seen.update(value)
            connection.send(json.dumps(dict(task_id='unrelated', is_final=True, text='wrong')))
            connection.send(json.dumps(dict(task_id=value['task_id'], is_final=False, text='partial')))
            connection.send(json.dumps(dict(task_id=value['task_id'], is_final=True, text='final result')))
        with serve(handler, '127.0.0.1', 0, subprotocols=['binary']) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            try:
                asr = DesktopASR(server.socket.getsockname()[1])
                pcm = struct.pack('<f', .25) * 4000
                self.assertEqual(asr.transcribe(pcm, 'task-protocol'), 'final result')
                self.assertEqual(base64.b64decode(seen['data']), pcm)
                self.assertEqual(seen['source'], 'mic')
                self.assertTrue(seen['is_final'])
                self.assertEqual(seen['seg_overlap'], 0)
            finally:
                server.shutdown(); thread.join()


if __name__ == '__main__': unittest.main()
