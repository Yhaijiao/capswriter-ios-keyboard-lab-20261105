"""Extract this project's private source export into a new, empty destination."""
import argparse
from pathlib import Path, PurePosixPath
import tarfile


def unpack(archive_path, destination):
    destination = Path(destination).resolve()
    if destination.exists() and any(destination.iterdir()):
        raise FileExistsError('Existing private runtime is preserved; choose a fresh directory')
    with tarfile.open(archive_path, 'r:gz') as archive:
        members = archive.getmembers()
        for member in members:
            name = PurePosixPath(member.name)
            if name.is_absolute() or '..' in name.parts or not member.isfile():
                raise ValueError('Unsupported private archive entry')
            if not (destination / member.name).resolve().is_relative_to(destination):
                raise ValueError('Private archive leaves target directory')
        destination.mkdir(parents=True, exist_ok=True)
        destination.chmod(0o700)
        for member in members:
            path = destination / member.name
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('xb') as stream: stream.write(archive.extractfile(member).read())
            path.chmod(0o600)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    unpack(args.archive, args.destination)
