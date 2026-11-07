"""Inspect an unsigned IPA before handing it to a local signing tool."""
import json
import plistlib
import sys
import zipfile


def verify(path, expected_version=None):
    with zipfile.ZipFile(path) as package:
        base = 'Payload/CapsWriterLab.app/'
        app = plistlib.loads(package.read(base + 'Info.plist'))
        extbase = base + 'PlugIns/CapsWriterKeyboard.appex/'
        extension = plistlib.loads(package.read(extbase + 'Info.plist'))
        assert app['CFBundleIdentifier'] == 'org.capswriterlab.keyboard'
        assert extension['CFBundleIdentifier'] == app['CFBundleIdentifier'] + '.extension'
        assert extension['CFBundleVersion'] == app['CFBundleVersion']
        spec = extension['NSExtension']
        assert spec['NSExtensionPointIdentifier'] == 'com.apple.keyboard-service'
        assert spec['NSExtensionPrincipalClass'].endswith('.KeyboardViewController')
        assert spec['NSExtensionAttributes']['IsASCIICapable'] is True
        assert package.read(base + app['CFBundleExecutable'])[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe')
        assert package.read(extbase + extension['CFBundleExecutable'])[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe')
        if expected_version == '0.4.8':
            activity_base = base + 'PlugIns/CapsWriterVoiceActivity.appex/'
            activity = plistlib.loads(package.read(activity_base + 'Info.plist'))
            assert activity['CFBundleIdentifier'] == app['CFBundleIdentifier'] + '.activity'
            assert activity['CFBundleVersion'] == app['CFBundleVersion']
            assert activity['CFBundleShortVersionString'] == app['CFBundleShortVersionString']
            assert activity['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
            assert app.get('NSSupportsLiveActivities') is True
            assert package.read(activity_base + activity['CFBundleExecutable'])[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe')
        if any(name.endswith('pinyin-lexicon.json') for name in package.namelist()):
            assert app.get('CFBundleShortVersionString') == extension.get('CFBundleShortVersionString'), 'Mismatched versions'
            if expected_version is not None:
                assert app.get('CFBundleShortVersionString') == expected_version, 'Unexpected app version'
            assert app.get('NSMicrophoneUsageDescription')
            assert 'audio' in app.get('UIBackgroundModes', [])
            for bundle in (base, extbase):
                lexicon = json.loads(package.read(bundle + 'pinyin-lexicon.json'))
                assert len(lexicon) >= 17000 and lexicon['nihao'][0] == '你好'
                if tuple(map(int, app['CFBundleShortVersionString'].split('.'))) >= (0, 4, 1):
                    costs = json.loads(package.read(bundle + 'pinyin-costs.json'))
                    assert len(costs) >= 17000 and costs['women'][0] > 0
                    assert all(len(costs[key]) == len(words) for key, words in lexicon.items())
                if tuple(map(int, app['CFBundleShortVersionString'].split('.'))) >= (0, 4, 3):
                    syllables = json.loads(package.read(bundle + 'pinyin-syllables.json'))
                    assert '我们' in syllables["wo'men"]
                    assert '你好吗' in syllables["ni'hao'ma"]
                    assert sum(map(len, syllables.values())) == sum(map(len, lexicon.values()))
                assert b'MIT License' in package.read(bundle + 'ThirdPartyNotices.txt')
        forbidden = ('hot-personal', 'hot-auto', 'hosts.yml', '.env', 'private/')
        assert not any(any(part in name for part in forbidden) for name in package.namelist())
    return {'package': str(path), 'app': app['CFBundleIdentifier'],
            'version': app.get('CFBundleShortVersionString'),
            'keyboard': extension['CFBundleIdentifier'], 'validation': 'passed',
            'signing': 'unsigned; requires local personal signing',
            'physical_device_test': 'not yet performed'}


if __name__ == '__main__':
    print(json.dumps(verify(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None), ensure_ascii=False, indent=2))
