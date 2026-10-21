#!/usr/bin/env python3
"""Extract, re-embed or check the helper archive inside convert.sh.

    tools/embedded_helpers.py extract convert.sh DIR   # unpack helpers to DIR
    tools/embedded_helpers.py embed   convert.sh DIR   # pack DIR back, update pins
    tools/embedded_helpers.py check   convert.sh DIR   # embedded == DIR and pins match

helpers/ in this repository is the readable source of the embedded archive:
edit a file there, then run `embed convert.sh helpers`.

`embed` keeps the member order of the current archive, writes a reproducible
tar.gz (root:root, gzip mtime 0) and rewrites every `readonly *_SHA256` pin that
convert.sh checks against a helper file, plus EMBEDDED_HELPERS_SHA256.
"""
import base64
import gzip
import hashlib
import io
import re
import sys
import tarfile
import textwrap
from pathlib import Path

START = "base64 -D > \"$archive\" <<'UNVR_UNAS_EMBEDDED_HELPERS'\n"
END = "\nUNVR_UNAS_EMBEDDED_HELPERS\n"


def split(src):
    i = src.index(START) + len(START)
    j = src.index(END, i)
    return i, j


def current_archive(src):
    i, j = split(src)
    return base64.b64decode("".join(src[i:j].split()))


def extract(script, directory):
    data = current_archive(Path(script).read_text())
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        tar.extractall(directory, filter="data")
        for name in tar.getnames():
            print(name)


def embed(script, directory):
    script, directory = Path(script), Path(directory)
    src = script.read_text()
    with tarfile.open(fileobj=io.BytesIO(current_archive(src)), mode="r:gz") as tar:
        members = tar.getnames()

    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for name in members:
            path = directory / name
            info = tar.gettarinfo(str(path), arcname=name)
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            with path.open("rb") as handle:
                tar.addfile(info, handle)
    packed = io.BytesIO()
    with gzip.GzipFile(fileobj=packed, mode="wb", mtime=0) as gz:
        gz.write(raw.getvalue())
    data = packed.getvalue()

    i, j = split(src)
    src = src[:i] + "\n".join(textwrap.wrap(base64.b64encode(data).decode(), 76)) + src[j:]

    pins = {"EMBEDDED_HELPERS_SHA256": hashlib.sha256(data).hexdigest()}
    files = {
        "remote_engine": "unvr_unas_remote.sh",
        "profile_builder": "build_update_profiles_macos.sh",
    }
    for match in re.finditer(r'\$\(sha "\$(\w+)(/[^"]*)?"\) == "\$([A-Z0-9_]+_SHA256)"', src):
        variable, rest, pin = match.groups()
        name = rest[1:] if variable == "script_dir" else files.get(variable)
        if not name:
            continue
        pins[pin] = hashlib.sha256((directory / name).read_bytes()).hexdigest()
    for pin, value in sorted(pins.items()):
        src, count = re.subn(rf"^readonly {pin}=[0-9a-f]{{64}}$", f"readonly {pin}={value}", src, flags=re.M)
        if count != 1:
            sys.exit(f"pin {pin} not found exactly once")
        print(f"{pin}={value}")
    script.write_text(src)


def check(script, directory):
    script, directory = Path(script), Path(directory)
    src = script.read_text()
    data = current_archive(src)
    problems = []
    pinned = re.search(r"^readonly EMBEDDED_HELPERS_SHA256=([0-9a-f]{64})$", src, re.M)
    if not pinned or pinned.group(1) != hashlib.sha256(data).hexdigest():
        problems.append("EMBEDDED_HELPERS_SHA256 does not match the embedded archive")
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        for member in tar.getmembers():
            embedded = tar.extractfile(member).read()
            local = directory / member.name
            if not local.is_file() or local.read_bytes() != embedded:
                problems.append(f"{member.name} differs from {local}")
    for problem in problems:
        print(problem)
    if problems:
        sys.exit(1)
    print("embedded helpers match", directory)


if __name__ == "__main__":
    commands = {"extract": extract, "embed": embed, "check": check}
    if len(sys.argv) != 4 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]](sys.argv[2], sys.argv[3])
