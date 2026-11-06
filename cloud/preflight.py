"""Validate private inputs before starting a Linux ASR service. Never claim live readiness."""
from __future__ import annotations
import argparse
import hashlib
import importlib
import json
import platform
from pathlib import Path
import sys


def sha256(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''): h.update(chunk)
    return h.hexdigest()


def validate_private(root):
    root = Path(root).resolve()
    manifest_path = root / 'private-manifest.json'
    manifest = json.loads(manifest_path.read_text())
    for name, expected in manifest['files'].items():
        original = root / name
        path = original.resolve()
        if not path.is_relative_to(root) or original.is_symlink(): raise ValueError('Unsafe private manifest path')
        if name not in manifest.get('mutable_files', []) and sha256(path) != expected:
            raise ValueError('Private source hash mismatch: ' + name)
    model_root = root / 'models/Qwen3-ASR/Qwen3-ASR-1.7B'
    model_bytes = 0
    for name, spec in manifest['model_files'].items():
        path = (model_root / name).resolve()
        if not path.is_relative_to(model_root.resolve()): raise ValueError('Unsafe model path')
        if path.stat().st_size != spec['size'] or sha256(path) != spec['sha256']:
            raise ValueError('Model hash mismatch: ' + name)
        model_bytes += spec['size']
    return {'private_source_hashes': 'passed', 'model_hashes': 'passed',
            'model_bytes': model_bytes, 'manifest_sha256': sha256(manifest_path),
            'live_asr_test': 'not performed by preflight'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-root', type=Path, required=True)
    parser.add_argument('--load-native', action='store_true')
    args = parser.parse_args()
    if sys.platform != 'linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('This trial kit requires Linux x86_64')
    mem = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
    memory_bytes = int(mem['MemTotal'].split()[0]) * 1024
    if memory_bytes < 7 * 1024**3: raise SystemExit('At least 7GiB visible RAM required for the 8GiB trial target')
    result = validate_private(args.private_root)
    if args.load_native:
        from runtime import configure
        configure(args.private_root)
        for module in ('numpy', 'onnxruntime', 'gguf', 'sherpa_onnx', 'soundfile', 'srt'):
            importlib.import_module(module)
        from core.server.engines.qwen_asr_gguf.asr_engine import QwenASREngine
        result['linux_native_bindings'] = 'imported; model inference still requires the speech probe'
    print(json.dumps(result, indent=2))


if __name__ == '__main__': main()
