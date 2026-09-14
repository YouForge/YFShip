#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/.." && pwd)"
install_dir="${YFSHIP_INSTALL_DIR:-${HOME}/.local/bin}"
release_binary="${project_dir}/.build/release/yfship"
installed_binary="${install_dir}/yfship"
install_marker="${install_dir}/.yfship-installed"
marker_content='Managed by YFShip Scripts/install.sh.'

is_yfship_build_link() {
    local target

    [[ -L "${installed_binary}" ]] || return 1
    target="$(readlink "${installed_binary}")"
    [[ "${target}" == */.build/release/yfship ]]
}

is_yfship_marker() {
    [[ ! -L "${install_marker}" && -f "${install_marker}" ]] || return 1
    cmp -s "${install_marker}" <(printf '%s\n' "${marker_content}")
}

is_managed_install() {
    [[ ! -L "${installed_binary}" && -f "${installed_binary}" && -x "${installed_binary}" ]] \
        && is_yfship_marker
}

printf 'Building yfship in release mode...\n'
(
    cd -- "${project_dir}"
    swift build -c release
)

mkdir -p -- "${install_dir}"

if [[ -e "${install_marker}" || -L "${install_marker}" ]] && ! is_yfship_marker; then
    printf 'Refusing to overwrite unrelated file: %s\n' "${install_marker}" >&2
    exit 1
fi

if [[ -e "${installed_binary}" || -L "${installed_binary}" ]]; then
    if is_yfship_build_link || is_managed_install; then
        rm -f -- "${installed_binary}"
    else
        printf 'Refusing to overwrite unrelated file: %s\n' "${installed_binary}" >&2
        exit 1
    fi
fi

cp -- "${release_binary}" "${installed_binary}"
printf '%s\n' "${marker_content}" > "${install_marker}"
printf 'Installed yfship at %s\n' "${installed_binary}"

case ":${PATH}:" in
    *":${install_dir}:"*)
        ;;
    *)
        printf 'Warning: %s is not on PATH. Add it before invoking yfship by name.\n' \
            "${install_dir}" >&2
        ;;
esac

printf 'Global configuration belongs at %s\n' "${HOME}/.config/yfship/.env"
printf 'Bootstrap it with:\n'
printf '  mkdir -p ~/.config/yfship\n'
printf '  cp %q ~/.config/yfship/.env\n' "${project_dir}/.env.example"
