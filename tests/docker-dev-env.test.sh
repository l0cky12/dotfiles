#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/hypr/.config/hypr/scripts/docker-dev-env"
compose_file="$repo_root/hypr/.config/hypr/docker-dev-env/compose.yaml"
menu="$repo_root/menu/.config/lmenu/menu.jsonc"
test_root=$(mktemp -d -t docker-dev-env.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"; }

mkdir -p "$test_root/bin" "$test_root/home" "$test_root/state"
calls="$test_root/calls"
running="$test_root/running"
: >"$calls"
: >"$running"

cat >"$test_root/bin/docker" <<'SH'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$DOCKER_DEV_TEST_CALLS"
case " $* " in
  *' compose version '*) printf 'Docker Compose fixture\n' ;;
  *' info '*) exit 0 ;;
  *' ps --status running --services '*)
    service=${*: -1}
    grep -Fxq "$service" "$DOCKER_DEV_TEST_RUNNING" && printf '%s\n' "$service"
    ;;
  *' up --detach --wait --wait-timeout 90 '*)
    service=${*: -1}
    grep -Fxq "$service" "$DOCKER_DEV_TEST_RUNNING" || printf '%s\n' "$service" >>"$DOCKER_DEV_TEST_RUNNING"
    ;;
  *' stop '*)
    service=${*: -1}
    grep -Fxv "$service" "$DOCKER_DEV_TEST_RUNNING" >"$DOCKER_DEV_TEST_RUNNING.tmp" || true
    mv "$DOCKER_DEV_TEST_RUNNING.tmp" "$DOCKER_DEV_TEST_RUNNING"
    ;;
  *' down '*) : >"$DOCKER_DEV_TEST_RUNNING" ;;
esac
SH

cat >"$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf 'notify %s\n' "$*" >>"$DOCKER_DEV_TEST_CALLS"
SH
chmod +x "$test_root/bin/docker" "$test_root/bin/notify-send"

run() {
  HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" \
    DOCKER="$test_root/bin/docker" NOTIFY_SEND="$test_root/bin/notify-send" \
    DOCKER_DEV_COMPOSE_FILE="$compose_file" DOCKER_DEV_TEST_CALLS="$calls" \
    DOCKER_DEV_TEST_RUNNING="$running" "$helper" "$@"
}

dry_output=$(run --dry-run up mysql)
[[ $dry_output == *'up --detach --wait --wait-timeout 90 mysql'* ]] || fail 'dry-run did not plan MySQL startup'
[[ ! -e $test_root/state/docker-dev-env ]] || fail 'dry-run created state'

run up mysql >/dev/null
environment_file="$test_root/state/docker-dev-env/environment.env"
[[ -f $environment_file ]] || fail 'startup did not create credentials'
[[ $(stat -c '%a' "$environment_file") == 600 ]] || fail 'credentials are not mode 600'
[[ $(run status mysql) == running ]] || fail 'MySQL did not become running'
run status postgres >/dev/null 2>&1 && fail 'a stopped PostgreSQL service reported running'

info=$(run info)
grep -Eq '^MySQL: +mysql://developer:[0-9a-f]+@127\.0\.0\.1:3306/development$' <<<"$info" || fail 'MySQL URL is invalid'
grep -Eq '^PostgreSQL: postgresql://developer:[0-9a-f]+@127\.0\.0\.1:5432/development$' <<<"$info" || fail 'PostgreSQL URL is invalid'
grep -Eq '^Redis: +redis://:[0-9a-f]+@127\.0\.0\.1:6379/0$' <<<"$info" || fail 'Redis URL is invalid'

run toggle mysql >/dev/null
run status mysql >/dev/null 2>&1 && fail 'toggle did not stop MySQL'
run up postgres >/dev/null
run stop-all >/dev/null
[[ ! -s $running ]] || fail 'stop-all left a service running'

# shellcheck disable=SC2016 # These are literal Compose interpolation expressions.
assert_contains "$compose_file" '127.0.0.1:${MYSQL_PORT:-3306}:3306'
# shellcheck disable=SC2016
assert_contains "$compose_file" '127.0.0.1:${POSTGRES_PORT:-5432}:5432'
# shellcheck disable=SC2016
assert_contains "$compose_file" '127.0.0.1:${MARIADB_PORT:-3307}:3306'
# shellcheck disable=SC2016
assert_contains "$compose_file" '127.0.0.1:${REDIS_PORT:-6379}:6379'
! grep -Eq 'restart:|container_name:' "$compose_file" || fail 'development containers would restart or claim global names'

grep -Fq '"id": "development"' "$menu" || fail 'Development is missing from the root menu'
grep -Fq '"id": "development.docker.mysql"' "$menu" || fail 'MySQL is missing from Development'
grep -Fq 'docker-dev-env toggle mysql' "$menu" || fail 'MySQL menu action is not wired to the helper'
grep -Fq 'docker-dev-env stop-all' "$menu" || fail 'stop-all is missing from Development'

# Real Compose parsing does not contact the daemon or pull images.
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose --env-file "$environment_file" --file "$compose_file" config --quiet
fi

printf 'ok: docker development environments\n'
