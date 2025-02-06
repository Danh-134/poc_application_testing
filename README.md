# How to use this testing

Below is an example Bash script that performs the following GitLab tests

1. **Clone a sample project repository** using an OAuth token.
2. **Create a GitLab group** via the GitLab API.
3. **Create a GitLab user** via the GitLab API.
4. **Add the new user to the new group**.
5. **Modify the project's README.md**, commit the change, and push it back to the repository.
6. **Create and run a sample Robot Framework test case** that calls a GitLab API endpoint.

> **Before Running the Script:**
> 
> - Ensure you have installed [jq](https://stedolan.github.io/jq/) for JSON parsing.
> - Ensure that [Robot Framework](https://robotframework.org/) is installed (for example, by using the `robotframework/robotframework` Docker image or installing via pip).  
> - Export the following environment variables:
>   - `GITLAB_API_URL` – Your GitLab instance URL (e.g. `https://gitlab.example.com`).
>   - `GITLAB_PRIVATE_TOKEN` – A personal access token with permissions to create users, groups, and push commits.
>   - `SAMPLE_PROJECT_REPO` – The HTTPS URL of your sample project repository (for token authentication, use a URL like `https://gitlab.example.com/group/project.git`).

Save the script below as (for example) `gitlab_feature_test.sh` and make it executable (`chmod +x gitlab_feature_test.sh`).

## How to Use This Script

1. **Set Environment Variables:**  
   Before running the script, export the required environment variables in your shell:

   ```bash
   export GITLAB_API_URL="https://gitlab.example.com"
   export GITLAB_PRIVATE_TOKEN="your_private_token_here"
   export SAMPLE_PROJECT_REPO="https://gitlab.example.com/your-group/your-project.git"
   ```

2. **Run the Script:**

   ```bash
   ./gitlab_feature_test.sh
   ```

This script will perform all the operations sequentially and print output to your console. Adjust the parameters (like user details, group names, etc.) as needed for your testing environment
