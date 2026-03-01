#!/usr/bin/env bash
# Distributed under the OSI-approved BSD 3-Clause License.
# See accompanying file LICENSE-BSD for details.
#
# Validate staged .po files for offline translation.

set -euo pipefail

# Defaults
LANGUAGE=""
VERSION="master"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --language)
            LANGUAGE="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --language LANG [--version VERSION]"
            echo ""
            echo "Validate staged .po files for offline translation."
            echo ""
            echo "Arguments:"
            echo "  --language  Language code (e.g., ko_KR) [required]"
            echo "  --version   Documentation version (default: master)"
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "${LANGUAGE}" ]]; then
    echo "Error: --language is required." >&2
    echo "Run '$0 --help' for usage information." >&2
    exit 1
fi

# Check dependencies
for cmd in msgfmt msgattrib; do
    if ! command -v "${cmd}" &>/dev/null; then
        echo "Error: '${cmd}' is not installed. Please install gettext." >&2
        exit 1
    fi
done

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STAGING_DIR="${REPO_DIR}/${VERSION}/.offline/${LANGUAGE}/LC_MESSAGES"

if [[ ! -d "${STAGING_DIR}" ]]; then
    echo "Error: Staging directory not found: ${STAGING_DIR}" >&2
    echo "Run prepare_pot.sh first." >&2
    exit 1
fi

echo "=== validate_po.sh ==="
echo "Language:     ${LANGUAGE}"
echo "Version:      ${VERSION}"
echo "Staging dir:  ${STAGING_DIR}"
echo ""

HAS_ERROR=false
TOTAL_FILES=0
VALID_FILES=0
TOTAL_TRANSLATED=0
TOTAL_FUZZY=0
TOTAL_UNTRANSLATED=0

while IFS= read -r -d '' po_file; do
    TOTAL_FILES=$((TOTAL_FILES + 1))
    rel_path="${po_file#"${STAGING_DIR}/"}"

    # Validate with msgfmt
    if ! msgfmt --check --output-file=/dev/null "${po_file}" 2>/dev/null; then
        echo "  [FAIL]  ${rel_path}"
        msgfmt --check --output-file=/dev/null "${po_file}" 2>&1 | sed 's/^/          /' || true
        HAS_ERROR=true
        continue
    fi

    VALID_FILES=$((VALID_FILES + 1))

    # Count statistics using msgattrib
    translated=$(msgattrib --translated --no-fuzzy "${po_file}" 2>/dev/null | grep -c '^msgid ' || true)
    fuzzy=$(msgattrib --only-fuzzy "${po_file}" 2>/dev/null | grep -c '^msgid ' || true)
    untranslated=$(msgattrib --untranslated "${po_file}" 2>/dev/null | grep -c '^msgid ' || true)

    TOTAL_TRANSLATED=$((TOTAL_TRANSLATED + translated))
    TOTAL_FUZZY=$((TOTAL_FUZZY + fuzzy))
    TOTAL_UNTRANSLATED=$((TOTAL_UNTRANSLATED + untranslated))

    total=$((translated + fuzzy + untranslated))
    if [[ ${total} -gt 0 ]]; then
        pct=$((translated * 100 / total))
    else
        pct=0
    fi

    printf "  [OK]    %-60s  translated: %3d  fuzzy: %3d  untranslated: %3d  total: %3d  (%d%%)\n" \
        "${rel_path}" "${translated}" "${fuzzy}" "${untranslated}" "${total}" "${pct}"
done < <(find "${STAGING_DIR}" -name '*.po' -print0 | sort -z)

echo ""
echo "=== Summary ==="
echo "Files:        ${TOTAL_FILES} total, ${VALID_FILES} valid"
echo "Translated:   ${TOTAL_TRANSLATED}"
echo "Fuzzy:        ${TOTAL_FUZZY}"
echo "Untranslated: ${TOTAL_UNTRANSLATED}"

GRAND_TOTAL=$((TOTAL_TRANSLATED + TOTAL_FUZZY + TOTAL_UNTRANSLATED))
if [[ ${GRAND_TOTAL} -gt 0 ]]; then
    GRAND_PCT=$((TOTAL_TRANSLATED * 100 / GRAND_TOTAL))
    echo "Progress:     ${GRAND_PCT}% (${TOTAL_TRANSLATED}/${GRAND_TOTAL})"
fi

echo ""
if [[ "${HAS_ERROR}" == "true" ]]; then
    echo "Validation FAILED. Fix the errors above before creating a PR."
    exit 1
else
    echo "Validation PASSED."
    exit 0
fi
