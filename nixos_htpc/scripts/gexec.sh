#!/bin/bash
# usage: gexec.sh DOMAIN 'shell command'
dom=$1; shift
pid=$(virsh qemu-agent-command "$dom" "$(python3 -c 'import json,sys;print(json.dumps({"execute":"guest-exec","arguments":{"path":"/bin/sh","arg":["-c",sys.argv[1]],"capture-output":True}}))' "$*")" | python3 -c 'import json,sys;print(json.load(sys.stdin)["return"]["pid"])')
for i in $(seq 1 600); do
  r=$(virsh qemu-agent-command "$dom" "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}")
  if echo "$r" | grep -q '"exited":true'; then
    echo "$r" | python3 -c 'import json,sys,base64;d=json.load(sys.stdin)["return"];sys.stdout.write(base64.b64decode(d.get("out-data","")).decode(errors="replace"));sys.stderr.write(base64.b64decode(d.get("err-data","")).decode(errors="replace"));sys.exit(d.get("exitcode",0))'
    exit $?
  fi
  sleep 1
done
echo timeout >&2; exit 124
