#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
JAR="$ROOT/private/approval-probe-20261123/lib/nimbus-jose-jwt-10.10.jar"
if [[ ! -f "$JAR" ]]; then
  printf 'Missing parent-supplied Nimbus 10.10 jar: %s\n' "$JAR" >&2
  exit 1
fi
OUT="$(mktemp -d "$ROOT/tools/approval-probe/tests/.protocol-classes.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT
if [[ -z "${JAVA_HOME:-}" && -x /usr/libexec/java_home ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 17)"
fi
if [[ -n "${JAVA_HOME:-}" ]]; then
  JAVAC="$JAVA_HOME/bin/javac"
  JAVA="$JAVA_HOME/bin/java"
else
  JAVAC=javac
  JAVA=java
fi
"$JAVAC" --release 8 -Xlint:all -Werror -cp "$JAR" -d "$OUT" \
  "$ROOT/tools/approval-probe/src/org/plf02wh/approvalprobe/ApprovalProtocol.java" \
  "$ROOT/tools/approval-probe/src/org/plf02wh/approvalprobe/ProtocolJson.java" \
  "$ROOT/tools/approval-probe/tests/"*.java
"$JAVA" -cp "$JAR:$OUT" org.plf02wh.approvalprobe.ApprovalProtocolTest
