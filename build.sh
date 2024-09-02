#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

TAG="${1}"

if [ -z "$TAG" ]; then
    echo "Error: arg must be set to TAG of jax you want to build docs for" >&2
    exit 1
fi

# Install uv only if it's not already installed
if ! command -v uv &> /dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

JAX_DIR=$(mktemp -d)
git clone --depth 1 --branch "${TAG}" https://github.com/google/jax.git "${JAX_DIR}"

cd "${JAX_DIR}/docs"
HTML_DIR="${PWD}/build/html"
uv venv
source .venv/bin/activate
uv pip install .
sphinx-build -b html -D nb_execution_mode=off ./ "${HTML_DIR}" -j auto
deactivate

cd "$(dirname "${BASH_SOURCE[0]}")"
uv venv
source .venv/bin/activate
uv pip install tqdm python-magic selectolax doc2dash beautifulsoup4 lxml
python3 ./transform.py "${HTML_DIR}"
sed -i 's/var(--pst-font-family-monospace)/monospace/g' $HTML_DIR/**/*.css
doc2dash -f -d ./ --online-redirect-url https://jax.readthedocs.io/ --name jax -i icon.png $HTML_DIR
tar --exclude='.DS_Store' -cvzf "${TAG}.tar.gz" jax.docset

readonly xml_file="jax.xml"

if [ ! -f "${xml_file}" ]; then
    echo "Error: File ${xml_file} not found."
    exit 1
fi

current_version=$(sed -n 's/.*<version>\(.*\)<\/version>.*/\1/p' "${xml_file}" | head -n 1)

version="${TAG#jax-v}"

# Update the XML file
sed -i.bak '
    # Update the version
    /<version>/s|>[^<]*<|>'"$version"'<|

    # Update the URL
    /<url>/s|/v[^/]*/jax-v[^.]*|/v'"$version"'/jax-v'"$version"'|

    # Move the current version to other-versions
    /<other-versions>/a\        <version><name>'"$current_version"'</name></version>
' "$xml_file"

echo "XML file updated successfully."

git add "${xml_file}"
git commit -m "Update version to ${TAG}"
git tag -a "${TAG}" -m "jax ${TAG}"
git push origin "${TAG}"
