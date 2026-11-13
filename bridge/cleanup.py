"""Rule-based speech cleanup: drop filler words and stuttered repeats.

Pure string rules, no model and no network, so it adds no measurable delay.
Every rule is deliberately narrow; when in doubt the text is left unchanged.
The word lists live in a small text file that is re-read when it changes.
"""
from __future__ import annotations
from pathlib import Path
import re
import threading

FILE_NAME = 'speech-cleanup.txt'
DEFAULTS = {
    'enabled': 'on',
    # Removed wherever they appear. Only sounds that are never part of a word.
    'fillers_anywhere': '嗯 呃 um uh',
    # Removed only as a whole clause before a comma: "那个，我想问" -> "我想问".
    # "我要那个" and "好啊" are never touched.
    'fillers_alone': '啊 额 那个 这个 就是 就是说',
    # "然后然后去" -> "然后去". Words whose doubling is never intended.
    'repeat_words': ('然后 那个 这个 就是 就是说 我们 你们 他们 因为 所以 但是 如果 '
                     '还有 或者 而且 不过 其实 比如 比如说 我觉得 我想 可以 应该 可能 现在'),
    # "我我我想" -> "我想". Single characters that never double in real words.
    'stutter_chars': '我 你 他 她 它 这 那 就',
    # "我今天我今天去" -> "我今天去": any 3-8 character phrase said twice in a row.
    'repeat_phrases': 'on',
}
TEMPLATE = '''# SayKey 语音清理规则（删语气词、删重复词）
# 改完保存即可，下一句话就生效，不用重启桥接。
# 每行格式：名称 = 内容；词与词之间用空格隔开；# 开头的行是说明。
# 想恢复默认：删掉这个文件，重启桥接会重新生成。

# 总开关：on 开启，off 关闭（关闭后完全不改动识别结果）
enabled = {enabled}

# 出现在任何位置都删掉（只放绝不会是正常词一部分的语气词）
fillers_anywhere = {fillers_anywhere}

# 只有单独成一小句、后面跟逗号时才删掉
# 例：「那个，我想问一下」变成「我想问一下」；「我要那个」「好啊」不会动
fillers_alone = {fillers_alone}

# 连着说了两遍以上时只留一遍。例：「然后然后我们」变成「然后我们」
repeat_words = {repeat_words}

# 口吃的单字，连着重复时只留一个。例：「我我我想」变成「我想」
# 不要放「看、谢、妈」这类本来就会叠用的字
stutter_chars = {stutter_chars}

# 3 到 8 个字的短语连着说两遍时只留一遍（on / off）
# 例：「我今天我今天去了」变成「我今天去了」；「一步一步」这类以「一」开头的不会动
repeat_phrases = {repeat_phrases}
'''

CJK = '一-鿿'
SOFT = '，,'                        # pauses inside a sentence
POINTERS = ('这个', '那个')
OPENERS = set('“‘"\'（(《「『【[ ')
PUNCT = SOFT + '、。．.！!？?；;：:…—~～'
NUMERALS = set('零〇一二三四五六七八九十百千万亿两幺')
_SPLIT = re.compile('([' + re.escape(PUNCT) + r']+\s*)')
_PHRASE = re.compile('([' + CJK + r']{3,8}?)\1+')


def _on(value):
    return value.strip().lower() not in ('off', 'false', '0', 'no', '关', '关闭')


def parse(source):
    """Read `name = words` lines; unknown names and broken lines are ignored."""
    values = dict(DEFAULTS)
    for line in source.splitlines():
        line = line.split('#', 1)[0].strip()
        if '=' not in line and '＝' not in line:
            continue
        key, _, value = line.replace('＝', '=').partition('=')
        key = key.strip().lower()
        if key in values:
            values[key] = value.replace('，', ' ').replace(',', ' ').replace('、', ' ').strip()
    return values


def _alternation(words):
    return '|'.join(re.escape(word) for word in sorted(set(words), key=len, reverse=True))


class Rules:
    def __init__(self, values=None):
        values = dict(DEFAULTS, **(values or {}))
        self.enabled = _on(values['enabled'])
        anywhere = values['fillers_anywhere'].split()
        cjk = [word for word in anywhere if not word.isascii()]
        ascii_words = [word for word in anywhere if word.isascii()]
        self.filler_cjk = re.compile('(?:' + _alternation(cjk) + ')+') if cjk else None
        # Latin fillers must be whole words: "um" must not eat "umbrella".
        self.filler_ascii = (re.compile(r'(?<![A-Za-z0-9])(?:' + _alternation(ascii_words) + r')(?![A-Za-z0-9])',
                                        re.IGNORECASE) if ascii_words else None)
        self.alone = set(values['fillers_alone'].split())
        words = [word for word in values['repeat_words'].split() if len(word) > 1]
        self.repeat_words = re.compile('(' + _alternation(words) + r')\1+') if words else None
        chars = [char for char in values['stutter_chars'].split() if len(char) == 1]
        self.stutter = re.compile('([' + re.escape(''.join(chars)) + r'])\1+') if chars else None
        self.repeat_phrases = _on(values['repeat_phrases'])

    def _phrase(self, match):
        unit = match.group(1)
        # "一步一步" is a real pattern, and spoken numbers may legitimately repeat.
        if unit[0] == '一' or len(set(unit)) == 1 or all(char in NUMERALS for char in unit):
            return match.group(0)
        return unit

    def _clause(self, text):
        if self.filler_cjk:
            text = self.filler_cjk.sub('', text)
        if self.filler_ascii and self.filler_ascii.search(text):
            cleaned = re.sub(r'\s{2,}', ' ', self.filler_ascii.sub('', text))
            # Do not leave a new space where the removed word used to touch the edge.
            if not text[:1].isspace(): cleaned = cleaned.lstrip()
            if not text[-1:].isspace(): cleaned = cleaned.rstrip()
            text = cleaned
        if self.stutter:
            text = self.stutter.sub(r'\1', text)
        if self.repeat_words:
            text = self.repeat_words.sub(r'\1', text)
        if self.repeat_phrases:
            text = _PHRASE.sub(self._phrase, text)
        return text

    def clean(self, text):
        if not self.enabled or not text or not text.strip():
            return text
        parts = _SPLIT.split(text)
        # parts alternates clause, punctuation, clause, ... (punctuation may be absent at the end)
        kept = []  # [clause, punctuation]
        for index in range(0, len(parts), 2):
            original = parts[index]
            punct = parts[index + 1] if index + 1 < len(parts) else ''
            clause = self._clause(original)
            soft = bool(punct) and punct.strip()[0] in SOFT
            if clause.strip() in self.alone and soft:
                # "我要这个，那个，还有..." is a list, not a hesitation.
                before = parts[index - 2].rstrip() if index >= 2 else ''
                after = parts[index + 2].lstrip() if index + 2 < len(parts) else ''
                listing = clause.strip() in POINTERS and (before.endswith(POINTERS) or after.startswith(POINTERS))
                if not listing:
                    clause = ''
            if clause != original and clause.strip() and soft and all(char in OPENERS for char in clause):
                # Only an opening quote is left: “嗯，可以” -> “可以”
                kept.append([clause, ''])
                continue
            if clause.strip() or not original.strip():
                # Untouched empty clauses (e.g. text starting with punctuation) stay as they are.
                kept.append([clause if clause.strip() else original, punct])
                continue
            # The whole clause was filler: drop it with one neighbouring mark.
            if kept and (not kept[-1][1] or kept[-1][1].strip()[0] in SOFT) and not soft:
                # "好的，嗯。" -> "好的。"   "好的，嗯" -> "好的"
                kept[-1][1] = punct
        result = ''.join(clause + punct for clause, punct in kept)
        # If nothing meaningful is left (the user only said "嗯"), keep the original.
        return result if re.sub('[' + re.escape(PUNCT) + r'\s]', '', result) else text


class Cleaner:
    """Rules backed by an optional text file; edits apply without a restart."""
    def __init__(self, path=None, create=False):
        self.path = Path(path) if path else None
        self.lock = threading.Lock()
        self.stamp = None
        self.rules = Rules()
        if self.path and create and not self.path.exists():
            try:
                self.path.write_text(TEMPLATE.format(**DEFAULTS), encoding='utf-8')
            except OSError:
                pass  # Read-only folder: built-in defaults still apply.
        self._reload()

    def _reload(self):
        if not self.path:
            return
        try:
            stat = self.path.stat()
            stamp = (stat.st_mtime_ns, stat.st_size)
        except OSError:
            stamp = None
        if stamp == self.stamp:
            return
        try:
            rules = Rules(parse(self.path.read_text(encoding='utf-8-sig'))) if stamp else Rules()
        except (OSError, UnicodeError, re.error):
            return  # Keep the last good rules while the file is half-saved or broken.
        self.rules, self.stamp = rules, stamp

    def clean(self, text):
        try:
            with self.lock:
                self._reload()
                rules = self.rules
            return rules.clean(text)
        except Exception:
            return text  # Cleanup is optional; never lose a recognition result over it.

    def status(self):
        with self.lock:
            self._reload()
            return dict(enabled=self.rules.enabled, file=str(self.path) if self.path else '')
