#!/usr/bin/env bash
# Function to measure and print timing
time_command() {
  local label="$1"
  shift
  local start=$(date +%s%N)
  "$@" >/dev/null 2>&1
  local end=$(date +%s%N)
  local duration=$(( (end - start) / 1000000 )) # Convert to milliseconds
  echo "⏱️ ${label}: ${duration} ms"
}

# Get current branch
start_branch=$(date +%s%N)
branch=$(git symbolic-ref --short HEAD)
end_branch=$(date +%s%N)
echo "⏱️ Get branch: $(( (end_branch - start_branch) / 1000000 )) ms"

# Get remote tracking branch
start_upstream=$(date +%s%N)
remote_branch=$(git for-each-ref --format='%(upstream:short)' "$(git symbolic-ref -q HEAD)")
end_upstream=$(date +%s%N)
echo "⏱️ Get upstream: $(( (end_upstream - start_upstream) / 1000000 )) ms"

# Extract remote and remote branch name
start_remote=$(date +%s%N)
remote=$(echo "$remote_branch" | cut -d'/' -f1)
remote_branch_name=$(echo "$remote_branch" | cut -d'/' -f2-)
end_remote=$(date +%s%N)
echo "⏱️ Parse remote: $(( (end_remote - start_remote) / 1000000 )) ms"

# Check if upstream is set
if [ -z "$remote_branch" ]; then
  echo "🚨 No upstream tracking branch set for '$branch'."
  exit 1
fi

# Get repository info from git config
start_repo_info=$(date +%s%N)
remote_url=$(git config --get remote.$remote.url)
# Extract owner and repo from various URL formats (HTTPS, SSH, etc.)
if [[ $remote_url =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
else
  echo "❌ Could not parse GitHub repository information from remote URL: $remote_url"
  exit 1
fi
end_repo_info=$(date +%s%N)
echo "⏱️ Get repo info: $(( (end_repo_info - start_repo_info) / 1000000 )) ms"

# Get local HEAD hash
start_local_hash=$(date +%s%N)
local_hash=$(git rev-parse HEAD)
end_local_hash=$(date +%s%N)
echo "⏱️ Get local hash: $(( (end_local_hash - start_local_hash) / 1000000 )) ms"

# Check if GitHub token exists
token_file="$HOME/.keys/graphqlapi.txt"
if [ -f "$token_file" ]; then
  token=$(cat "$token_file" | tr -d '[:space:]')
else
  echo "⚠️ No GitHub token found at $token_file. Using unauthenticated request (rate limits apply)."
  token="<add-token-here>"
fi

# Get remote hash using GitHub GraphQL API
start_remote_hash=$(date +%s%N)

# Prepare the GraphQL query
query="{\"query\": \"{ repository(owner:\\\"$owner\\\", name:\\\"$repo\\\") { ref(qualifiedName:\\\"refs/heads/$remote_branch_name\\\") { target { oid }}}}\""

# Make the API call
if [ -n "$token" ]; then
  api_response=$(curl -s -H "Authorization: bearer $token" -X POST -d "$query" https://api.github.com/graphql)
else
  api_response=$(curl -s -X POST -d "$query" https://api.github.com/graphql)
fi

# Extract the commit hash from the response
if command -v jq >/dev/null 2>&1; then
  # Use jq if available (preferred for reliability)
  remote_hash=$(echo "$api_response" | jq -r '.data.repository.ref.target.oid // empty')
else
  # Fallback to grep and cut if jq is not available
  remote_hash=$(echo "$api_response" | grep -o '"oid":"[^"]*"' | head -1 | cut -d'"' -f4)
fi

# Check if we got a valid hash
if [ -z "$remote_hash" ]; then
  echo "❌ Failed to get remote hash. API response: $api_response"
  exit 1
fi

end_remote_hash=$(date +%s%N)
echo "⏱️ Get remote hash: $(( (end_remote_hash - start_remote_hash) / 1000000 )) ms"

# Compare hashes
if [ "$local_hash" != "$remote_hash" ]; then
  echo "🚨 You are behind the remote ($remote/$remote_branch_name)!"
else
  echo "✅ Up to date with $remote/$remote_branch_name."
fi
