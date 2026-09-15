# glances for the Intel Xeon Phi 3120A

glances 4.5.6 running on the Xeon Phi 3120A (Knights Corner, 57 cores,
228 threads) under the mainline Linux port from
[Intel-Phi-3120A](https://github.com/Lasimeri/Intel-Phi-3120A). glances is
Python, so this repository is also where CPython first ran on the card:
a static CPython 3.14.7 built with that repository's toolchain
(`card/userland/components/cpython.sh`), with psutil's C extension linked
into the interpreter (static musl has no `dlopen`), and glances,
defusedxml, packaging and jinja2 unpacked from their wheels into
`site-packages` (MarkupSafe from its sdist, pure-Python fallback).
Everything is restricted to the instruction subset the card executes (no
SSE, no CMOV, x87 floating point) and checked with `phi-isa-audit`.

## Build

Requirements: the Intel-Phi-3120A repository with its toolchain built and
its `zlib.sh` and `ncurses.sh` components run once; a host `python3` of
the same version as the target (3.14.7), which CPython's own build uses to
run its scripts. Then:

```
PHI_ROOT=~/Intel\ Phi\ 3120A ./build.sh
```

produces `build/glances-phi.tar.gz` (unpacks to `/opt/phi`: `bin/python3`,
`bin/glances`, `lib/python3.14` with the standard library and
`site-packages`). Package files are fetched from PyPI by exact name and
verified against `SHA256SUMS`. `build.sh` ends by importing psutil and
glances with the card interpreter on the host (card binaries run there
too) and printing the CPU count it sees.

## Run on the card

With the card booted through the main repository's tools:

```
./push.sh                                      # install and run glances --stdout on the card
ssh root@10.9.0.2 -t /opt/phi/bin/glances      # the full terminal UI
```

The terminal UI needs a terminal, so that is over SSH (dropbear on the
card, network bridge up) or the ring console; through the non-interactive
control socket, `glances --stdout FIELDS` and `--export` work as they do
anywhere. What glances shows: 228 CPUs (57 cores x 4 threads at 1.1 GHz,
no frequency or temperature sources), 5.7 GB of GDDR, no disks, one
network device (`phi0`, the ring), and the processes on the card.

## How psutil is linked in

`build.sh` writes a `Modules/Setup` fragment listing psutil's Linux sources
with its build macros and hands it to `cpython.sh`, which appends it to
`Setup.local` under `*static*`; the resulting built-in module is top-level
`_psutil_linux`, and a two-line `psutil/_psutil_linux.py` shim makes the
package-relative import resolve to it. No psutil source changes.

## Not included

`ssl`, `sqlite3`, `ctypes`, `bz2`, `lzma` and `zstd` are absent from the card
interpreter (no OpenSSL or sqlite for the card yet; libffi's x86-64 code
assumes SSE). glances' web server mode needs FastAPI and pydantic-core
(Rust), not attempted.

## Files

- `build.sh`: fetch, verify, build the interpreter with psutil, assemble
  site-packages, audit, package.
- `push.sh`: load onto a running card and run `glances --stdout` there.
- `patches/`: empty.
- `docs/results.md`: what was measured on the card.
