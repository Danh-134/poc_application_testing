#!/bin/bash
set -euo pipefail

# GitLab integration test script
# Tests group/user creation, git operations, and API functionality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/test_run_$(date +%Y%m%d_%H%M%S).log"
CLONE_DIR="sample-project"

# Git config
GIT_COMMITTER_NAME="CI Bot"
GIT_COMMITTER_EMAIL="ci@example.com"

# Test data
GROUP_NAME="CI-Test-Group"
GROUP_PATH="ci-test-group"
USER_EMAIL="newuser@example.com"
USER_USERNAME="newuser"
USER_NAME="New User"
USER_PASSWORD="NewUserPassword"
ACCESS_LEVEL=30

# Track resources for cleanup
GROUP_ID=""
USER_ID=""
PROJECT_ID=""

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

err_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

cleanup_on_exit() {
    local exit_status=$?
    
    if [ $exit_status -ne 0 ]; then
        err_msg "Script failed with code $exit_status"
    fi
    
    log_msg "Running cleanup..."
    
    # Remove temp directory
    if [ -d "$CLONE_DIR" ]; then
        cd "$SCRIPT_DIR"
        rm -rf "$CLONE_DIR"
    fi
    
    # Clean up created resources
    [ -n "$GROUP_ID" ] && cleanup_group "$GROUP_ID"
    [ -n "$USER_ID" ] && cleanup_user "$USER_ID"
    [ -n "$PROJECT_ID" ] && cleanup_project "$PROJECT_ID"
    
    log_msg "Cleanup done. Log saved to: $LOG_FILE"
}

trap cleanup_on_exit EXIT

verify_tools() {
    log_msg "Checking required tools..."
    
    local deps="git curl jq robot"
    for tool in $deps; do
        if ! command -v "$tool" > /dev/null 2>&1; then
            err_msg "Missing dependency: $tool"
            echo "Install missing tools:"
            echo "  git, curl, jq"
            echo "  pip install robotframework robotframework-requests"
            exit 1
        fi
    done
}

verify_config() {
    log_msg "Validating configuration..."
    
    if [ -z "${GITLAB_API_URL:-}" ] || [ -z "${GITLAB_PRIVATE_TOKEN:-}" ] || [ -z "${SAMPLE_PROJECT_REPO:-}" ]; then
        err_msg "Missing environment variables"
        echo ""
        echo "Required variables:"
        echo "  export GITLAB_API_URL='https://gitlab.example.com'"
        echo "  export GITLAB_PRIVATE_TOKEN='your-token'"
        echo "  export SAMPLE_PROJECT_REPO='https://gitlab.example.com/group/project.git'"
        exit 1
    fi
    
    # Quick sanity check on URLs
    [[ ! "$GITLAB_API_URL" =~ ^https?:// ]] && { err_msg "Invalid GITLAB_API_URL"; exit 1; }
    [[ ! "$SAMPLE_PROJECT_REPO" =~ ^https?:// ]] && { err_msg "Invalid SAMPLE_PROJECT_REPO"; exit 1; }
}

test_connection() {
    log_msg "Testing GitLab connection..."
    
    local resp
    resp=$(curl -sf -H "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
        "${GITLAB_API_URL}/api/v4/version" 2>&1) || {
        err_msg "Cannot connect to GitLab API"
        exit 1
    }
    
    local ver=$(echo "$resp" | jq -r '.version')
    log_msg "Connected to GitLab v${ver}"
}


#------------------------------------------------------------------------------
# GitLab operations
#------------------------------------------------------------------------------

create_test_group() {
    log_msg "Creating test group..."
    
    local resp
    resp=$(curl -sf -H "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
        -X POST "${GITLAB_API_URL}/api/v4/groups" \
        -d "name=${GROUP_NAME}" \
        -d "path=${GROUP_PATH}") || return 1
    
    GROUP_ID=$(echo "$resp" | jq -r '.id')
    [ -z "$GROUP_ID" ] || [ "$GROUP_ID" = "null" ] && return 1
    
    log_msg "Group created: $GROUP_ID"
}

create_test_user() {
    log_msg "Creating test user..."
    
    local resp
    resp=$(curl -sf -H "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
        -X POST "${GITLAB_API_URL}/api/v4/users" \
        -d "email=${USER_EMAIL}" \
        -d "username=${USER_USERNAME}" \
        -d "name=${USER_NAME}" \
        -d "password=${USER_PASSWORD}" \
        -d "skip_confirmation=true") || return 1
    
    USER_ID=$(echo "$resp" | jq -r '.id')
    [ -z "$USER_ID" ] || [ "$USER_ID" = "null" ] && return 1
    
    log_msg "User created: $USER_ID"
}

add_member() {
    log_msg "Adding user to group..."
    
    curl -sf -H "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
        -X POST "${GITLAB_API_URL}/api/v4/groups/${GROUP_ID}/members" \
        -d "user_id=${USER_ID}" \
        -d "access_level=${ACCESS_LEVEL}" > /dev/null || return 1
    
    log_msg "Member added successfully"
}

cleanup_project() {
    local pid=$1
    local code
    code=$(curl -sw "%{http_code}" -o /dev/null \
        -H "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
        -X DELETE "${GITLAB_API_URL}/api/v4/projects/${pid}")
    
    [[ "$code" =~ ^(200|202|204)$ ]] && log_msg "Project deleted" || err_msg "Failed to delete project"
}

cleanup_user() {
    local uid=$1
    local code
    code=$(curl -sw "%{http_code}" -o /dev/null \
        -H "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
        -X DELETE "${GITLAB_API_URL}/api/v4/users/${uid}")
    
    [[ "$code" =~ ^(200|202|204)$ ]] && log_msg "User deleted" || err_msg "Failed to delete user"
}

cleanup_group() {
    local gid=$1
    local code
    code=$(curl -sw "%{http_code}" -o /dev/null \
        -H "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
        -X DELETE "${GITLAB_API_URL}/api/v4/groups/${gid}")
    
    [[ "$code" =~ ^(200|202|204)$ ]] && log_msg "Group deleted" || err_msg "Failed to delete group"
}

main() {
    log_msg "Starting GitLab integration test"
    
    verify_tools
    verify_config
    test_connection
    
    clone_repo || exit 1
    
    create_test_group || exit 1
    create_test_user || exit 1
    add_member || exit 1
    
    return 0
}

main