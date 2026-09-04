#!/usr/bin/env bash

set -euo pipefail

install_dir="${YFSHIP_INSTALL_DIR:-${HOME}/.local/bin}"
installed_binary="${install_dir}/yfship"
config_file="${HOME}/.config/yfship/.env"

is_yfship_build_link() {
    local target

    [[ -L "${installed_binary}" ]] || return 1
    target="$(readlink "${installed_binary}")"
    [[ "${target}" == */.build/release/yfship ]]
}

if [[ ! -e "${installed_binary}" && ! -L "${installed_binary}" ]]; then
    printf 'No yfship installation found at %s\n' "${installed_binary}"
elif is_yfship_build_link; then
    rm -f -- "${installed_binary}"
    printf 'Removed yfship from %s\n' "${installed_binary}"
else
    printf 'Refusing to remove unrelated file: %s\n' "${installed_binary}" >&2
    exit 1
fi

printf 'User configuration was left untouched at %s\n' "${config_file}"
