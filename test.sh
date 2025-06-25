#!/bin/bash

ECHO=echo

$ECHO "hello"


# string formatters
if [[ -t 1 ]]
then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_underline="$(tty_escape "4;39")"
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

shell_join() {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"
  do
    printf " "
    printf "%s" "${arg// /\ }"
  done
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

ohai() {
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
  printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")" >&2
}

info() {
  printf "${tty_blue}INFO${tty_reset}: %s\n" "$(chomp "$1")" >&2
}

confirm() {
    # call with a prompt string or use a default
    read -r -p "${tty_bold}${1:-Are you sure}?${tty_reset} [y/N] " response
    case "$response" in
    [yY][eE][sS] | [yY])
        true
        ;;
    *)
        false
        ;;
    esac
}

USER="$(chomp "$(id -un)")"

$ECHO $USER

ohai "Hi, I am" $USER

warn "Hi, I am $USER"
info "Hi, I am $USER"

confirm && $ECHO "Hi, I am $USER"

if confirm "Hello!"; then
    $ECHO "Hi, I am $USER"
fi