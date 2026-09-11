#!/usr/bin/env python3
"""Read and write a CrossOver bottle's [EnvironmentVariables] block.

One place understands the file format, because three scripts need it: setup.sh
writes the block, uninstall.sh takes it away, and ow2.sh lifts it for one launch
so `--plain` can mean something.

Why the block at all, rather than exporting variables before launching: the
bottle's own config wins. CrossOver's launcher is a Perl script, and
lib/perl/CXBottle.pm assigns every key in this section unconditionally
(`$ENV{$var}=expand_string($value)`), so a key listed here overrides the
environment it was launched with, and a key not listed passes through. That also
makes the block the only way to be configured for a launch from CrossOver's own
window, which is how most people will start the game.

usage:
  cxenv.py set   <conf> KEY=VALUE...        # add or replace, keeping the rest
  cxenv.py unset <conf> KEY...              # remove those keys
  cxenv.py get   <conf> KEY                 # print the value, or nothing
"""
import re
import sys

def load(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def split(text):
    """Return (head, block, tail) around the [EnvironmentVariables] section."""
    if "[EnvironmentVariables]" not in text:
        text = text.rstrip("\n") + "\n\n[EnvironmentVariables]\n"
    head, sep, rest = text.partition("[EnvironmentVariables]")
    end = rest.find("\n[")
    if end == -1:
        return head + sep, rest, ""
    return head + sep, rest[:end], rest[end:]


def set_keys(path, pairs):
    head, block, tail = split(load(path))
    for key, value in pairs:
        line = '"%s" = "%s"' % (key, value)
        pat = re.compile(r'^"%s"\s*=.*$' % re.escape(key), re.M)
        block = pat.sub(line, block) if pat.search(block) \
            else block.rstrip("\n") + "\n" + line + "\n"
    write(path, head, block, tail)


def unset_keys(path, keys):
    head, block, tail = split(load(path))
    for key in keys:
        block = re.sub(r'^"%s"\s*=.*$\n?' % re.escape(key), "", block, flags=re.M)
    write(path, head, block, tail)


def write(path, head, block, tail):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(head + block + tail)


def get_key(path, key):
    _, block, _ = split(load(path))
    found = re.search(r'^"%s"\s*=\s*"(.*)"\s*$' % re.escape(key), block, re.M)
    return found.group(1) if found else None


def main(argv):
    if len(argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    what, conf, rest = argv[1], argv[2], argv[3:]
    if what == "set":
        pairs = []
        for item in rest:
            if "=" not in item:
                sys.stderr.write("not a KEY=VALUE pair: %s\n" % item)
                return 2
            key, _, value = item.partition("=")
            pairs.append((key, value))
        set_keys(conf, pairs)
    elif what == "unset":
        unset_keys(conf, rest)
    elif what == "get":
        value = get_key(conf, rest[0]) if rest else None
        if value is None:
            return 1
        print(value)
    else:
        sys.stderr.write("unknown command: %s\n" % what)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
