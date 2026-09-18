-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-- Copyright (c) 2023-2026 Thomas Floeren

local MYNAME, NS = ...
local db = NS.db
local map = NS.map
local dprint = NS.dprint
local schedule_reapply = NS.schedule_reapply

--[[===========================================================================
	Options panel (Settings API)

	Live-editable: every setter below calls schedule_reapply(), and main.lua's
	reapply_all() restores a bar's default layout as soon as it's no longer
	enabled, so changes take effect immediately, no /reload required.
===========================================================================]]--

local BAR_LABELS = {
	[1] = 'Main Action Bar',
	[2] = 'Action Bar 2',
	[3] = 'Action Bar 3',
	[4] = 'Action Bar 4',
	[5] = 'Action Bar 5',
	[6] = 'Action Bar 6',
	[7] = 'Action Bar 7',
	[8] = 'Action Bar 8',
	[9] = 'Stance Bar',
	[10] = 'Pet Action Bar',
}
local MAX_BAR_INDEX = 10

local ENABLE_OPTIONS = {
	{ value = 'none', label = 'None (per-bar settings ignored)' },
	{ value = 'some', label = 'Per bar (use the checkboxes below)' },
	{ value = 'all', label = 'All bars' },
}

local function make_enable_dropdown(category, axis, axis_label)
	local function get() return db.enable[axis] end
	local function set(value)
		db.enable[axis] = value
		schedule_reapply('OPTIONS_enable_' .. axis)
	end

	local setting = Settings.RegisterProxySetting(
		category, 
		'ABBGD_enable_' .. axis, 
		Settings.VarType.String,
		'Axis activation mode', 
		'some', 
		get, 
		set
	)

	local function options()
		local container = Settings.CreateControlTextContainer()
		for _, opt in ipairs(ENABLE_OPTIONS) do
			container:Add(opt.value, opt.label)
		end
		return container:GetData()
	end
	
	return Settings.CreateDropdown(
		category, 
		setting, 
		options,
		'Controls whether the ' .. axis_label .. '-axis growth direction is reversed, and for which bars.')
end

-- parent_initializer is the axis' enable-mode dropdown; its checkboxes are
-- greyed out and non-interactive whenever that axis' enable mode is 'none'.
local function make_bar_checkboxes(category, axis, axis_label, note, parent_initializer)
	local function is_axis_enabled() return db.enable[axis] ~= 'none' and db.enable[axis] ~= 'all' end
	
	for idx = 1, MAX_BAR_INDEX do
		local current_idx = idx
		
		local label = BAR_LABELS[current_idx] or tostring(current_idx)
		local function get() return db[axis][current_idx] end
		local function set(value)
			db[axis][current_idx] = value
			schedule_reapply('OPTIONS_' .. axis .. '_' .. current_idx)
		end

		local setting = Settings.RegisterProxySetting(
			category, 
			'ABBGD_' .. axis .. '_' .. current_idx, 
			Settings.VarType.Boolean,
			label, 
			false, 
			get, 
			set
		)
		local checkbox = Settings.CreateCheckbox(
			category, 
			setting, 
			'Reverse the ' .. axis_label .. '-axis growth direction of ' .. label .. note)
		if parent_initializer then
			checkbox:SetParentInitializer(parent_initializer, is_axis_enabled)
			
		end
	end
end

local function build_options_panel()
	if type(Settings) ~= 'table' or type(Settings.RegisterVerticalLayoutCategory) ~= 'function' then
		dprint('build_options_panel: Settings API not available, skipping options panel')
		return
	end

	local ok, err = pcall(function()
		local category = Settings.RegisterVerticalLayoutCategory('Action Bar Button Growth Direction')
		Settings.RegisterAddOnCategory(category)
		
		Settings.RegisterInitializer(category, CreateSettingsListSectionHeaderInitializer('Y-axis reversal :'))
		local y_dropdown = make_enable_dropdown(category, 'y', 'Y')
		make_bar_checkboxes(category, 'y', 'Y', '. Only used when the Y-axis dropdown above is set to "Per bar".', y_dropdown)

		Settings.RegisterInitializer(category, CreateSettingsListSectionHeaderInitializer('X-axis reversal :'))
		local x_dropdown = make_enable_dropdown(category, 'x', 'X')
		make_bar_checkboxes(category, 'x', 'X', '. Only used when the X-axis dropdown above is set to "Per bar".', x_dropdown)
	end)
	if not ok then
		dprint('build_options_panel: failed to build options panel:', tostring(err))
	end
end

build_options_panel()
