"""Synchronize one explicitly selected desktop hot.txt with a paired HTTPS server.

No credential discovery, audio upload, arbitrary server-selected paths or content
logging. State, backups and conflicts are confined to --state-dir.
"""
from __future__ import annotations
import argparse
from contextlib import contextmanager
from dataclasses import dataclass
import hashlib
import ipaddress
import json
import math
import os
from pathlib import Path
import re
import ssl
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
from hotwords import HotwordError, HotwordStore, MAX_HOT_BYTES

REVISION = re.compile(r'[0-9a-f]{64}\Z')


class SyncError(Exception):
    """Only fixed safe codes belong in messages; never remote bodies or words."""
    def __init__(self, code, *, status=None):
        super().__init__(code); self.code = code; self.status = status


def normalized(text):
    return text.replace('\r\n', '\n')


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical_path(value, code):
    path = Path(value).absolute()
    if path.is_symlink() or path.resolve() != path: raise SyncError(code)
    return path


@dataclass(frozen=True)
class HotFile:
    text: str
    revision: str
    writable: bool = False
    raw: bytes | None = None


def hot_file(response):
    if not isinstance(response, dict) or not isinstance(response.get('hotword_files'), list):
        raise SyncError('invalid_remote_response')
    files = [file for file in response['hotword_files'] if isinstance(file, dict) and file.get('id') == 'hot']
    if len(files) != 1: raise SyncError('invalid_remote_response')
    file = files[0]
    text, revision, writable = file.get('text'), file.get('revision'), file.get('writable')
    if not isinstance(text, str) or not isinstance(revision, str) or not REVISION.fullmatch(revision) or not isinstance(writable, bool):
        raise SyncError('invalid_remote_response')
    try: raw = text.encode('utf-8')
    except UnicodeError: raise SyncError('invalid_remote_text')
    if len(raw) > MAX_HOT_BYTES or '\0' in text: raise SyncError('invalid_remote_text')
    return HotFile(normalized(text), revision, writable)


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        # Never forward a bearer token, including to a different origin or a
        # same-origin URL that changes POST into GET. Configure the final URL.
        raise SyncError('remote_redirect_rejected')


class HotwordHTTPClient:
    def __init__(self, endpoint, token_file, *, allow_lan_http=False, timeout=15, expires_at=None):
        if expires_at is not None and (not math.isfinite(expires_at) or expires_at <= 0):
            raise SyncError('invalid_endpoint_expiry')
        parts = urllib.parse.urlsplit(endpoint)
        if parts.scheme not in ('https', 'http') or not parts.hostname or parts.username is not None or parts.password is not None or parts.query or parts.fragment:
            raise SyncError('invalid_endpoint')
        try: parts.port
        except ValueError: raise SyncError('invalid_endpoint')
        if parts.scheme == 'http':
            local = parts.hostname == 'localhost'
            try:
                address = ipaddress.ip_address(parts.hostname)
                local = (address.is_loopback or address.is_private) and not (address.is_unspecified or address.is_multicast or address.is_link_local)
            except ValueError: pass
            if not allow_lan_http or not local: raise SyncError('https_required')
        self.endpoint = urllib.parse.urlunsplit((parts.scheme, parts.netloc, parts.path.rstrip('/'), '', ''))
        try:
            token_bytes = Path(token_file).read_bytes()
            if len(token_bytes) > 4096: raise SyncError('invalid_token_file')
            self.token = token_bytes.decode('utf-8-sig').strip()
        except (OSError, UnicodeError): raise SyncError('token_file_unavailable')
        if len(self.token) < 24 or any(char.isspace() for char in self.token): raise SyncError('invalid_token_file')
        self.timeout = timeout
        self.expires_at = expires_at
        self.opener = urllib.request.build_opener(NoRedirects(), urllib.request.HTTPSHandler(context=ssl.create_default_context()))

    def _request(self, path, value=None):
        if self.expires_at is not None and time.time() >= self.expires_at:
            raise SyncError('temporary_endpoint_expired')
        headers = {'Authorization': 'Bearer ' + self.token, 'Accept': 'application/json'}
        raw = None
        if value is not None:
            headers['Content-Type'] = 'application/json'
            raw = json.dumps(value, ensure_ascii=False).encode('utf-8')
        request = urllib.request.Request(self.endpoint + path, raw, headers)
        try:
            with self.opener.open(request, timeout=self.timeout) as response:
                data = response.read(MAX_HOT_BYTES * 12 + 1)
                if len(data) > MAX_HOT_BYTES * 12: raise SyncError('remote_response_too_large')
                return hot_file(json.loads(data))
        except urllib.error.HTTPError as error:
            # Error bodies can contain user text; intentionally do not read or log them.
            raise SyncError('remote_http_' + str(error.code), status=error.code)
        except (urllib.error.URLError, TimeoutError, ssl.SSLError): raise SyncError('remote_unavailable')
        except (UnicodeError, json.JSONDecodeError): raise SyncError('invalid_remote_response')

    def read(self):
        return self._request('/v1/hotwords')

    def save(self, revision, text):
        result = self._request('/v1/hotwords/save', {'file_id': 'hot', 'revision': revision, 'text': text})
        if result.text != normalized(text): raise SyncError('remote_save_not_confirmed')
        return result


class HotwordSynchronizer:
    def __init__(self, desktop_hot_file, state_dir, remote, *, enable_desktop_save=False, desktop_inplace_save=False):
        self.path = canonical_path(desktop_hot_file, 'linked_desktop_path_rejected')
        if self.path.name != 'hot.txt': raise SyncError('desktop_filename_must_be_hot_txt')
        self.state_dir = canonical_path(state_dir, 'linked_state_path_rejected')
        if self.state_dir == self.path.parent or self.path.parent in self.state_dir.parents:
            raise SyncError('state_directory_must_be_separate')
        self.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.remote = remote
        self.enable_desktop_save = enable_desktop_save
        self.local_store = HotwordStore(self.path.parent, self.state_dir / 'backups', writable=enable_desktop_save, inplace=desktop_inplace_save)
        self.state_file = self.state_dir / 'state.json'
        if self.state_file.is_symlink(): raise SyncError('linked_state_path_rejected')
        binding = str(self.path) + '\0' + remote.endpoint
        self.binding = digest(binding.encode('utf-8'))
        self.step_lock = threading.RLock()

    def _local(self):
        canonical_path(self.path, 'linked_desktop_path_rejected')
        if not self.path.is_file(): raise SyncError('desktop_file_missing')
        raw = self.path.read_bytes()
        if len(raw) > MAX_HOT_BYTES: raise SyncError('desktop_file_too_large')
        try: text = normalized(raw.decode('utf-8-sig'))
        except UnicodeError: raise SyncError('invalid_desktop_text')
        if '\0' in text: raise SyncError('invalid_desktop_text')
        return HotFile(text, digest(raw), self.enable_desktop_save, raw)

    def _state(self):
        if not self.state_file.exists(): return None
        canonical_path(self.state_file, 'linked_state_path_rejected')
        try:
            if self.state_file.stat().st_size > 4096: raise SyncError('invalid_state')
            state = json.loads(self.state_file.read_text(encoding='utf-8'))
        except (UnicodeError, json.JSONDecodeError): raise SyncError('invalid_state')
        if not isinstance(state, dict) or state.get('schema') != 1 or state.get('binding') != self.binding:
            raise SyncError('state_configuration_mismatch')
        for key in ('local_revision', 'remote_revision'):
            if not isinstance(state.get(key), str) or not REVISION.fullmatch(state[key]): raise SyncError('invalid_state')
        return state

    def _baseline(self, local, remote):
        value = {'schema': 1, 'binding': self.binding,
                 'local_revision': local.revision, 'remote_revision': remote.revision}
        temp = None
        try:
            with tempfile.NamedTemporaryFile(dir=self.state_dir, prefix='.state-', delete=False) as stream:
                temp = Path(stream.name)
                stream.write((json.dumps(value, sort_keys=True) + '\n').encode('utf-8'))
                stream.flush(); os.fsync(stream.fileno())
            canonical_path(self.state_file, 'linked_state_path_rejected')
            os.replace(temp, self.state_file)
        finally:
            if temp is not None and temp.exists(): temp.unlink()

    @staticmethod
    def _exclusive_snapshot(path, data):
        if path.is_symlink(): raise SyncError('linked_state_path_rejected')
        try:
            with path.open('xb') as stream: stream.write(data)
        except FileExistsError:
            if path.read_bytes() != data: raise SyncError('conflict_snapshot_collision')

    def _conflict(self, local, remote):
        folder = self.state_dir / 'conflicts' / ('conflict-' + local.revision[:12] + '-' + remote.revision[:12])
        canonical_path(folder, 'linked_state_path_rejected')
        folder.mkdir(parents=True, exist_ok=True, mode=0o700)
        self._exclusive_snapshot(folder / 'desktop.txt', local.raw)
        self._exclusive_snapshot(folder / 'cloud.txt', remote.text.encode('utf-8'))
        metadata = {'local_revision': local.revision, 'remote_revision': remote.revision}
        self._exclusive_snapshot(folder / 'revisions.json', (json.dumps(metadata, sort_keys=True) + '\n').encode('utf-8'))
        return 'conflict'

    def _changed_during_save(self):
        local, remote = self._local(), self.remote.read()
        if local.text == remote.text:
            self._baseline(local, remote)
            return 'aligned'
        return self._conflict(local, remote)

    def step(self):
        with self.step_lock:
            local, remote = self._local(), self.remote.read()
            state = self._state()
            if local.text == remote.text:
                if state is None or local.revision != state['local_revision'] or remote.revision != state['remote_revision']:
                    self._baseline(local, remote)
                    return 'baseline' if state is None else 'aligned'
                return 'unchanged'
            if state is None: return self._conflict(local, remote)
            local_changed = local.revision != state['local_revision']
            remote_changed = remote.revision != state['remote_revision']
            if local_changed and not remote_changed:
                if not remote.writable: raise SyncError('remote_save_disabled')
                try: saved = self.remote.save(remote.revision, local.text)
                except SyncError as error:
                    if error.status == 409: return self._changed_during_save()
                    raise
                # Save the version actually sent, not a later local edit. A new
                # desktop edit during the HTTP request is detected next poll.
                self._baseline(local, saved)
                return 'pushed'
            if remote_changed and not local_changed:
                if not self.enable_desktop_save: raise SyncError('desktop_save_disabled')
                try: result = hot_file(self.local_store.save('hot', local.revision, remote.text))
                except HotwordError as error:
                    if error.status == 409: return self._changed_during_save()
                    raise SyncError('desktop_save_rejected', status=error.status)
                if result.text != remote.text: raise SyncError('desktop_save_not_confirmed')
                self._baseline(result, remote)
                return 'pulled'
            return self._conflict(local, remote)

    @contextmanager
    def process_lock(self):
        path = canonical_path(self.state_dir / 'sync.lock', 'linked_state_path_rejected')
        with path.open('a+b') as stream:
            stream.seek(0, os.SEEK_END)
            if stream.tell() == 0: stream.write(b'\0'); stream.flush()
            stream.seek(0)
            try:
                if os.name == 'nt':
                    import msvcrt
                    msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError: raise SyncError('another_sync_is_running')
            try: yield
            finally:
                if os.name == 'nt':
                    import msvcrt
                    stream.seek(0); msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--endpoint', required=True)
    parser.add_argument('--token-file', type=Path, required=True)
    parser.add_argument('--desktop-hot-file', type=Path, required=True)
    parser.add_argument('--state-dir', type=Path, required=True)
    parser.add_argument('--enable-desktop-save', action='store_true')
    parser.add_argument('--desktop-inplace-save', action='store_true', help='Explicit single-file permission mode: locked write with backup/rollback, instead of directory rename')
    parser.add_argument('--allow-lan-http', action='store_true', help='Explicit private/LAN HTTP test mode only')
    parser.add_argument('--once', action='store_true')
    parser.add_argument('--interval', type=float, default=10)
    parser.add_argument('--expires-at', type=float, help='Unix expiry for a temporary server address; no requests after this time')
    args = parser.parse_args(argv)
    if not 1 <= args.interval <= 3600: parser.error('Interval must be between 1 and 3600 seconds')
    try:
        remote = HotwordHTTPClient(args.endpoint, args.token_file, allow_lan_http=args.allow_lan_http, expires_at=args.expires_at)
        sync = HotwordSynchronizer(args.desktop_hot_file, args.state_dir, remote, enable_desktop_save=args.enable_desktop_save, desktop_inplace_save=args.desktop_inplace_save)
        with sync.process_lock():
            failures, last_status = 0, None
            while True:
                try:
                    status = sync.step(); failures = 0
                    if status != last_status: print('hotword-sync: ' + status, flush=True)
                    last_status = status
                    if args.once: return 2 if status == 'conflict' else 0
                    delay = args.interval
                except (SyncError, OSError) as error:
                    code = error.code if isinstance(error, SyncError) else 'io_failed'
                    if code == 'temporary_endpoint_expired':
                        print('hotword-sync: temporary_endpoint_expired', flush=True)
                        return 0
                    status = 'error:' + code
                    if status != last_status: print('hotword-sync: ' + status, file=sys.stderr, flush=True)
                    last_status = status
                    if args.once: return 1
                    failures = min(failures + 1, 6)
                    delay = max(args.interval, min(60, 2 ** failures))
                time.sleep(delay)
    except SyncError as error:
        print('hotword-sync: error:' + error.code, file=sys.stderr); return 1
    except OSError:
        print('hotword-sync: error:io_failed', file=sys.stderr); return 1
    except KeyboardInterrupt: return 0


if __name__ == '__main__': raise SystemExit(main())
