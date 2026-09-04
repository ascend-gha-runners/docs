# Cluster & Project Map

Auto-generated from CI deployment configuration: each runner's cluster is derived from the ArgoCD Application that deploys it.

<!-- CLUSTER_MAP_START -->
<p class="cluster-legend">Each row is one label: <code>runner label</code> · <code>N × NPU model</code>. Projects claim resources via these labels and queue for available machines. <code>· cpu</code> = CPU-only · <code>· on-demand</code> = elastic pool (business starts pods itself). Click a project to show its labels.</p>
<div class="cluster-stats">
  <div class="stat-card">
    <span class="stat-num">11</span>
    <span class="stat-label">Clusters</span>
  </div>
  <div class="stat-card">
    <span class="stat-num">18</span>
    <span class="stat-label">Projects</span>
  </div>
  <div class="stat-card">
    <span class="stat-num">236</span>
    <span class="stat-label">Labels</span>
  </div>
</div>
<div class="cluster-toolbar">
<input type="search" id="cluster-filter" class="cluster-filter" placeholder="Filter clusters, projects or labels…" aria-label="Filter clusters">
<select id="cluster-npu" class="cluster-npu-filter" aria-label="Filter by hardware">
  <option value="">All hardware</option>
  <option value="ascend-1980">ascend-1980 · 159</option>
  <option value="cpu">CPU (no NPU) · 42</option>
  <option value="npu">npu · 15</option>
  <option value="on-demand">on-demand · 11</option>
  <option value="Ascend910">Ascend910 · 4</option>
  <option value="ascend-310">ascend-310 · 3</option>
  <option value="ascend-1980-10c.3cpu.32g">ascend-1980-10c.3cpu.32g · 1</option>
  <option value="ascend-1980-5c.1cpu.16g">ascend-1980-5c.1cpu.16g · 1</option>
</select>
<span class="cluster-hint">11 clusters · 236 labels</span>
</div>
<div class="cluster-grid" id="cluster-grid">

<div class="cluster-card" data-name="ascend-cn12-001-cluster">
  <div class="cluster-card-header">
    <span class="cluster-name">ascend-cn12-001-cluster</span>
    <span class="cluster-meta">11 projects · 91 labels</span>
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
    <div class="project-row" data-search="alibaba/ROLL linux-aarch64-a3-0 linux-aarch64-a3-2 linux-aarch64-a3-4 linux-aarch64-a3-8 linux-aarch64-a3-16 linux-aarch64-a3-800i-2 linux-aarch64-a3-800i-4 linux-aarch64-a3-800i-8 linux-aarch64-a3-800i-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">alibaba/ROLL</span>
          <span class="project-count">9 labels</span>
        </button>
        <a class="project-link" href="https://github.com/alibaba/ROLL" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--ondemand" data-label="linux-aarch64-a3-0" data-npu="on-demand"><span class="machine-label">linux-aarch64-a3-0</span><span class="machine-npu"> · on-demand</span></div>        <div class="machine" data-label="linux-aarch64-a3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-16" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>alibaba-roll</code></div>
      </div>
    </div>
    <div class="project-row" data-search="areal-project/AReaL linux-aarch64-a3-0 linux-aarch64-a3-2 linux-aarch64-a3-4 linux-aarch64-a3-8 linux-aarch64-a3-16 linux-aarch64-a3-800i-2 linux-aarch64-a3-800i-4 linux-aarch64-a3-800i-8 linux-aarch64-a3-800i-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">areal-project/AReaL</span>
          <span class="project-count">9 labels</span>
        </button>
        <a class="project-link" href="https://github.com/areal-project/AReaL" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--ondemand" data-label="linux-aarch64-a3-0" data-npu="on-demand"><span class="machine-label">linux-aarch64-a3-0</span><span class="machine-npu"> · on-demand</span></div>        <div class="machine" data-label="linux-aarch64-a3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-16" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-16" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>areal-project-areal</code></div>
      </div>
    </div>
    <div class="project-row" data-search="sgl-project/sgl-kernel-npu linux-aarch64-a3-16 a3-560t linux-aarch64-a3-800i-2 linux-aarch64-a3-800i-4 linux-aarch64-a3-800i-8 linux-aarch64-a3-800t-2 linux-aarch64-a3-800t-4 linux-aarch64-a3-800t-8 linux-aarch64-a3-800i-16 linux-aarch64-a3-800t-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">sgl-project/sgl-kernel-npu</span>
          <span class="project-count">9 labels</span>
        </button>
        <a class="project-link" href="https://github.com/sgl-project/sgl-kernel-npu" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a3-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16 + a3-560t</span><span class="machine-npu"> · 16 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>sgl-kernel-npu</code></div>
      </div>
    </div>
    <div class="project-row" data-search="sgl-project/sglang linux-aarch64-a3-2 linux-aarch64-a3-4 linux-aarch64-a3-8 linux-aarch64-a3-16 linux-aarch64-a3-800t-2 linux-aarch64-a3-800t-4 linux-aarch64-a3-800t-8 linux-aarch64-a3-800t-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">sgl-project/sglang</span>
          <span class="project-count">8 labels</span>
        </button>
        <a class="project-link" href="https://github.com/sgl-project/sglang" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a3-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>sgl-project</code></div>
      </div>
    </div>
    <div class="project-row" data-search="tile-ai/tilelang-mlir-ascend linux-aarch64-a3-2 linux-aarch64-a3-4 linux-aarch64-a3-8 linux-aarch64-a3-16 linux-aarch64-a3-800i-2 linux-aarch64-a3-800i-4 linux-aarch64-a3-800i-8 linux-aarch64-a3-800i-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">tile-ai/tilelang-mlir-ascend</span>
          <span class="project-count">8 labels</span>
        </button>
        <a class="project-link" href="https://github.com/tile-ai/tilelang-mlir-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-16" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>tile-ai-tilelang-mlir-ascend</code></div>
      </div>
    </div>
    <div class="project-row" data-search="triton-lang/triton-ascend linux-aarch64-a3-2 linux-aarch64-a3-4 linux-aarch64-a3-8 linux-aarch64-a3-16 linux-aarch64-a3-800i-2 linux-aarch64-a3-800i-4 linux-aarch64-a3-800i-8 linux-aarch64-a3-800i-16 linux-amd64-cpu-4 linux-aarch64-cpu-4">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">triton-lang/triton-ascend</span>
          <span class="project-count">10 labels</span>
        </button>
        <a class="project-link" href="https://github.com/triton-lang/triton-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-16" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>        <div class="machine machine--cpu" data-label="linux-amd64-cpu-4-buildkit-cn12-001" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-4</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-cpu-4-buildkit-cn12-001" data-npu="cpu"><span class="machine-label">linux-aarch64-cpu-4</span><span class="machine-npu"> · cpu</span></div>
        <div class="project-ns">namespace: <code>triton-ascend</code></div>
      </div>
    </div>
    <div class="project-row" data-search="vllm-project/vllm-ascend linux-amd64-cpu-4 linux-aarch64-a3-0 a3-560t linux-aarch64-a3-2 linux-aarch64-a3-4 linux-aarch64-a3-8 linux-aarch64-a3-16 linux-aarch64-cpu-4 linux-aarch64-a3-800i-2 linux-aarch64-a3-800i-4 linux-aarch64-a3-800i-8 linux-aarch64-a3-800t-0 linux-aarch64-a3-800t-2 linux-aarch64-a3-800t-4 linux-aarch64-a3-800t-8 linux-aarch64-a3-800i-16 linux-aarch64-a3-800t-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-project/vllm-ascend</span>
          <span class="project-count">16 labels</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-project/vllm-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-amd64-cpu-4-cn12-001" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-4</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--ondemand" data-label="linux-aarch64-a3-0-cn12-001" data-npu="on-demand"><span class="machine-label">linux-aarch64-a3-0 + a3-560t</span><span class="machine-npu"> · on-demand</span></div>        <div class="machine" data-label="linux-aarch64-a3-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-cpu-4-cn12-001" data-npu="cpu"><span class="machine-label">linux-aarch64-cpu-4</span><span class="machine-npu"> · cpu</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine machine--ondemand" data-label="linux-aarch64-a3-800t-0-cn12-001" data-npu="on-demand"><span class="machine-label">linux-aarch64-a3-800t-0</span><span class="machine-npu"> · on-demand</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800t-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800t-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>vllm-project</code></div>
      </div>
    </div>
    <div class="project-row" data-search="vllm-project/vllm-omni linux-aarch64-a3">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-project/vllm-omni</span>
          <span class="project-count">1 label</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-project/vllm-omni" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-aarch64-a3" data-npu="cpu"><span class="machine-label">linux-aarch64-a3</span><span class="machine-npu"> · cpu</span></div>
        <div class="project-ns">namespace: <code>vllm-project</code></div>
      </div>
    </div>
    <div class="project-row" data-search="verl-project/verl linux-aarch64-a3-800i-2 linux-aarch64-a3-800i-4 linux-aarch64-a3-800i-8 linux-aarch64-a3-800i-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">verl-project/verl</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/verl-project/verl" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a3-800i-2-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-4-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-8-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-16-cn12-001" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>volcengine</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-card" data-name="ascend-hk-001-cluster">
  <div class="cluster-card-header">
    <span class="cluster-name">ascend-hk-001-cluster</span>
    <span class="cluster-meta">12 projects · 57 labels</span>
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
    <div class="project-row" data-search="fla-org/flash-linear-attention linux-aarch64-a2-1 linux-aarch64-a2-2 linux-aarch64-a2-4 linux-aarch64-a2-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">fla-org/flash-linear-attention</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/fla-org/flash-linear-attention" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a2-1" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-1</span><span class="machine-npu"> · 1 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>fla-org-flash-linear-attention</code></div>
      </div>
    </div>
    <div class="project-row" data-search="hiyouga/LlamaFactory linux-aarch64-a2-1 linux-aarch64-a2-2 linux-aarch64-a2-4 linux-aarch64-a2-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">hiyouga/LlamaFactory</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/hiyouga/LlamaFactory" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a2-1" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-1</span><span class="machine-npu"> · 1 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>hiyouga</code></div>
      </div>
    </div>
    <div class="project-row" data-search="modelscope/ms-swift linux-aarch64-a2-1 linux-aarch64-a2-2 linux-aarch64-a2-4 linux-aarch64-a2-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">modelscope/ms-swift</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/modelscope/ms-swift" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a2-1" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-1</span><span class="machine-npu"> · 1 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>modelscope</code></div>
      </div>
    </div>
    <div class="project-row" data-search="sgl-project/sgl-kernel-npu linux-aarch64-a2-0 linux-aarch64-a2-1 linux-aarch64-a2-2 linux-aarch64-a2-4 linux-aarch64-a2-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">sgl-project/sgl-kernel-npu</span>
          <span class="project-count">5 labels</span>
        </button>
        <a class="project-link" href="https://github.com/sgl-project/sgl-kernel-npu" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--ondemand" data-label="linux-aarch64-a2-0" data-npu="on-demand"><span class="machine-label">linux-aarch64-a2-0</span><span class="machine-npu"> · on-demand</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-a2-1" data-npu="cpu"><span class="machine-label">linux-aarch64-a2-1</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-a2-2" data-npu="cpu"><span class="machine-label">linux-aarch64-a2-2</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-a2-4" data-npu="cpu"><span class="machine-label">linux-aarch64-a2-4</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-a2-8" data-npu="cpu"><span class="machine-label">linux-aarch64-a2-8</span><span class="machine-npu"> · cpu</span></div>
        <div class="project-ns">namespace: <code>sgl-kernel-npu</code></div>
      </div>
    </div>
    <div class="project-row" data-search="sgl-project/sglang linux-aarch64-a2-1 linux-aarch64-a2-2 linux-aarch64-a2-4 linux-aarch64-a2-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">sgl-project/sglang</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/sgl-project/sglang" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a2-1" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-1</span><span class="machine-npu"> · 1 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>sgl-project</code></div>
      </div>
    </div>
    <div class="project-row" data-search="sgl-project/sglang-omni linux-aarch64-a2-1 linux-aarch64-a2-2 linux-aarch64-a2-4 linux-aarch64-a2-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">sgl-project/sglang-omni</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/sgl-project/sglang-omni" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-aarch64-a2-1" data-npu="cpu"><span class="machine-label">linux-aarch64-a2-1</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-a2-2" data-npu="cpu"><span class="machine-label">linux-aarch64-a2-2</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-a2-4" data-npu="cpu"><span class="machine-label">linux-aarch64-a2-4</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-a2-8" data-npu="cpu"><span class="machine-label">linux-aarch64-a2-8</span><span class="machine-npu"> · cpu</span></div>
        <div class="project-ns">namespace: <code>sgl-project-sglang-omni</code></div>
      </div>
    </div>
    <div class="project-row" data-search="triton-lang/triton-ascend linux-amd64-cpu-2-hk linux-amd64-cpu-4-hk linux-amd64-cpu-8-hk linux-amd64-cpu-16-hk">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">triton-lang/triton-ascend</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/triton-lang/triton-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-amd64-cpu-2-hk" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-2-hk</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-amd64-cpu-4-hk" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-4-hk</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-amd64-cpu-8-hk" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-8-hk</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-amd64-cpu-16-hk" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-16-hk</span><span class="machine-npu"> · cpu</span></div>
        <div class="project-ns">namespace: <code>triton-ascend</code></div>
      </div>
    </div>
    <div class="project-row" data-search="vllm-project/vllm-ascend linux-aarch64-910b-1 linux-aarch64-910b-2 linux-aarch64-910b-4 linux-aarch64-910b-8 linux-aarch64-a2b3-0 linux-aarch64-a2b3-1 linux-aarch64-a2b3-2 linux-aarch64-a2b3-4 linux-aarch64-a2b3-8 linux-amd64-cpu-2-hk linux-amd64-cpu-4-hk linux-amd64-cpu-8-hk linux-amd64-cpu-16-hk linux-amd64-cpu-32-hk linux-arm64-cpu-32-hk linux-aarch64-a2b3-v-half linux-aarch64-a2b3-v-quarter">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-project/vllm-ascend</span>
          <span class="project-count">17 labels</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-project/vllm-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-910b-1" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-910b-1</span><span class="machine-npu"> · 1 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-910b-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-910b-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-910b-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-910b-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-910b-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-910b-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine machine--ondemand" data-label="linux-aarch64-a2b3-0" data-npu="on-demand"><span class="machine-label">linux-aarch64-a2b3-0</span><span class="machine-npu"> · on-demand</span></div>        <div class="machine" data-label="linux-aarch64-a2b3-1" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b3-1</span><span class="machine-npu"> · 1 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine machine--cpu" data-label="linux-amd64-cpu-2-hk" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-2-hk</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-amd64-cpu-4-hk" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-4-hk</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-amd64-cpu-8-hk" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-8-hk</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-amd64-cpu-16-hk" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-16-hk</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-amd64-cpu-32-hk" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-32-hk</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-arm64-cpu-32-hk" data-npu="cpu"><span class="machine-label">linux-arm64-cpu-32-hk</span><span class="machine-npu"> · cpu</span></div>        <div class="machine" data-label="linux-aarch64-a2b3-v-half" data-npu="ascend-1980-10c.3cpu.32g"><span class="machine-label">linux-aarch64-a2b3-v-half</span><span class="machine-npu"> · 1 × ascend-1980-10c.3cpu.32g</span></div>        <div class="machine" data-label="linux-aarch64-a2b3-v-quarter" data-npu="ascend-1980-5c.1cpu.16g"><span class="machine-label">linux-aarch64-a2b3-v-quarter</span><span class="machine-npu"> · 1 × ascend-1980-5c.1cpu.16g</span></div>
        <div class="project-ns">namespace: <code>vllm-project</code></div>
      </div>
    </div>
    <div class="project-row" data-search="vllm-project/vllm-omni linux-aarch64-a2b3">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-project/vllm-omni</span>
          <span class="project-count">1 label</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-project/vllm-omni" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-aarch64-a2b3" data-npu="cpu"><span class="machine-label">linux-aarch64-a2b3</span><span class="machine-npu"> · cpu</span></div>
        <div class="project-ns">namespace: <code>vllm-project</code></div>
      </div>
    </div>
    <div class="project-row" data-search="verl-project/verl linux-aarch64-a2-1 linux-aarch64-a2-2 linux-aarch64-a2-4 linux-aarch64-a2-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">verl-project/verl</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/verl-project/verl" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-aarch64-a2-1" data-npu="cpu"><span class="machine-label">linux-aarch64-a2-1</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-a2-2" data-npu="cpu"><span class="machine-label">linux-aarch64-a2-2</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-a2-4" data-npu="cpu"><span class="machine-label">linux-aarch64-a2-4</span><span class="machine-npu"> · cpu</span></div>        <div class="machine" data-label="linux-aarch64-a2-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>volcengine</code></div>
      </div>
    </div>
    <div class="project-row" data-search="verl-project/verl-SpeCo linux-aarch64-a2-4 linux-aarch64-a2-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">verl-project/verl-SpeCo</span>
          <span class="project-count">2 labels</span>
        </button>
        <a class="project-link" href="https://github.com/verl-project/verl-SpeCo" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-aarch64-a2-4" data-npu="cpu"><span class="machine-label">linux-aarch64-a2-4</span><span class="machine-npu"> · cpu</span></div>        <div class="machine" data-label="linux-aarch64-a2-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>verl-project-verl-speco</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-card" data-name="ascend-infra-guiyang-cluster-001">
  <div class="cluster-card-header">
    <span class="cluster-name">ascend-infra-guiyang-cluster-001</span>
    <span class="cluster-meta">4 projects · 15 labels</span>
  </div>
  <div class="cluster-body">
    <div class="project-row" data-search="triton-lang/triton-ascend linux-aarch64-a2b1-1 linux-aarch64-a2b1-2 linux-aarch64-a2b1-4 linux-aarch64-a2b1-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">triton-lang/triton-ascend</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/triton-lang/triton-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a2b1-1" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b1-1</span><span class="machine-npu"> · 1 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b1-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b1-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b1-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b1-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b1-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b1-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>triton-ascend</code></div>
      </div>
    </div>
    <div class="project-row" data-search="vllm-ascend/vllm-ascend-recipes linux-aarch64-a2b4-0 linux-aarch64-a2b4-1 linux-aarch64-a2b4-2 linux-aarch64-a2b4-4 linux-aarch64-a2b4-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-ascend/vllm-ascend-recipes</span>
          <span class="project-count">5 labels</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-ascend/vllm-ascend-recipes" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--ondemand" data-label="linux-aarch64-a2b4-0" data-npu="on-demand"><span class="machine-label">linux-aarch64-a2b4-0</span><span class="machine-npu"> · on-demand</span></div>        <div class="machine" data-label="linux-aarch64-a2b4-1" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b4-1</span><span class="machine-npu"> · 1 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b4-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b4-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b4-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b4-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b4-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b4-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>vllm-ascend-vllm-ascend-recipes</code></div>
      </div>
    </div>
    <div class="project-row" data-search="vllm-project/vllm-ascend linux-aarch64-a2b1-1 linux-aarch64-a2b1-2 linux-aarch64-a2b1-4 linux-aarch64-a2b1-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-project/vllm-ascend</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-project/vllm-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a2b1-1" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b1-1</span><span class="machine-npu"> · 1 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b1-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b1-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b1-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b1-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b1-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b1-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>vllm-project</code></div>
      </div>
    </div>
    <div class="project-row" data-search="verl-project/verl-omni linux-aarch64-a2b4-4 linux-aarch64-a2b4-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">verl-project/verl-omni</span>
          <span class="project-count">2 labels</span>
        </button>
        <a class="project-link" href="https://github.com/verl-project/verl-omni" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a2b4-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b4-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a2b4-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a2b4-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>verl-project-verl-omni</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-card" data-name="openmerlin-guiyang-003-cluster">
  <div class="cluster-card-header">
    <span class="cluster-name">openmerlin-guiyang-003-cluster</span>
    <span class="cluster-meta">2 projects · 4 labels</span>
  </div>
  <div class="cluster-body">
    <div class="project-row" data-search="vllm-project/vllm-ascend linux-aarch64-310p-1 linux-aarch64-310p-2 linux-aarch64-310p-4">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-project/vllm-ascend</span>
          <span class="project-count">3 labels</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-project/vllm-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-310p-1" data-npu="ascend-310"><span class="machine-label">linux-aarch64-310p-1</span><span class="machine-npu"> · 1 × ascend-310</span></div>        <div class="machine" data-label="linux-aarch64-310p-2" data-npu="ascend-310"><span class="machine-label">linux-aarch64-310p-2</span><span class="machine-npu"> · 2 × ascend-310</span></div>        <div class="machine" data-label="linux-aarch64-310p-4" data-npu="ascend-310"><span class="machine-label">linux-aarch64-310p-4</span><span class="machine-npu"> · 4 × ascend-310</span></div>
        <div class="project-ns">namespace: <code>vllm-project</code></div>
      </div>
    </div>
    <div class="project-row" data-search="vllm-project/vllm-omni linux-aarch64-310p">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-project/vllm-omni</span>
          <span class="project-count">1 label</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-project/vllm-omni" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-aarch64-310p" data-npu="cpu"><span class="machine-label">linux-aarch64-310p</span><span class="machine-npu"> · cpu</span></div>
        <div class="project-ns">namespace: <code>vllm-project</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-card" data-name="openmerlin-guiyang-004-cluster">
  <div class="cluster-card-header">
    <span class="cluster-name">openmerlin-guiyang-004-cluster</span>
    <span class="cluster-meta">3 projects · 15 labels</span>
  </div>
  <div class="cluster-body">
    <div class="project-row" data-search="Ascend/sglang linux-amd64-cpu-8 linux-aarch64-a3-2 linux-aarch64-a3-4 linux-aarch64-a3-8 linux-aarch64-a3-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">Ascend/sglang</span>
          <span class="project-count">5 labels</span>
        </button>
        <a class="project-link" href="https://github.com/Ascend/sglang" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-amd64-cpu-8" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-8</span><span class="machine-npu"> · cpu</span></div>        <div class="machine" data-label="linux-aarch64-a3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-16" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>ascend</code></div>
      </div>
    </div>
    <div class="project-row" data-search="sgl-project/sgl-kernel-npu linux-aarch64-a3-2 a3-752t linux-aarch64-a3-4 a3-752t linux-aarch64-a3-8 a3-752t linux-aarch64-a3-16 a3-752t">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">sgl-project/sgl-kernel-npu</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/sgl-project/sgl-kernel-npu" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2 + a3-752t</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4 + a3-752t</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8 + a3-752t</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-16" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16 + a3-752t</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>sgl-kernel-npu</code></div>
      </div>
    </div>
    <div class="project-row" data-search="sgl-project/sglang linux-amd64-cpu-4 linux-aarch64-a3-0 a3-752t linux-aarch64-a3-2 a3-752t linux-aarch64-a3-4 a3-752t linux-aarch64-a3-8 a3-752t linux-aarch64-a3-16 a3-752t">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">sgl-project/sglang</span>
          <span class="project-count">6 labels</span>
        </button>
        <a class="project-link" href="https://github.com/sgl-project/sglang" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-amd64-cpu-4" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-4</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-amd64-cpu-8" data-npu="cpu"><span class="machine-label">linux-aarch64-a3-0 + a3-752t</span><span class="machine-npu"> · cpu</span></div>        <div class="machine" data-label="linux-aarch64-a3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2 + a3-752t</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4 + a3-752t</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8 + a3-752t</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-16" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16 + a3-752t</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>sgl-project</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-card" data-name="openmerlin-guiyang-005-cluster">
  <div class="cluster-card-header">
    <span class="cluster-name">openmerlin-guiyang-005-cluster</span>
    <span class="cluster-meta">3 projects · 18 labels</span>
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
    <div class="project-row" data-search="triton-lang/triton-ascend linux-amd64-cpu-8 linux-amd64-cpu-16 linux-aarch64-cpu-1 linux-aarch64-cpu-2 linux-aarch64-cpu-8 linux-aarch64-cpu-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">triton-lang/triton-ascend</span>
          <span class="project-count">6 labels</span>
        </button>
        <a class="project-link" href="https://github.com/triton-lang/triton-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-amd64-cpu-8" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-8</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-amd64-cpu-16" data-npu="cpu"><span class="machine-label">linux-amd64-cpu-16</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-cpu-1" data-npu="cpu"><span class="machine-label">linux-aarch64-cpu-1</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-cpu-2" data-npu="cpu"><span class="machine-label">linux-aarch64-cpu-2</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-cpu-8" data-npu="cpu"><span class="machine-label">linux-aarch64-cpu-8</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--cpu" data-label="linux-aarch64-cpu-16" data-npu="cpu"><span class="machine-label">linux-aarch64-cpu-16</span><span class="machine-npu"> · cpu</span></div>
        <div class="project-ns">namespace: <code>triton-ascend</code></div>
      </div>
    </div>
    <div class="project-row" data-search="vllm-project/vllm-ascend linux-arm64-cpu-8 linux-aarch64-a3-0 linux-aarch64-a3-2 linux-aarch64-a3-4 linux-aarch64-a3-8 linux-arm64-cpu-16 linux-aarch64-a3-16 linux-aarch64-nightly-a3-2 linux-aarch64-nightly-a3-4 linux-aarch64-nightly-a3-8 linux-aarch64-nightly-a3-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-project/vllm-ascend</span>
          <span class="project-count">11 labels</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-project/vllm-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-arm64-cpu-8" data-npu="cpu"><span class="machine-label">linux-arm64-cpu-8</span><span class="machine-npu"> · cpu</span></div>        <div class="machine machine--ondemand" data-label="linux-aarch64-a3-0" data-npu="on-demand"><span class="machine-label">linux-aarch64-a3-0</span><span class="machine-npu"> · on-demand</span></div>        <div class="machine" data-label="linux-aarch64-a3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine machine--cpu" data-label="linux-arm64-cpu-16" data-npu="cpu"><span class="machine-label">linux-arm64-cpu-16</span><span class="machine-npu"> · cpu</span></div>        <div class="machine" data-label="linux-aarch64-a3-16" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-nightly-a3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-nightly-a3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-nightly-a3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-nightly-a3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-nightly-a3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-nightly-a3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-nightly-a3-16" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-nightly-a3-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>vllm-project</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-card" data-name="openmerlin-sh-001-cluster">
  <div class="cluster-card-header">
    <span class="cluster-name">openmerlin-sh-001-cluster</span>
    <span class="cluster-meta">3 projects · 9 labels</span>
  </div>
  <div class="cluster-body">
    <div class="project-row" data-search="vllm-ascend/vllm-ascend-recipes linux-aarch64-a5-0 linux-aarch64-a5-2 linux-aarch64-a5-4 linux-aarch64-a5-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-ascend/vllm-ascend-recipes</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-ascend/vllm-ascend-recipes" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--ondemand" data-label="linux-aarch64-a5-0" data-npu="on-demand"><span class="machine-label">linux-aarch64-a5-0</span><span class="machine-npu"> · on-demand</span></div>        <div class="machine" data-label="linux-aarch64-a5-2" data-npu="npu"><span class="machine-label">linux-aarch64-a5-2</span><span class="machine-npu"> · 2 × npu</span></div>        <div class="machine" data-label="linux-aarch64-a5-4" data-npu="npu"><span class="machine-label">linux-aarch64-a5-4</span><span class="machine-npu"> · 4 × npu</span></div>        <div class="machine" data-label="linux-aarch64-a5-8" data-npu="npu"><span class="machine-label">linux-aarch64-a5-8</span><span class="machine-npu"> · 8 × npu</span></div>
        <div class="project-ns">namespace: <code>vllm-ascend-vllm-ascend-recipes</code></div>
      </div>
    </div>
    <div class="project-row" data-search="vllm-project/vllm-ascend linux-aarch64-a5-0 linux-aarch64-a5-2 linux-aarch64-a5-4 linux-aarch64-a5-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-project/vllm-ascend</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-project/vllm-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--ondemand" data-label="linux-aarch64-a5-0" data-npu="on-demand"><span class="machine-label">linux-aarch64-a5-0</span><span class="machine-npu"> · on-demand</span></div>        <div class="machine" data-label="linux-aarch64-a5-2" data-npu="npu"><span class="machine-label">linux-aarch64-a5-2</span><span class="machine-npu"> · 2 × npu</span></div>        <div class="machine" data-label="linux-aarch64-a5-4" data-npu="npu"><span class="machine-label">linux-aarch64-a5-4</span><span class="machine-npu"> · 4 × npu</span></div>        <div class="machine" data-label="linux-aarch64-a5-8" data-npu="npu"><span class="machine-label">linux-aarch64-a5-8</span><span class="machine-npu"> · 8 × npu</span></div>
        <div class="project-ns">namespace: <code>vllm-project</code></div>
      </div>
    </div>
    <div class="project-row" data-search="vllm-project/vllm-omni linux-aarch64-a5">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-project/vllm-omni</span>
          <span class="project-count">1 label</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-project/vllm-omni" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine machine--cpu" data-label="linux-aarch64-a5" data-npu="cpu"><span class="machine-label">linux-aarch64-a5</span><span class="machine-npu"> · cpu</span></div>
        <div class="project-ns">namespace: <code>vllm-project</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-divider">Other clusters</div>
<div class="cluster-card" data-name="ascend-aiframework">
  <div class="cluster-card-header">
    <span class="cluster-name">ascend-aiframework</span>
    <span class="cluster-meta">2 projects · 7 labels</span>
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
    <div class="project-row" data-search="vllm-project/vllm-ascend linux-aarch64-a3-800i-2-aiframe linux-aarch64-a3-800i-4-aiframe linux-aarch64-a3-800i-8-aiframe">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-project/vllm-ascend</span>
          <span class="project-count">3 labels</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-project/vllm-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a3-800i-2-aiframe" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-2-aiframe</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-4-aiframe" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-4-aiframe</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-8-aiframe" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-8-aiframe</span><span class="machine-npu"> · 8 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>vllm-project</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-card" data-name="ascend-mind-third-ci">
  <div class="cluster-card-header">
    <span class="cluster-name">ascend-mind-third-ci</span>
    <span class="cluster-meta">2 projects · 7 labels</span>
  </div>
  <div class="cluster-body">
    <div class="project-row" data-search="vllm-project/vllm-ascend linux-aarch64-a3-800i-2-mind linux-aarch64-a3-800i-4-mind linux-aarch64-a3-800i-8-mind">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">vllm-project/vllm-ascend</span>
          <span class="project-count">3 labels</span>
        </button>
        <a class="project-link" href="https://github.com/vllm-project/vllm-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a3-800i-2-mind" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-2-mind</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-4-mind" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-4-mind</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-800i-8-mind" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-800i-8-mind</span><span class="machine-npu"> · 8 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>vllm-project</code></div>
      </div>
    </div>
    <div class="project-row" data-search="verl-project/verl linux-aarch64-a3-2 linux-aarch64-a3-4 linux-aarch64-a3-8 linux-aarch64-a3-16">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">verl-project/verl</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/verl-project/verl" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a3-2" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-2</span><span class="machine-npu"> · 2 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-4" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-4</span><span class="machine-npu"> · 4 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-8" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-8</span><span class="machine-npu"> · 8 × ascend-1980</span></div>        <div class="machine" data-label="linux-aarch64-a3-16" data-npu="ascend-1980"><span class="machine-label">linux-aarch64-a3-16</span><span class="machine-npu"> · 16 × ascend-1980</span></div>
        <div class="project-ns">namespace: <code>volcengine</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-card" data-name="in-cluster">
  <div class="cluster-card-header">
    <span class="cluster-name">in-cluster</span>
    <span class="cluster-meta">1 project · 4 labels</span>
  </div>
  <div class="cluster-body">
    <div class="project-row" data-search="verl-project/verl linux-aarch64-a2b3-1 linux-aarch64-a2b3-2 linux-aarch64-a2b3-4 linux-aarch64-a2b3-8">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">verl-project/verl</span>
          <span class="project-count">4 labels</span>
        </button>
        <a class="project-link" href="https://github.com/verl-project/verl" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-aarch64-a2b3-1" data-npu="Ascend910"><span class="machine-label">linux-aarch64-a2b3-1</span><span class="machine-npu"> · 1 × Ascend910</span></div>        <div class="machine" data-label="linux-aarch64-a2b3-2" data-npu="Ascend910"><span class="machine-label">linux-aarch64-a2b3-2</span><span class="machine-npu"> · 2 × Ascend910</span></div>        <div class="machine" data-label="linux-aarch64-a2b3-4" data-npu="Ascend910"><span class="machine-label">linux-aarch64-a2b3-4</span><span class="machine-npu"> · 4 × Ascend910</span></div>        <div class="machine" data-label="linux-aarch64-a2b3-8" data-npu="Ascend910"><span class="machine-label">linux-aarch64-a2b3-8</span><span class="machine-npu"> · 8 × Ascend910</span></div>
        <div class="project-ns">namespace: <code>volcengine</code></div>
      </div>
    </div>
  </div>
</div>

<div class="cluster-card" data-name="openmerlin-sh-002-cluster">
  <div class="cluster-card-header">
    <span class="cluster-name">openmerlin-sh-002-cluster</span>
    <span class="cluster-meta">3 projects · 9 labels</span>
  </div>
  <div class="cluster-body">
    <div class="project-row" data-search="sgl-project/sgl-kernel-npu linux-amd64-a5-2 sh-002 linux-amd64-a5-4 sh-002 linux-amd64-a5-8 sh-002">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">sgl-project/sgl-kernel-npu</span>
          <span class="project-count">3 labels</span>
        </button>
        <a class="project-link" href="https://github.com/sgl-project/sgl-kernel-npu" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-amd64-a5-2-sh-002" data-npu="npu"><span class="machine-label">linux-amd64-a5-2 + sh-002</span><span class="machine-npu"> · 2 × npu</span></div>        <div class="machine" data-label="linux-amd64-a5-4-sh-002" data-npu="npu"><span class="machine-label">linux-amd64-a5-4 + sh-002</span><span class="machine-npu"> · 4 × npu</span></div>        <div class="machine" data-label="linux-amd64-a5-8-sh-002" data-npu="npu"><span class="machine-label">linux-amd64-a5-8 + sh-002</span><span class="machine-npu"> · 8 × npu</span></div>
        <div class="project-ns">namespace: <code>sgl-kernel-npu</code></div>
      </div>
    </div>
    <div class="project-row" data-search="sgl-project/sglang linux-amd64-a5-2 sh-002 linux-amd64-a5-4 sh-002 linux-amd64-a5-8 sh-002">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">sgl-project/sglang</span>
          <span class="project-count">3 labels</span>
        </button>
        <a class="project-link" href="https://github.com/sgl-project/sglang" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-amd64-a5-2-sh-002" data-npu="npu"><span class="machine-label">linux-amd64-a5-2 + sh-002</span><span class="machine-npu"> · 2 × npu</span></div>        <div class="machine" data-label="linux-amd64-a5-4-sh-002" data-npu="npu"><span class="machine-label">linux-amd64-a5-4 + sh-002</span><span class="machine-npu"> · 4 × npu</span></div>        <div class="machine" data-label="linux-amd64-a5-8-sh-002" data-npu="npu"><span class="machine-label">linux-amd64-a5-8 + sh-002</span><span class="machine-npu"> · 8 × npu</span></div>
        <div class="project-ns">namespace: <code>sgl-project</code></div>
      </div>
    </div>
    <div class="project-row" data-search="triton-lang/triton-ascend linux-amd64-a5-2 sh-002 linux-amd64-a5-4 sh-002 linux-amd64-a5-8 sh-002">
      <div class="project-line">
        <button type="button" class="project-head" aria-expanded="false">
          <span class="project-toggle"></span>
          <span class="project-name-text">triton-lang/triton-ascend</span>
          <span class="project-count">3 labels</span>
        </button>
        <a class="project-link" href="https://github.com/triton-lang/triton-ascend" target="_blank" rel="noopener" title="Open on GitHub">↗</a>
      </div>
      <div class="machine-list" hidden>
        <div class="machine" data-label="linux-amd64-a5-2-sh-002" data-npu="npu"><span class="machine-label">linux-amd64-a5-2 + sh-002</span><span class="machine-npu"> · 2 × npu</span></div>        <div class="machine" data-label="linux-amd64-a5-4-sh-002" data-npu="npu"><span class="machine-label">linux-amd64-a5-4 + sh-002</span><span class="machine-npu"> · 4 × npu</span></div>        <div class="machine" data-label="linux-amd64-a5-8-sh-002" data-npu="npu"><span class="machine-label">linux-amd64-a5-8 + sh-002</span><span class="machine-npu"> · 8 × npu</span></div>
        <div class="project-ns">namespace: <code>triton-ascend</code></div>
      </div>
    </div>
  </div>
</div>

</div>
<div class="cluster-empty" id="cluster-empty" hidden><p>No matching clusters.</p></div>
<!-- CLUSTER_MAP_END -->
