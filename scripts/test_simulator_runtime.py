import unittest
from select_simulator_runtime import select_runtime


class RuntimeSelectionTests(unittest.TestCase):
    def test_never_choose_newer_os_than_active_sdk(self):
        data = {'runtimes': [
            {'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-26-2', 'version': '26.2', 'isAvailable': True},
            {'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-18-5', 'version': '18.5', 'isAvailable': True}]}
        self.assertTrue(select_runtime(data, '18.5').endswith('18-5'))
        self.assertTrue(select_runtime(data, '26.2').endswith('26-2'))

    def test_unavailable_or_too_old_is_not_a_fallback(self):
        data = {'runtimes': [
            {'identifier': 'iOS-18-5', 'version': '18.5', 'isAvailable': False},
            {'identifier': 'iOS-16-4', 'version': '16.4', 'isAvailable': True}]}
        with self.assertRaises(ValueError): select_runtime(data, '18.5')
