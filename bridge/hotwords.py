"""Versioned access to explicitly configured hotword files.

Only hot.txt is writable, and only when the local operator enables it. Backups
and temporary files stay in the configured private state directory.
"""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import tempfile
import threading

FILES = {'hot': 'hot.txt', 'aliases': 'hot-personal-aliases.txt',
         'auto': 'auto-hotwords/hot-auto.txt', 'rule': 'hot-rule.txt',
         'asr': 'hot-server.txt'}
MAX_HOT_BYTES = 256 * 1024


class HotwordError(ValueError):
    def __init__(self, status, message):
        super().__init__(message); self.status = status


class HotwordStore:
    def __init__(self, source_root, state_root, *, writable=False, validate=None):
        self.source_root = Path(source_root).resolve()
        self.state_root = Path(state_root).resolve()
        self.writable = writable
        self.validate = validate
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
                                  writable=self.writable and file_id == 'hot'))
            return dict(hotword_files=files)

    def save(self, file_id, revision, text):
        if not self.writable or file_id != 'hot':
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
                try: self.validate(raw.decode('utf-8'))
                except Exception: raise HotwordError(400, '热词格式无法加载，请检查后重试。')
            # Re-check after validation, which may take time on a large lexicon.
            if self._read(file_id)[3] != current:
                raise HotwordError(409, '词库已在其他位置修改，请重新加载后再保存。')
            if old != raw:
                self.state_root.mkdir(parents=True, exist_ok=True)
                backup = self.state_root / ('hot.' + current + '.txt')
                try:
                    with backup.open('xb') as stream: stream.write(old)
                except FileExistsError:
                    if backup.read_bytes() != old: raise HotwordError(500, 'Backup conflict; original preserved')
                temp = None
                try:
                    with tempfile.NamedTemporaryFile(dir=self.state_root, prefix='hot-save-', delete=False) as stream:
                        temp = Path(stream.name); stream.write(raw); stream.flush(); os.fsync(stream.fileno())
                    os.replace(temp, target)
                finally:
                    if temp is not None and temp.exists(): temp.unlink()
            return self.read()
