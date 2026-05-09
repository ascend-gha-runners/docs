# GitHub Actions Integration Guide

> This document is for open-source community administrators, guiding you through integrating your project with the GitHub Actions CI system to run CI tasks on Ascend NPU compute resources.

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                        Your Project Repository (GitHub)                        │
│ https://github.com/<org>/<repo>                                                │
│ .github/workflows/*.yaml                                                       │
└────────────────────────┬───────────────────────────────────────────────────────┘
                         │ GitHub Event Trigger
                         │ (push/PR/schedule, etc.)
                         ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│                        GitHub Actions Cloud                                     │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│   │  Workflow   │───▶│   Runner    │───▶│    Pod      │───▶│    Job      │     │
│   │  Define Flow│───▶│  Scale Set  │───▶│  Executor   │───▶│  Run Task   │     │
│   └─────────────┘    └─────────────┘    └──────┬──────┘    └─────────────┘     │
└────────────────────────────────────────────────┼───────────────────────────────┘
                                                  │ GitHub App/PAT Authentication
                                                  ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│                       Infrastructure Kubernetes Clusters                       │
│   ┌─────────────────────┐              ┌─────────────────────┐                 │
│   │  CN12-001 Cluster   │              │   HK-001 Cluster    │                 │
│   │   Ascend 910A3      │              │   Ascend 910A2B3    │                 │
│   │  runner: 310p/910c  │              │ runner: arm64-npu   │                 │
│   └─────────────────────┘              └─────────────────────┘                 │
└────────────────────────────────────────────────────────────────────────────────┘
```

We implement GitHub Action tasks on Ascend cluster nodes based on [ARC](https://github.com/actions/actions-runner-controller/).

## Runner Pod Types and Naming Methods

Ascend clusters create runner pods to execute GitHub Action jobs. We offer the following types of Ascend chips. If no name is specified, the default naming will be applied.

|Type|Architecture|Number of Nodes|Number of chips per Node|Default name(x = chip count)|
|--|--|--|--|--|
|310P3|arm64|1|8|linux-aarch64-310p-x|
|910C|arm64|2|16|linux-aarch64-910c-x|
|910B4|arm64|4|8|linux-arm64-npu-x|
|910B1|arm64|4|8|linux-aarch64-a2-x|

### Runner Naming Convention

The naming convention for runner pod is composed of the following parts:

```
linux-arm64-npu-x
^     ^     ^   ^
|     |     |   |
|     |     |   Number of NPUs Available
|     |     NPU Designator
|     Architecture
Operating System
```

## Onboarding Flowchart

```
                       Start
                         │
                         ▼
┌───────────────────────────────────────────────────────────────────┐
│ Step 1: Choose Installation Scope and Authentication Method        │
│ You: Determine organization-level or repository-level installation │
│ You: Choose GitHub App or PAT authentication                       │
│ Acceptance: Installation plan clarified                            │
└────────────────────────┬──────────────────────────────────────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────────────────┐
│ Step 2: Prepare Permissions and Credentials                       │
│ You: Obtain organization or repository admin permissions          │
│ You: (Optional) Create GitHub App or PAT                          │
│ Acceptance: Permissions and credentials ready                     │
└────────────────────────┬──────────────────────────────────────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────────────────┐
│ Step 3: Install GitHub App or Submit PAT                          │
│ You: Install App on GitHub or generate PAT                        │
│ We: Provide installation guidance                                 │
│ Acceptance: App installed or PAT generated                        │
└────────────────────────┬──────────────────────────────────────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────────────────┐
│ Step 4: Submit Activation Request                                 │
│ You: Submit request via Issue or email                            │
│ We: Deploy and configure Runner                                   │
│ Acceptance: Request confirmation received                         │
└────────────────────────┬──────────────────────────────────────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────────────────┐
│ Step 5: Validate Runner Availability                              │
│ You: Check Runner status in repository Settings                   │
│ We: Assist with connection troubleshooting                        │
│ Acceptance: Runner status shows Online                            │
└────────────────────────┬──────────────────────────────────────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────────────────┐
│ Step 6: Write and Test Workflow                                   │
│ You: Write workflow file using NPU                                │
│ We: Provide templates and best practices                          │
│ Acceptance: Workflow successfully runs on NPU                     │
└────────────────────────┬──────────────────────────────────────────┘
                         │
                         ▼
                Integration Complete
```

## Detailed Steps

### Step 1: Choose Installation Scope and Authentication Method

**Goal**: Determine the Runner installation scope (organization-level or repository-level) and authentication method (GitHub App or PAT).

What you need to do:

1. **Determine installation scope**:
   - **Organization-level installation**: Runner can be reused across all repositories under the organization, access control via Runner Groups
   - **Repository-level installation**: Runner is only available for a single repository

2. **Choose authentication method**:
   - **GitHub App** (Recommended): More secure, fine-grained permission control, but requires organization admin permissions
   - **PAT (Personal Access Token)**: Suitable for scenarios where organization permissions cannot be obtained, note Token expiration

Comparison table:

| Approach | Advantages | Disadvantages | Use Case |
|----------|------------|---------------|----------|
| Organization + GitHub App | High security, fine-grained permission control | Requires organization admin permissions | Multi-repository reuse, production environment |
| Organization + PAT | Lower permission requirements | Token needs periodic updates | Temporary testing, restricted permissions |
| Repository + GitHub App | No organization permissions needed | Only single repository available | Single repository projects |
| Repository + PAT | Lowest permission requirements | Token needs periodic updates, single repository | Quick testing, restricted permissions |

How to verify this step is complete:

- Installation scope clarified (organization or repository)
- Appropriate authentication method chosen (GitHub App or PAT)
- Necessary permissions confirmed

---

### Step 2: Prepare Permissions and Credentials

**Goal**: Ensure necessary permissions are in place and prepare authentication credentials.

What you need to do:

#### If choosing GitHub App method:

1. **Verify permissions**:
   - Organization-level installation: Requires **Owner** permissions for the organization
   - Repository-level installation: Requires **Owner** permissions for the organization + **Admin** permissions for the repository

2. **Install GitHub App**:
   - Visit [apps/ascend-runner-mgmt](https://github.com/apps/ascend-runner-mgmt) in your browser
   - Click `Install`
   - Select target organization
   - Select repository scope:
     - Organization-level: Select `All repositories`
     - Repository-level: Select `Only select repositories`, then choose target repositories
   - Click `Install`

![alt text](assets/user-manual-zh/image-3.png)

#### If choosing PAT method:

1. **Create Personal Access Token**:
   - Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Click `Generate new token (classic)`
   - Fill in Token description, e.g.: `Ascend NPU Runner`
   - Select scopes:
     - Organization-level: Select `admin:org`
     - Repository-level: Select `repo`
   - Set expiration (recommended 90 days)
   - Click `Generate token`
   - **Copy and save the Token immediately** (Token is only displayed once)

![alt text](assets/user-manual-zh/image-23.png)

2. **Important notes**:
   - After Token expires, Runner will stop working and requires regeneration
   - Do not commit Token to code repositories or share through public channels

What we do:

- Provide detailed permission requirements and Token creation guidance
- Assist with permission troubleshooting

How to verify this step is complete:

- GitHub App successfully installed to target organization or repository
- Or PAT successfully created and securely saved

---

### Step 3: Submit Activation Request

**Goal**: Submit Runner activation request to infrastructure team and wait for deployment.

What you need to do:

#### If choosing GitHub App method:

1. **Submit Issue request**:
   - Visit [ascend-gha-runners/org-archive/issues](https://github.com/ascend-gha-runners/org-archive/issues)
   - Click `New issue`
   - Select corresponding template:
     - Organization-level: Select `Add Or Modify Organization`
     - Repository-level: Select `Add Or Modify Repository`

![alt text](assets/user-manual-zh/image-17.png)

2. **Fill in request information**:

   **Organization-level request** needs:
   ```
   org-name: <your-organization-name>
   runner-group-name: Default (or custom Runner Group name)
   runner-names: linux-arm64-npu-1 (or custom Runner names, comma-separated for multiple)
   ```
   
   ![alt text](assets/user-manual-zh/image-1.png)
   
   **Repository-level request** needs:
   ```
   repo-name: <org-name/repo-name>
   runner-names: linux-arm64-npu-1 (or custom Runner names, comma-separated for multiple)
   ```
   
   ![alt text](assets/user-manual-zh/image-2.png)

3. **Click `Create` to submit request**

#### If choosing PAT method:

Considering Token security requirements, send an email to `gouzhonglin@huawei.com`:

1. **Email subject**: `Request Ascend NPU Runners`

2. **Email content template**:

   **Organization-level request**:
   ```yaml
   repo: https://github.com/my-org/
   runner-group: ascend-ci
   token: ghp_xxx
   expire-at: 30days
   runner-names: linux-arm64-npu-1
   ```
   
   **Repository-level request**:
   ```yaml
   repo: https://github.com/my-org/my-repo
   token: ghp_xxx
   expire-at: 30days
   runner-names: linux-arm64-npu-1
   ```

3. **Send email and wait for confirmation reply**

What we do:

- After receiving request, deploy and configure Runner in Kubernetes cluster
- Configure Runner Scale Set and register with GitHub
- Verify Runner connection status

How to verify this step is complete:

- GitHub App method: Issue submitted, received confirmation reply from infrastructure team
- PAT method: Email sent, received confirmation reply

---

### Step 4: (Optional) Configure Runner Group

**Goal**: Configure Runner Group for organization-level installation to control which repositories can use the Runner.

What you need to do:

1. **Create Runner Group** (if default Runner Group doesn't meet requirements):
   - Navigate to organization → `Settings` → `Actions` → `Runner groups`
   - Click `New runner group`
   - Fill in name, e.g.: `ascend-ci`
   - Configure repository access permissions:
     - `Repository access`: Select `All repositories` or `Selected repositories`
     - `Visibility`: Select `Private` or `Public`
   - Click `Create group`

2. **Configure Runner Group**:
   - Runner Group has 3 configuration options:
     - **Repositories**: All repositories in organization / Specific repositories
     - **Repository access**: private / public
     - **workflow**: All workflows / Specific workflows
   - Repositories meeting all 3 configurations can use organization's Runner

3. **Important notes**:
   - If no Runner Group specified, default Runner Group will be used
   - Default Runner Group configuration: All repositories + Private + All Workflows
   - Default Runner Group permissions can be modified

How to verify this step is complete:

- Runner Group created or using default Runner Group
- Runner Group repository access permissions configured as expected

---

### Step 5: Validate Runner Availability

**Goal**: Confirm Runner successfully deployed and connected to GitHub, status is Online.

What you need to do:

1. **Check Runner status**:
   - Navigate to your repository → `Settings` → `Actions` → `Runners`
   - Or navigate to organization → `Settings` → `Actions` → `Runners`

2. **Confirm Runner list**:
   - `Runner scale set`: Runners configured for the repository
   - `Shared with this repository`: Organization runners accessible to the repository
   - Check `Status` column: **Green `Online`** indicates Runner connected and available

![alt text](assets/user-manual-zh/image-24.png)

3. **If status is not Online**:
   - Check if GitHub App is correctly installed
   - Check if PAT is valid and not expired
   - Check Runner Group permission configuration
   - Contact infrastructure team for troubleshooting

What we do:

- Monitor Runner deployment status
- Assist with connection troubleshooting
- Confirm Runner Scale Set running normally

How to verify this step is complete:

- Can see Runner in GitHub Settings
- Runner status shows **Online** (green dot)

---

### Step 6: Write and Test Workflow

**Goal**: Write GitHub Actions workflow file, correctly use NPU Runner to execute tasks.

What you need to do:

1. **Create workflow file**:
   - Create `.github/workflows/` directory in repository root
   - Create YAML file, e.g.: `npu-test.yml`

2. **Write workflow**:

**Example workflow**:

```yaml
name: Test NPU Runner
on:
  workflow_dispatch:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test-npu:
    runs-on: linux-arm64-npu-1
    container:
      image: ascendai/cann:latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Show NPU info
        run: |
          npu-smi info
          echo "NPU is ready!"
      
      - name: Run tests
        run: |
          # Your test commands
          echo "Running tests on NPU..."
```

3. **Key field descriptions**:

| Field | Meaning | Example | Description |
|-------|---------|---------|-------------|
| `runs-on` | **Runner label** | `linux-arm64-npu-1` | **Required**, specify which Runner to use, must match name requested in Step 3 |
| `container.image` | **Runtime image** | `ascendai/cann:latest` | **Required**, specify container image with NPU drivers, otherwise NPU resources won't be allocated |
| `container.options` | Container options | `--privileged` | Optional, specify container runtime options |
| `steps` | Task steps | See example | Define specific steps to execute |

4. **Resource class selection**:

Choose corresponding NPU card count based on requested Runner name:

| Runner Name | NPU Cards | CPU | Memory | Use Case |
|-------------|-----------|-----|--------|----------|
| `linux-arm64-npu-1` | 1 card | 23 cores | 64Gi | Lightweight testing |
| `linux-arm64-npu-2` | 2 cards | 39-46 cores | 128Gi | Standard testing (recommended) |
| `linux-arm64-npu-4` | 4 cards | 78 cores | 256Gi | Medium-scale testing |
| `linux-arm64-npu-8` | 8 cards | 156 cores | 512Gi | Large-scale testing |

> **Note**: If specified Runner in `runs-on` doesn't exist or is offline, workflow will wait until Runner becomes available.

5. **Submit and test**:
   - Commit workflow file to repository
   - Trigger methods:
     - Manual trigger: On GitHub → Actions page select workflow and click `Run workflow`
     - Automatic trigger: Push code or create PR

What we do:

- Provide workflow templates and best practices
- Assist with workflow troubleshooting
- Confirm NPU resources correctly allocated

How to verify this step is complete:

- Workflow file committed to repository
- Workflow successfully triggered and running
- Logs show NPU information (`npu-smi info` output normal)
- Task successfully executed on NPU

Validation checklist:

- [ ] Installation scope clarified (organization-level or repository-level)
- [ ] Authentication method chosen (GitHub App or PAT)
- [ ] GitHub App installed or PAT generated
- [ ] Activation request submitted, received confirmation from infrastructure team
- [ ] Runner Group configured (if needed)
- [ ] Can see Runner in GitHub Settings
- [ ] Runner status shows Online (green)
- [ ] `.github/workflows/*.yaml` committed to repository
- [ ] Workflow uses correct `runs-on` label
- [ ] Workflow specifies `container.image`
- [ ] Workflow successfully triggered and running
- [ ] Job successfully executed on Ascend NPU

---

## FAQ

**Q1: How do I know if my organization has permission to install GitHub App?**

Requires organization Owner permissions. If unsure, contact your organization administrator. To check:
- Navigate to organization → `Settings` → `Members` → view your role

**Q2: What if Runner status stays Offline?**

- Check if GitHub App is correctly installed (Settings → Applications)
- Check if PAT is valid and not expired
- Confirm Runner Group permission configuration is correct
- Contact infrastructure team to troubleshoot Runner Pod status

**Q3: Workflow keeps waiting for Runner, cannot run?**

- Confirm `runs-on` field value matches requested Runner name exactly
- Check if Runner status is Online
- Confirm repository has access to the Runner (Runner Group configuration)
- If using custom Runner name, confirm it was specified in request

**Q4: Workflow runs with error "no space left on device"?**

- May be due to large container image or excessive intermediate files
- Add cleanup steps in workflow:
  ```yaml
  - name: Clean up
    run: |
      docker system prune -af
      rm -rf /tmp/*
  ```

**Q5: How to use multiple NPU cards?**

Specify corresponding card count Runner name in `runs-on`:
- 2 cards: `linux-arm64-npu-2`
- 4 cards: `linux-arm64-npu-4`
- 8 cards: `linux-arm64-npu-8`

**Q6: What to do when PAT expires?**

- Regenerate PAT (refer to Step 2)
- Send new Token to infrastructure team via email
- Wait for infrastructure team to update configuration

**Q7: How to share Runner across multiple repositories?**

- Use organization-level installation (install to organization via GitHub App or PAT)
- Control repository access via Runner Group
- Use organization Runner label directly in repository workflows

**Q8: How to use custom container image in workflow?**

```yaml
jobs:
  test:
    runs-on: linux-arm64-npu-1
    container:
      image: your-registry/your-image:tag
      credentials:
        username: ${{ secrets.REGISTRY_USERNAME }}
        password: ${{ secrets.REGISTRY_PASSWORD }}
```

**Q9: How to view workflow execution logs?**

- Navigate to repository → `Actions` tab
- Click specific workflow run record
- Click individual jobs and steps to view detailed logs

**Q10: What if project needs multiple types of NPU simultaneously?**

- Request multiple Runners at once in request (comma-separated names)
- Example: `runner-names: linux-arm64-npu-1, linux-aarch64-310p-2`
- Use different `runs-on` labels in different jobs

---

## Feedback & Support

If you encounter any issues during integration, please report through:

- **Submit Discussion**: [https://github.com/ascend-gha-runners/docs/discussions](https://github.com/ascend-gha-runners/docs/discussions)
- When submitting, please provide:
  - Project name and Git repository URL
  - Issue description and error log screenshots
  - Completed steps and where stuck
  - Installation method used (GitHub App or PAT)
  - Runner name and status

---

*Document version: v2.0*  
*Last updated: 2026-04-28*