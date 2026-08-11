#!/usr/bin/env python3
"""Generate local secret files without printing secret values."""
from __future__ import annotations

import os
import pathlib
import secrets
import string

ALPHABET = string.ascii_letters + string.digits
ITEMS = {
    "secrets/silo_secret_key": 96,
    "secrets/postgres_password": 48,
}


def main() -> None:
    pathlib.Path("secrets").mkdir(parents=True, exist_ok=True)
    for path, length in ITEMS.items():
        p = pathlib.Path(path)
        if p.exists():
            print(f"kept existing {path}")
            continue
        value = "".join(secrets.choice(ALPHABET) for _ in range(length))
        p.write_text(value, encoding="utf-8")
        os.chmod(p, 0o600)
        print(f"created {path} mode 0600")


if __name__ == "__main__":
    main()
