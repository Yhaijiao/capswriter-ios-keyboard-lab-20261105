"""Single-phone, in-memory voice relay. No recordings or transcripts are saved."""
from __future__ import annotations
import array
import base64
from dataclasses import asdict
import json
import math
import secrets
import socket
import sys
import threading
import time

RATE = 16000
MAX_SECONDS = 300
MAX_AUDIO = RATE * MAX_SECONDS * 4
MAX_AUDIO_S16 = RATE * MAX_SECONDS * 2
# A phone on cellular can miss a few heartbeats while recording; keep the job
# alive this long without one. Agent ownership still uses the short window.
HEARTBEAT_GRACE = 20
AGENT_WINDOW = 8
# Upload time for a whole segment once the phone has started sending it.
RECEIVE_SECONDS = 200
ACTIVE_STATES = ('pending', 'recording', 'stopping', 'receiving', 'processing')


class VoiceError(Exception):
    def __init__(self, status, message):
        self.status = status
        super().__init__(message)


class DesktopASR:
    """Use the already running desktop server, including its numeric formatter."""
    def __init__(self, port=6016):
        if not 1 <= port <= 65535:
            raise ValueError('Invalid local ASR port')
        self.port = port

    def available(self):
        try:
            with socket.create_connection(('127.0.0.1', self.port), timeout=.4):
                return True
        except OSError:
            return False

    def transcribe(self, pcm, task_id):
        from websockets.sync.client import connect
        # Feed the same 60s/4s overlapping segmentation used by the desktop mic.
        # Sending all five minutes as one final packet would bypass server
        # segmentation and silently hit the model's per-chunk duration limit.
        packet_size = RATE * 4 * 15
        packets = [pcm[i:i + packet_size] for i in range(0, len(pcm), packet_size)]
        started = time.time()
        deadline = time.monotonic() + 180
        with connect(f'ws://127.0.0.1:{self.port}', proxy=None, open_timeout=5,
                     close_timeout=2, max_size=2**20, subprotocols=['binary']) as connection:
            for index, packet in enumerate(packets):
                request = dict(task_id=task_id, source='mic', data=base64.b64encode(packet).decode('ascii'),
                               is_final=index == len(packets) - 1, time_start=started,
                               seg_duration=60.0, seg_overlap=4.0, context='', language='auto')
                connection.send(json.dumps(request))
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError('Desktop recognition timed out')
                value = json.loads(connection.recv(timeout=remaining))
                if value.get('task_id') == task_id and value.get('is_final'):
                    text = value.get('text')
                    if not isinstance(text, str) or len(text) > 20000:
                        raise ValueError('Invalid desktop recognition result')
                    return text


class VoiceRelay:
    def __init__(self, engine, recognizer, clock=time.monotonic):
        self.engine, self.recognizer, self.clock = engine, recognizer, clock
        self.lock = threading.RLock()
        self.agent_id = None
        self.heartbeat = -float('inf')
        self.job = None

    def _expire(self):
        if self.job is None:
            return
        now = self.clock()
        age = now - self.job['created']
        state = self.job['state']
        # The recording limit counts capture time only; upload and recognition
        # of a full five-minute segment happen after it and have their own limits.
        lost = state in ('pending', 'recording', 'stopping') and now - self.heartbeat > HEARTBEAT_GRACE
        too_long = state in ('pending', 'recording') and age > MAX_SECONDS + 15
        stalled = state == 'receiving' and now - self.job.get('receiving_since', now) > RECEIVE_SECONDS
        if lost or too_long or stalled:
            self.job.update(updated=self.clock(), state='error', error='手机语音会话已断开或录音超时，请回主 App 重新开启。', text='')
            self.job.pop('receiving_since', None)
        if self.job['state'] not in ACTIVE_STATES and now - self.job.get('updated', self.job['created']) > 180:
            self.job = None

    def _public(self):
        self._expire()
        if self.job is None:
            raise VoiceError(404, '录音任务已过期，请重新开始。')
        value = {k: v for k, v in self.job.items() if k not in ('created', 'updated', 'receiving_since')}
        if value['state'] == 'receiving':
            value['state'] = 'processing'  # Clients treat an upload in flight as processing.
        return value

    def _job(self, job_id):
        self._expire()
        if self.job is None or not secrets.compare_digest(str(job_id), self.job['id']):
            raise VoiceError(404, '录音任务已过期，请重新开始。')

    def _agent(self, agent_id):
        if not self.agent_id or not secrets.compare_digest(str(agent_id), self.agent_id):
            raise VoiceError(409, '手机语音会话已更换，请重新开启。')

    def status(self):
        with self.lock:
            self._expire()
            return dict(voice_enabled=True, agent_ready=self.clock() - self.heartbeat <= AGENT_WINDOW,
                        asr_ready=self.recognizer.available(), max_seconds=MAX_SECONDS,
                        phone_asr_v1=True, audio_s16_v1=True)

    def agent(self, agent_id, active=True):
        if not isinstance(agent_id, str) or not 16 <= len(agent_id) <= 80:
            raise VoiceError(400, 'Invalid agent ID')
        with self.lock:
            self._expire()
            if self.agent_id != agent_id and self.clock() - self.heartbeat <= AGENT_WINDOW:
                raise VoiceError(409, '已有另一个手机语音会话，请先关闭。')
            if not active:
                self._agent(agent_id)
                self.heartbeat = -float('inf')
                if self.job and self.job['state'] in ('pending', 'recording', 'stopping', 'receiving'):
                    self.job.update(updated=self.clock(), state='error', error='语音会话已关闭。', text='')
                return dict(state='closed')
            self.agent_id = agent_id
            self.heartbeat = self.clock()
            result = dict(state='idle') if self.job is None else self._public()
            return result

    def start(self):
        with self.lock:
            self._expire()
            if self.clock() - self.heartbeat > AGENT_WINDOW:
                raise VoiceError(409, '请先在 CapsWriter Lab 主 App 开启语音会话。')
            if not self.recognizer.available():
                raise VoiceError(503, '电脑 CapsWriter 识别服务未启动（本机 6016 端口）。')
            if self.job and self.job['state'] in ACTIVE_STATES:
                raise VoiceError(409, '上一段录音仍在处理，请稍后。')
            self.job = dict(id=secrets.token_hex(16), state='pending', text='',
                            error='', created=self.clock(), updated=self.clock(),
                            max_seconds=MAX_SECONDS)
            return self._public()

    def ack(self, job_id, agent_id):
        with self.lock:
            self._agent(agent_id); self._job(job_id)
            if self.job['state'] == 'pending':
                self._set_state('recording')
            return self._public()

    def stop(self, job_id):
        with self.lock:
            self._job(job_id)
            if self.job['state'] == 'recording':
                self._set_state('stopping')
            return self._public()

    def result(self, job_id):
        with self.lock:
            self._job(job_id)
            return self._public()

    def cancel(self, job_id):
        with self.lock:
            self._job(job_id)
            self.job.update(updated=self.clock(), state='cancelled', text='', error='已取消')
            return self._public()

    def consume(self, job_id):
        with self.lock:
            self._job(job_id)
            if self.job['state'] == 'done':
                self.job.update(updated=self.clock(), state='consumed', text='')
            return self._public()

    def upload(self, value):
        """Legacy JSON upload: base64 float32 samples in one request body."""
        job_id, agent_id = value.get('id'), value.get('agent_id')
        with self.lock:
            self._agent(agent_id); self._job(job_id)
            if self.job['state'] not in ('recording', 'stopping'):
                raise VoiceError(409, '录音已结束或取消。')
            if value.get('sample_rate') != RATE or value.get('encoding') != 'f32le':
                raise VoiceError(400, 'Expected mono float32 little-endian audio at 16000Hz')
            encoded = value.get('audio')
            if not isinstance(encoded, str) or len(encoded) > (MAX_AUDIO * 4 // 3 + 8):
                raise VoiceError(413, '录音最长 5 分钟。')
            try:
                pcm = base64.b64decode(encoded, validate=True)
                if not RATE * 4 // 5 <= len(pcm) <= MAX_AUDIO or len(pcm) % 4:
                    raise ValueError('Invalid audio length')
                samples = array.array('f'); samples.frombytes(pcm)
                if sys.byteorder != 'little': samples.byteswap()
                if any(not math.isfinite(v) or abs(v) > 2 for v in samples):
                    raise ValueError('Invalid audio samples')
            except (ValueError, TypeError):
                raise VoiceError(400, '录音不足 0.2 秒或音频格式无效。') from None
            self._set_state('processing')
        return self._recognize(job_id, pcm)

    def begin_receive(self, job_id, agent_id, encoding, sample_rate, length):
        """Called before a binary body is read, so a slow cellular upload is not
        mistaken for a lost phone while heartbeats queue behind it."""
        with self.lock:
            self._agent(agent_id); self._job(job_id)
            if self.job['state'] not in ('recording', 'stopping'):
                raise VoiceError(409, '录音已结束或取消。')
            if sample_rate != RATE or encoding != 's16le':
                raise VoiceError(400, 'Expected mono int16 little-endian audio at 16000Hz')
            if not RATE * 2 // 5 <= length <= MAX_AUDIO_S16 or length % 2:
                raise VoiceError(413 if length > MAX_AUDIO_S16 else 400, '录音不足 0.2 秒或超过 5 分钟。')
            self._set_state('receiving')
            self.job['receiving_since'] = self.clock()

    def abort_receive(self, job_id):
        """The body never fully arrived; let the phone retry the same segment."""
        with self.lock:
            if self.job is None or not secrets.compare_digest(str(job_id), self.job['id']):
                return
            if self.job['state'] == 'receiving':
                self._set_state('stopping')
                self.job.pop('receiving_since', None)
                self.heartbeat = max(self.heartbeat, self.clock())

    def upload_pcm(self, job_id, agent_id, pcm):
        """Binary upload body after begin_receive: raw int16 little-endian."""
        with self.lock:
            self._agent(agent_id); self._job(job_id)
            if self.job['state'] != 'receiving':
                raise VoiceError(409, '录音已结束或取消。')
            if not RATE * 2 // 5 <= len(pcm) <= MAX_AUDIO_S16 or len(pcm) % 2:
                self._set_state('stopping'); self.job.pop('receiving_since', None)
                raise VoiceError(400, '录音不足 0.2 秒或音频格式无效。')
            self._set_state('processing'); self.job.pop('receiving_since', None)
        samples = array.array('h'); samples.frombytes(pcm)
        if sys.byteorder != 'little': samples.byteswap()
        floats = array.array('f', [v / 32768.0 for v in samples])
        if sys.byteorder != 'little': floats.byteswap()
        return self._recognize(job_id, floats.tobytes())

    def _set_state(self, state):
        self.job['state'] = state
        self.job['updated'] = self.clock()

    def _recognize(self, job_id, pcm):
        try:
            raw = self.recognizer.transcribe(pcm, job_id)
            corrected = asdict(self.engine.correct(raw))
            with self.lock:
                self._job(job_id)
                if self.job['state'] == 'processing':
                    self.job.update(corrected, error='')
                    self._set_state('done')
                return self._public()
        except VoiceError:
            raise
        except Exception:
            with self.lock:
                self._job(job_id)
                if self.job['state'] == 'processing':
                    self.job.update(error='电脑识别失败，请检查 CapsWriter 服务后重试。', text='')
                    self._set_state('error')
                return self._public()

    def upload_text(self, value):
        """A paired microphone agent submits its on-device final transcript."""
        job_id = value.get('id')
        with self.lock:
            self._agent(value.get('agent_id')); self._job(job_id)
            if self.job['state'] not in ('recording', 'stopping'):
                raise VoiceError(409, '录音已结束或取消。')
            text = value.get('text')
            if not isinstance(text, str) or not text.strip() or len(text) > 20000:
                raise VoiceError(400, '本地识别没有有效文字，或文字过长，请重新录音。')
            self._set_state('processing')
        try:
            corrected = asdict(self.engine.correct(text))
            with self.lock:
                self._job(job_id)
                if self.job['state'] == 'processing':
                    self.job.update(corrected, updated=self.clock(), state='done', error='')
                return self._public()
        except VoiceError:
            raise
        except Exception:
            with self.lock:
                self._job(job_id)
                if self.job['state'] == 'processing':
                    self.job.update(updated=self.clock(), state='error', text='', error='热词纠错失败，请检查识别服务。')
                return self._public()
