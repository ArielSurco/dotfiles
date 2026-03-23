# sentry — Interactive Sentry issue search
# Search events by custom tags across projects with environment filtering.
# Requires: curl, jq, gum, ~/.sentryclirc

_SENTRY_PRIORITY_PROJECTS=("payments-service" "app-waiters")

_sentry_load_config() {
  _SENTRY_TOKEN=""
  _SENTRY_URL=""
  _SENTRY_ORG=""

  local configfile="$HOME/.sentryclirc"
  if [[ ! -f "$configfile" ]]; then
    echo "sentry: ~/.sentryclirc not found. Configure Sentry CLI first." >&2
    return 1
  fi

  local current_section="" line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    [[ -z "$line" || "$line" == \#* || "$line" == \;* ]] && continue
    # Section header
    if [[ "$line" == "["*"]" ]]; then
      current_section="${line#\[}"
      current_section="${current_section%\]}"
      continue
    fi
    # Key=value
    key="${line%%=*}"
    val="${line#*=}"
    key="${key## }" ; key="${key%% }"
    val="${val## }" ; val="${val%% }"

    case "$current_section" in
      auth)
        [[ "$key" == "token" ]] && _SENTRY_TOKEN="$val"
        ;;
      defaults)
        [[ "$key" == "url" ]] && _SENTRY_URL="$val"
        [[ "$key" == "org" ]] && _SENTRY_ORG="$val"
        ;;
    esac
  done < "$configfile"

  if [[ -z "$_SENTRY_TOKEN" || -z "$_SENTRY_URL" || -z "$_SENTRY_ORG" ]]; then
    echo "sentry: incomplete config in ~/.sentryclirc (need token, url, org)" >&2
    return 1
  fi
}

_sentry_api() {
  local endpoint="$1"
  curl -sf -H "Authorization: Bearer $_SENTRY_TOKEN" "${_SENTRY_URL}${endpoint}"
}

_sentry_get_projects() {
  local cachefile="$DOTFILES_DATA/sentry-projects"
  if [[ -f "$cachefile" ]]; then
    command cat "$cachefile"
    return 0
  fi

  local raw
  raw=$(_sentry_api "/api/0/organizations/${_SENTRY_ORG}/projects/?per_page=100")
  if [[ -z "$raw" ]]; then
    echo "sentry: failed to fetch projects" >&2
    return 1
  fi
  local result
  result=$(echo "$raw" | jq -r '.[] | "\(.slug)=\(.id)"')
  [[ -d "$DOTFILES_DATA" ]] || mkdir -p "$DOTFILES_DATA"
  echo "$result" > "$cachefile"
  echo "$result"
}

_sentry_get_tags() {
  local proj_slug="$1"
  local cachefile="$DOTFILES_DATA/sentry-tags-${proj_slug}"
  if [[ -f "$cachefile" ]]; then
    command cat "$cachefile"
    return 0
  fi

  local raw
  raw=$(_sentry_api "/api/0/projects/${_SENTRY_ORG}/${proj_slug}/tags/")
  if [[ -z "$raw" ]]; then
    echo "sentry: failed to fetch tags" >&2
    return 1
  fi
  local result
  result=$(echo "$raw" | jq -r '.[] | "\(.key)=\(.name)"')
  [[ -d "$DOTFILES_DATA" ]] || mkdir -p "$DOTFILES_DATA"
  echo "$result" > "$cachefile"
  echo "$result"
}

_sentry_search_events() {
  local proj_id="$1"
  local sentry_env="$2"
  local tag_key="$3"
  local tag_val="$4"

  local query="${tag_key}:${tag_val}"
  [[ -n "$sentry_env" ]] && query="${query} environment:${sentry_env}"

  local encoded_query
  encoded_query=$(printf '%s' "$query" | jq -sRr @uri)

  local raw
  raw=$(_sentry_api "/api/0/organizations/${_SENTRY_ORG}/events/?field=id&field=title&field=timestamp&field=project&field=issue.id&query=${encoded_query}&statsPeriod=24h&project=${proj_id}&sort=-timestamp&per_page=25")
  if [[ -z "$raw" ]]; then
    return 1
  fi
  echo "$raw"
}

_sentry_display_results() {
  local raw="$1"
  local proj_slug="$2"

  local evt_count
  evt_count=$(echo "$raw" | jq '.data | length')

  if [[ "$evt_count" == "0" || -z "$evt_count" ]]; then
    echo "No events found in the last 24h"
    return 0
  fi

  echo "Found $evt_count events (last 24h):"
  echo ""
  printf "%-36s  %-50s  %-20s  %s\n" "EVENT ID" "TITLE" "TIMESTAMP" "URL"
  printf "%-36s  %-50s  %-20s  %s\n" "--------" "-----" "---------" "---"

  echo "$raw" | jq -r '.data[] | [.id, .title, .timestamp, ."issue.id"] | @tsv' | while IFS=$'\t' read -r eid etitle ets issue_id; do
    [[ ${#etitle} -gt 50 ]] && etitle="${etitle:0:47}..."
    local ts_short="${ets%%.*}"
    ts_short="${ts_short/T/ }"
    local eurl="${_SENTRY_URL}/organizations/${_SENTRY_ORG}/issues/${issue_id}/events/${eid}/"
    printf "%-36s  %-50s  %-20s  %s\n" "$eid" "$etitle" "$ts_short" "$eurl"
  done
}

sentry() {
  local subcmd="$1"

  if [[ -z "$subcmd" ]]; then
    echo "Usage: sentry search" >&2
    return 1
  fi

  case "$subcmd" in
    search)
      _sentry_search
      ;;
    *)
      echo "sentry: unknown command '$subcmd'" >&2
      echo "Usage: sentry search" >&2
      return 1
      ;;
  esac
}

_sentry_search() {
  # Check deps
  if ! command -v curl &>/dev/null; then
    echo "sentry: curl not found" >&2
    return 1
  fi
  if ! command -v jq &>/dev/null; then
    echo "sentry: jq is required: brew install jq" >&2
    return 1
  fi
  if ! command -v gum &>/dev/null; then
    echo "sentry: gum is required: brew install gum" >&2
    return 1
  fi

  # Load config
  _sentry_load_config || return 1

  # Step 1: Choose environment
  local sentry_env
  sentry_env=$(printf '%s\n' "production" "staging" "sandbox" | gum choose --header "Select environment:")
  [[ -z "$sentry_env" ]] && return 0

  # Step 2: Choose project
  local proj_data
  proj_data=$(_sentry_get_projects) || return 1

  local priority_items=()
  local other_items=()
  local pslug pid is_priority pp
  while IFS='=' read -r pslug pid; do
    is_priority=0
    for pp in "${_SENTRY_PRIORITY_PROJECTS[@]}"; do
      [[ "$pslug" == "$pp" ]] && { is_priority=1; break; }
    done
    if [[ $is_priority -eq 1 ]]; then
      priority_items+=("$pslug")
    else
      other_items+=("$pslug")
    fi
  done <<< "$proj_data"

  local sorted_others=(${(o)other_items})
  local all_projects=("${priority_items[@]}" "${sorted_others[@]}")

  local proj_slug
  proj_slug=$(printf '%s\n' "${all_projects[@]}" | gum choose --header "Select project ($sentry_env):")
  [[ -z "$proj_slug" ]] && return 0

  # Resolve project ID
  local proj_id
  proj_id=$(echo "$proj_data" | while IFS='=' read -r s i; do
    [[ "$s" == "$proj_slug" ]] && echo "$i"
  done)

  # Step 3: Smart tag detection
  local tag_data
  tag_data=$(_sentry_get_tags "$proj_slug") || return 1

  local tag_key tag_val
  # Look for *.sn pattern
  local sn_tag
  sn_tag=$(echo "$tag_data" | while IFS='=' read -r tk tn; do
    [[ "$tk" == *.sn ]] && echo "$tk" && break
  done)

  if [[ -n "$sn_tag" ]]; then
    echo -n "Ingrese el Serial Number ($sn_tag): "
    read -r tag_val
    [[ -z "$tag_val" ]] && { echo "sentry: tag value cannot be empty" >&2; return 1; }
    tag_key="$sn_tag"
  else
    # Show all tags via gum choose
    local tag_items=()
    local tk tn
    while IFS='=' read -r tk tn; do
      tag_items+=("${tn} (${tk})")
    done <<< "$tag_data"

    local tag_selection
    tag_selection=$(printf '%s\n' "${tag_items[@]}" | gum choose --header "Select tag:")
    [[ -z "$tag_selection" ]] && return 0

    tag_key="${tag_selection##*\(}"
    tag_key="${tag_key%)}"

    echo -n "Enter value for $tag_key: "
    read -r tag_val
    [[ -z "$tag_val" ]] && { echo "sentry: tag value cannot be empty" >&2; return 1; }
  fi

  # Step 4: Search events
  echo "Searching events ($sentry_env / $proj_slug / $tag_key:$tag_val)..."
  local results
  results=$(_sentry_search_events "$proj_id" "$sentry_env" "$tag_key" "$tag_val")

  if [[ -z "$results" ]]; then
    echo "sentry: search failed or no results" >&2
    return 1
  fi

  # Step 5: Display
  _sentry_display_results "$results" "$proj_slug"
}

_sentry_completions() {
  if [[ $CURRENT -eq 2 ]]; then
    compadd "search"
  fi
}
compdef _sentry_completions sentry
