"""Public HTTPS terminates at nginx; this gateway binds loopback only."""
from __future__ import annotations
import argparse
from http.server import ThreadingHTTPServer
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
from engine import DesktopEngine
from server import make_handler
from voice import DesktopASR, VoiceRelay


class ValidatedASR(DesktopASR):
    def __init__(self, ready_file):
        super().__init__(6016); self.ready_file = Path(ready_file)

    def available(self): return self.ready_file.is_file() and super().available()


def with_activity(handler, path):
    """Record only the time of the last POST (no content) for the idle auto-stop."""
    path = Path(path)

    class ActivityHandler(handler):
        def do_POST(self):
            try: path.touch()
            except OSError: pass
            return super().do_POST()

    return ActivityHandler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-root', type=Path, required=True)
    parser.add_argument('--token-file', type=Path, required=True)
    parser.add_argument('--ready-file', type=Path, default=Path('/run/capswriter/asr-ready.json'))
    parser.add_argument('--hotwords-state', type=Path, required=True)
    parser.add_argument('--enable-hotword-save', action='store_true')
    parser.add_argument('--activity-file', type=Path,
                        help='touched on every POST; idle_stop.sh powers off when it goes stale')
    args = parser.parse_args()
    token = args.token_file.read_text().strip()
    if len(token) < 24: raise SystemExit('Pairing token must contain at least 24 characters')
    engine = DesktopEngine(args.private_root)
    relay = VoiceRelay(engine, ValidatedASR(args.ready_file))
    from hotwords import HotwordStore
    hotwords = HotwordStore(args.private_root, args.hotwords_state,
                           writable=args.enable_hotword_save, validate=engine.validate_hotwords)
    handler = make_handler(engine, token, relay, hotwords)
    if args.activity_file:
        handler = with_activity(handler, args.activity_file)
    server = ThreadingHTTPServer(('127.0.0.1', 8765), handler)
    server.daemon_threads = True
    try: server.serve_forever(poll_interval=.5)
    finally: server.server_close()


if __name__ == '__main__': main()
