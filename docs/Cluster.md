# Cluster & Project Map

Auto-generated from CI deployment configuration: each runner's cluster is derived from the ArgoCD Application that deploys it.

<!-- CLUSTER_MAP_START -->
<p class="cluster-legend">Each row is one label: <code>runner label</code> · <code>N × NPU model</code>. Projects claim resources via these labels and queue for available machines. <code>· cpu</code> = CPU-only · <code>· on-demand</code> = elastic pool (business starts pods itself). Click a project to show its labels.</p>
<div class="cluster-stats">
  <div class="stat-card">
    <span class="stat-num">6</span>
    <span class="stat-label">Clusters</span>
  </div>
  <div class="stat-card">
    <span class="stat-num">2</span>
    <span class="stat-label">Projects</span>
  </div>
  <div class="stat-card">
    <span class="stat-num">35</span>
    <span class="stat-label">Labels</span>
  </div>
</div>
<div class="cluster-toolbar">
<input type="search" id="cluster-filter" class="cluster-filter" placeholder="Filter by keywords (space-separated)" aria-label="Filter clusters">
<select id="cluster-npu" class="cluster-npu-filter" aria-label="Filter by hardware">
  <option value="">All hardware</option>
  <option value="ascend-1980">ascend-1980 · 28</option>
  <option value="cpu">CPU (no NPU) · 3</option>
  <option value="npu">npu · 3</option>
  <option value="on-demand">on-demand · 1</option>
</select>
<span class="cluster-hint">6 clusters · 35 labels</span>
</div>
<div class="cluster-grid" id="cluster-grid">

<div class="cluster-card" data-name="ascend-cn12-001-cluster">
  <div class="cluster-card-header">
    <span class="cluster-name">ascend-cn12-001-cluster</span>
    <span class="cluster-meta">2 projects · 17 labels</span>
  </div>
  <div class="cluster-body">
    <div class="project-row" data-search="Ascend/pytorch linux-aarch64-a3-800i-2 linux-aarch64-a3-800i-4 linux-aarch64-a3-800i-8 linux-aarch64-a3-800i-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">Ascend/pytorch</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/Ascend/pytorch" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a3-800i-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>ascend</code></div>
      </div>
    </div>
    <div class="project-row" data-search="Ascend/sglang linux-aarch64-a3-0 a3-560t linux-aarch64-a3-2 a3-560t linux-aarch64-a3-4 a3-560t linux-aarch64-a3-8 a3-560t linux-aarch64-a3-16 a3-560t linux-aarch64-a3-800i-2 linux-aarch64-a3-800i-4 linux-aarch64-a3-800i-8 linux-aarch64-a3-800t-2 linux-aarch64-a3-800t-4 linux-aarch64-a3-800t-8 linux-aarch64-a3-800i-16 linux-aarch64-a3-800t-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">Ascend/sglang</span>
          <span class="project-count">13 labels</span>
        </button>
        <a class="project-link" href="https://github.com/Ascend/sglang" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--ondemand" data-label="linux-aarch64-a3-0-cn12-001" data-npu="on-demand"><span class="machine-label">linux-aarch64-a3-0 + a3-560t</span><span class="machine-npu"> · on-demand</span></div>        <div class="machine" data-label="linux-aarch64-a3-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2 + a3-560t</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4 + a3-560t</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8 + a3-560t</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16 + a3-560t</span><span class="machine-npu"> · 16 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>ascend</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-card" data-name="ascend-hk-001-cluster">
  <div class="cluster-card-header">
    <span class="cluster-name">ascend-hk-001-cluster</span>
    <span class="cluster-meta">1 project · 4 labels</span>
  </div>
  <div class="cluster-body">
    <div class="project-row" data-search="Ascend/sglang linux-aarch64-a2b3-1 linux-aarch64-a2b3-2 linux-aarch64-a2b3-4 linux-aarch64-a2b3-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">Ascend/sglang</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/Ascend/sglang" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a2b3-1" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b3-1</span><span class="machine-npu"> · 1 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>ascend</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-card" data-name="openmerlin-guiyang-004-cluster">
  <div class="cluster-card-header">
    <span class="cluster-name">openmerlin-guiyang-004-cluster</span>
    <span class="cluster-meta">1 project · 6 labels</span>
  </div>
  <div class="cluster-body">
    <div class="project-row" data-search="Ascend/sglang linux-amd64-cpu-4 linux-amd64-cpu-8 linux-aarch64-a3-2 linux-aarch64-a3-4 linux-aarch64-a3-8 linux-aarch64-a3-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">Ascend/sglang</span>
          <span class="project-count">6 labels</span>
        </button>
        <a class="project-link" href="https://github.com/Ascend/sglang" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-amd64-cpu-4" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-4</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-amd64-cpu-8" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-8</span><span class="machine-npu"> · cpu</span></div>        <div class="machine" data-label="linux-aarch64-a3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-16" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>ascend</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-card" data-name="openmerlin-guiyang-005-cluster">
  <div class="cluster-card-header">
    <span class="cluster-name">openmerlin-guiyang-005-cluster</span>
    <span class="cluster-meta">1 project · 1 label</span>
  </div>
  <div class="cluster-body">
    <div class="project-row" data-search="Ascend/pytorch linux-aarch64-cpu-24">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">Ascend/pytorch</span>
          <span class="project-count">1 label</span>
        </button>
        <a class="project-link" href="https://github.com/Ascend/pytorch" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-aarch64-cpu-24" data-npu="cpu"><span class="machine-label">linux-aarch64-cpu-24</span><span class="machine-npu"> · cpu</span></div>
        <div class="project-ns">namespace: <code>ascend</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-divider">Other clusters</div>
<div class="cluster-card" data-name="ascend-aiframework">
  <div class="cluster-card-header">
    <span class="cluster-name">ascend-aiframework</span>
    <span class="cluster-meta">1 project · 4 labels</span>
  </div>
  <div class="cluster-body">
    <div class="project-row" data-search="Ascend/pytorch linux-aarch64-a3-2 linux-aarch64-a3-4 linux-aarch64-a3-8 linux-aarch64-a3-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">Ascend/pytorch</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/Ascend/pytorch" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-16" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>ascend</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-card" data-name="openmerlin-sh-002-cluster">
  <div class="cluster-card-header">
    <span class="cluster-name">openmerlin-sh-002-cluster</span>
    <span class="cluster-meta">1 project · 3 labels</span>
  </div>
  <div class="cluster-body">
    <div class="project-row" data-search="Ascend/pytorch linux-amd64-a5-2 sh-002 linux-amd64-a5-4 sh-002 linux-amd64-a5-8 sh-002">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">Ascend/pytorch</span>
          <span class="project-count">3 labels</span>
        </button>
        <a class="project-link" href="https://github.com/Ascend/pytorch" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-amd64-a5-2-sh-002" data-npu="npu"><span class="machine-label">linux-amd64-a5-2 + sh-002</span><span class="machine-npu"> · 2 × npu</span></div>        <div class="machine" data-label="linux-amd64-a5-4-sh-002" data-npu="npu"><span class="machine-label">linux-amd64-a5-4 + sh-002</span><span class="machine-npu"> · 4 × npu</span></div>        <div class="machine" data-label="linux-amd64-a5-8-sh-002" data-npu="npu"><span class="machine-label">linux-amd64-a5-8 + sh-002</span><span class="machine-npu"> · 8 × npu</span></div>
        <div class="project-ns">namespace: <code>ascend</code></div>
      </div>
    </div>
  </div>
</div>

</div>
<div class="cluster-empty" id="cluster-empty" hidden><p>No matching clusters.</p></div>
<!-- CLUSTER_MAP_END -->
