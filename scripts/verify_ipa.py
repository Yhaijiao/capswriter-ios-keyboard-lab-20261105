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
        forbidden = ('hot-personal', 'hot-auto', 'hosts.yml', '.env', 'private/')
        assert not any(any(part in name for part in forbidden) for name in package.namelist())
    return {'package': str(path), 'app': app['CFBundleIdentifier'],
            'keyboard': extension['CFBundleIdentifier'], 'validation': 'passed',
            'signing': 'unsigned; requires local personal signing',
            'physical_device_test': 'not yet performed'}


if __name__ == '__main__':
    print(json.dumps(verify(sys.argv[1]), ensure_ascii=False, indent=2))
