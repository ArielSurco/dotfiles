# pf — Kubernetes port-forwarding via HAProxy
# Forward ports from HAProxy service across clusters.
# Requires: kubectl, gum

_pf_get_ports() {
  local kube_ctx="$1"
  local raw_output
  raw_output=$(kubectl --context="$kube_ctx" -n haproxy describe service haproxy 2>/dev/null)
  if [[ $? -ne 0 || -z "$raw_output" ]]; then
    return 1
  fi

  echo "$raw_output" | awk '
    /Port:/ && !/NodePort:/ && !/TargetPort:/ {
      # Find field after "Port:" label — name is $(NF-1), number is $NF
      name = $(NF-1)
      split($NF, a, "/")
      if (name != "" && a[1] != "") print name "=" a[1]
    }
  '
}

pf() {
  if ! command -v kubectl &>/dev/null; then
    echo "pf: kubectl not found" >&2
    return 1
  fi
  if ! command -v gum &>/dev/null; then
    echo "pf: gum is required: brew install gum" >&2
    return 1
  fi
  if [[ -n "$3" ]]; then
    echo "Usage: pf [context] [port-name]" >&2
    return 1
  fi

  local kube_ctx="$1"
  local port_arg="$2"

  # Step 1: Resolve context
  if [[ -z "$kube_ctx" ]]; then
    local ctx_list
    ctx_list=$(kubectl config get-contexts -o name 2>/dev/null)
    if [[ -z "$ctx_list" ]]; then
      echo "pf: no kubectl contexts found" >&2
      return 1
    fi
    kube_ctx=$(echo "$ctx_list" | gum choose --header "Select context:")
    [[ -z "$kube_ctx" ]] && return 0
  fi

  # Step 2: Get ports
  echo "Fetching ports from haproxy ($kube_ctx)..."
  local port_data
  port_data=$(_pf_get_ports "$kube_ctx")
  if [[ -z "$port_data" ]]; then
    echo "pf: no ports found in haproxy service (context: $kube_ctx)" >&2
    return 1
  fi

  # Cache for tab completion
  [[ -d "$DOTFILES_DATA" ]] || mkdir -p "$DOTFILES_DATA"
  echo "$port_data" > "$DOTFILES_DATA/pf-ports-${kube_ctx}"

  # Step 3: Resolve port
  local pname pnum
  if [[ -n "$port_arg" ]]; then
    # Lookup port by name from fetched data
    local match
    match=$(echo "$port_data" | while IFS='=' read -r n v; do
      [[ "$n" == "$port_arg" ]] && echo "$v"
    done)
    if [[ -z "$match" ]]; then
      echo "pf: port '$port_arg' not found in haproxy service" >&2
      return 1
    fi
    pname="$port_arg"
    pnum="$match"
  else
    # Interactive selection
    local items=()
    local n v
    while IFS='=' read -r n v; do
      items+=("${n} (${v})")
    done <<< "$port_data"

    local selection
    selection=$(printf '%s\n' "${items[@]}" | gum choose --header "Select port ($kube_ctx):")
    [[ -z "$selection" ]] && return 0

    pname="${selection%% \(*}"
    pnum="${selection##*\(}"
    pnum="${pnum%)}"
  fi

  # Step 4: Connect
  echo "Forwarding $kube_ctx → haproxy:$pname on port $pnum"
  kubectl --context="$kube_ctx" port-forward -n haproxy svc/haproxy "${pnum}:${pnum}"
}

_pf_completions() {
  if [[ $CURRENT -eq 2 ]]; then
    # First arg: kubectl contexts
    local ctx_list
    ctx_list=$(kubectl config get-contexts -o name 2>/dev/null)
    if [[ -n "$ctx_list" ]]; then
      compadd ${(f)ctx_list}
    fi
  elif [[ $CURRENT -eq 3 ]]; then
    # Second arg: cached port names for the context in arg 1
    local kube_ctx="${words[2]}"
    local cachefile="$DOTFILES_DATA/pf-ports-${kube_ctx}"
    if [[ -f "$cachefile" ]]; then
      local port_names=()
      local n v
      while IFS='=' read -r n v; do
        port_names+=("$n")
      done < "$cachefile"
      compadd "${port_names[@]}"
    fi
  fi
}
compdef _pf_completions pf
