# dbs — Start local Docker database containers
# Ensures Docker daemon is running and starts all required containers.

dbs() {
  # Check Docker is available
  if ! command -v docker &>/dev/null; then
    echo "dbs: docker not found" >&2
    return 1
  fi

  # Start Docker daemon if not running
  if ! docker info &>/dev/null; then
    echo "Docker daemon not running, starting..."
    open -g -a Docker
    local elapsed=0
    while ! docker info &>/dev/null; do
      sleep 2
      (( elapsed += 2 ))
      if [[ $elapsed -ge 60 ]]; then
        echo "dbs: Docker daemon failed to start within 60s" >&2
        return 1
      fi
    done
    echo "Docker daemon ready"
  else
    echo "Docker daemon running"
  fi

  echo "Starting containers..."

  local containers=(
    fudo-redis
    fudo-memcached
    fudo-database
    fudo-database_payments
    db-shard-0-1
    db-shard-1-1
    db-accounts-1
    db-payments-1
  )

  local cname
  for cname in "${containers[@]}"; do
    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | command grep -q "^${cname}$"; then
      continue
    fi
    # Check if already running
    if docker ps -q -f "name=^${cname}$" | command grep -q .; then
      echo "  $cname: running"
    else
      if docker start "$cname" &>/dev/null; then
        echo "  $cname: started"
      else
        echo "  $cname: failed to start" >&2
      fi
    fi
  done

  echo "All databases ready"
}
