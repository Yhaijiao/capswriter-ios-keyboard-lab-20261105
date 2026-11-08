# Third-party components

SayKey is an independent project. It is not affiliated with or endorsed by
CapsWriter-Offline; it only talks to a speech-recognition server that the user
runs themselves.

The optional desktop adapter reads code from the user's installed
[CapsWriter-Offline](https://github.com/HaujetZhao/CapsWriter-Offline).
That source code is not included or relicensed in this repository. Its original
license remains applicable. Model files and personal word lists are not included.

Optional Python dependencies: [pypinyin](https://github.com/mozillazg/python-pinyin)
and [RapidFuzz](https://github.com/rapidfuzz/RapidFuzz). See their distributions for
their respective license notices.

The bundled compact full-pinyin dictionary is derived from jieba 0.42.1's public
word/frequency dictionary and pypinyin 0.55.0's public pronunciation data. Both
projects use the MIT license. Full notices are bundled in
`ios/Shared/ThirdPartyNotices.txt`. The generator reads only explicit public
package data; it never reads the user's CapsWriter vocabulary. Generated data:
17,398 pinyin keys / 30,953 word entries, about 473 KB. Jieba source dictionary
SHA-256: `7197c3211ddd98962b036cdf40324d1ea2bfaa12bd028e68faa70111a88e12a8`.

The build uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) and GitHub's
official Actions. The app uses UIKit and SF Symbols supplied by Apple.

This is an independent experiment. It does not include Typeless code, logo,
assets, service access or subscription functionality.
