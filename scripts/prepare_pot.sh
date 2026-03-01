#!/usr/bin/env bash
# Distributed under the OSI-approved BSD 3-Clause License.
# See accompanying file LICENSE-BSD for details.
#
# Prepare .pot files from the l10n branch for offline translation.
# Creates skeleton .po files in the staging directory.

set -euo pipefail

# Defaults
LANGUAGE=""
VERSION="master"
FILES=""
MERGE_EXISTING=false

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
        --files)
            FILES="$2"
            shift 2
            ;;
        --merge-existing)
            MERGE_EXISTING=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --language LANG [--version VERSION] [--files \"file1,file2\"] [--merge-existing]"
            echo ""
            echo "Prepare .pot files from the l10n branch for offline translation."
            echo ""
            echo "Arguments:"
            echo "  --language        Language code (e.g., ko_KR) [required]"
            echo "  --version         Documentation version (default: master)"
            echo "  --files           Comma-separated list of files to extract (without extension)"
            echo "  --merge-existing  Merge with existing translations from l10n branch"
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
for cmd in git msginit msgmerge; do
    if ! command -v "${cmd}" &>/dev/null; then
        echo "Error: '${cmd}' is not installed. Please install gettext." >&2
        exit 1
    fi
done

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STAGING_DIR="${REPO_DIR}/${VERSION}/.offline/${LANGUAGE}/LC_MESSAGES"
POT_PREFIX="${VERSION}/locale/pot/LC_MESSAGES"
EXISTING_PREFIX="${VERSION}/locale/${LANGUAGE}/LC_MESSAGES"

echo "=== prepare_pot.sh ==="
echo "Language:        ${LANGUAGE}"
echo "Version:         ${VERSION}"
echo "Merge existing:  ${MERGE_EXISTING}"
echo "Staging dir:     ${STAGING_DIR}"
echo ""

# Fetch the latest l10n branch
echo "Fetching latest l10n branch..."
git -C "${REPO_DIR}" fetch origin l10n
echo ""

# Get the list of .pot files
echo "Extracting .pot file list..."
POT_FILES=$(git -C "${REPO_DIR}" ls-tree -r --name-only origin/l10n -- "${POT_PREFIX}/" | \
    sed "s|^${POT_PREFIX}/||" | \
    sed 's|\.pot$||')

if [[ -z "${POT_FILES}" ]]; then
    echo "Error: No .pot files found in origin/l10n:${POT_PREFIX}/" >&2
    exit 1
fi

# Filter files if --files is specified
if [[ -n "${FILES}" ]]; then
    IFS=',' read -ra FILTER_ARRAY <<< "${FILES}"
    FILTERED=""
    while IFS= read -r f; do
        for filter in "${FILTER_ARRAY[@]}"; do
            filter=$(echo "${filter}" | xargs)  # trim whitespace
            if [[ "${f}" == "${filter}" ]]; then
                FILTERED="${FILTERED}${f}"$'\n'
            fi
        done
    done <<< "${POT_FILES}"
    POT_FILES=$(echo "${FILTERED}" | sed '/^$/d')
    if [[ -z "${POT_FILES}" ]]; then
        echo "Error: No .pot files matched the filter: ${FILES}" >&2
        exit 1
    fi
fi

FILE_COUNT=$(echo "${POT_FILES}" | wc -l | tr -d ' ')
echo "Found ${FILE_COUNT} .pot file(s) to process."
echo ""

# Create staging directory
mkdir -p "${STAGING_DIR}"

# Process each .pot file
CREATED=0
MERGED=0

while IFS= read -r pot_name; do
    [[ -z "${pot_name}" ]] && continue

    pot_ref="origin/l10n:${POT_PREFIX}/${pot_name}.pot"
    po_path="${STAGING_DIR}/${pot_name}.po"

    # Create subdirectories as needed
    mkdir -p "$(dirname "${po_path}")"

    # Extract .pot content from l10n branch
    tmp_pot=$(mktemp "${TMPDIR:-/tmp}/pot.XXXXXX")
    git -C "${REPO_DIR}" show "${pot_ref}" > "${tmp_pot}"

    if [[ "${MERGE_EXISTING}" == "true" ]]; then
        # Try to get existing .po file
        existing_ref="origin/l10n:${EXISTING_PREFIX}/${pot_name}.po"
        tmp_po=$(mktemp "${TMPDIR:-/tmp}/po.XXXXXX")

        if git -C "${REPO_DIR}" show "${existing_ref}" > "${tmp_po}" 2>/dev/null; then
            # Merge existing .po with .pot template
            msgmerge --quiet --width=79 --no-fuzzy-matching \
                "${tmp_po}" "${tmp_pot}" -o "${po_path}"
            rm -f "${tmp_po}"
            rm -f "${tmp_pot}"
            MERGED=$((MERGED + 1))
            echo "  [merged]  ${pot_name}.po"
            continue
        fi
        rm -f "${tmp_po}"
    fi

    # Create skeleton .po from .pot using msginit
    msginit --no-translator --locale="${LANGUAGE}.UTF-8" --width=79 \
        -i "${tmp_pot}" -o "${po_path}" 2>/dev/null || \
    msginit --no-translator --locale="${LANGUAGE}" --width=79 \
        -i "${tmp_pot}" -o "${po_path}" 2>/dev/null || \
    # Fallback: use msgcat if msginit fails (e.g., locale not installed)
    msgcat --lang="${LANGUAGE}" --width=79 "${tmp_pot}" -o "${po_path}"

    rm -f "${tmp_pot}"
    CREATED=$((CREATED + 1))
    echo "  [created] ${pot_name}.po"
done <<< "${POT_FILES}"

echo ""
echo "Done. ${CREATED} created, ${MERGED} merged — ${FILE_COUNT} file(s) staged in:"
echo "  ${STAGING_DIR}"
echo ""
echo "Next steps:"
echo "  1. Translate the .po files (LLM or manual)"
echo "  2. Run: ./scripts/validate_po.sh --language ${LANGUAGE} --version ${VERSION}"
echo "  3. Create PR to l10n branch with 'offline' label"
