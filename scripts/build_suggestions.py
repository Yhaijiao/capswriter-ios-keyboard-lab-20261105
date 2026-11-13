"""Build the bundled next-word suggestion tables from public n-gram counts.

Never reads desktop hotwords or anything the user typed. Inputs are explicit
paths to public data:

Chinese: Google Books Ngram Viewer exports, version 20200217, corpus chi_sim
(CC BY 3.0). First reduce the raw shards to "ngram<TAB>count" with this
script's --aggregate mode, for example:

    curl -s https://storage.googleapis.com/books/ngrams/books/20200217/chi_sim/1-00000-of-00001.gz \
        | zcat | python3 scripts/build_suggestions.py --aggregate 1 > zh1.tsv
    for i in 0 1 2 3 4 5; do
        curl -s https://storage.googleapis.com/books/ngrams/books/20200217/chi_sim/2-0000$i-of-00006.gz \
            | zcat | python3 scripts/build_suggestions.py --aggregate 2
    done > zh2.tsv

English: the frequency dictionaries shipped in symspellpy 6.10.2 (MIT), which
SymSpell derived from Google Books Ngram data (CC BY 3.0) and SCOWL.

    python3 scripts/build_suggestions.py --zh-unigrams zh1.tsv --zh-bigrams zh2.tsv \
        --en-unigrams frequency_dictionary_en_82_765.txt \
        --en-bigrams frequency_bigramdictionary_en_243_342.txt --output ios/Shared
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
import sys

FIRST_YEAR = '1980'
MIN_COUNT = 300
ZH_KEYS = 12000
EN_KEYS = 9000
EN_WORDS = 20000
# Followers that only reflect the book corpus (official documents), not chat.
ZH_SKIP = {'党', '省', '主席', '同志', '大锅饭', '国', '军', '主义', '党委', '政府'}
# A prediction bar should not volunteer these.
EN_SKIP = {'fuck', 'fucking', 'fucked', 'shit', 'bitch', 'cunt', 'nigger', 'nigga', 'porn', 'sex',
           'sexy', 'dick', 'cock', 'pussy', 'whore', 'slut', 'rape', 'nude', 'naked', 'xxx'}


def aggregate(order):
    """Raw Google Books shard on stdin -> 'ngram<TAB>count since 1980' on stdout."""
    word = r'[一-鿿]{1,6}' if order == 1 else r'[一-鿿]{1,4} [一-鿿]{1,4}'
    pattern = re.compile(word)
    for line in sys.stdin:
        tab = line.find('\t')
        if tab < 0 or not pattern.fullmatch(line, 0, tab): continue
        total = 0
        for field in line[tab + 1:].split('\t'):
            year, count, _ = field.split(',')
            if year >= FIRST_YEAR: total += int(count)
        if total >= MIN_COUNT: sys.stdout.write(f'{line[:tab]}\t{total}\n')


def read_counts(path, separator):
    counts = {}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        parts = line.rsplit(separator, 1)
        if len(parts) == 2 and parts[1].strip().isdigit(): counts[parts[0]] = int(parts[1])
    return counts


def table(scores, ranking, keys, skip):
    """Top followers per key; frequent keys keep more of them."""
    ordered = sorted((key for key in scores if key in ranking), key=lambda key: -ranking[key])[:keys]
    lines = []
    for index, key in enumerate(ordered):
        limit = 8 if index < 3000 else 5
        followers = sorted(scores[key].items(), key=lambda item: (-item[1], item[0]))
        chosen = [word for word, _ in followers if word not in skip][:limit]
        if chosen: lines.append(key + '\t' + ' '.join(chosen))
    return lines


def chinese(unigrams, bigrams):
    scores = defaultdict(lambda: defaultdict(int))
    for pair, count in bigrams.items():
        first, second = pair.split(' ')
        scores[first][second] += count
    # A word that continues the key ("今" -> "今天") is a suggestion too.
    for word, count in unigrams.items():
        for cut in range(1, len(word)):
            head, tail = word[:cut], word[cut:]
            if head in unigrams: scores[head][tail] += count
    return table(scores, unigrams, ZH_KEYS, ZH_SKIP)


def english(unigrams, bigrams):
    plain = re.compile(r"[a-z]+")
    scores = defaultdict(lambda: defaultdict(int))
    for pair, count in bigrams.items():
        first, second = pair.split(' ')
        if plain.fullmatch(first) and plain.fullmatch(second) and second in unigrams:
            scores[first][second] += count
    words = [word for word, _ in sorted(unigrams.items(), key=lambda item: -item[1])
             if plain.fullmatch(word) and word not in EN_SKIP
             and (len(word) > 1 or word in {'a', 'i'})][:EN_WORDS]
    return table(scores, unigrams, EN_KEYS, EN_SKIP), words


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--aggregate', type=int, choices=[1, 2])
    parser.add_argument('--zh-unigrams', type=Path)
    parser.add_argument('--zh-bigrams', type=Path)
    parser.add_argument('--en-unigrams', type=Path)
    parser.add_argument('--en-bigrams', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.aggregate: aggregate(args.aggregate); return
    zh = chinese(read_counts(args.zh_unigrams, '\t'), read_counts(args.zh_bigrams, '\t'))
    en, words = english(read_counts(args.en_unigrams, ' '), read_counts(args.en_bigrams, ' '))
    args.output.mkdir(parents=True, exist_ok=True)
    report = {}
    for name, lines in [('suggest-zh.txt', zh), ('suggest-en.txt', en), ('suggest-en-words.txt', words)]:
        target = args.output / name
        target.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        report[name] = {'lines': len(lines), 'bytes': target.stat().st_size}
    print(json.dumps(report, indent=2))


if __name__ == '__main__': main()
