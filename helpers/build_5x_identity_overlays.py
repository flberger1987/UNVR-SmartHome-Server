#!/usr/bin/env python3
"""Build exact 4.1/5.x ULP and UID overlays for a physical UNVR lookup."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path


PROFILES = {
    (
        "67b5bf6741aefea8808487fd3bb032fb401ce52eae9d7c86869789d6f49a85e8",
        "96c26dc4a0130ea7071bf7a552d7182ff2526365135f32185927da796ed561ad",
    ): (
        "0d9ece01185cd04978c4016544bba19c5b3da89b679f7a6c6bcf5faf1687dc11",
        "a0e60cadd33c11ca9b658cb5166b8ce8ab59aa2e58fb6dd531c1264399540a7d",
    ),
    (
        "a7db66c52b418eb39bc2f66f5fc73f5a55083237863ffec50f921ecf303dbe35",
        "4accb0af048a5a52deb9ff0c60a0fb98c72d9a4efd0fa7e48721117f94bdad1b",
    ): (
        "424c7f663a94a06557d379d47944734483ee039467ebbb3c5ea750b6f99e5f32",
        "29c94693d4586d20352c9aee22c08fa1f8c734a68fe588905d5b590babcd78f7",
    ),
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=False) + "\n")


def main() -> int:
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: build_5x_identity_overlays.py UID_SOURCE ULP_SOURCE UID_OUTPUT ULP_OUTPUT"
        )
    uid_source, ulp_source, uid_output, ulp_output = map(Path, sys.argv[1:])
    source_pair = (sha256(uid_source), sha256(ulp_source))
    if source_pair not in PROFILES:
        raise SystemExit("unexpected or mismatched UID/ULP profile sources")
    expected_uid_output, expected_ulp_output = PROFILES[source_pair]

    uid = json.loads(uid_source.read_text())
    ulp = json.loads(ulp_source.read_text())

    for key in ("UNVR", "UNVR4"):
        entry = uid[key]
        entry.update(
            {
                "display_name": uid["UNASPRO"]["display_name"],
                "model_name": uid["UNASPRO"]["model_name"],
                "unifi_access": False,
                "unifi_nas": True,
                "support_services": ["FILE_ACCESS"],
            }
        )

    ulp["UNVR"].update(
        {
            "display_name": ulp["UNASPRO"]["display_name"],
            "model_name": ulp["UNASPRO"]["model_name"],
            "unifi_access": False,
            "unifi_connect": False,
            "unifi_nas": True,
            "unifi_protect": False,
        }
    )

    for key in ("UNVR", "UNVR4"):
        if uid[key]["display_name"] != "UniFi Network Attached Storage Pro":
            raise SystemExit(f"generated UID display name mismatch for {key}")
        if uid[key]["model_name"] != "UNAS Pro":
            raise SystemExit(f"generated UID model name mismatch for {key}")
        if uid[key]["unifi_nas"] is not True:
            raise SystemExit(f"generated UID NAS capability mismatch for {key}")
        if uid[key]["support_services"] != ["FILE_ACCESS"]:
            raise SystemExit(f"generated UID support services mismatch for {key}")
        if not uid[key]["primary_interfaces"]:
            raise SystemExit(f"generated UID primary interfaces are empty for {key}")
    if ulp["UNVR"]["unifi_nas"] is not True:
        raise SystemExit("generated ULP NAS capability mismatch")
    if ulp["UNVR"]["unifi_protect"] is not False:
        raise SystemExit("generated ULP Protect capability mismatch")

    write_json(uid_output, uid)
    write_json(ulp_output, ulp)
    if sha256(uid_output) != expected_uid_output:
        raise SystemExit("generated UID identity overlay hash mismatch")
    if sha256(ulp_output) != expected_ulp_output:
        raise SystemExit("generated ULP identity overlay hash mismatch")
    print(f"{sha256(uid_output)}  {uid_output}")
    print(f"{sha256(ulp_output)}  {ulp_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
