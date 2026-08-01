#!/usr/bin/env python3
"""Run nixos-rebuild with one getpass value supplied through stdin."""

import getpass
import runpy
import sys


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(
            "usage: nixos-rebuild-with-password.py WRAPPED_REBUILD ARG [ARG ...]"
        )

    wrapped_rebuild = sys.argv[1]
    rebuild_args = sys.argv[2:]
    password = sys.stdin.readline()
    if password.endswith("\n"):
        password = password[:-1]
    if not password:
        raise SystemExit("no sudo password was supplied on stdin")

    def supplied_password(prompt: str = "", stream: object = None) -> str:
        del prompt, stream
        return password

    getpass.getpass = supplied_password
    sys.argv = [wrapped_rebuild, *rebuild_args]

    try:
        runpy.run_path(wrapped_rebuild, run_name="__main__")
    finally:
        password = ""


if __name__ == "__main__":
    main()
