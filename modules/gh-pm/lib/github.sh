#!/usr/bin/env bash
# gh-pm/lib/github.sh — GitHub interaction via gh CLI
# All GitHub operations go through the `gh` command.

# gh_poll_issues REPO — JSON array of open issues assigned to @me.
gh_poll_issues() {
  local repo="$1"
  if [[ "${GH_PM_DRY_RUN:-0}" == "1" ]]; then
    log_debug "github" "[DRY-RUN] Would poll issues for $repo"
    echo '[]'
    return 0
  fi
  gh issue list --repo "$repo" --assignee @me --state open \
    --json number,title,body,labels,url,createdAt,updatedAt \
    --limit 100 2>/dev/null || echo '[]'
}

# gh_poll_prs REPO — JSON array of open PRs assigned to, review-requested from, or authored by @me.
gh_poll_prs() {
  local repo="$1"
  if [[ "${GH_PM_DRY_RUN:-0}" == "1" ]]; then
    log_debug "github" "[DRY-RUN] Would poll PRs for $repo"
    echo '[]'
    return 0
  fi
  local assigned review_requested authored
  assigned="$(gh pr list --repo "$repo" --assignee @me --state open \
    --json number,title,body,labels,url,author,createdAt,updatedAt \
    --limit 100 2>/dev/null || echo '[]')"
  review_requested="$(gh pr list --repo "$repo" --search "review-requested:@me" --state open \
    --json number,title,body,labels,url,author,createdAt,updatedAt \
    --limit 100 2>/dev/null || echo '[]')"
  authored="$(gh pr list --repo "$repo" --author @me --state open \
    --json number,title,body,labels,url,author,createdAt,updatedAt \
    --limit 100 2>/dev/null || echo '[]')"
  jq -s 'add | unique_by(.number)' <<< "${assigned}${review_requested}${authored}"
}

# gh_get_comments REPO TYPE NUMBER — JSON array of comments.
# TYPE: "issue" or "pr"
gh_get_comments() {
  local repo="$1" type="$2" number="$3"
  if [[ "${GH_PM_DRY_RUN:-0}" == "1" ]]; then
    echo '[]'; return 0
  fi
  local cmd="issue"
  [[ "$type" == "pr" ]] && cmd="pr"
  gh "$cmd" view "$number" --repo "$repo" --json comments --jq '.comments' 2>/dev/null || echo '[]'
}

# gh_post_comment REPO NUMBER BODY
gh_post_comment() {
  local repo="$1" number="$2" body="$3"
  if [[ "${GH_PM_DRY_RUN:-0}" == "1" ]]; then
    log_info "github" "[DRY-RUN] Would post comment to $repo#$number"
    echo "$body" >&2
    return 0
  fi
  gh issue comment "$number" --repo "$repo" --body "$body" >/dev/null 2>&1
}

# gh_update_comment REPO COMMENT_ID BODY
gh_update_comment() {
  local repo="$1" comment_id="$2" body="$3"
  if [[ "${GH_PM_DRY_RUN:-0}" == "1" ]]; then
    log_info "github" "[DRY-RUN] Would update comment $comment_id on $repo"
    echo "$body" >&2
    return 0
  fi
  gh api --method PATCH "/repos/${repo}/issues/comments/${comment_id}" \
    -f body="$body" >/dev/null 2>&1
}

# gh_find_tracking_comment REPO NUMBER TASK_ID — print comment ID or "".
gh_find_tracking_comment() {
  local repo="$1" number="$2" task_id="$3"
  local marker="<!-- gh-pm:${task_id} -->"
  if [[ "${GH_PM_DRY_RUN:-0}" == "1" ]]; then
    echo ""; return 0
  fi
  local comments
  comments="$(gh api "/repos/${repo}/issues/${number}/comments" --paginate 2>/dev/null || echo '[]')"
  echo "$comments" | jq -r --arg m "$marker" '.[] | select(.body | contains($m)) | .id' | head -n1
}

# gh_get_labels REPO TYPE NUMBER — comma-separated label names.
gh_get_labels() {
  local repo="$1" type="$2" number="$3"
  if [[ "${GH_PM_DRY_RUN:-0}" == "1" ]]; then
    echo ""; return 0
  fi
  local cmd="issue"
  [[ "$type" == "pr" ]] && cmd="pr"
  gh "$cmd" view "$number" --repo "$repo" --json labels \
    --jq '[.labels[].name] | join(",")' 2>/dev/null || echo ""
}

# gh_get_pending_reviews REPO PR_NUMBER — JSON array of CHANGES_REQUESTED reviews.
gh_get_pending_reviews() {
  local repo="$1" number="$2"
  if [[ "${GH_PM_DRY_RUN:-0}" == "1" ]]; then
    echo '[]'; return 0
  fi
  gh api "/repos/${repo}/pulls/${number}/reviews" 2>/dev/null \
    | jq '[.[] | select(.state == "CHANGES_REQUESTED")]' 2>/dev/null || echo '[]'
}
