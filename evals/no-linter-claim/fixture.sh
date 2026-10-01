#!/bin/sh
# Copy the plugin's canonical proxy into the run's empty workspace (cwd).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
cp "$here/../../scripts/lib/guile-repl-proxy.scm" ./guile-repl-proxy.scm
