"""Run real synthetic speech through the ASR before publishing its readiness marker."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import uuid

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
from voice import DesktopASR
from preflight import sha256


def probe(private_root, ready_file):
    ready = Path(ready_file)
    ready.parent.mkdir(parents=True, exist_ok=True)
    if ready.exists(): ready.unlink()
    recognizer = DesktopASR(6016)
    deadline = time.monotonic() + 180
    while not recognizer.available():
        if time.monotonic() >= deadline: raise RuntimeError('ASR socket did not start')
        time.sleep(.5)
    with tempfile.TemporaryDirectory(prefix='synthetic-probe-', dir=ready.parent) as folder:
        wav = Path(folder) / 'probe.wav'; pcm = Path(folder) / 'probe.f32'
        subprocess.run(['espeak-ng', '-s', '130', '-w', str(wav), 'Hello keyboard test.'], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['ffmpeg', '-v', 'error', '-i', str(wav), '-ar', '16000', '-ac', '1',
                        '-f', 'f32le', str(pcm)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        text = recognizer.transcribe(pcm.read_bytes(), 'health-' + uuid.uuid4().hex)
        words = set(re.findall('[a-z]+', text.lower()))
        if len(words & {'hello', 'keyboard', 'test'}) < 2:
            raise RuntimeError('Synthetic speech recognition check did not meet its acceptance criterion')
    # No transcript, audio, or credentials are saved in this marker.
    ready.write_text(json.dumps({'synthetic_speech_probe': 'passed',
        'manifest_sha256': sha256(Path(private_root) / 'private-manifest.json'),
        'validated_at_unix': time.time()}))
    print('ASR synthetic speech probe passed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-root', type=Path, required=True)
    parser.add_argument('--ready-file', type=Path, default=Path('/run/capswriter/asr-ready.json'))
    args = parser.parse_args()
    try: probe(args.private_root, args.ready_file)
    except Exception:
        print('ASR readiness probe failed; gateway must remain unready', file=sys.stderr)
        raise SystemExit(1)
