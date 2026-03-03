# Credentials and Authorization

To integrate your GitHub organization or repository with our Ascend NPU CI cluster (powered by ARC - Actions Runner Controller), we require appropriate authorization. You can choose one of the following two methods based on your security requirements and administrative privileges.

## Comparison of Authorization Methods

| Method | Scope | Requirements | Security | Recommendation |
| :--- | :--- | :--- | :--- | :--- |
| **GitHub App** | Org / Repo | Organization Admin | High (Granular permissions, no expiration) | **Recommended** |
| **PAT (Classic)** | Org / Repo | Repo/Org Admin | Medium (Has expiration, requires manual renewal) | Alternative |

---

## 1. Authorization via GitHub App (Recommended)

This is the most secure and low-maintenance method.

### Steps:
1. **Visit the App Link**: Open [ascend-runner-mgmt](https://github.com/apps/ascend-runner-mgmt) in your browser.
2. **Click Install**:
   - Select the **GitHub Organization** where you want to install the app.
   - **Choose Repository Scope**:
     - **All repositories**: Authorize all current and future repositories in the organization.
     - **Only select repositories**: Authorize only specific repositories.
3. **Complete Installation**: Review the permissions and click `Install`.

### Next Steps:
Once installed, please open an Issue at [ascend-gha-runners/docs](https://github.com/ascend-gha-runners/docs/issues) to activate your configuration.

---

## 2. Authorization via PAT (Personal Access Token)

If you are unable to obtain permissions to install a GitHub App at the organization level, you may use a Personal Access Token.

### Steps:
1. **Create Token**: Go to GitHub [Settings -> Developer settings -> Personal access tokens (classic)](https://github.com/settings/tokens) and generate a new token.
2. **Set Scopes**:
   - **For Organization installation**: Select `admin:org`.
   - **For Repository installation**: Select `repo`.
3. **Set Expiration**: We recommend a longer expiration period, but please ensure you renew it before it expires to avoid CI downtime.

### Submitting Credentials:
Since a PAT is sensitive information, **do not submit it via a public GitHub Issue**. Please send the following details via email to: `wenlang1@h-partners.com`

**Email Subject**: `Request Ascend NPU Runners Credentials`
**Email Body Template**:
```yaml
repo_url: https://github.com/your-org/your-repo
token: ghp_xxxxxxxxxxxx  # Your PAT
expire_at: YYYY-MM-DD    # Expiration date
Machine Type​: A2 or A3
```

---

## FAQ

- **Why are these permissions required?**
  ARC needs these permissions to register self-hosted runners to your organization/repository and to monitor the GitHub Actions job queue for auto-scaling.
- **Is my token secure?**
  We only use the token to communicate with the GitHub API for managing runner instances. Using the GitHub App is the recommended best practice for security.
- **What happens if the token expires?**
  If the token expires, runners will fail to register, and your GitHub Action jobs will remain in a `Starting` state indefinitely. Please send an updated token before expiration.
