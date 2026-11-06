"""Export a private Linux runtime without unrelated desktop credentials.

Output must remain private, outside the public repository. Models are deliberately
not copied: transfer the three model files separately over the approved SSH link.
"""
from __future__ import annotations
import argparse
import ast
import hashlib
import json
from pathlib import Path
import tarfile
import io

CONFIG_KEYS = ('hot', 'hot_thresh', 'hot_similar', 'hot_rule', 'trash_punc',
               'trash_punc_thresh', 'trash_punc_apps', 'traditional_convert')
HOT_FILES = ('hot.txt', 'hot-personal-aliases.txt', 'hot-rule.txt',
             'auto-hotwords/hot-auto.txt', 'hot-server.txt')
MODELS = ('qwen3_asr_encoder_frontend.onnx', 'qwen3_asr_encoder_backend.onnx', 'qwen3_asr_llm.gguf')


def minimal_client_config(source):
    tree = ast.parse(source)
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'ClientConfig')
    values = {}
    for node in cls.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id in CONFIG_KEYS:
                    values[target.id] = ast.literal_eval(node.value)
    missing = set(CONFIG_KEYS) - values.keys()
    if missing: raise ValueError('Missing client configuration keys: ' + ','.join(sorted(missing)))
    return 'from pathlib import Path\nBASE_DIR = str(Path(__file__).resolve().parent)\nclass ClientConfig:\n' + ''.join(
        f'    {key} = {values[key]!r}\n' for key in CONFIG_KEYS)


def minimal_output_source(source):
    tree = ast.parse(source)
    counter = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'count_semantic_units')
    assignment = next(n for n in tree.body if isinstance(n, ast.Assign) and any(
        isinstance(t, ast.Name) and t.id == '_SEMANTIC_UNIT_RE' for t in n.targets))
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'TextOutput')
    method = next(n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name == 'strip_punc')
    return ast.unparse(ast.Module(body=[assignment, counter, ast.ClassDef(
        name='TextOutput', bases=[], keywords=[], body=[method], decorator_list=[])], type_ignores=[])) + '\n'


def export(source_root, output):
    root = Path(source_root).resolve()
    destination = Path(output).resolve()
    public_root = Path(__file__).resolve().parents[1]
    if destination.is_relative_to(public_root):
        raise ValueError('Private export must be outside the public repository')
    if destination.exists(): raise FileExistsError('Existing export is preserved')
    selected = {}
    for folder in ('core/server', 'core/tools', 'core/client/hotword'):
        for path in (root / folder).rglob('*.py'):
            if path.is_symlink(): raise ValueError('Symlink source is not supported')
            selected[path.relative_to(root).as_posix()] = path.read_bytes()
    for name in ('core/__init__.py', 'core/logger.py', 'config_server.py', *HOT_FILES):
        path = root / name
        if path.is_file(): selected[name] = path.read_bytes()
    selected['config_client.py'] = minimal_client_config((root / 'config_client.py').read_text(encoding='utf-8-sig')).encode()
    selected['core/client/output/text_output.py'] = minimal_output_source(
        (root / 'core/client/output/text_output.py').read_text(encoding='utf-8-sig')).encode()
    manifest = {'files': {name: hashlib.sha256(data).hexdigest() for name, data in sorted(selected.items())},
                'model_files': {}, 'models_copied': False, 'mutable_files': ['hot.txt'],
                'scope': 'Private numerical/format/hotword source only; client config whitelisted, output source minimized'}
    model_root = root / 'models/Qwen3-ASR/Qwen3-ASR-1.7B'
    for name in MODELS:
        path = model_root / name
        hasher = hashlib.sha256()
        with path.open('rb') as stream:
            for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''): hasher.update(chunk)
        manifest['model_files'][name] = {'sha256': hasher.hexdigest(), 'size': path.stat().st_size}
    selected['private-manifest.json'] = json.dumps(manifest, ensure_ascii=False, indent=2).encode()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(destination, 'x:gz') as archive:
        for name, data in sorted(selected.items()):
            info = tarfile.TarInfo(name); info.size = len(data); info.mode = 0o600
            archive.addfile(info, io.BytesIO(data))
    return {'private_export': str(destination), 'file_count': len(selected), 'models_copied': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--desktop', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(export(args.desktop, args.output), ensure_ascii=False))
