#!/usr/bin/env python3
"""Patch SukiSU-Nova v3.0.0 so it builds against the LineageOS 5.4 sm8350 tree.

Differences handled:
  1. <linux/pgtable.h> (5.8+) and <linux/minmax.h> (5.11+) don't exist in 5.4.
  2. This tree has a backported fsnotify_ops whose event callback is
     `handle_event` (no `dir` argument), while SukiSU assumes the 6.0
     `handle_inode_event` layout.

Usage: patch-sukisu-5.4.py <path-to-KernelSU/kernel>
"""
import pathlib
import re
import sys

HEADER_MAP = {
    "#include <linux/pgtable.h>": "#include <asm/pgtable.h>",
    "#include <linux/minmax.h>": "#include <linux/kernel.h>",
}


def patch_headers(root: pathlib.Path) -> None:
    for path in root.rglob("*"):
        if path.suffix not in (".c", ".h"):
            continue
        text = path.read_text(errors="ignore")
        new = text
        for old, repl in HEADER_MAP.items():
            new = new.replace(old, repl)
        if new != text:
            path.write_text(new)
            print(f"[+] header patch: {path.relative_to(root)}")


def patch_fsnotify(root: pathlib.Path) -> None:
    path = root / "manager" / "pkg_observer.c"
    text = path.read_text()

    sig_re = re.compile(
        r"static int ksu_handle_inode_event\(struct fsnotify_mark \*mark, u32 mask, "
        r"struct inode \*inode, struct inode \*dir,\s*\n\s*"
        r"const struct qstr \*file_name, u32 cookie\)"
    )
    new_sig = (
        "#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 0, 0)\n"
        "static int ksu_handle_inode_event(struct fsnotify_mark *mark, u32 mask, "
        "struct inode *inode, struct inode *dir,\n"
        "                                  const struct qstr *file_name, u32 cookie)\n"
        "#else\n"
        "static int ksu_handle_event(struct fsnotify_group *group, struct inode *inode, u32 mask,\n"
        "                            const void *data, int data_type, const struct qstr *file_name,\n"
        "                            u32 cookie, struct fsnotify_iter_info *iter_info)\n"
        "#endif"
    )

    ops_re = re.compile(
        r"static const struct fsnotify_ops ksu_ops = \{\s*\n"
        r"\s*\.handle_inode_event = ksu_handle_inode_event,\s*\n\};"
    )
    new_ops = (
        "static const struct fsnotify_ops ksu_ops = {\n"
        "#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 0, 0)\n"
        "    .handle_inode_event = ksu_handle_inode_event,\n"
        "#else\n"
        "    .handle_event = ksu_handle_event,\n"
        "#endif\n"
        "};"
    )

    changed = False
    if ".handle_event = ksu_handle_event" in text:
        print("[=] fsnotify already patched")
        return
    if sig_re.search(text):
        text = sig_re.sub(new_sig, text, count=1)
        changed = True
    else:
        raise SystemExit("[!] could not find ksu_handle_inode_event signature")
    if ops_re.search(text):
        text = ops_re.sub(new_ops, text, count=1)
        changed = True
    else:
        raise SystemExit("[!] could not find ksu_ops initializer")
    if changed:
        path.write_text(text)
        print("[+] fsnotify ops patched for 5.4")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    root = pathlib.Path(sys.argv[1])
    if not root.is_dir():
        raise SystemExit(f"[!] not a directory: {root}")
    patch_headers(root)
    patch_fsnotify(root)
    print("[+] done")


if __name__ == "__main__":
    main()
