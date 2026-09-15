# Results

## 2026-09-14: first build and first run on the card

Toolchain: Intel-Phi-3120A at commit `b0590b0` (clang 22 patched for the
knc64-x87 ABI, musl, zlib 1.3.1, ncurses 6.5 wide with fallbacks, CPython
3.14.7 static). Card: mainline Linux 7.2.3 with 23 patches, 228 CPUs,
booted unattended with the main repository's `scripts/phi-up.sh`.

### Build

- CPython configured cross with `MODULE_BUILDTYPE=static`, no mimalloc
  (its spin loop is an inline-assembly `pause`), no `_hmac` (duplicate
  HACL* objects in a static link), HACL* SIMD variants off (compile tests
  answered through cache variables), pkg-config confined to the sysroot.
- psutil 7.2.2's C extension linked in as the built-in module
  `_psutil_linux` from a generated `Setup` fragment (macros through a
  Makefile variable line, since `makesetup` takes any line containing
  `=` for one), with a two-line shim for the package-relative import.
- glances 4.5.6, defusedxml 0.7.1, packaging 26.3 and jinja2 3.1.6 from
  their wheels, MarkupSafe 3.0.3 from its sdist (pure-Python fallback).
  jinja2 is not in glances' declared requirements but is imported at
  module level by its "fetch" output.
- Audit of the interpreter: 1184903 instructions, 0 illegal, 0 suspect.
- Package: 21.5 MB tarball, 66 MB unpacked as `/opt/phi`.
- On the host, the card interpreter imports psutil and glances and reports
  the host's 16 CPUs.

### On the card

`./push.sh` (21.5 MB through the control socket, unpack, import check,
then `glances --stdout`):

```
psutil 7.2.2 cpus 228 glances 4.5.6
cpu.user: 0.3
cpu.system: 0.1
load.min1: 0.51806640625
mem.used: 507125760
mem.total: 5959094272
```

psutil on the card: `cpu_count 228`, per-CPU percentages for all 228,
5683 MB, 1483 pids. The curses interface, started on the console tty with
a window size set (`stty rows 50 cols 160`), ran until the test timeout
and stopped gracefully; its log shows every plugin initialised and the IP
plugin reporting `10.9.0.2/24`. Its screen was not recovered as text from
the console log (the curses drawing is positioned cell by cell); Python's
curses itself was verified on the same tty with a test string that did
appear in the log.
Interactive use is over SSH (`ssh root@10.9.0.2 -t /opt/phi/bin/glances`)
once the network bridge is up. The web server mode is not built (FastAPI
and pydantic-core would be needed).
