local function check_health()
  local health = vim.health or require("health")
  ---@diagnostic disable: deprecated
  local h_ok = health.ok or health.report_ok
  local h_warn = health.warn or health.report_warn
  local h_error = health.error or health.report_error

  --- Check requires
  local ok_requires = true
  local telescope_ok, telescope = pcall(require, "telescope")
  if not telescope_ok then
    h_error("unexpected: Telescope configuration couldn't be loaded.")
    ok_requires = false
  end
  if not pcall(require, "lazy") then
    h_error("unexpected: Can't access Lazy config spec.")
    ok_requires = false
  end
  if not telescope.extensions.lazy_plugins then
    h_error("unexpected: Telescope Lazy Plugins is not loaded")
    ok_requires = false
  end
  if not ok_requires then
    return
  end

  --- Check config
  local ok_configs = true
  local ok_cfg, config = pcall(require, "telescope._extensions.lazy_plugins.config")
  if not ok_cfg or not config then
    h_error([[Telescope Lazy Plugins configuration couldn't be loaded.
May be a problem in the configuration. Refer to the config examples in the README.]])
    ok_configs = false
  else
    h_ok("Telescope Lazy Plugins configuration found.")
  end
  if not config.options then
    h_error([[Missing options field in configuration.
Might be a problem in the configuration. Refer to the config examples in the README.]])
    ok_configs = false
  else
    h_ok("Telescope Lazy Plugins configuration options found.")
  end
  if not ok_configs then
    return
  end

  local opts = config.options --[[@as TelescopeLazyPluginsConfig]]

  --- Check Lazy config path
  if not (vim.uv or vim.loop).fs_stat(opts.lazy_config) then
    h_error("No Lazy configuration file found. (Set in `lazy_config`)")
  else
    h_ok(("lazy_config found: `%s`"):format(opts.lazy_config))
  end

  --- Entries

  --- Check plugins imports and search lines
  local finder = telescope.extensions.lazy_plugins.finder
  local collection_ok, plugins_collection = pcall(finder.finder)
  if not collection_ok then
    h_warn("Problems detected importing plugin configurations. Maybe missing entries.")
  else
    h_ok("No problems importing plugins config specs.")
  end
  local min_plugins = 4 -- at least: lazy, telescope, plenary and telescope-lazy-plugins
  if #plugins_collection.results < min_plugins then
    h_error("Missing plugins (at least 4). Check configuration.")
  end

  ---@param entry LazyPluginsData
  ---@return boolean
  local function is_custom_entry(entry)
    local custom_entries = vim.tbl_get(config, "options", "custom_entries")
    if custom_entries and #custom_entries > 0 then
      for _, custom in pairs(custom_entries) do
        if entry.name == custom.name and entry.filepath == custom.filepath then
          return true
        end
      end
    end
    return false
  end

  local plugins_without_matches = {}
  for _, plugin in pairs(plugins_collection.results) do
    local full_name = plugin.value.full_name
    if not is_custom_entry(plugin.value) and full_name ~= "folke/lazy.nvim" then
      local filepath = plugin.value.filepath
      -- Only check line 1 plugins since that's the default
      if plugin.value.line == 1 then
        local _, match = finder.line_number_search(full_name, filepath)
        if not match then
          table.insert(plugins_without_matches, { name = full_name, path = filepath })
        end
      end
    end
  end

  if #plugins_without_matches > 0 then
    local msg = "Problems detected searching plugin(s) in the config files:\n"
    for _, plugin in pairs(plugins_without_matches) do
      msg = ("%s- name: '%s'\n  file: '%s'\n"):format(msg, plugin.name, plugin.path)
    end
    h_error(msg)
  else
    h_ok("Found all imported plugin configurations in the module files.")
  end

  --- Check custom user entries
  if not config.raw_custom_entries then
    return
  end

  local custom_entries_errors = {}
  local errors_detected = false
  for i, entry in ipairs(config.raw_custom_entries) do
    local msg = ""
    if not entry.name or type(entry.name) ~= "string" or entry.name == "" then
      msg = ("- name: '%s'\n"):format(entry.name or "Empty name")
      errors_detected = true
    end
    if not entry.filepath or vim.fn.filereadable(entry.filepath) ~= 1 then
      msg = ("%s- filepath: '%s'\n"):format(msg, entry.filepath or "Empty filepath")
      errors_detected = true
    end
    if entry.repo_dir and vim.fn.isdirectory(entry.repo_dir) ~= 1 then
      msg = ("%s- repo_dir:\n'%s'\n"):format(msg, entry.repo_dir)
      errors_detected = true
    end

    if msg == "" then
      msg = "- No errors detected\n"
    end
    table.insert(custom_entries_errors, i, msg)
  end

  if errors_detected then
    local msg = "Problems detected in user custom_entries:\n"
    for idx, error_msg in pairs(custom_entries_errors) do
      msg = ("%sCustom entry number %d:\n%s"):format(msg, idx, error_msg)
    end
    h_error(msg)
  else
    h_ok("No problems detected in custom_entries.")
  end
end

return check_health
