#!/bin/bash
set -e

# Check required environment variables.
if [[ -z "$GITLAB_API_URL" ]] || [[ -z "$GITLAB_PRIVATE_TOKEN" ]] || [[ -z "$SAMPLE_PROJECT_REPO" ]]; then
  echo "Missing required environment variables."
  echo "Please set GITLAB_API_URL, GITLAB_PRIVATE_TOKEN, and SAMPLE_PROJECT_REPO."
  exit 1
fi

# Variables used in this script
GIT_COMMITTER_NAME="CI Bot"
GIT_COMMITTER_EMAIL="ci@example.com"
CLONE_DIR="sample-project"
GROUP_NAME="CI-Test-Group"
GROUP_PATH="ci-test-group"
USER_EMAIL="newuser@example.com"
USER_USERNAME="newuser"
USER_NAME="New User"
USER_PASSWORD="NewUserPassword"
ACCESS_LEVEL=30  # Developer role

echo "=== Cloning the sample project repository ==="
# Clone the repository using OAuth token embedded in the URL.
git clone "https://oauth2:${GITLAB_PRIVATE_TOKEN}@${SAMPLE_PROJECT_REPO#https://}" "$CLONE_DIR"
cd "$CLONE_DIR" || exit 1

###############################################
# Create a new GitLab group via API
###############################################
echo "=== Creating a new GitLab group via API ==="
GROUP_CREATE_RESPONSE=$(curl --silent --fail --header "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
  -X POST "${GITLAB_API_URL}/api/v4/groups" \
  -d "name=${GROUP_NAME}" \
  -d "path=${GROUP_PATH}")
echo "Group creation response: $GROUP_CREATE_RESPONSE"

# Extract group ID using jq
GROUP_ID=$(echo "$GROUP_CREATE_RESPONSE" | jq -r '.id')
echo "Created group with ID: $GROUP_ID"

###############################################
# Create a new GitLab user via API
###############################################
echo "=== Creating a new GitLab user via API ==="
USER_CREATE_RESPONSE=$(curl --silent --fail --header "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
  -X POST "${GITLAB_API_URL}/api/v4/users" \
  -d "email=${USER_EMAIL}" \
  -d "username=${USER_USERNAME}" \
  -d "name=${USER_NAME}" \
  -d "password=${USER_PASSWORD}")
echo "User creation response: $USER_CREATE_RESPONSE"

# Extract user ID using jq
USER_ID=$(echo "$USER_CREATE_RESPONSE" | jq -r '.id')
echo "Created user with ID: $USER_ID"

####################################################
# Add the newly created user to the new group via API
####################################################
echo "=== Adding the new user to the group ==="
ADD_MEMBER_RESPONSE=$(curl --silent --fail --header "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
  -X POST "${GITLAB_API_URL}/api/v4/groups/${GROUP_ID}/members" \
  -d "user_id=${USER_ID}" \
  -d "access_level=${ACCESS_LEVEL}")
echo "Add member response: $ADD_MEMBER_RESPONSE"

####################################################
# Modify README.md, commit, and push changes
####################################################
echo "=== Modifying README.md ==="
echo "Updated by CI pipeline on $(date)" >> README.md

echo "=== Configuring Git and pushing changes ==="
git config --global user.email "$GIT_COMMITTER_EMAIL"
git config --global user.name "$GIT_COMMITTER_NAME"
git add README.md
git commit -m "Update README.md via CI pipeline"
git push origin HEAD

####################################################################
# Deletion API calls: Delete project, delete user, and delete group
####################################################################
#
# Note: Deleting a project is destructive.
#       The project id is computed from the SAMPLE_PROJECT_REPO.
####################################################################

# --- Delete the sample project ---
echo "=== Deleting the sample project via API ==="
# Extract the group/project portion from the repo URL.
# SAMPLE_PROJECT_REPO is expected to be like: https://gitlab.example.com/group/project.git
PROJECT_PATH_WITH_DOMAIN="${SAMPLE_PROJECT_REPO#https://}"
# Remove the domain (first part) to obtain group/project
PROJECT_PATH=$(echo "$PROJECT_PATH_WITH_DOMAIN" | cut -d'/' -f2-)
# Remove the .git suffix if present
PROJECT_PATH=$(echo "$PROJECT_PATH" | sed 's/\.git$//')
# URL-encode the project path by replacing "/" with "%2F"
PROJECT_ID=$(echo "$PROJECT_PATH" | sed 's/\//%2F/g')
echo "Deleting project with id: $PROJECT_ID"

DELETE_PROJECT_RESPONSE=$(curl --write-out "%{http_code}" --silent --output /dev/null \
  --header "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
  -X DELETE "${GITLAB_API_URL}/api/v4/projects/${PROJECT_ID}")

if [[ "$DELETE_PROJECT_RESPONSE" =~ ^(200|202|204)$ ]]; then
  echo "Project deletion successful with status code: $DELETE_PROJECT_RESPONSE"
else
  echo "Project deletion failed: Expected status code 200/202/204, got $DELETE_PROJECT_RESPONSE"
  exit 1
fi

# --- Delete the created user ---
echo "=== Deleting the created user via API ==="
DELETE_USER_RESPONSE=$(curl --write-out "%{http_code}" --silent --output /dev/null \
  --header "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
  -X DELETE "${GITLAB_API_URL}/api/v4/users/${USER_ID}")

if [[ "$DELETE_USER_RESPONSE" =~ ^(200|202|204)$ ]]; then
  echo "User deletion successful with status code: $DELETE_USER_RESPONSE"
else
  echo "User deletion failed: Expected status code 200/202/204, got $DELETE_USER_RESPONSE"
  exit 1
fi

# --- Delete the created group ---
echo "=== Deleting the created group via API ==="
DELETE_GROUP_RESPONSE=$(curl --write-out "%{http_code}" --silent --output /dev/null \
  --header "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
  -X DELETE "${GITLAB_API_URL}/api/v4/groups/${GROUP_ID}")

if [[ "$DELETE_GROUP_RESPONSE" =~ ^(200|202|204)$ ]]; then
  echo "Group deletion successful with status code: $DELETE_GROUP_RESPONSE"
else
  echo "Group deletion failed: Expected status code 200/202/204, got $DELETE_GROUP_RESPONSE"
  exit 1
fi

####################################################################
# Create and run a sample Robot Framework API test
####################################################################
echo "=== Creating a sample Robot Framework test file ==="
cat > sample_api_test.robot << 'EOF'
*** Settings ***
Library           RequestsLibrary

*** Test Cases ***
Get GitLab Version
    [Documentation]    Verify that the GitLab API returns version information.
    Create Session    gitlab    ${GITLAB_API_URL}
    ${resp}=          GET    gitlab/api/v4/version
    Should Be Equal As Integers    ${resp.status_code}    200
    Log    GitLab version is: ${resp.json()['version']}
EOF

echo "=== Running the Robot Framework test ==="
robot sample_api_test.robot

echo "=== All operations completed successfully. ==="