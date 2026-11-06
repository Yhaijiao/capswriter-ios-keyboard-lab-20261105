"""Select an available iOS runtime the active Xcode SDK can actually target."""
import argparse
import json
from pathlib import Path


def version(value):
    return tuple(int(part) for part in value.split('.')[:2])


def select_runtime(data, sdk):
    compatible = [item for item in data['runtimes']
                  if item.get('isAvailable') and 'iOS' in item.get('identifier', '')
                  and (17, 0) <= version(item['version']) <= version(sdk)]
    if not compatible:
        raise ValueError('No available iOS runtime compatible with active SDK ' + sdk)
    return max(compatible, key=lambda item: version(item['version']))['identifier']


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--sdk', required=True)
    parser.add_argument('--json-file', type=Path, required=True)
    args = parser.parse_args()
    print(select_runtime(json.loads(args.json_file.read_text()), args.sdk))
