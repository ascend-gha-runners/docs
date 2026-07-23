# Workflow Actions 使用清单

## 文件清单

_schedule_image_build.yaml、_nightly_image_build.yaml、schedule_weekly_test_a3.yaml、/schedule_vllm_e2e_test.yaml、schedule_update_estimated_times.yaml、
schedule_release_code_and_wheel.yml、schedule_nightly_test_a3.yaml、schedule_lint_image_build.yaml、schedule_image_build_and_push.yaml、labeled_doctest.yaml

## Action 汇总

### 官方 Actions

| Action | 使用次数 |
| --- | ---: |
| `actions/checkout@v7` | 41 |
| `actions/download-artifact@v8` | 6 |
| `actions/github-script@v9` | 5 |
| `actions/github-script@3a2844b7e9c422d3c10d287c895573f7108da1b3` | 1 |
| `actions/labeler@v6` | 1 |
| `actions/setup-python@v6` | 3 |
| `actions/setup-python@a309ff8b426b58ec0e2a45f0f869d46889d02405` | 5 |
| `actions/stale@v10` | 2 |
| `actions/upload-artifact@v7` | 12 |
| `actions/upload-artifact/merge@v7` | 3 |

### Docker Actions

| Action | 使用次数 |
| --- | ---: |
| `docker/build-push-action@v7` | 3 |
| `docker/login-action@v4` | 5 |
| `docker/metadata-action@v6` | 2 |
| `docker/setup-buildx-action@v4` | 4 |
| `docker/setup-qemu-action@v4` | 1 |

### Runs-on Actions

| Action | 使用次数 |
| --- | ---: |
| `runs-on/cache@v5` | 4 |
| `runs-on/cache/restore@v5` | 2 |
| `runs-on/cache/save@v5` | 1 |

### 三方 Actions

| Action | 使用次数 |
| --- | ---: |
| `ascend-gha-runners/artifact/upload@v0.3` | 4 |
| `dorny/paths-filter@v4` | 2 |
| `eps1lon/actions-label-merge-conflict@v3` | 1 |
| `github/issue-labeler@v3.4` | 1 |
| `jlumbroso/free-disk-space@54081f138730dfa15788a46383842cd2f914a1be` | 4 |
| `peter-evans/create-or-update-comment@v5` | 7 |
| `peter-evans/slash-command-dispatch@v5` | 1 |
| `tj-actions/changed-files@v47` | 1 |

### 本地 Action

| Action | 使用次数 |
| --- | ---: |
| `./.github/actions/read-vllm-release-tag` | 1 |


## 各 Workflow 使用清单

### `.github/workflows/_e2e_nightly_multi_node.yaml`

- `actions/checkout@v7`
- `ascend-gha-runners/artifact/upload@v0.3`
- `actions/upload-artifact@v7`

### `.github/workflows/_e2e_nightly_single_node.yaml`

- `actions/checkout@v7`
- `ascend-gha-runners/artifact/upload@v0.3`
- `actions/upload-artifact@v7`

### `.github/workflows/_e2e_nightly_single_node_models.yaml`

- `actions/checkout@v7`
- `ascend-gha-runners/artifact/upload@v0.3`
- `actions/upload-artifact@v7`

### `.github/workflows/_nightly_image_build.yaml`

- `actions/checkout@v7`

### `.github/workflows/_schedule_image_build.yaml`

- `actions/checkout@v7`
- `jlumbroso/free-disk-space@54081f138730dfa15788a46383842cd2f914a1be`
- `docker/login-action@v4`
- `docker/setup-buildx-action@v4`
- `runs-on/cache/restore@v5`
- `docker/build-push-action@v7`
- `actions/upload-artifact@v7`
- `actions/download-artifact@v8`
- `docker/metadata-action@v6`

### `.github/workflows/_selected_tests.yaml`

- `actions/checkout@v7`
- `dorny/paths-filter@v4`
- `runs-on/cache/restore@v5`
- `runs-on/cache/save@v5`
- `actions/upload-artifact@v7`

### `.github/workflows/bot_issue_manage.yaml`

- `github/issue-labeler@v3.4`

### `.github/workflows/bot_merge_conflict.yaml`

- `eps1lon/actions-label-merge-conflict@v3`

### `.github/workflows/bot_pr_create.yaml`

- `actions/labeler@v6`
- `actions/github-script@3a2844b7e9c422d3c10d287c895573f7108da1b3`

### `.github/workflows/labeled_doctest.yaml`

- `actions/checkout@v7`

### `.github/workflows/labled_download_model_dataset.yaml`

- `actions/checkout@v7`

### `.github/workflows/pr_close_cancel_job.yaml`

- `actions/github-script@v9`

### `.github/workflows/pr_e2e_command.yml`

- `peter-evans/create-or-update-comment@v5`
- `actions/checkout@v7`

### `.github/workflows/pr_nightly_command.yml`

- `actions/checkout@v7`
- `peter-evans/create-or-update-comment@v5`

### `.github/workflows/pr_rerun_command.yml`

- `peter-evans/create-or-update-comment@v5`

### `.github/workflows/pr_test.yaml`

- `actions/checkout@v7`
- `dorny/paths-filter@v4`

### `.github/workflows/push_build_csrc_cache.yaml`

- `actions/checkout@v7`
- `runs-on/cache@v5`

### `.github/workflows/schedule_doc_linkcheck.yaml`

- `actions/checkout@v7`
- `tj-actions/changed-files@v47`
- `actions/upload-artifact@v7`

### `.github/workflows/schedule_doc_translate.yaml`

- `actions/checkout@v7`
- `actions/setup-python@v6`
- `actions/github-script@v9`

### `.github/workflows/schedule_image_build_and_push.yaml`

- `./.github/workflows/_schedule_image_build.yaml`

### `.github/workflows/schedule_lint_image_build.yaml`

- `actions/checkout@v7`
- `docker/metadata-action@v6`
- `docker/setup-qemu-action@v4`
- `docker/setup-buildx-action@v4`
- `docker/login-action@v4`
- `docker/build-push-action@v7`

### `.github/workflows/schedule_nightly_test_a2.yaml`

- `actions/github-script@v9`
- `actions/checkout@v7`
- `actions/upload-artifact/merge@v7`

### `.github/workflows/schedule_nightly_test_a3.yaml`

- `actions/github-script@v9`
- `actions/upload-artifact/merge@v7`

### `.github/workflows/schedule_release_code_and_wheel.yml`

- `actions/checkout@v7`
- `actions/setup-python@a309ff8b426b58ec0e2a45f0f869d46889d02405`
- `actions/upload-artifact@v7`
- `jlumbroso/free-disk-space@54081f138730dfa15788a46383842cd2f914a1be`
- `actions/download-artifact@v8`

### `.github/workflows/schedule_stale_manage.yaml`

- `actions/stale@v10`

### `.github/workflows/schedule_update_estimated_times.yaml`

- `actions/checkout@v7`
- `actions/setup-python@v6`
- `actions/download-artifact@v8`
- `actions/github-script@v9`

### `.github/workflows/schedule_vllm_e2e_test.yaml`

- `actions/checkout@v7`
- `runs-on/cache@v5`

### `.github/workflows/schedule_weekly_test_a2.yaml`

- `./.github/workflows/labeled_doctest.yaml`

### `.github/workflows/schedule_weekly_test_a3.yaml`

- `actions/upload-artifact/merge@v7`

### `.github/workflows/slash_command_dispatch.yml`

- `peter-evans/slash-command-dispatch@v5`
