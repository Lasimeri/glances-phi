#!/usr/bin/env bash
# push.sh: load build/glances-phi.tar.gz onto the running card through the
# main repository's control socket and run glances in its stdout mode, which
# needs no terminal. Interactive use: ssh root@10.9.0.2 -t /opt/phi/bin/glances
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
PHI_ROOT="${PHI_ROOT:-$HOME/Intel Phi 3120A}"
P="$PHI_ROOT/host/target/debug/phictl"
PKG="$here/build/glances-phi.tar.gz"
[ -s "$PKG" ] || { echo "push.sh: $PKG missing; run build.sh" >&2; exit 1; }
"$P" status
"$P" put "$PKG" /tmp/glances-phi.tar.gz
"$P" exec -- sh -c 'cd / && tar -xzf /tmp/glances-phi.tar.gz && rm /tmp/glances-phi.tar.gz && /opt/phi/bin/python3 -c "import psutil, glances; print(\"psutil\", psutil.__version__, \"cpus\", psutil.cpu_count(), \"glances\", glances.__version__)"'
"$P" exec -- sh -c '/opt/phi/bin/glances --stdout cpu.user,cpu.system,load.min1,mem.used,mem.total --time 2 --stop-after 2'
