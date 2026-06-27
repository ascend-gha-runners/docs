# Ascend GitHub Action Runners

Self-hosted [GitHub Actions](https://docs.github.com/en/actions) and [Buildkite](https://buildkite.com) runners running on **Ascend NPU** (Huawei AI accelerators), offered as a managed CI service for open-source AI/ML projects. Jobs run on real Ascend chips (Atlas 300I DUO / 800 A2 / A3) with the CANN software stack, so you can build and test NPU workloads without owning the hardware — see [which projects already use it](https://ascend-gha-runners.github.io/docs/Repo/).

> Access is **not self-serve**: install the [`ascend-runner-mgmt`](https://github.com/apps/ascend-runner-mgmt) GitHub App (or send a PAT) and contact `ascendinfra@huawei.com` to activate. See the integration guides below.

## Documentation

Rendered site: **https://ascend-gha-runners.github.io/docs/**

### Integration guides

| CI | English | 中文 |
|---|---|---|
| GitHub Actions | [user-manual-gha-en.md](docs/user-manual-gha-en.md) | [user-manual-gha-zh.md](docs/user-manual-gha-zh.md) |
| Buildkite | [user-manual-buildkite-en.md](docs/user-manual-buildkite-en.md) | [user-manual-buildkite-zh.md](docs/user-manual-buildkite-zh.md) |

### Reference

- [Platform features](docs/feature.md) — PyPI/Apt cache, Git smart proxy, S3 cache, sccache
- [Runner advanced features](docs/runner-features-en.md) · [中文](docs/runner-features-zh.md)
- [Integrated repositories](docs/Repo.md)
- [CI infrastructure deployment (contributor)](docs/ci-infrastructure-deployment-zh.md)

## Feedback

Open a [discussion](https://github.com/ascend-gha-runners/docs/discussions) or an [issue](https://github.com/ascend-gha-runners/docs/issues).
