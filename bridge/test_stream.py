import os
from pathlib import Path
import unittest
import wave

from stream import _join, LivePreview


class JoinTests(unittest.TestCase):
    def test_spaces_only_between_english_words(self):
        self.assertEqual(_join('今天', '天气'), '今天天气')
        self.assertEqual(_join('today', 'is'), 'today is')
        self.assertEqual(_join('我说', 'hello'), '我说hello')
        self.assertEqual(_join('', 'hello'), 'hello')

    def test_missing_model_files_are_named(self):
        with self.assertRaisesRegex(FileNotFoundError, 'encoder.int8.onnx'):
            LivePreview(Path(__file__).parent)


@unittest.skipUnless(os.environ.get('CW_STREAM_MODEL'), 'Set CW_STREAM_MODEL to a streaming Paraformer folder')
class RealModelTests(unittest.TestCase):
    def test_draft_grows_while_audio_arrives(self):
        model = Path(os.environ['CW_STREAM_MODEL'])
        with wave.open(str(model / 'test_wavs' / '1.wav')) as source:
            pcm = source.readframes(source.getnframes())
        session = LivePreview(model).session()
        drafts = [session.feed(pcm[i:i + 16000]) for i in range(0, len(pcm), 16000)]
        self.assertTrue(drafts[-1])
        self.assertGreaterEqual(len(drafts[-1]), len(drafts[len(drafts) // 2]))


if __name__ == '__main__': unittest.main()
