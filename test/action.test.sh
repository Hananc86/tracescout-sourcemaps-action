#!/usr/bin/env bash
# GitHub Action tests — run the composite's run.sh locally exactly as Actions
# would (env-driven), against a mock API + the LOCAL CLI (npx replaced by a
# wrapper so no registry fetch). Covers: secret handling, success summary,
# typed failure annotation, retries, dry-run, multi-artifact upload.
set -uo pipefail
cd "$(dirname "$0")/.."
PASS=0; FAIL=0
ok(){ echo "PASS $1"; PASS=$((PASS+1)); }
bad(){ echo "FAIL $1"; FAIL=$((FAIL+1)); }

# fake npx that routes to the local CLI bin
BINDIR=$(mktemp -d)
cat > "$BINDIR/npx" <<SH
#!/usr/bin/env bash
shift 2 2>/dev/null # drop --yes @tracescout/cli@latest
exec node /root/sdk-b3/cli/bin/tracescout.js "\$@"
SH
# npx wrapper: args are: --yes @tracescout/cli@<v> <cli args...>
cat > "$BINDIR/npx" <<'SH'
#!/usr/bin/env bash
args=("$@")
out=()
skip=0
for a in "${args[@]}"; do
  if [ "$a" = "--yes" ]; then continue; fi
  if [[ "$a" == @tracescout/cli@* ]]; then continue; fi
  out+=("$a")
done
exec node /root/sdk-b3/cli/bin/tracescout.js "${out[@]}"
SH
chmod +x "$BINDIR/npx"
export PATH="$BINDIR:$PATH"

# fixture with 2 maps
FIX=$(mktemp -d)
for i in 0 1; do
  echo "console.log($i)" > "$FIX/c$i.js"
  echo "{\"version\":3,\"file\":\"c$i.js\",\"names\":[],\"mappings\":\"AAAA\",\"sources\":[\"../s$i.ts\"],\"sourcesContent\":[\"SECRET_SRC_$i\"]}" > "$FIX/c$i.js.map"
done
node /root/sdk-b3/cli/bin/tracescout.js sourcemaps inject --path "$FIX" >/dev/null

# mock API
node -e '
const http=require("http");
let mode=process.argv[1];
const srv=http.createServer((q,s)=>{ 
  if(mode==="fail" && q.url.includes("c0")){s.writeHead(409);s.end(JSON.stringify({status:"conflict",code:"identity_conflict"}));return;}
  s.writeHead(200);s.end(JSON.stringify({status:"valid",idempotent:false,artifact:{id:"a"}}));
});
srv.listen(18844,"127.0.0.1",()=>console.log("up"));
process.on("SIGTERM",()=>process.exit(0));
' ok & API_PID=$!
sleep 1

runAction(){ # $1=dry $2=summaryfile
  TRACESCOUT_AUTH_TOKEN="tsk_sm_ACTION_SECRET_TOKEN" \
  TRACESCOUT_API_URL="http://127.0.0.1:18844" \
  TS_PROJECT="proj-1" TS_RELEASE="act-r1" TS_DIST="web" TS_PATH="$FIX" \
  TS_URL_PREFIX="~/assets" TS_POLICY="" TS_DRY_RUN="$1" TS_RETRIES="2" \
  TS_CLI_VERSION="latest" TS_ACTION_DIR="$(pwd)" \
  GITHUB_STEP_SUMMARY="$2" bash ./run.sh 2>&1
}

# 1) dry-run
S1=$(mktemp)
OUT=$(runAction true "$S1"); CODE=$?
[ $CODE -eq 0 ] && ok "dry-run exit 0" || bad "dry-run exit $CODE"
grep -q "planned" "$S1" && ok "dry-run summary lists planned artifacts" || bad "dry-run summary"
echo "$OUT" | grep -q "ACTION_SECRET" && bad "token leaked in dry-run output" || ok "no token in dry-run output"

# 2) success multi-artifact
S2=$(mktemp)
OUT=$(runAction false "$S2"); CODE=$?
[ $CODE -eq 0 ] && ok "success exit 0" || bad "success exit $CODE"
grep -q "uploaded: \*\*2\*\*" "$S2" && ok "summary shows 2 uploads" || bad "summary uploads: $(cat $S2)"
echo "$OUT" | grep -q "ACTION_SECRET" && bad "token leaked" || ok "no token in success output"
echo "$OUT$(cat $S2)" | grep -q "SECRET_SRC" && bad "source content leaked" || ok "no source content in output/summary"

# 3) typed failure annotation (restart API in fail mode)
kill $API_PID 2>/dev/null; wait $API_PID 2>/dev/null
node -e '
const http=require("http");
const srv=http.createServer((q,s)=>{ 
  if(q.url.includes("c0")){s.writeHead(409);s.end(JSON.stringify({status:"conflict",code:"identity_conflict"}));return;}
  s.writeHead(200);s.end(JSON.stringify({status:"valid",idempotent:true,artifact:{id:"a"}}));
});
srv.listen(18844,"127.0.0.1",()=>console.log("up"));
' & API_PID=$!
sleep 1
S3=$(mktemp)
OUT=$(runAction false "$S3"); CODE=$?
[ $CODE -eq 1 ] && ok "partial failure exit 1" || bad "partial failure exit $CODE"
echo "$OUT" | grep -q "::error title=TraceScout upload identity_conflict::" && ok "typed ::error annotation" || bad "annotation missing"
grep -q "identity_conflict" "$S3" && ok "summary carries the typed code" || bad "summary code"

kill $API_PID 2>/dev/null
echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
