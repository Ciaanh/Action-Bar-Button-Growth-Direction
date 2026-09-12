-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-- Copyright (c) 2023-2026 Thomas Floeren

local MYNAME, NS = ...

local DB_VERSION = 1
--local debug = true

local function dprint(...)
	if debug then print('|cff33ff99'..MYNAME..'|r DEBUG:', ...) end
end
NS.dprint = dprint

--[[===========================================================================
	Init
===========================================================================]]--

local defaults = {
	db_version = DB_VERSION,
	method = 3, -- 3 = new taint-safe container repositioning (default); 1/2 = legacy, tainting
	enable = { y = 'some', x = 'none' },
	y = {
		[1] = true,
		[2] = false,
		[3] = false,
		[4] = false,
		[5] = false,
		[6] = false,
		[7] = false,
		[8] = false,
		[9] = false, -- StanceBar
		[10] = false, -- PetActionBar
	},
	x = {
		[1] = false,
		[2] = false,
		[3] = false,
		[4] = false,
		[5] = false,
		[6] = false,
		[7] = false,
		[8] = false,
		[9] = false, -- StanceBar
		[10] = false, -- PetActionBar
	},
}

-- We have `LoadSavedVariablesFirst: 1`

if type(ABBGD_db) ~= 'table' or ABBGD_db.db_version ~= DB_VERSION then
	ABBGD_db = defaults
end

-- Auto-upgrade existing profiles off the known-tainting mechanism.
if ABBGD_db.method == 1 or ABBGD_db.method == 2 then
	ABBGD_db.method = 3
end

-- No db merge needed ATM

local db = ABBGD_db
NS.db = db

--[[===========================================================================
	Main

	NOTE :
	Writing to a bar's own fields (addButtonsToTop/addButtonsToRight) and/or
	calling a protected method (UpdateGridLayout/Layout) on it from insecure
	addon code permanently taints that secure frame for the whole session.
	Under the 12.0+ (and 1.60 beta) "secret values" security model this taint 
	leaks into unrelated systems later touching the same frame (party frames, 
	action button cooldowns, Edit Mode, etc.), throwing errors like
	"tainted by 'ActionBarButtonGrowthDirection'".

	To avoid this we never write to the bar's own table and never call any
	method on the bar itself. We only reposition its (non-secure) button
	container child frames directly, replicating Blizzard's own grid-layout
	math, and we always do this from a freshly scheduled (C_Timer.After)
	callback so it never executes inside a call stack that Blizzard itself
	initiated.

	This taint-safe method also fix issues with Pet and Stance bars.
===========================================================================]]--

local modified = {}
local map = {
	-- Updated to match Blizzard's current frame name (MainActionBar), both for Classic and Retail,
	-- while keeping a fallback resolver for older clients using MainMenuBar.
	[1] = 'MainActionBar', -- previously MainMenuBar
	[2] = 'MultiBarBottomLeft',
	[3] = 'MultiBarBottomRight',
	[4] = 'MultiBarRight',
	[5] = 'MultiBarLeft',
	[6] = 'MultiBar5',
	[7] = 'MultiBar6',
	[8] = 'MultiBar7',
	-- Re-enabled under method 3: StanceBar/PetActionBar taint (issues #5/#6) came
	-- from writing fields/hooking UpdateGridLayout on them directly, which method
	-- 3 never does. Disable again (comment out) if they still misbehave.
	[9] = 'StanceBar',
	[10] = 'PetActionBar',
}
NS.map = map

-- Fallbacks for frames that were renamed in recent client patches
local fallback_map = {
	-- known rename: MainMenuBar -> MainActionBar. Add both directions so we can
	-- resolve either name on older or newer clients.
	['MainMenuBar'] = 'MainActionBar',
	['MainActionBar'] = 'MainMenuBar',
}

local function resolve_bar_name(name)
	if type(name) ~= 'string' then return nil end
	if _G[name] then return name end
	if fallback_map[name] and _G[fallback_map[name]] then return fallback_map[name] end
	-- Generic substitution in case of simple renames
	local alt = name:gsub('MainMenuBar', 'MainActionBar')
	if alt ~= name and _G[alt] then return alt end
	return nil
end

-- Try to resolve a frame from either a name or an existing frame object.
-- Returns: frame, resolvedName
local function try_get_frame(name_or_frame)
	if type(name_or_frame) == 'table' then
		-- already a frame-like object; try to get its name if available
		local ok_name = nil
		if type(name_or_frame.GetName) == 'function' then
			ok_name = name_or_frame:GetName()
		end
		return name_or_frame, ok_name
	end
	if type(name_or_frame) ~= 'string' then
		return nil, nil
	end
	local resolved = resolve_bar_name(name_or_frame) or name_or_frame
	local frame = _G[resolved]
	if frame then
		return frame, resolved
	end
	return nil, nil
end

local reverse_growth = {
	-- Accepts: axis, frame, opt_name
	-- LEGACY, kept only for anyone who explicitly forces db.method back to 1/2.
	-- Known to taint the bar (see NOTE above); prefer method 3 (the default).
	[1] = function(axis, frame, opt_name)
		if not frame then
			dprint('reverse_growth[1]: frame not found', tostring(opt_name))
			return
		end
		if axis == 'y' then
			frame.addButtonsToTop = not frame.addButtonsToTop
		else
			frame.addButtonsToRight = not frame.addButtonsToRight
		end
	end,
	[2] = function(axis, frame, opt_name)
		if not frame then
			dprint('reverse_growth[2]: frame not found', tostring(opt_name))
			return
		end
		if axis == 'y' then
			hooksecurefunc(frame, 'UpdateGridLayout', function(self)
				self.addButtonsToTop = not self.addButtonsToTop
			end)
		else
			hooksecurefunc(frame, 'UpdateGridLayout', function(self)
				self.addButtonsToRight = not self.addButtonsToRight
			end)
		end
	end,
}

local function modify_bars_legacy()
	for axis, enableaxis in pairs(db.enable) do
		if enableaxis ~= 'none' then
			local bars = db[axis]
			if type(bars) == 'table' then
				for idx, enablebar in pairs(bars) do
					if enableaxis == 'all' or enablebar then
						local bar_name = map[idx]
						local frame, resolved = try_get_frame(bar_name)
						if frame then
							reverse_growth[db.method](axis, frame, resolved or bar_name)
							-- Store the resolved frame to avoid re-resolving later
							modified[resolved or bar_name] = frame
						else
							-- Frame not present; simply log. No deferred retry.
							dprint('modify_bars_legacy: bar not found', tostring(bar_name))
						end
					end
				end
			end
		end
	end
end

local function update_grid_layouts_legacy()
	local c = 0
	for name, frame in pairs(modified) do
		if frame and type(frame.UpdateGridLayout) == 'function' then
			frame:UpdateGridLayout()
			c = c + 1
		else
			dprint('update_grid_layouts_legacy: could not update', tostring(name))
		end
	end
	wipe(modified)
	dprint('updated', c, 'modified action bars(s) (legacy).')
end

-- Reproduces ActionBarMixin:UpdateGridLayout's math ourselves, but only ever
-- touches the (non-secure) button container children, never the bar itself.
local function apply_reversed_layout(name, frame, axes)
	if not frame or type(frame.shownButtonContainers) ~= 'table' then
		dprint('apply_reversed_layout: no frame or shownButtonContainers for', tostring(name))
		return
	end
	if type(GridLayoutUtil) ~= 'table' or type(AnchorUtil) ~= 'table' then
		dprint('apply_reversed_layout: GridLayoutUtil/AnchorUtil not available')
		return
	end
	local containers = frame.shownButtonContainers
	if #containers == 0 then
		dprint('apply_reversed_layout:', name, 'has 0 shown containers, skipping')
		return
	end

	local addTop = frame.addButtonsToTop
	if axes.y then
		addTop = not addTop
	end
	local addRight = frame.addButtonsToRight
	if axes.x then
		addRight = not addRight
	end

	local numRows = frame.numRows or 1
	local stride = math.max(1, math.ceil(#containers / numRows))
	local minPad = frame.minButtonPadding or 2
	local buttonPadding = math.max(minPad, frame.buttonPadding or minPad)
	local xMultiplier = addRight and 1 or -1
	local yMultiplier = addTop and 1 or -1

	local layout
	if frame.isHorizontal then
		layout = GridLayoutUtil.CreateStandardGridLayout(stride, buttonPadding, buttonPadding, xMultiplier, yMultiplier)
	else
		layout = GridLayoutUtil.CreateVerticalGridLayout(stride, buttonPadding, buttonPadding, xMultiplier, yMultiplier)
	end

	local anchorPoint
	if frame.addButtonsToLeft then
		anchorPoint = 'LEFT'
	elseif addTop then
		anchorPoint = addRight and 'BOTTOMLEFT' or 'BOTTOMRIGHT'
	else
		anchorPoint = addRight and 'TOPLEFT' or 'TOPRIGHT'
	end

	if DEBUG then
		dprint(string.format(
			'apply_reversed_layout: %s containers=%d numRows=%s isHorizontal=%s addTop=%s addRight=%s stride=%d pad=%s anchor=%s',
			tostring(name), #containers, tostring(numRows), tostring(frame.isHorizontal),
			tostring(addTop), tostring(addRight), stride, tostring(buttonPadding), anchorPoint
		))
	end

	GridLayoutUtil.ApplyGridLayout(containers, AnchorUtil.CreateAnchor(anchorPoint, frame, anchorPoint), layout)
end

-- Bars we've ever touched, so we can restore their default layout
-- if a setting is turned off via the options panel without a UI reload.
local known_bars = {}

local function collect_modified_bars()
	wipe(modified)
	for axis, enableaxis in pairs(db.enable) do
		dprint('collect_modified_bars: axis', axis, 'enable', tostring(enableaxis))
		if enableaxis ~= 'none' then
			local bars = db[axis]
			if type(bars) == 'table' then
				for idx, enablebar in pairs(bars) do
					if enableaxis == 'all' or enablebar then
						local bar_name = map[idx]
						local frame, resolved = try_get_frame(bar_name)
						if frame then
							local key = resolved or bar_name
							modified[key] = modified[key] or { frame = frame, axes = {} }
							modified[key].axes[axis] = true
							known_bars[key] = frame
							dprint('collect_modified_bars: will reverse', axis, 'for', tostring(key))
						else
							dprint('collect_modified_bars: bar not found', tostring(bar_name))
						end
					end
				end
			end
		end
	end
end

local function reapply_all()
	local c = 0
	-- Iterate every bar we've touched, not just the currently-enabled ones,
	-- so unchecking a bar restores its default layout immediately.
	for name, frame in pairs(known_bars) do
		local entry = modified[name]
		apply_reversed_layout(name, frame, entry and entry.axes or {})
		c = c + 1
	end
	dprint('reapply_all: processed', c, 'bar(s)')
end

local reapply_pending = false
local function run_pending_reapply()
	reapply_pending = false
	reapply_all()
end

-- Always run on a fresh, untainted execution context (next frame tick), so we
-- never execute right inside a call stack that Blizzard itself initiated.
-- Debounced: multiple events in the same frame only schedule one timer.
local function schedule_reapply(event)
	dprint('schedule_reapply: triggered by', tostring(event))
	collect_modified_bars()
	if reapply_pending then return end
	if C_Timer and C_Timer.After then
		reapply_pending = true
		C_Timer.After(0, run_pending_reapply)
	else
		reapply_all()
	end
end

-- expose schedule_reapply to the namespace for use by the options panel
NS.schedule_reapply = schedule_reapply

--[[===========================================================================
	Events
===========================================================================]]--

local ef = CreateFrame 'Frame'
ef:RegisterEvent 'ADDON_LOADED'
ef:RegisterEvent 'PLAYER_LOGIN'
ef:RegisterEvent 'PLAYER_ENTERING_WORLD'
ef:RegisterEvent 'ACTIONBAR_PAGE_CHANGED'
ef:RegisterEvent 'UPDATE_BONUS_ACTIONBAR'
ef:RegisterEvent 'UPDATE_VEHICLE_ACTIONBAR'
ef:RegisterEvent 'UPDATE_OVERRIDE_ACTIONBAR'
ef:RegisterEvent 'UPDATE_SHAPESHIFT_FORM'
ef:RegisterEvent 'ACTIONBAR_SHOW_BOTTOMLEFT'
ef:RegisterEvent 'UPDATE_EXTRA_ACTIONBAR'
ef:RegisterEvent 'UPDATE_POSSESS_BAR'
-- PetActionBar triggers
ef:RegisterEvent 'PET_BAR_UPDATE'
ef:RegisterEvent 'UNIT_PET'
ef:RegisterEvent 'PLAYER_CONTROL_GAINED'
ef:RegisterEvent 'PLAYER_CONTROL_LOST'

ef:SetScript('OnEvent', function(self, event, unit)
	dprint('OnEvent:', event, 'method', tostring(db.method))
	if event == 'ADDON_LOADED' then
		self:UnregisterEvent 'ADDON_LOADED'
		return
	end

	-- UNIT_PET fires for any unit in the group; only react to our own pet.
	if event == 'UNIT_PET' and unit ~= 'player' then
		return
	end

	if db.method == 1 or db.method == 2 then
		-- Legacy, opt-in only; known to cause taint.
		if event == 'PLAYER_LOGIN' then
			modify_bars_legacy()
			update_grid_layouts_legacy()
		end
		return
	end

	schedule_reapply(event)
end)

