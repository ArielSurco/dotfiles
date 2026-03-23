# pod — Interactive Kubernetes pod connector
# Connect to any pod across clusters with context and namespace selection.
# Requires: kubectl, gum

pod() {
  # Check dependencies
  if ! command -v kubectl &>/dev/null; then
    echo "kubectl not found. Install: https://kubernetes.io/docs/tasks/tools/" >&2
    return 1
  fi
  if ! command -v gum &>/dev/null; then
    echo "gum not found. Install: brew install gum" >&2
    return 1
  fi

  # Validate arg count
  if [[ -n "$3" ]]; then
    echo "Usage: pod [context] [namespace]" >&2
    return 1
  fi

  local kube_ctx="$1"
  local kube_ns="$2"

  # Step 1: Resolve context
  if [[ -z "$kube_ctx" ]]; then
    local ctx_list
    ctx_list=$(kubectl config get-contexts -o name 2>/dev/null)
    if [[ -z "$ctx_list" ]]; then
      echo "pod: no kubectl contexts found" >&2
      return 1
    fi
    kube_ctx=$(echo "$ctx_list" | gum choose --header "Select context")
    [[ -z "$kube_ctx" ]] && return 1
  fi

  # Step 2: Resolve namespace
  if [[ -z "$kube_ns" ]]; then
    echo -n "Namespace ($kube_ctx): "
    read -r kube_ns
    if [[ -z "$kube_ns" ]]; then
      echo "No namespace provided" >&2
      return 1
    fi
  fi

  # Step 3: List and choose pod
  local pod_list
  pod_list=$(kubectl --context="$kube_ctx" -n "$kube_ns" get pods --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    echo "Failed to list pods in $kube_ns (context: $kube_ctx)" >&2
    return 1
  fi
  if [[ -z "$pod_list" ]]; then
    echo "No pods found in $kube_ns (context: $kube_ctx)" >&2
    return 1
  fi

  local pod_name
  pod_name=$(echo "$pod_list" | gum choose --header "Select pod ($kube_ctx/$kube_ns):")
  [[ -z "$pod_name" ]] && return 1

  # Step 4: Connect
  echo "Connecting to $pod_name..."
  kubectl --context="$kube_ctx" -n "$kube_ns" exec -it "$pod_name" -- bash
}

_pod_completions() {
  if [[ $CURRENT -eq 2 ]]; then
    local ctx_list
    ctx_list=$(kubectl config get-contexts -o name 2>/dev/null)
    if [[ -n "$ctx_list" ]]; then
      compadd ${(f)ctx_list}
    fi
  fi
}
compdef _pod_completions pod
