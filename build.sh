#!/usr/bin/env bash
# build.sh: glances for the Intel Xeon Phi 3120A (Knights Corner). Builds
# the card's CPython with psutil's C extension linked in (the interpreter
# is static; static musl has no dlopen), unpacks glances and its pure-Python
# dependencies into site-packages, adds a launcher, audits, packages.
# Requires the Intel-Phi-3120A repository with its toolchain and the zlib
# and ncurses components; set PHI_ROOT (default ~/Intel Phi 3120A).
# Output: build/glances-phi.tar.gz (installs /opt/phi: python3.14, glances).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
PHI_ROOT="${PHI_ROOT:-$HOME/Intel Phi 3120A}"
. "$PHI_ROOT/toolchain/env.sh"
DL="$here/build/downloads"
mkdir -p "$DL"
PSUTIL_VER="${PSUTIL_VERSION:-7.2.2}"
GLANCES_VER="${GLANCES_VERSION:-4.5.6}"
DEFUSEDXML_VER="${DEFUSEDXML_VERSION:-0.7.1}"
PACKAGING_VER="${PACKAGING_VERSION:-26.3}"
JINJA2_VER="${JINJA2_VERSION:-3.1.6}"
MARKUPSAFE_VER="${MARKUPSAFE_VERSION:-3.0.3}"
AUDIT="$PHI_ROOT/host/target/debug/phi-isa-audit"

# One PyPI file by exact name, verified against SHA256SUMS in this repo.
fetch() {
    local pkg="$1" ver="$2" name="$3"
    if [ ! -s "$DL/$name" ]; then
        local url
        url=$(curl -fsSL "https://pypi.org/pypi/$pkg/$ver/json" | grep -oE "https://files\.pythonhosted\.org/packages/[^\"]*/$name" | head -1)
        [ -n "$url" ] || { echo "build.sh: no $name on PyPI" >&2; exit 1; }
        echo "== fetching $name"
        curl -fsSL -o "$DL/$name" "$url"
    fi
    local sum; sum=$(sha256sum "$DL/$name" | awk '{print $1}')
    if grep -q " $name\$" "$here/SHA256SUMS" 2>/dev/null; then
        [ "$(grep " $name\$" "$here/SHA256SUMS" | awk '{print $1}')" = "$sum" ] || { echo "SHA-256 mismatch for $name" >&2; exit 1; }
    else
        echo "$sum  $name" >> "$here/SHA256SUMS"
    fi
}
fetch psutil "$PSUTIL_VER" "psutil-$PSUTIL_VER.tar.gz"
fetch glances "$GLANCES_VER" "glances-$GLANCES_VER-py3-none-any.whl"
fetch defusedxml "$DEFUSEDXML_VER" "defusedxml-$DEFUSEDXML_VER-py2.py3-none-any.whl"
fetch packaging "$PACKAGING_VER" "packaging-$PACKAGING_VER-py3-none-any.whl"
# glances 4.5 imports jinja2 at module level (its "fetch" output), though
# its metadata does not require it; MarkupSafe comes from the sdist for its
# pure-Python fallback (the C speedup is left out).
fetch jinja2 "$JINJA2_VER" "jinja2-$JINJA2_VER-py3-none-any.whl"
fetch markupsafe "$MARKUPSAFE_VER" "markupsafe-$MARKUPSAFE_VER.tar.gz"

# 1. psutil's C extension as a built-in module of the card interpreter.
#    The module name in Modules/Setup must be a plain identifier, so it is
#    built as top-level _psutil_linux; psutil/_psutil_linux.py (below)
#    redirects the package-relative import to it.
PS="$here/build/psutil-$PSUTIL_VER"
rm -rf "$PS"; mkdir -p "$PS"
tar -xzf "$DL/psutil-$PSUTIL_VER.tar.gz" -C "$PS" --strip-components=1
srcs=$(cd "$PS/psutil" && ls _psutil_linux.c arch/all/*.c arch/posix/*.c arch/linux/*.c | sed 's#^#psutil-src/#' | tr '\n' ' ')
# makesetup takes any line containing "=" for a Makefile variable, so the
# macros go into one (that is what a variable line is for) and the module
# line refers to it.
{
    printf 'PSUTIL_CFLAGS=-D_GNU_SOURCE -DPSUTIL_POSIX=1 -DPSUTIL_LINUX=1 -DPSUTIL_SIZEOF_PID_T=4 -DPSUTIL_VERSION=%s\n' "$(echo "$PSUTIL_VER" | tr -d .)"
    printf '_psutil_linux %s -I$(srcdir)/Modules/psutil-src $(PSUTIL_CFLAGS)\n' "$srcs"
} > "$here/build/Setup.psutil"
rm -rf "$here/build/psutil-src"; cp -a "$PS/psutil" "$here/build/psutil-src"
for p in "$here"/patches/*.patch; do [ -e "$p" ] && (cd "$PS" && patch -p1 < "$p"); done
echo "== CPython with psutil built in (Intel-Phi-3120A/card/userland/components/cpython.sh)"
PHI_PYTHON_SETUP="$here/build/Setup.psutil" PHI_PYTHON_EXTRA_SRC="$here/build/psutil-src" \
    bash "$PHI_ROOT/card/userland/components/cpython.sh" > "$here/build/cpython.log" 2>&1 || { tail -20 "$here/build/cpython.log"; exit 1; }
PYROOT="$PHI_ROOT/card/userland/build/cpython/root"
PYVER=$(ls "$PYROOT/opt/phi/lib" | grep -o 'python3\.[0-9]*' | head -1)
SITE="$PYROOT/opt/phi/lib/$PYVER/site-packages"

# 2. Pure-Python packages: wheels are zip files, no pip needed.
rm -rf "$SITE"; mkdir -p "$SITE"
for w in "glances-$GLANCES_VER-py3-none-any.whl" "defusedxml-$DEFUSEDXML_VER-py2.py3-none-any.whl" "packaging-$PACKAGING_VER-py3-none-any.whl" "jinja2-$JINJA2_VER-py3-none-any.whl"; do
    unzip -q -o "$DL/$w" -d "$SITE"
done
tar -xzf "$DL/markupsafe-$MARKUPSAFE_VER.tar.gz" -C "$here/build" "markupsafe-$MARKUPSAFE_VER/src/markupsafe"
cp -a "$here/build/markupsafe-$MARKUPSAFE_VER/src/markupsafe" "$SITE/markupsafe"
rm -f "$SITE/markupsafe/_speedups.c" "$SITE/markupsafe/_speedups.pyi"
cp -a "$PS/psutil" "$SITE/psutil"
rm -rf "$SITE/psutil/tests" "$SITE"/psutil/*.c "$SITE"/psutil/arch
cat > "$SITE/psutil/_psutil_linux.py" <<'PY'
# The C extension is a built-in module of this interpreter (top-level
# _psutil_linux); make the package-relative import find it.
import sys as _sys
_sys.modules[__name__] = __import__("_psutil_linux")
PY
mkdir -p "$PYROOT/opt/phi/bin"
cat > "$PYROOT/opt/phi/bin/glances" <<'SH'
#!/bin/sh
# glances on the card: the static interpreter with psutil built in.
export TERM="${TERM:-xterm-256color}"
exec /opt/phi/bin/python3 -m glances "$@"
SH
chmod 755 "$PYROOT/opt/phi/bin/glances"
[ -e "$PYROOT/opt/phi/bin/python3" ] || ln -s "$PYVER" "$PYROOT/opt/phi/bin/python3"
"$PHI_ROOT/toolchain/build/llvm/bin/llvm-strip" "$PYROOT/opt/phi/bin/$PYVER" 2>/dev/null || true
echo "== audit (must be clean)"
"$AUDIT" "$PYROOT/opt/phi/bin/$PYVER" | tail -1
echo "== glances imports on the host with the card interpreter"
PYTHONHOME="$PYROOT/opt/phi" "$PYROOT/opt/phi/bin/$PYVER" -c 'import psutil, glances, defusedxml, packaging, jinja2, markupsafe; print("psutil", psutil.__version__, "cpus", psutil.cpu_count(), "glances", glances.__version__)'
rm -rf "$here/build/root"; mkdir -p "$here/build/root"
cp -a "$PYROOT/opt" "$here/build/root/opt"
(cd "$here/build/root" && tar -czf "$here/build/glances-phi.tar.gz" opt)
ls -l "$here/build/glances-phi.tar.gz"; du -sh "$here/build/root/opt/phi" | cut -f1
