"""Build a bounded offline lexicon from public MIT-licensed jieba+pypinyin data.

Never reads desktop hotwords. Inputs are explicit public-package paths.
"""
import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import re
import sys

from pypinyin import Style, lazy_pinyin, pinyin

SEEDS = {
    'nihao': ['你好'], 'xiexie': ['谢谢'], 'zaijian': ['再见'], 'shijie': ['世界'],
    'wo': ['我'], 'ni': ['你'], 'hao': ['好'], 'de': ['的'], 'shi': ['是'],
    'ceshi': ['测试'], 'zhongwen': ['中文'], 'shuru': ['输入'], 'shouji': ['手机'],
    'jintian': ['今天'], 'mingtian': ['明天'], 'women': ['我们'], 'nihaoma': ['你好吗'],
    'xianzai': ['现在'], 'keyi': ['可以'], 'zhongguo': ['中国'],
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dictionary', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    rows = []
    source = args.dictionary.read_bytes()
    for line in source.decode('utf-8').splitlines():
        parts = line.split()
        if len(parts) >= 2 and re.fullmatch(r'[\u4e00-\u9fff]{1,6}', parts[0]):
            rows.append((parts[0], int(parts[1])))
    rows.sort(key=lambda row: (-row[1], row[0]))
    selected = dict(rows[:24000])
    selected.update((word, freq) for word, freq in rows if len(word) == 1)
    result = defaultdict(list)
    for key, words in SEEDS.items(): result[key].extend(words)
    for word, freq in sorted(selected.items(), key=lambda row: (-row[1], row[0])):
        readings = (pinyin(word, style=Style.NORMAL, heteronym=True)[0] if len(word) == 1
                    else [''.join(lazy_pinyin(word, style=Style.NORMAL))])
        for reading in readings:
            key = reading.replace('ü', 'v').lower()
            if re.fullmatch('[a-z]{1,32}', key) and word not in result[key] and len(result[key]) < 40:
                result[key].append(word)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    frequencies = dict(rows)
    # Jieba's tokenizer dictionary omits productive phrases such as 我妈 / 我买.
    # Add a small public starter vocabulary; this is not personal word learning.
    common = {}
    for prefix in ['我', '你', '他', '她']:
        for suffix in ['妈', '爸', '哥', '姐', '妹', '弟', '家', '想', '要', '有', '没', '买', '卖', '会', '能', '不', '是', '说', '在', '的']:
            word = prefix + suffix
            spelling = ''.join(lazy_pinyin(word, style=Style.NORMAL)).replace('ü', 'v')
            common[word] = max(1, int(min(frequencies.get(prefix, 1), frequencies.get(suffix, 1)) * 0.35))
            if word not in result[spelling] and len(result[spelling]) < 40: result[spelling].append(word)
    total = sum(frequencies.values())
    seeds = {word for words in SEEDS.values() for word in words}
    costs = {}
    for spelling, words in result.items():
        scored = []
        for word in words:
            frequency = max(frequencies.get(word, 1), common.get(word, 1), 100000 if word in seeds else 1)
            reading_rank = 0
            if len(word) == 1:
                readings = [reading.replace('ü', 'v') for reading in pinyin(word, style=Style.NORMAL, heteronym=True)[0]]
                if spelling in readings: reading_rank = readings.index(spelling)
            cost = round(math.log(total / frequency) + reading_rank * 2.5, 4)
            seed_order = SEEDS.get(spelling, []).index(word) if word in SEEDS.get(spelling, []) else 1000
            scored.append((seed_order, cost, word))
        scored.sort()
        result[spelling] = [word for _, _, word in scored]
        costs[spelling] = [cost for _, cost, _ in scored]
    args.output.write_text(json.dumps(dict(sorted(result.items())), ensure_ascii=False,
                                      separators=(',', ':')), encoding='utf-8')
    costs_output = args.output.with_name('pinyin-costs.json')
    costs_output.write_text(json.dumps(dict(sorted(costs.items())), ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    print(json.dumps({'pinyin_keys': len(result), 'word_entries': sum(map(len, result.values())),
                      'output_bytes': args.output.stat().st_size,
                      'jieba_dict_sha256': hashlib.sha256(source).hexdigest()}, indent=2))


if __name__ == '__main__': main()
