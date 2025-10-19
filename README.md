# GitLab Integration Testing

Quick test script for GitLab API operations - creates groups, users, makes commits, and runs some Robot Framework tests.

## What it does

The script handles:

- Clones a repo using OAuth token
- Creates a test group and user via API
- Adds the user to the group
- Makes a commit and pushes it
- Runs Robot Framework API tests
- Cleans everything up automatically

## Prerequisites

You'll need these tools installed:

- `git` - for repo operations
- `curl` - API calls
- `jq` - JSON parsing ([grab it here](https://stedolan.github.io/jq/))
- `robot` - Robot Framework testing

Install Robot Framework:

```bash
pip install robotframework robotframework-requests
```

Or use Docker:

```bash
docker pull robotframework/robotframework
```

## Setup

Set these environment variables before running:

```bash
export GITLAB_API_URL="https://gitlab.example.com"
export GITLAB_PRIVATE_TOKEN="your_personal_access_token"
export SAMPLE_PROJECT_REPO="https://gitlab.example.com/group/project.git"
```

**Token permissions needed:**

- Create users & groups
- Push to repositories
- API read access

## Running the tests

Make it executable first:

```bash
   chmod +x gitlab_feature_test.sh
   chmod +x gitlab_feature_testingv2.sh
```

Then just run it:

```bash
   ./gitlab_feature_test.sh
   ./gitlab_feature_testingv2.sh
```

The script validates everything before starting - if something's missing it'll tell you.

## What happens

1. Checks dependencies and config
2. Tests GitLab connection
3. Clones your sample repo
4. Creates a test group (CI-Test-Group)
5. Creates a test user (newuser)
6. Adds user to group with developer access
7. Updates README.md and pushes
8. Generates Robot Framework tests
9. Runs the tests
10. Cleans up everything (even if something fails)

## Output

Logs are saved to `test_run_YYYYMMDD_HHMMSS.log` in the same directory.

Robot Framework results go to the `results/` folder.

## Cleanup

Don't worry about cleanup - it's automatic. The script tracks what it creates and deletes everything on exit (success or failure).

Resources deleted:

- Test group
- Test user  
- Cloned directory
- Project (if specified)

## Customization

Edit these variables in the script if you want different test data:

```bash
GROUP_NAME="CI-Test-Group"
GROUP_PATH="ci-test-group"
USER_EMAIL="newuser@example.com"
USER_USERNAME="newuser"
USER_PASSWORD="NewUserPassword"
ACCESS_LEVEL=30  # 30 = Developer
```

Access levels:

- 10 = Guest
- 20 = Reporter
- 30 = Developer
- 40 = Maintainer
- 50 = Owner

## Troubleshooting

**Connection fails:**

- Check GITLAB_API_URL is correct (include https://)
- Verify token has proper permissions
- Make sure GitLab instance is reachable

**Clone fails:**

- Token needs push access to the repo
- Check SAMPLE_PROJECT_REPO URL is correct
- Remove `.git` suffix or keep it - both work

**Tests fail:**

- Check the `results/log.html` for details
- Verify created resources exist before tests run
- Token might not have API read access

**Dependencies missing:**

```bash
   # Ubuntu/Debian
   apt-get install git curl jq
   pip install robotframework robotframework-requests

   # macOS
   brew install git curl jq
   pip install robotframework robotframework-requests
```

## Notes

- Commit messages include `[skip ci]` to prevent recursive CI runs
- User creation skips email confirmation
- Script uses `set -euo pipefail` for strict error handling
- All curl calls use `-s` (silent) and `-f` (fail on HTTP errors)
