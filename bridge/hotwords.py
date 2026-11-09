"""Versioned access to explicitly configured hotword files.

Only the personal files (hot.txt, personal aliases and replacement rules) are
writable, and only when the local operator enables it. Backups and temporary
files stay in the configured private state directory.
"""
from __future__ import annotations
from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import tempfile
import threading

FILES = {'hot': 'hot.txt', 'aliases': 'hot-personal-aliases.txt',
         'auto': 'auto-hotwords/hot-auto.txt', 'rule': 'hot-rule.txt',
         'asr': 'hot-server.txt'}
# Files the owner edits by hand. hot-auto is generated and hot-server only
# takes effect after a server restart, so both stay read-only.
WRITABLE = ('hot', 'aliases', 'rule')
MAX_HOT_BYTES = 256 * 1024


class HotwordError(ValueError):
    def __init__(self, status, message):
        super().__init__(message); self.status = status


class HotwordStore:
    def __init__(self, source_root, state_root, *, writable=False, validate=None, inplace=False):
        self.source_root = Path(source_root).resolve()
        self.state_root = Path(state_root).resolve()
        self.writable = writable
        self.validate = validate
        self.inplace = inplace
        self.lock = threading.RLock()

    def _path(self, file_id):
        if file_id not in FILES: raise HotwordError(400, 'Unknown hotword file')
        path = self.source_root / FILES[file_id]
        if path.is_symlink() or path.resolve() != path:
            raise HotwordError(400, 'Linked hotword paths are not supported')
        return path

    def _read(self, file_id):
        path = self._path(file_id)
        raw = path.read_bytes() if path.exists() else b''
        if len(raw) > MAX_HOT_BYTES: raise HotwordError(413, 'Hotword file exceeds 256 KiB')
        text = raw.decode('utf-8-sig').replace('\r\n', '\n')
        return path, raw, text, hashlib.sha256(raw).hexdigest()

    def read(self):
        with self.lock:
            files = []
            for file_id, name in FILES.items():
                _, _, text, revision = self._read(file_id)
                files.append(dict(id=file_id, name=name, text=text, revision=revision,
                                  writable=self.writable and file_id in WRITABLE))
            return dict(hotword_files=files)

    def save(self, file_id, revision, text):
        if not self.writable or file_id not in WRITABLE:
            raise HotwordError(403, '这份词库尚未启用手机写回；当前可查看。')
        if not isinstance(text, str) or '\0' in text:
            raise HotwordError(400, 'Invalid hotword text')
        try: raw = text.replace('\r\n', '\n').encode('utf-8')
        except UnicodeError: raise HotwordError(400, 'Invalid UTF-8 hotword text')
        if len(raw) > MAX_HOT_BYTES: raise HotwordError(413, 'Hotword file exceeds 256 KiB')
        with self.lock:
            target, old, old_text, current = self._read(file_id)
            if revision != current:
                raise HotwordError(409, '词库已在其他位置修改，请重新加载后再保存。')
            if raw.decode('utf-8') == old_text:
                return self.read()
            if self.validate:
                try: self.validate(raw.decode('utf-8'), file_id)
                except Exception: raise HotwordError(400, '热词格式无法加载，请检查后重试。')
            # Re-check after validation, which may take time on a large lexicon.
            if self._read(file_id)[3] != current:
                raise HotwordError(409, '词库已在其他位置修改，请重新加载后再保存。')
            if old != raw:
                self.state_root.mkdir(parents=True, exist_ok=True)
                backup = self.state_root / (file_id + '.' + current + '.txt')
                try:
                    with backup.open('xb') as stream: stream.write(old)
                except FileExistsError:
                    if backup.read_bytes() != old: raise HotwordError(500, 'Backup conflict; original preserved')
                if self.inplace:
                    self._save_existing_file(target, current, old, raw)
                    return self.read()
                temp = None
                try:
                    with tempfile.NamedTemporaryFile(dir=self.state_root, prefix='hot-save-', delete=False) as stream:
                        temp = Path(stream.name); stream.write(raw); stream.flush(); os.fsync(stream.fileno())
                    os.replace(temp, target)
                finally:
                    if temp is not None and temp.exists(): temp.unlink()
            return self.read()

    def _save_existing_file(self, target, revision, old, raw):
        # Explicit single-file permission mode. Creates nothing in the source
        # directory; preserves the existing file and its ACL. Cloud/default saves
        # continue to use atomic replacement instead.
        with target.open('r+b') as stream, self._file_lock(stream, max(len(old), len(raw), 1)):
            if hashlib.sha256(stream.read()).hexdigest() != revision:
                raise HotwordError(409, '词库已在其他位置修改，请重新加载后再保存。')
            try:
                stream.seek(0); stream.write(raw); stream.truncate(); stream.flush(); os.fsync(stream.fileno())
            except OSError:
                # The content-addressed original backup already exists, even if
                # the device also fails while attempting this immediate rollback.
                stream.seek(0); stream.write(old); stream.truncate(); stream.flush(); os.fsync(stream.fileno())
                raise

    @staticmethod
    @contextmanager
    def _file_lock(stream, length):
        stream.seek(0)
        if os.name == 'nt':
            import msvcrt
            msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, length)
            try: yield
            finally:
                stream.seek(0); msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, length)
        else:
            import fcntl
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            try: yield
            finally: fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
