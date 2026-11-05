"""Inspect an unsigned IPA before handing it to a local signing tool."""
import json
import plistlib
import sys
import zipfile


def verify(path):
    with zipfile.ZipFile(path) as package:
        base = 'Payload/CapsWriterLab.app/'
        app = plistlib.loads(package.read(base + 'Info.plist'))
        extbase = base + 'PlugIns/CapsWriterKeyboard.appex/'
        extension = plistlib.loads(package.read(extbase + 'Info.plist'))
        assert app['CFBundleIdentifier'] == 'org.capswriterlab.keyboard'
        assert extension['CFBundleIdentifier'] == app['CFBundleIdentifier'] + '.extension'
        spec = extension['NSExtension']
        assert spec['NSExtensionPointIdentifier'] == 'com.apple.keyboard-service'
        assert spec['NSExtensionPrincipalClass'].endswith('.KeyboardViewController')
        assert spec['NSExtensionAttributes']['IsASCIICapable'] is True
        assert package.read(base + app['CFBundleExecutable'])[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe')
        assert package.read(extbase + extension['CFBundleExecutable'])[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe')
        if any(name.endswith('pinyin-lexicon.json') for name in package.namelist()):
            assert app.get('CFBundleShortVersionString') == '0.2.0', 'Unexpected app version'
            assert extension.get('CFBundleShortVersionString') == '0.2.0', 'Unexpected keyboard version'
            for bundle in (base, extbase):
                lexicon = json.loads(package.read(bundle + 'pinyin-lexicon.json'))
                assert len(lexicon) >= 17000 and lexicon['nihao'][0] == '你好'
                assert b'MIT License' in package.read(bundle + 'ThirdPartyNotices.txt')
        forbidden = ('hot-personal', 'hot-auto', 'hosts.yml', '.env', 'private/')
        assert not any(any(part in name for part in forbidden) for name in package.namelist())
    return {'package': str(path), 'app': app['CFBundleIdentifier'],
            'version': app.get('CFBundleShortVersionString'),
            'keyboard': extension['CFBundleIdentifier'], 'validation': 'passed',
            'signing': 'unsigned; requires local personal signing',
            'physical_device_test': 'not yet performed'}


if __name__ == '__main__':
    print(json.dumps(verify(sys.argv[1]), ensure_ascii=False, indent=2))
