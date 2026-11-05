"""Explicitly started, authenticated LAN text-test bridge. No audio or persistence."""
from __future__ import annotations
import argparse
from dataclasses import asdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hmac
import ipaddress
import json
from pathlib import Path
import secrets
import socket
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from engine import DemoEngine, DesktopEngine

MAX_BODY = 32768
MAX_TEXT = 2000


def make_handler(engine, token):
    class Handler(BaseHTTPRequestHandler):
        server_version = 'CapsWriterLab/0.1'
        def log_message(self, *args):
            pass  # Never log user text, bearer tokens or request bodies.

        def reply(self, status, value):
            data = json.dumps(value, ensure_ascii=False).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.end_headers()
            self.wfile.write(data)

        def authorized(self):
            try:
                remote = ipaddress.ip_address(self.client_address[0])
                if not (remote.is_private or remote.is_loopback):
                    self.reply(403, {'error': 'LAN only'}); return False
            except ValueError:
                self.reply(403, {'error': 'LAN only'}); return False
            if self.headers.get('Origin') or self.headers.get('Transfer-Encoding'):
                self.reply(403, {'error': 'Browser and chunked requests are not supported'}); return False
            actual = self.headers.get('Authorization', '')
            if not hmac.compare_digest(actual.encode(), ('Bearer ' + token).encode()):
                self.reply(401, {'error': 'Pairing token required'}); return False
            return True

        def do_GET(self):
            if not self.authorized(): return
            if self.path != '/v1/status': self.reply(404, {'error': 'Not found'}); return
            try: self.reply(200, engine.status())
            except Exception: self.reply(503, {'error': 'Desktop sources are updating or unavailable; retry'})

        def do_POST(self):
            if not self.authorized(): return
            if self.path != '/v1/correct': self.reply(404, {'error': 'Not found'}); return
            if self.headers.get('Content-Type', '').split(';')[0].strip().lower() != 'application/json':
                self.reply(415, {'error': 'JSON required'}); return
            try: length = int(self.headers.get('Content-Length', '-1'))
            except ValueError: length = -1
            if not 0 < length <= MAX_BODY:
                self.reply(413, {'error': 'Body length limit exceeded'}); return
            self.connection.settimeout(10)
            try:
                raw = self.rfile.read(length)
                if len(raw) != length: raise ValueError('Incomplete body')
                value = json.loads(raw)
                text = value.get('text') if isinstance(value, dict) else None
                if not isinstance(text, str) or len(text) > MAX_TEXT:
                    raise ValueError('Text must contain at most 2000 characters')
            except (ValueError, UnicodeError, TimeoutError):
                self.reply(400, {'error': 'Invalid JSON or text'}); return
            try: self.reply(200, asdict(engine.correct(text)))
            except Exception: self.reply(503, {'error': 'Desktop correction unavailable; check local console'})
    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--desktop', type=Path, help='Read-only path to CapsWriter-v3')
    parser.add_argument('--demo', action='store_true')
    parser.add_argument('--host', default='127.0.0.1', help='Use your LAN IP explicitly to allow the phone')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--token-file', type=Path, help='Optional token file inside your private project folder')
    args = parser.parse_args()
    if bool(args.desktop) == bool(args.demo): parser.error('Choose exactly one of --desktop or --demo')
    ip = ipaddress.ip_address(args.host)
    if not (ip.is_loopback or ip.is_private) or ip.is_unspecified:
        parser.error('Bind to a specific LAN or loopback IP, never 0.0.0.0/public IP')
    engine = DemoEngine() if args.demo else DesktopEngine(args.desktop)
    token = secrets.token_urlsafe(24)
    if args.token_file:
        if args.token_file.exists():
            token = args.token_file.read_text(encoding='utf-8').strip()
            if len(token) < 24: parser.error('Stored token is too short')
        else:
            args.token_file.parent.mkdir(parents=True, exist_ok=True)
            args.token_file.write_text(token, encoding='utf-8')
    server = ThreadingHTTPServer((args.host, args.port), make_handler(engine, token))
    server.daemon_threads = True
    print(f'CapsWriter Lab text bridge: http://{args.host}:{args.port}', flush=True)
    print(f'Pairing token (keep local): {token}', flush=True)
    print(json.dumps(engine.status(), ensure_ascii=False), flush=True)
    print('No audio recognition. No text is saved. Ctrl+C stops the server.', flush=True)
    try: server.serve_forever(poll_interval=.5)
    except KeyboardInterrupt: pass
    finally: server.server_close()


if __name__ == '__main__': main()
