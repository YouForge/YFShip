#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/.." && pwd)"
install_dir="${YFSHIP_INSTALL_DIR:-${HOME}/.local/bin}"
release_binary="${project_dir}/.build/release/yfship"
installed_binary="${install_dir}/yfship"

is_mach_o_executable() {
    local candidate="$1"
    local description

    [[ -f "${candidate}" && -x "${candidate}" ]] || return 1
    description="$(file -b "${candidate}" 2>/dev/null || true)"
    [[ "${description}" == *"Mach-O"* && "${description}" == *"executable"* ]]
}

printf 'Building yfship in release mode...\n'
(
    cd -- "${project_dir}"
    swift build -c release
)

mkdir -p -- "${install_dir}"

if [[ -e "${installed_binary}" || -L "${installed_binary}" ]]; then
    if [[ -L "${installed_binary}" ]] || is_mach_o_executable "${installed_binary}"; then
        rm -f -- "${installed_binary}"
    else
        printf 'Refusing to overwrite unrelated file: %s\n' "${installed_binary}" >&2
        exit 1
    fi
fi

ln -s -- "${release_binary}" "${installed_binary}"
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
