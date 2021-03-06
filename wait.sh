#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:-$(basename "${PWD}" | sed 's/[\w.-]//g')}

function ping() {
  local connect_timeout=2
  local string=greenpeace

  local network=${PROJECT}_proxy
  local endpoint=${APP_HOSTNAME:-http://www.planet4.test}

  if [[ -n "${APP_HOSTPATH:-}" ]]
  then
    endpoint="$endpoint/$APP_HOSTPATH/"
  fi

  if docker run --network "$network" --rm appropriate/curl --connect-timeout $connect_timeout -s -k "$endpoint" | grep -s "$string" > /dev/null
  then
    success=$((success+1))
    echo -en "\\xE2\\x9C\\x94"
  else
    echo -n "."
    success=0
  fi
}

function check_services() {
  local services=(
    "openresty"
    "php-fpm"
    "db"
    "redis"
  )
  for s in "${services[@]}"
  do
    if ! grep -q "$(docker-compose -p "${PROJECT}" ps -q "$s")" <<< "$(docker ps -q --no-trunc)"
    then
      echo
      docker ps -a | >&2 grep -E "Exited"
      echo
      docker-compose -p "${PROJECT}" logs "$s" | >&2 tail -20
      echo
      >&2 echo "ERROR: $s is not running"
      echo
      return 1
    fi
  done
}

function main() {
  # ~6 seconds * 100 == 10+ minutes
  # Actual interval varies depending on platform due to docker calls
  local interval=1
  local loop=120

  # Number of consecutive successes to qualify as 'up'
  local threshold=3
  local success=0

  echo
  echo "Starting P4 Wordpress docker-compose stack."
  echo "Note, this may take up to 10 minutes on the first run!"
  echo
  printf "Waiting for services to start "

  until [[ $success -ge $threshold ]]
  do
    ping
    check_services

    loop=$((loop-1))
    if [[ $loop -lt 1 ]]
    then
      >&2 echo "[ERROR] Timeout waiting for docker-compose to start"
      >&2 docker-compose -p "${PROJECT}" logs
      return 1
    fi

    [[ $success -ge $threshold ]] || sleep $interval
  done

  echo
  echo "Services started successfully"
}

main
