#!/usr/bin/env zsh
# aliases/init.sh — Source all alias files

for file in "${0:A:h}"/*.sh; do
  [[ "${file:t}" == "init.sh" ]] && continue
  source "$file" || echo "Failed to load ${file:t}" >&2
done
