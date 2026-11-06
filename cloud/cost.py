"""Small cost calculator; prices are public, user balances are not persisted."""
from decimal import Decimal
import argparse
import json
from pathlib import Path


def estimate(hours, storage_gb=30):
    rates = json.loads(Path(__file__).with_name('pricing-ohio.json').read_text())
    duration = Decimal(str(hours))
    cpu = duration * Decimal(rates['instance_usd_per_hour'])
    ip = duration * Decimal(rates['public_ipv4_usd_per_hour'])
    disk = duration / Decimal(730) * Decimal(str(storage_gb)) * Decimal(rates['gp3_usd_per_gb_month'])
    return {key: str(value.quantize(Decimal('0.00001'))) for key, value in
            [('instance', cpu), ('ipv4', ip), ('storage', disk), ('total', cpu + ip + disk)]}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hours', type=Decimal, default=Decimal(24))
    parser.add_argument('--storage-gb', type=Decimal, default=Decimal(30))
    args = parser.parse_args()
    if args.hours < 0 or args.storage_gb < 0: parser.error('Nonnegative values required')
    print(json.dumps(estimate(args.hours, args.storage_gb), indent=2))
