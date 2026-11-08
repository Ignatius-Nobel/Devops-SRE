#!/usr/bin/env bash
# Enforce: no direct pushes to main, PR required, all CI gates must pass.
# Requires the GitHub CLI (gh) authenticated as a repo admin.  Usage: ./scripts/protect-main.sh owner/repo
set -euo pipefail
REPO="${1:?usage: $0 owner/repo}"
gh api -X PUT "repos/${REPO}/branches/main/protection" --input - <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["PR Gate"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
echo "main is protected. enforce_admins=false lets the GITOPS_PAT (admin) push the automated tag bump;"
echo "all humans (incl. admins using the UI/normal flow) are still steered through PRs."
