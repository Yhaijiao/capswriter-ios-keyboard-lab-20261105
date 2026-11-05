"""Test the real installed correction engine over the same HTTP API as iPhone.

Only synthetic input is submitted; no private vocabulary text is printed/saved.
Run with PYTHONPATH pointing to bridge/ and the private pip target folder.
"""
import argparse
from dataclasses import asdict
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import sys
import threading
import urllib.request

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
from engine import DesktopEngine
from server import make_handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--desktop', required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    engine = DesktopEngine(args.desktop)
    token = secrets.token_urlsafe(24)
    server = ThreadingHTTPServer(('127.0.0.1', 0), make_handler(engine, token))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    cases = ['测试热词：卡普斯赖特', '这是一个很长的普通中文测试句子，验证末尾标点是否按语义长度保留。',
             'Hello world.', '一、测试列表。', '请输出 iPhone 15 Pro Max。', '', 'A😀中英混合']
    results = []
    try:
        for index, text in enumerate(cases):
            direct = asdict(engine.correct(text))
            request = urllib.request.Request(f'http://127.0.0.1:{server.server_port}/v1/correct',
                json.dumps({'text': text}).encode(), {'Content-Type': 'application/json',
                'Authorization': 'Bearer ' + token})
            with urllib.request.urlopen(request, timeout=15) as response:
                transported = json.load(response)
            assert transported == direct, f'Transport mismatch on synthetic case {index}'
            results.append({'synthetic_case': index + 1, 'http_matches_direct_engine': True})
    finally:
        server.shutdown(); server.server_close(); thread.join()
    report = {'result': 'passed', 'scope': 'installed desktop hotword/rule source over HTTP; not ASR/iPhone',
              'status': engine.status(), 'cases': results,
              'source_directory_writes': 'none by adapter design',
              'physical_iphone': 'not tested', 'automatic_resigning': 'not tested'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__': main()
