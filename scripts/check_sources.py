"""Portable preflight checks. These are explicitly not an Xcode build."""
import ast
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    python_files = list(ROOT.glob('bridge/*.py')) + list(ROOT.glob('scripts/*.py')) + list(ROOT.glob('cloud/*.py'))
    for path in python_files:
        ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
    swift_files = list(ROOT.glob('ios/**/*.swift'))
    assert len(swift_files) >= 3
    assert (ROOT / 'project.yml').is_file()
    workflow = (ROOT / '.github/workflows/build-ios.yml').read_text(encoding='utf-8')
    assert '-sdk iphoneos' in workflow and 'CODE_SIGNING_ALLOWED=NO' in workflow
    assert 'PlugIns/CapsWriterKeyboard.appex' in workflow
    assert 'workflow_dispatch' in workflow
    forbidden_names = {'hosts.yml', 'hot.txt', 'hot-personal-aliases.txt', 'hot-auto.txt', 'hot-rule.txt', '.env'}
    forbidden_suffixes = {'.p12', '.mobileprovision', '.pem', '.key', '.wav', '.mp3', '.m4a'}
    offending = []
    for path in ROOT.rglob('*'):
        if '.git' in path.parts or not path.is_file(): continue
        if path.name in forbidden_names or path.suffix in forbidden_suffixes or 'private' in path.relative_to(ROOT).parts:
            offending.append(str(path.relative_to(ROOT)))
        if path.suffix in {'.swift', '.py', '.yml', '.md'}:
            data = path.read_text(encoding='utf-8')
            # Detect credential-shaped literals, not descriptions/examples.
            import re
            assert not re.search(r'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}', data), str(path)
    assert not offending, offending
    result = {'python_syntax_files': len(python_files), 'swift_source_files': len(swift_files),
              'private_data_publication_check': 'passed', 'workflow_structure': 'passed',
              'xcode_compilation': 'not checked by this script'}
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__': main()
