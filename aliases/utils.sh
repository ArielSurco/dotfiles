# utils — Small shell utilities
# General-purpose helpers that don't warrant their own file.

_DOTFILES_ALIASES_DIR="${0:A:h}"

dotalias() {
  source "$_DOTFILES_ALIASES_DIR/init.sh" && echo "Aliases reloaded"
}
