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

#------------------------------------------------------------------------------
# Git operations on local machine
#------------------------------------------------------------------------------

clone_repo() {
    log_msg "Cloning repository..."
    
    [ -d "$CLONE_DIR" ] && rm -rf "$CLONE_DIR"
    
    local url="${SAMPLE_PROJECT_REPO#https://}"
    git clone "https://oauth2:${GITLAB_PRIVATE_TOKEN}@${url}" "$CLONE_DIR" || return 1
    
    cd "$CLONE_DIR" || return 1
    log_msg "Repository cloned"
}

commit_and_push() {
    log_msg "Making changes and pushing..."
    
    [ ! -d ".git" ] && { err_msg "Not in git repo"; return 1; }
    
    echo "" >> README.md
    echo "Test run: $(date)" >> README.md
    
    git config user.email "$GIT_COMMITTER_EMAIL"
    git config user.name "$GIT_COMMITTER_NAME"
    git add README.md
    git commit -m "Test commit [skip ci]" || return 1
    git push origin HEAD || return 1
    
    log_msg "Changes pushed"
}

calc_project_id() {
    local path="${SAMPLE_PROJECT_REPO#https://}"
    path=$(echo "$path" | cut -d'/' -f2- | sed 's/\.git$//')
    PROJECT_ID=$(echo "$path" | sed 's/\//%2F/g')
    log_msg "Project identifier: $PROJECT_ID"
}

#------------------------------------------------------------------------------
# Robot Framework tests
#------------------------------------------------------------------------------

write_robot_tests() {
    log_msg "Generating test suite..."
    
    cd "$SCRIPT_DIR"
    
    cat > api_tests.robot << 'ROBOTEOF'
*** Settings ***
Library    RequestsLibrary
Library    Collections

*** Variables ***
${BASE_URL}    %GITLAB_URL%
${TOKEN}       %GITLAB_TOKEN%

*** Test Cases ***
Check API Version
    [Tags]    smoke
    Create Session    api    ${BASE_URL}    verify=${False}
    ${r}=    GET On Session    api    /api/v4/version
    Status Should Be    200    ${r}
    Dictionary Should Contain Key    ${r.json()}    version

Verify Group
    [Tags]    group
    Create Session    api    ${BASE_URL}    verify=${False}
    &{headers}=    Create Dictionary    PRIVATE-TOKEN=${TOKEN}
    ${r}=    GET On Session    api    /api/v4/groups/%GROUP_ID%    headers=${headers}
    Status Should Be    200    ${r}
    Should Be Equal As Strings    ${r.json()}[name]    %GROUP_NAME%

Verify User
    [Tags]    user
    Create Session    api    ${BASE_URL}    verify=${False}
    &{headers}=    Create Dictionary    PRIVATE-TOKEN=${TOKEN}
    ${r}=    GET On Session    api    /api/v4/users/%USER_ID%    headers=${headers}
    Status Should Be    200    ${r}
    Should Be Equal As Strings    ${r.json()}[username]    %USER_NAME%
ROBOTEOF

    # Replace placeholders
    sed -i "s|%GITLAB_URL%|${GITLAB_API_URL}|g" api_tests.robot
    sed -i "s|%GITLAB_TOKEN%|${GITLAB_PRIVATE_TOKEN}|g" api_tests.robot
    sed -i "s|%GROUP_ID%|${GROUP_ID}|g" api_tests.robot
    sed -i "s|%GROUP_NAME%|${GROUP_NAME}|g" api_tests.robot
    sed -i "s|%USER_ID%|${USER_ID}|g" api_tests.robot
    sed -i "s|%USER_NAME%|${USER_USERNAME}|g" api_tests.robot
}

run_tests() {
    log_msg "Running Robot Framework tests..."
    
    cd "$SCRIPT_DIR"
    robot -d results -L INFO api_tests.robot || return 1
    
    log_msg "Tests completed - results in: ${SCRIPT_DIR}/results/"
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
    
    commit_and_push || exit 1
    
    calc_project_id

    cd "$SCRIPT_DIR"
    write_robot_tests || exit 1
    run_tests || exit 1
    
    log_msg "All tests passed"
    log_msg "Summary: Group($GROUP_ID), User($USER_ID)"
    
    return 0
}

main