#!/usr/bin/env bash
# ai-agent picks an agent from --agent, AI_AGENT_DEFAULT or its config and
# execs it. Every agent here is a stub on a fixture PATH that records how it
# was called; nothing real is launched.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
launcher="$repo_root/ai/.local/bin/ai-agent"
test_root=$(mktemp -d -t ai-agent-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

bin="$test_root/bin"
log="$test_root/calls.log"
config="$test_root/config"
mkdir -p "$bin"
for program in teamclaude codex webapp-launch; do
  printf '#!/bin/sh\necho "%s $*" >>"%s"\n' "$program" "$log" >"$bin/$program"
  chmod +x "$bin/$program"
done

run() {
  env -i HOME="$test_root" PATH="$bin:/usr/bin:/bin" AI_AGENT_CONFIG="$config" \
    "$launcher" "$@"
}
last_call() {
  tail -n 1 "$log"
}

# The config's default, including a web app.
printf '# comment\ndefault_agent=webapp:chatgpt\n' >"$config"
run
[[ $(last_call) == 'webapp-launch chatgpt' ]] || fail "web app default launched: $(last_call)"

# --agent overrides the config; built-in agents are unchanged.
run --agent codex -- --help
[[ $(last_call) == 'codex --help' ]] || fail "codex was launched as: $(last_call)"
run --agent claude
[[ $(last_call) == 'teamclaude run --' ]] || fail "claude was launched as: $(last_call)"
run --agent=webapp:claude-ai
[[ $(last_call) == 'webapp-launch claude-ai' ]] || fail "--agent=webapp:ID launched: $(last_call)"

# A web app id must be a slug, and web apps take no agent arguments.
calls_before=$(wc -l <"$log")
for bad in 'webapp:' 'webapp:../etc' 'webapp:Chat_GPT' 'webapp:-x' 'webapp:a b'; do
  if run --agent "$bad" 2>"$test_root/err"; then
    fail "an invalid web app id was accepted: $bad"
  fi
  grep -Fq 'invalid web app id' "$test_root/err" || fail "no id error for $bad"
done
if run --agent webapp:chatgpt -- --flag 2>"$test_root/err"; then
  fail 'a web app agent accepted arguments'
fi
grep -Fq 'take no arguments' "$test_root/err" || fail 'argument refusal did not explain itself'

# Unknown agents name webapp:ID in the error; a missing launcher is reported.
if run --agent nope 2>"$test_root/err"; then
  fail 'an unknown agent was accepted'
fi
grep -Fq 'or webapp:ID' "$test_root/err" || fail 'unknown-agent error does not mention webapp:ID'
rm "$bin/webapp-launch"
if run 2>"$test_root/err"; then
  fail 'a web app agent ran without webapp-launch'
fi
grep -Fq "executable 'webapp-launch' was not found" "$test_root/err" ||
  fail 'missing webapp-launch was not reported'
[[ $(wc -l <"$log") == "$calls_before" ]] || fail 'a refused invocation still launched something'

printf 'ok: ai-agent\n'
