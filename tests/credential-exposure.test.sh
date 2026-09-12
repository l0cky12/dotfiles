#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
assistant_root="$repo_root/noctalia/.config/noctalia/plugins/assistant-panel"
annotate="$repo_root/noctalia/.config/noctalia/plugins/screen-toolkit/overlays/Annotate.qml"
share_script="$repo_root/noctalia/.config/noctalia/plugins/screen-toolkit/scripts/share-upload.sh"
test_root=$(mktemp -d -t credential-exposure.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_absent() {
    local path=$1 pattern=$2
    ! grep -Eq -- "$pattern" "$path" || fail "$path contains forbidden pattern: $pattern"
}

assert_present() {
    local path=$1 pattern=$2
    grep -Eq -- "$pattern" "$path" || fail "$path is missing required pattern: $pattern"
}

# Fail closed if provider URLs regain key parameters or sensitive values are logged.
assert_absent "$assistant_root/Main.qml" '\?[^"[:space:]]*key=\{apiKey\}'
if grep -REn --include='*.qml' --include='*.js' \
    '(console\.log|Logger\.[A-Za-z]+).*([?&]key=|commandData\.url)' "$assistant_root"; then
    fail "assistant-panel logs a credential-bearing provider URL"
fi
assert_absent "$assistant_root/Main.qml" 'Logger\.[A-Za-z]+\(.*userMessage'

# All assistant-panel curl builders must keep payloads and authorization out of argv.
node - "$assistant_root/ProviderLogic.js" <<'NODE'
const fs = require("fs");
const vm = require("vm");

const source = fs.readFileSync(process.argv[2], "utf8").replace(/^\.pragma library\s*/, "");
const logic = {};
vm.createContext(logic);
vm.runInContext(source, logic);

const secret = "fixture-secret-SEC03";
const content = "fixture chat content SEC03";
const cases = [
  logic.buildGeminiCommand(
    "https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse",
    "fixture-model", secret, "system " + content,
    [{role: "user", content}], 0.5),
  logic.buildOpenAICommand(
    "https://api.example.test/v1/chat/completions", secret, "fixture-model",
    "system " + content, [{role: "user", content}], 0.5),
  logic.buildGoogleTranslateCommand(content, "de", "en"),
  logic.buildDeepLTranslateCommand(content, "de", secret),
];

for (const request of cases) {
  const argv = request.args.join(" ");
  if (request.args.join("\0") !== "curl\0--config\0-")
    throw new Error("curl request is not config-over-stdin only: " + argv);
  if (argv.includes(secret) || argv.includes(content))
    throw new Error("credential or content leaked into argv: " + argv);
  if (!request.stdin || !request.stdin.includes(content.replaceAll(" ", "%20")) &&
      !request.stdin.includes(content))
    throw new Error("request payload was not delivered through stdin");
}

if (!cases[0].stdin.includes("x-goog-api-key: " + secret))
  throw new Error("Gemini API key is not sent as an stdin-delivered header");
if (!cases[1].stdin.includes("Authorization: Bearer " + secret))
  throw new Error("OpenAI authorization is not delivered through stdin");
if (!cases[3].stdin.includes("Authorization: DeepL-Auth-Key " + secret))
  throw new Error("DeepL authorization is not delivered through stdin");
NODE

# The QML caller writes the X02 key to stdin, and the script reads it there.
assert_absent "$annotate" 'command: \[[^]]*apiKey'
assert_present "$annotate" 'uploadProc\.write\(apiKey \+ "\\n"\)'
assert_absent "$share_script" 'API_KEY="\$\{[0-9]'
assert_absent "$share_script" '(-H|--header)[[:space:]]+"x-api-key:'
assert_present "$share_script" 'read -r API_KEY'
assert_present "$share_script" '--header @-'

# Exercise the X02 path with a curl fixture and inspect its argv and stdin.
mkdir -p "$test_root/bin"
cat >"$test_root/bin/curl" <<'CURL_FIXTURE'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CURL_ARGS"
cat >"$CURL_STDIN"
printf '%s\n' 'https://fixture.example/upload'
CURL_FIXTURE
chmod +x "$test_root/bin/curl"
printf 'png' >"$test_root/image.png"

PATH="$test_root/bin:$PATH" \
CURL_ARGS="$test_root/curl.args" \
CURL_STDIN="$test_root/curl.stdin" \
  "$share_script" "$test_root/image.png" 7d \
  <<<'fixture-x02-key-SEC03' >"$test_root/result"

assert_absent "$test_root/curl.args" 'fixture-x02-key-SEC03'
assert_present "$test_root/curl.args" '^@-$'
assert_present "$test_root/curl.stdin" '^x-api-key: fixture-x02-key-SEC03$'
assert_present "$test_root/result" '^https://fixture\.example/upload$'

printf 'ok: credentials and request content are delivered through stdin, not argv or logs\n'
