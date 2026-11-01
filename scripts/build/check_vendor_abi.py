#!/usr/bin/env python3
"""Compare arm64 kernel BTF member offsets and exported symbol CRCs.
Requires pyelftools; use matching configurations and build-time feature patches.
Checks structure size, member offsets, and bitfield widths, not every
member type or runtime behavior. This does not replace vendor-module loading
or a real-device boot test.
"""
import argparse
import json
import struct
from pathlib import Path
from elftools.elf.elffile import ELFFile

def btf_records(path):
    with open(path, "rb") as stream:
        section = ELFFile(stream).get_section_by_name(".BTF")
        if section is None:
            raise ValueError(f"{path}: no .BTF section")
        data = section.data()
    magic, version, flags, hdrlen, toff, tlen, soff, slen = struct.unpack_from("<HBBIIIII", data)
    if magic != 0xEB9F or version != 1:
        raise ValueError("unsupported BTF format")
    strings = data[hdrlen + soff:hdrlen + soff + slen]
    def name(off):
        return strings[off:strings.index(b"\0", off)].decode()
    records = {0: {"kind": 0}}
    pos, stop, index = hdrlen + toff, hdrlen + toff + tlen, 1
    while pos < stop:
        noff, info, size = struct.unpack_from("<III", data, pos)
        pos += 12
        kind, vlen, kflag = (info >> 24) & 31, info & 65535, info >> 31
        record = {"kind": kind, "name": name(noff), "size": size}
        if kind in (4, 5):
            members = []
            for i in range(vlen):
                member, tid, offset = struct.unpack_from("<III", data, pos + 12 * i)
                members.append((name(member), tid, offset & 0xFFFFFF if kflag else offset,
                                offset >> 24 if kflag else 0))
            record["members"] = members
        extra = {1: 4, 2: 0, 3: 12, 4: 12*vlen, 5: 12*vlen, 6: 8*vlen,
                 7: 0, 8: 0, 9: 0, 10: 0, 11: 0, 12: 0, 13: 8*vlen,
                 14: 4, 15: 12*vlen, 16: 0, 17: 4, 18: 0, 19: 12*vlen}
        if kind not in extra:
            raise ValueError(f"unknown BTF kind {kind}")
        pos += extra[kind]
        records[index] = record
        index += 1
    return records

def layouts(records):
    def flatten(tid, base=0):
        result = {}
        for name, mid, offset, width in records[tid].get("members", []):
            if name:
                if not name.startswith(("android_kabi_reserved", "android_backport_reserved")):
                    # A byte-wide bitfield and a u8 member have the same
                    # arm64 storage contract (e.g. net_device.reg_state).
                    # Keep ordinary members at width=0, preserving this tool's
                    # documented offset/bitfield comparison semantics.
                    member = records[mid]
                    seen = set()
                    while member["kind"] in (8, 9, 10, 11, 18):
                        if mid in seen:
                            break
                        seen.add(mid)
                        mid = member["size"]
                        member = records[mid]
                    if not width and member["kind"] in (1, 6) and member["size"] == 1:
                        width = 8
                    result[name] = [base + offset, width]
            elif records[mid]["kind"] in (4, 5):
                result.update(flatten(mid, base + offset))
        return result
    return {r["name"]: {"size": r["size"], "members": flatten(tid)}
            for tid, r in records.items()
            if r["kind"] == 4 and r["name"] and r["size"]}

def symvers(path):
    result = {}
    for line in Path(path).read_text().splitlines():
        fields = line.split()
        if len(fields) >= 2:
            result[fields[1]] = fields[0]
    return result

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("baseline", help="baseline output directory")
    p.add_argument("current", help="current output directory")
    types = p.add_mutually_exclusive_group()
    types.add_argument("--types", nargs="*", help="only check these struct names")
    types.add_argument("--types-file", help="file with one struct name per line")
    p.add_argument("--symbols", nargs="*", help="Android ABI symbol-list files")
    p.add_argument("--limit", type=int, default=40)
    args = p.parse_args()
    old = layouts(btf_records(Path(args.baseline) / "vmlinux"))
    new = layouts(btf_records(Path(args.current) / "vmlinux"))
    changed = []
    selected_types = args.types or (Path(args.types_file).read_text().split()
                                    if args.types_file else old)
    for name in sorted(selected_types):
        if name not in old or name not in new:
            changed.append({"type": name, "missing": "baseline" if name not in old else "current"})
            continue
        a, b = old[name], new[name]
        members = {m: [v, b["members"].get(m)] for m, v in a["members"].items()
                   if b["members"].get(m) != v}
        if a["size"] != b["size"] or members:
            changed.append({"type": name, "size": [a["size"], b["size"]], "members": members})
    a = symvers(Path(args.baseline) / "vmlinux.symvers")
    b = symvers(Path(args.current) / "vmlinux.symvers")
    selected = set(a)
    if args.symbols:
        selected = set()
        for path in args.symbols:
            for line in Path(path).read_text().splitlines():
                word = line.split("#")[0].strip()
                if word and word.replace("_", "").isalnum():
                    selected.add(word)
        selected &= a.keys()
    crcs = {name: [a[name], b.get(name)] for name in sorted(selected) if a[name] != b.get(name)}
    print(json.dumps({"layout_changes": len(changed), "layouts": changed[:args.limit],
                      "symbols_checked": len(selected), "crc_changes": len(crcs),
                      "crcs": dict(list(crcs.items())[:args.limit])}, indent=2))
    return int(bool(changed or crcs))

if __name__ == "__main__":
    raise SystemExit(main())
