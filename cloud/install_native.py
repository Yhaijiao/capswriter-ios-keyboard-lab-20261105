"""Install pinned official llama.cpp Linux libraries; no Windows DLL reuse."""
import argparse
import hashlib
import io
from pathlib import Path, PurePosixPath
import tarfile
import urllib.request

URL = 'https://github.com/ggml-org/llama.cpp/releases/download/b10621/llama-b10621-bin-ubuntu-x64.tar.gz'
SHA256 = '91d7b03ddae498a39f28fdb85d84d2b4a0fd3838d10b4f897e0ef8975bb9b583'


def install(private_root):
    with urllib.request.urlopen(URL, timeout=60) as response: data = response.read(32 * 1024 * 1024)
    if hashlib.sha256(data).hexdigest() != SHA256: raise ValueError('Official Linux library archive hash mismatch')
    target = Path(private_root) / 'core/server/engines/llama/bin'
    target.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        entries = {member.name: member for member in archive.getmembers()}
        def materialize(member, seen=None):
            seen = set() if seen is None else seen
            if member.name in seen: raise ValueError('Library link cycle')
            seen.add(member.name)
            if member.isfile(): return archive.extractfile(member).read()
            if member.issym():
                path = str(PurePosixPath(member.name).parent / member.linkname)
                return materialize(entries[path], seen)
            if member.islnk(): return materialize(entries[member.linkname], seen)
            raise ValueError('Unsupported native library entry')
        installed = []
        for member in entries.values():
            name = PurePosixPath(member.name).name
            if '.so' not in name: continue
            if '..' in PurePosixPath(member.name).parts: raise ValueError('Unsafe archive path')
            content = materialize(member)
            destination = target / name
            if destination.exists() and destination.read_bytes() != content:
                raise FileExistsError('Existing differing library preserved: ' + name)
            if not destination.exists(): destination.write_bytes(content)
            installed.append(name)
    for name in ('libllama.so', 'libggml.so', 'libggml-base.so'):
        if name not in installed: raise ValueError('Required Linux library missing: ' + name)
    print('Pinned Linux native libraries installed; live inference not yet verified')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-root', type=Path, required=True)
    install(parser.parse_args().private_root)
