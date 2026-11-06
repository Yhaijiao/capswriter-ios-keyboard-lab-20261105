import hashlib
from pathlib import Path
import tempfile
import threading
import unittest
from hotwords import HotwordStore, HotwordError


class HotwordTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / 'desktop'; self.source.mkdir()
        self.state = self.root / 'private-backups'
        (self.source / 'hot.txt').write_text('CapsWriter\n', encoding='utf-8')
        self.store = HotwordStore(self.source, self.state, writable=True)

    def tearDown(self): self.temp.cleanup()
    def hot(self): return self.store.read()['hotword_files'][0]
    def assert_error(self, status, callback):
        with self.assertRaises(HotwordError) as error: callback()
        self.assertEqual(error.exception.status, status)

    def test_save_backs_up_original_and_revisions(self):
        before = self.hot()
        result = self.store.save('hot', before['revision'], 'CapsWriter\n手机词条\n')
        self.assertEqual(result['hotword_files'][0]['text'], 'CapsWriter\n手机词条\n')
        self.assertNotEqual(self.hot()['revision'], before['revision'])
        self.assertEqual(next(self.state.glob('hot.*.txt')).read_text(encoding='utf-8'), before['text'])
        self.assertFalse(list(self.state.glob('hot-save-*')))

    def test_external_edit_is_not_overwritten(self):
        before = self.hot()
        (self.source / 'hot.txt').write_text('电脑刚修改\n', encoding='utf-8')
        self.assert_error(409, lambda: self.store.save('hot', before['revision'], '旧手机副本'))
        self.assertEqual(self.hot()['text'], '电脑刚修改\n')

    def test_readonly_is_default(self):
        store = HotwordStore(self.source, self.state)
        self.assertFalse(store.read()['hotword_files'][0]['writable'])
        self.assert_error(403, lambda: store.save('hot', self.hot()['revision'], '变化'))

    def test_other_files_and_paths_never_writable(self):
        for name in ['aliases', 'auto', 'rule', 'asr', '../hot', 'C:/other']:
            self.assert_error(403, lambda: self.store.save(name, self.hot()['revision'], '变化'))

    def test_validation_failure_preserves_original(self):
        def invalid(_): raise ValueError('bad format')
        self.store.validate = invalid
        before = self.hot()
        self.assert_error(400, lambda: self.store.save('hot', before['revision'], '非法格式'))
        self.assertEqual(self.hot(), before)
        self.assertFalse(self.state.exists())

    def test_edit_during_validation_is_detected(self):
        self.store.validate = lambda _: (self.source / 'hot.txt').write_text('另一处更新', encoding='utf-8')
        self.assert_error(409, lambda: self.store.save('hot', self.hot()['revision'], '旧副本'))
        self.assertEqual(self.hot()['text'], '另一处更新')

    def test_concurrent_mobile_saves_only_one_wins(self):
        revision = self.hot()['revision']
        results = []
        def save(text):
            try: self.store.save('hot', revision, text); results.append(200)
            except HotwordError as error: results.append(error.status)
        threads = [threading.Thread(target=save, args=(word,)) for word in ['手机一', '手机二']]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
        self.assertEqual(sorted(results), [200, 409])

    def test_limits_and_nul(self):
        for text in ['a' * (256 * 1024 + 1), 'bad\0word']:
            self.assert_error(413 if '\0' not in text else 400,
                              lambda: self.store.save('hot', self.hot()['revision'], text))

    def test_unchanged_save_makes_no_backup(self):
        file = self.hot()
        self.store.save('hot', file['revision'], file['text'])
        self.assertFalse(self.state.exists())


if __name__ == '__main__': unittest.main()
