# Setup Guide

This guide walks through the two required steps to integrate your GitHub organization with Ascend NPU CI runners in HA mode:

1. [Install the GitHub App](#step-1-install-the-github-app)
2. [Create Runner Groups](#step-2-create-runner-groups)

---

## Step 1: Install the GitHub App

### Prerequisites

Requires **organization admin** permissions.

### Steps

1. Open [apps/ascend-runner-mgmt](https://github.com/apps/ascend-runner-mgmt) in your browser and click **Install**.
2. Select the **GitHub Organization** where you want to install the app.
3. Choose the repository scope:
   - **Only select repositories** — select `vllm-ascend` and `vllm-omni`.
4. Review the requested permissions and click **Install**.

---

## Step 2: Create Runner Groups

Runner groups control which repositories and workflows can access the organization's self-hosted runners. You need to create **two runner groups** for the selected repositories.

### Navigate to Runner Groups

In your GitHub organization, go to **Settings** (①) → **Actions** (②) → **Runner groups** (③), then click **New runner group** (④).

![Navigate to Runner Groups](image-1.png)

---

### Runner Group: Selected Repositories

This group restricts runner access to specific repositories only.

1. **Group name** (①): Two groups need to be created, named `guiyang-cluster` and `cn12-cluster` respectively.
2. **Repository access** (②): Select **Selected repositories**, click the gear icon to pick the target repositories, and select `vllm-ascend` and `vllm-omni`.
3. **Workflow access** (③): Keep the default **All workflows**.
4. Click **Create group** (④) to finish.

![Create Runner Group Form](image-2.png)
