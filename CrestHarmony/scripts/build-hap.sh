#!/usr/bin/env bash
set -euo pipefail
crest_harmony_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$crest_harmony_root"
crest_hvigor="${CREST_HVIGORW:-}"
if [[ -z "$crest_hvigor" ]]; then
  crest_hvigor="$(command -v hvigorw || true)"
fi
# Use the official macOS installation when no custom toolchain was selected.
crest_deveco_contents='/Applications/DevEco-Studio.app/Contents'
if [[ -z "$crest_hvigor" && -f "$crest_deveco_contents/tools/hvigor/bin/hvigorw" ]]; then
  crest_hvigor="$crest_deveco_contents/tools/hvigor/bin/hvigorw"
  export NODE_HOME="${NODE_HOME:-$crest_deveco_contents/tools/node}"
  export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$crest_deveco_contents/sdk}"
fi
if [[ -z "$crest_hvigor" || ! -f "$crest_hvigor" ]]; then
  echo 'HAP build blocked: DevEco Studio / Hvigor not found.' >&2
  echo 'Install official DevEco Studio with its bundled HarmonyOS SDK, import this project, and build in the IDE.' >&2
  echo 'For command-line use, set CREST_HVIGORW to the installed hvigorw path and configure the SDK as documented by Huawei.' >&2
  exit 2
fi
"$crest_hvigor" --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
