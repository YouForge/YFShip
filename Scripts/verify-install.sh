#!/usr/bin/env bash

# Run after installer changes: bash Scripts/verify-install.sh
# Kept separate from swift test to avoid nested SwiftPM builds and release-build
# cost in the unit suite. All installs use temporary directories; no live APIs.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/.." && pwd)"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/yfship-install.XXXXXX")"
trap 'rm -rf -- "${temp_dir}"' EXIT
install_dir="${temp_dir}/install with spaces"
installed_binary="${install_dir}/yfship"
install_marker="${install_dir}/.yfship-installed"
test_home="${temp_dir}/home"
config_file="${test_home}/.config/yfship/.env"
release_binary="${project_dir}/.build/release/yfship"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

install_yfship() {
    YFSHIP_INSTALL_DIR="${install_dir}" bash "${script_dir}/install.sh"
}

uninstall_yfship() {
    HOME="${test_home}" YFSHIP_INSTALL_DIR="${install_dir}" \
        bash "${script_dir}/uninstall.sh"
}

assert_standalone() {
    [[ -f "${installed_binary}" && ! -L "${installed_binary}" ]] \
        || fail 'Installed binary must be a regular file, not a source-checkout symlink.'
    [[ -x "${installed_binary}" ]] || fail 'Copy did not preserve executable permissions.'
    [[ -f "${install_marker}" && ! -L "${install_marker}" ]] || fail 'Missing regular ownership marker.'
    cmp -s "${install_marker}" "${temp_dir}/expected-marker" || fail 'Incorrect ownership marker content.'
    cmp -s "${release_binary}" "${installed_binary}" || fail 'Installed bytes differ from release binary.'
    (
        cd -- "${temp_dir}"
        HOME="${test_home}" "${installed_binary}" --help > "${temp_dir}/help.txt"
    )
    grep -q 'USAGE: yfship' "${temp_dir}/help.txt" || fail 'Installed binary did not launch outside checkout.'
}

mkdir -p -- "${test_home}/.config/yfship"
printf '# Synthetic config preservation marker\n' > "${config_file}"
cp -- "${config_file}" "${temp_dir}/expected-config"
printf 'Managed by YFShip Scripts/install.sh.\n' > "${temp_dir}/expected-marker"

install_yfship
assert_standalone
ls -l "${installed_binary}"
file "${installed_binary}"
printf 'PASS: standalone executable, permissions preserved, launches outside checkout.\n'

install_yfship
assert_standalone
printf 'PASS: reinstall replaces a standalone executable.\n'

uninstall_yfship
[[ ! -e "${installed_binary}" && ! -L "${installed_binary}" ]] || fail 'Uninstall left the copied executable.'
[[ ! -e "${install_marker}" && ! -L "${install_marker}" ]] || fail 'Uninstall left the ownership marker.'
uninstall_yfship
printf 'PASS: copied executable uninstall and repeated uninstall.\n'

ln -s -- "${release_binary}" "${installed_binary}"
install_yfship
assert_standalone
uninstall_yfship
[[ ! -e "${install_marker}" && ! -L "${install_marker}" ]] || fail 'Uninstall left the migrated ownership marker.'
printf 'PASS: legacy symlink upgrades to a standalone executable.\n'

for target in "${release_binary}" "${temp_dir}/removed-checkout/.build/release/yfship"; do
    ln -s -- "${target}" "${installed_binary}"
    uninstall_yfship
    [[ ! -e "${installed_binary}" && ! -L "${installed_binary}" ]] || fail 'Legacy link was not removed.'
done
printf 'PASS: valid and dangling legacy symlinks uninstall.\n'

printf 'Unrelated file must survive\n' > "${installed_binary}"
cp -- "${installed_binary}" "${temp_dir}/expected-unrelated"
if install_yfship; then
    fail 'Installer accepted an unrelated file.'
fi
cmp -s "${installed_binary}" "${temp_dir}/expected-unrelated" || fail 'Installer changed unrelated file.'
if uninstall_yfship; then
    fail 'Uninstaller accepted an unrelated file.'
fi
cmp -s "${installed_binary}" "${temp_dir}/expected-unrelated" || fail 'Uninstaller changed unrelated file.'
rm -- "${installed_binary}"
printf 'PASS: unrelated files are preserved by install and uninstall.\n'

ln -s -- /usr/bin/true "${installed_binary}"
if install_yfship; then
    fail 'Installer accepted an unrelated symlink.'
fi
[[ -L "${installed_binary}" && "$(readlink "${installed_binary}")" == /usr/bin/true ]] \
    || fail 'Installer changed unrelated symlink.'
if uninstall_yfship; then
    fail 'Uninstaller accepted an unrelated symlink.'
fi
[[ -L "${installed_binary}" && "$(readlink "${installed_binary}")" == /usr/bin/true ]] \
    || fail 'Uninstaller changed unrelated symlink.'
printf 'PASS: unrelated executable symlink is preserved.\n'
rm -- "${installed_binary}"

cp -- /usr/bin/true "${installed_binary}"
cp -- "${installed_binary}" "${temp_dir}/expected-unrelated-mach-o"
description="$(file -b "${installed_binary}")"
[[ "${description}" == *"Mach-O"* && "${description}" == *"executable"* ]] \
    || fail 'Regression fixture must be a real Mach-O executable.'
[[ -f "${installed_binary}" && ! -L "${installed_binary}" && -x "${installed_binary}" ]] \
    || fail 'Regression fixture must be a regular executable.'
for marker_shape in absent incorrect symlink; do
    case "${marker_shape}" in
        absent) ;;
        incorrect) printf 'Unrelated marker\n' > "${install_marker}" ;;
        symlink) ln -s -- "${temp_dir}/expected-marker" "${install_marker}" ;;
    esac
    if install_yfship; then
        fail "Installer accepted unrelated Mach-O executable (${marker_shape} marker)."
    fi
    cmp -s "${installed_binary}" "${temp_dir}/expected-unrelated-mach-o" \
        || fail 'Installer changed unrelated Mach-O executable.'
    if uninstall_yfship; then
        fail "Uninstaller accepted unrelated Mach-O executable (${marker_shape} marker)."
    fi
    cmp -s "${installed_binary}" "${temp_dir}/expected-unrelated-mach-o" \
        || fail 'Uninstaller changed unrelated Mach-O executable.'
    case "${marker_shape}" in
        absent)
            [[ ! -e "${install_marker}" && ! -L "${install_marker}" ]] || fail 'Refusal created a marker.'
            ;;
        incorrect)
            cmp -s "${install_marker}" <(printf 'Unrelated marker\n') || fail 'Unrelated marker changed.'
            rm -- "${install_marker}"
            ;;
        symlink)
            [[ -L "${install_marker}" && "$(readlink "${install_marker}")" == "${temp_dir}/expected-marker" ]] \
                || fail 'Marker symlink changed.'
            cmp -s "${temp_dir}/expected-marker" <(printf 'Managed by YFShip Scripts/install.sh.\n') \
                || fail 'Marker symlink target changed.'
            rm -- "${install_marker}"
            ;;
    esac
done
rm -- "${installed_binary}"
printf 'PASS: unrelated regular Mach-O executable preserved with absent, incorrect, or symlinked marker.\n'

printf 'Not an executable\n' > "${installed_binary}"
cp -- "${installed_binary}" "${temp_dir}/expected-nonexecutable"
cp -- "${temp_dir}/expected-marker" "${install_marker}"
if install_yfship; then
    fail 'Installer accepted nonexecutable file with a marker.'
fi
if uninstall_yfship; then
    fail 'Uninstaller accepted nonexecutable file with a marker.'
fi
cmp -s "${installed_binary}" "${temp_dir}/expected-nonexecutable" || fail 'Nonexecutable file changed.'
cmp -s "${install_marker}" "${temp_dir}/expected-marker" || fail 'Refusal changed ownership marker.'
printf 'PASS: a marker alone does not authorize replacement or removal.\n'

cmp -s "${config_file}" "${temp_dir}/expected-config" || fail 'User configuration changed.'
printf 'PASS: user configuration preserved.\n'
