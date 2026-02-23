#!/usr/bin/env bash
set -euo pipefail

workspace="${GITHUB_WORKSPACE:-$(pwd)}"
target_repo_url="${TARGET_REPO_URL:-https://github.com/google/adk-python.git}"
target_repo_name="${TARGET_REPO_NAME:-google/adk-python}"
target_repo_web_url="${TARGET_REPO_WEB_URL:-https://github.com/${target_repo_name}}"
state_file="${STATE_FILE:-.github/adk-python-state/last_sha.txt}"
report_dir="${REPORT_DIR:-reports/adk-python}"
today_utc="${TODAY_UTC:-$(date -u +%F)}"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

mkdir -p "${workspace}/$(dirname "${state_file}")"
mkdir -p "${workspace}/${report_dir}"

git clone --quiet --filter=blob:none "${target_repo_url}" "${tmp_dir}/repo"
cd "${tmp_dir}/repo"

latest_sha="$(git rev-parse HEAD)"
previous_sha=""
if [[ -f "${workspace}/${state_file}" ]]; then
  previous_sha="$(tr -d '[:space:]' < "${workspace}/${state_file}")"
fi

if [[ -n "${previous_sha}" ]] && ! git cat-file -e "${previous_sha}^{commit}" 2>/dev/null; then
  previous_sha=""
fi

report_file="${workspace}/${report_dir}/${today_utc}.md"
has_upstream_changes="false"

{
  echo "# ADK Python Daily Change Report"
  echo
  echo "- Date (UTC): ${today_utc}"
  echo "- Source: \`${target_repo_name}\`"
  echo "- Latest SHA: \`${latest_sha}\`"
  if [[ -n "${previous_sha}" ]]; then
    echo "- Previous SHA: \`${previous_sha}\`"
  else
    echo "- Previous SHA: *(none - first run)*"
  fi
  echo

  if [[ -z "${previous_sha}" ]]; then
    has_upstream_changes="true"
    echo "## Result"
    echo
    echo "Initial snapshot recorded. Future runs will include diffs from this baseline."
    echo
    echo "## Latest Commit"
    echo
    git --no-pager show -s --date=short --format="- [%h](${target_repo_web_url}/commit/%H) %s (%an, %ad)" "${latest_sha}"
  elif [[ "${previous_sha}" == "${latest_sha}" ]]; then
    echo "## Result"
    echo
    echo "No upstream changes since the last check."
  else
    has_upstream_changes="true"
    range="${previous_sha}..${latest_sha}"
    commit_count="$(git rev-list --count "${range}")"

    echo "## Summary"
    echo
    echo "- New commits: ${commit_count}"
    echo
    echo "## Commits"
    echo
    git --no-pager log --date=short --pretty=format:"- [%h](${target_repo_web_url}/commit/%H) %s (%an, %ad)" "${range}"
    echo
    echo
    echo "## Changed Files"
    echo
    while IFS= read -r line; do
      printf -- '- `%s`\n' "${line}"
    done < <(git --no-pager diff --name-status "${range}")
  fi
} > "${report_file}"

cp "${report_file}" "${workspace}/${report_dir}/latest.md"
echo "${latest_sha}" > "${workspace}/${state_file}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "report_file=${report_file#${workspace}/}"
    echo "has_upstream_changes=${has_upstream_changes}"
  } >> "${GITHUB_OUTPUT}"
fi
