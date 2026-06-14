-- editutor/repo_rank.lua
-- Repo-wide symbol graph ranking inspired by Aider's repomap.

local M = {}

local cache = require("editutor.cache")
local project_scanner = require("editutor.project_scanner")
local repo_tags = require("editutor.repo_tags")

M.config = {
  damping = 0.85,
  max_iterations = 30,
  tolerance = 0.0001,
  max_files = 800,
  top_files = 40,
}

local function rel_path(filepath, project_root)
  if filepath:sub(1, #project_root) == project_root then
    return filepath:sub(#project_root + 2):gsub("^/", "")
  end
  return vim.fn.fnamemodify(filepath, ":t")
end

local function abs_path(rel_fname, project_root)
  return vim.fn.simplify(project_root .. "/" .. rel_fname)
end

local function is_meaningful_name(name)
  if not name or #name < 8 then
    return false
  end
  local is_snake = name:find("_") and name:find("%a")
  local is_kebab = name:find("-") and name:find("%a")
  local is_camel = name:find("%u") and name:find("%l")
  return is_snake or is_kebab or is_camel
end

local function normalize_personalization(nodes, seed_nodes)
  local personalization = {}
  local total = 0

  for node, weight in pairs(seed_nodes) do
    if nodes[node] and weight > 0 then
      personalization[node] = (personalization[node] or 0) + weight
      total = total + weight
    end
  end

  if total == 0 then
    local count = vim.tbl_count(nodes)
    if count == 0 then
      return personalization
    end
    for node in pairs(nodes) do
      personalization[node] = 1 / count
    end
    return personalization
  end

  for node, weight in pairs(personalization) do
    personalization[node] = weight / total
  end

  return personalization
end

local function pagerank(nodes, edges, personalization, opts)
  opts = opts or {}
  local damping = opts.damping or M.config.damping
  local max_iterations = opts.max_iterations or M.config.max_iterations
  local tolerance = opts.tolerance or M.config.tolerance
  local node_count = vim.tbl_count(nodes)

  if node_count == 0 then
    return {}
  end

  local rank = {}
  for node in pairs(nodes) do
    rank[node] = 1 / node_count
  end

  for _ = 1, max_iterations do
    local next_rank = {}
    for node in pairs(nodes) do
      next_rank[node] = (1 - damping) * (personalization[node] or 0)
    end

    local dangling_rank = 0
    for src in pairs(nodes) do
      local outgoing = edges[src]
      local out_weight = 0
      if outgoing then
        for _, weight in pairs(outgoing) do
          out_weight = out_weight + weight
        end
      end

      if out_weight == 0 then
        dangling_rank = dangling_rank + rank[src]
      else
        for dst, weight in pairs(outgoing) do
          next_rank[dst] = (next_rank[dst] or 0) + damping * rank[src] * weight / out_weight
        end
      end
    end

    if dangling_rank > 0 then
      for node in pairs(nodes) do
        next_rank[node] = (next_rank[node] or 0) + damping * dangling_rank * (personalization[node] or 0)
      end
    end

    local delta = 0
    for node in pairs(nodes) do
      delta = delta + math.abs((next_rank[node] or 0) - (rank[node] or 0))
    end

    rank = next_rank
    if delta < tolerance then
      break
    end
  end

  return rank
end

local function build_graph(tags, current_rel, mentioned_idents)
  local defines = {}
  local references = {}
  local nodes = {}
  local mentioned = {}

  for _, ident in ipairs(mentioned_idents or {}) do
    mentioned[ident] = true
  end

  for _, tag in ipairs(tags or {}) do
    nodes[tag.rel_fname] = true
    if tag.kind == "def" then
      defines[tag.name] = defines[tag.name] or {}
      defines[tag.name][tag.rel_fname] = true
    elseif tag.kind == "ref" then
      references[tag.name] = references[tag.name] or {}
      references[tag.name][tag.rel_fname] = (references[tag.name][tag.rel_fname] or 0) + 1
    end
  end

  local edges = {}
  local edge_idents = {}

  for ident, definers in pairs(defines) do
    local referencers = references[ident]
    if not referencers then
      for definer in pairs(definers) do
        edges[definer] = edges[definer] or {}
        edges[definer][definer] = (edges[definer][definer] or 0) + 0.1
      end
    else
      local definer_count = vim.tbl_count(definers)
      local mul = 1.0

      if mentioned[ident] then
        mul = mul * 10
      end
      if is_meaningful_name(ident) then
        mul = mul * 10
      end
      if ident:sub(1, 1) == "_" then
        mul = mul * 0.1
      end
      if definer_count > 5 then
        mul = mul * 0.1
      end

      for referencer, num_refs in pairs(referencers) do
        for definer in pairs(definers) do
          local use_mul = mul
          if referencer == current_rel then
            use_mul = use_mul * 50
          end

          local weight = use_mul * math.sqrt(num_refs)
          edges[referencer] = edges[referencer] or {}
          edges[referencer][definer] = (edges[referencer][definer] or 0) + weight

          local edge_key = referencer .. "\n" .. definer
          edge_idents[edge_key] = edge_idents[edge_key] or {}
          edge_idents[edge_key][ident] = true
        end
      end
    end
  end

  return nodes, edges, edge_idents
end

local function sorted_rank(rank, project_root, opts)
  opts = opts or {}
  local limit = opts.limit or M.config.top_files
  local ranked = {}

  for rel_fname, score in pairs(rank or {}) do
    table.insert(ranked, {
      rel_path = rel_fname,
      path = abs_path(rel_fname, project_root),
      repo_rank_score = score,
    })
  end

  table.sort(ranked, function(a, b)
    if a.repo_rank_score == b.repo_rank_score then
      return a.rel_path < b.rel_path
    end
    return a.repo_rank_score > b.repo_rank_score
  end)

  if #ranked > limit then
    ranked = vim.list_slice(ranked, 1, limit)
  end

  return ranked
end

function M.rank_project(current_file, project_root, scan_result, opts)
  opts = opts or {}
  project_root = project_root or project_scanner.get_project_root(current_file)
  scan_result = scan_result or project_scanner.scan_project({ root = project_root })

  local max_files = opts.max_files or M.config.max_files
  local cache_key = string.format("repo_rank:%s:%d", project_root, max_files)
  local graph_data = cache.get(cache_key)

  if not graph_data then
    local tags, tag_meta = repo_tags.extract_project_tags(project_root, scan_result, { max_files = max_files })
    graph_data = {
      tags = tags,
      tag_meta = tag_meta,
    }
    cache.set(cache_key, graph_data, {
      ttl = cache.config.project_ttl,
      tags = { "project" },
    })
  end

  local current_rel = rel_path(current_file, project_root)
  local nodes, edges = build_graph(graph_data.tags, current_rel, opts.mentioned_idents)
  nodes[current_rel] = true

  local seed_nodes = { [current_rel] = 100 }
  for _, file in ipairs(opts.mentioned_files or {}) do
    seed_nodes[rel_path(file, project_root)] = 25
  end

  local personalization = normalize_personalization(nodes, seed_nodes)
  local rank = pagerank(nodes, edges, personalization, opts)
  local ranked = sorted_rank(rank, project_root, { limit = opts.top_files or M.config.top_files })

  local scores_by_path = {}
  for _, item in ipairs(ranked) do
    scores_by_path[item.path] = item.repo_rank_score
  end

  return ranked, {
    tags = graph_data.tag_meta and graph_data.tag_meta.tags or #(graph_data.tags or {}),
    files_scanned = graph_data.tag_meta and graph_data.tag_meta.files_scanned or 0,
    nodes = vim.tbl_count(nodes),
    ranked = #ranked,
    scores_by_path = scores_by_path,
  }
end

return M
