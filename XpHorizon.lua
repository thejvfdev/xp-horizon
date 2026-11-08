-- XP Horizon
-- Hold Shift while hovering the XP bar to see how much of the total XP from
-- level 1 to the level cap you have already earned: the bar itself fills to
-- show it, and the tooltip breaks it down.

local ADDON_NAME = ...

local MAX_LEVEL = 60

-- XP needed to go from level N to level N + 1: the vanilla Classic curve,
-- 4,084,700 XP in total. The game only reports this number for the level you
-- are currently at (UnitXPMax), so every time a character on this account is
-- seen at a level, the reported value is saved and used instead of this table.
-- If Forever's curve differs from vanilla, the totals correct themselves for
-- every level you have played.
local DEFAULT_XP_TO_NEXT_LEVEL = {
    400,    900,    1400,   2100,   2800,   3600,   4500,   5400,   6500,   7600,   -- 1-10
    8800,   10100,  11400,  12900,  14400,  16000,  17700,  19400,  21300,  23200,  -- 11-20
    25200,  27300,  29400,  31700,  34000,  36400,  38900,  41400,  44300,  47400,  -- 21-30
    50800,  54500,  58600,  62800,  67100,  71600,  76100,  80800,  85700,  90700,  -- 31-40
    95800,  101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500, -- 41-50
    153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,         -- 51-59
}

-- Level ranges in the breakdown. Each one covers the XP from reaching the
-- first level to reaching the second.
local BRACKETS = {
    { 1, 10 }, { 10, 20 }, { 20, 30 }, { 30, 40 }, { 40, 50 }, { 50, 60 },
}

-- Art used by Forever's XP bar, so the 1-60 bar looks like the normal one.
local BAR_BACKGROUND_ATLAS = "UI-HUD-ExperienceBar-Background"
local BAR_FILL_ATLAS = "UI-HUD-ExperienceBar-Fill-Experience"

local LABEL_COLOR = { 1, 0.82, 0 }       -- gold
local VALUE_COLOR = { 1, 1, 1 }          -- white
local DONE_COLOR = { 0.25, 1, 0.25 }     -- green
local PENDING_COLOR = { 0.5, 0.5, 0.5 }  -- grey

local db

local function InitDb()
    if type(XpHorizonDb) ~= "table" then
        XpHorizonDb = {}
    end
    if type(XpHorizonDb.xpToNextLevel) ~= "table" then
        XpHorizonDb.xpToNextLevel = {}
    end
    db = XpHorizonDb
end

-- Saves the XP the game reports for the player's current level. Only call
-- this when level and XP are stable (login, hovering), not during a level-up,
-- when UnitLevel and UnitXPMax can briefly disagree.
local function LearnCurrentLevel()
    if not db then
        return
    end
    local level = UnitLevel("player")
    if level < 1 or level >= MAX_LEVEL then
        return
    end
    local xpToNext = UnitXPMax("player")
    if xpToNext and xpToNext > 0 then
        db.xpToNextLevel[level] = xpToNext
    end
end

local function XpToNextLevel(level)
    return (db and db.xpToNextLevel[level]) or DEFAULT_XP_TO_NEXT_LEVEL[level] or 0
end

-- XP needed to go from reaching fromLevel to reaching toLevel.
local function XpBetween(fromLevel, toLevel)
    local sum = 0
    for level = fromLevel, toLevel - 1 do
        sum = sum + XpToNextLevel(level)
    end
    return sum
end

local function GetProgress()
    local level = math.min(UnitLevel("player"), MAX_LEVEL)
    local total = XpBetween(1, MAX_LEVEL)
    local earned
    if level >= MAX_LEVEL then
        earned = total
    else
        earned = XpBetween(1, level) + math.min(UnitXP("player"), XpToNextLevel(level))
    end
    return level, earned, total
end

local function FormatPercent(part, whole)
    if whole <= 0 then
        return "0%"
    end
    -- Round down so 99.96% shows as 99.9% rather than 100.0%.
    return ("%.1f%%"):format(math.floor(part / whole * 1000) / 10)
end

-- Tooltip -------------------------------------------------------------------

local function AddRow(tooltip, label, value, valueColor)
    local l, v = LABEL_COLOR, valueColor or VALUE_COLOR
    tooltip:AddDoubleLine(label, value, l[1], l[2], l[3], v[1], v[2], v[3])
end

local function ShowHorizonTooltip()
    local level, earned, total = GetProgress()
    local tooltip = GameTooltip

    -- Hiding first also releases the progress bar from an earlier render.
    tooltip:Hide()
    GameTooltip_SetDefaultAnchor(tooltip, UIParent)

    tooltip:AddDoubleLine("XP Horizon", ("Level %d / %d"):format(level, MAX_LEVEL), 1, 1, 1, 1, 1, 1)
    AddRow(tooltip, "Earned", BreakUpLargeNumbers(earned) .. " / " .. BreakUpLargeNumbers(total))
    AddRow(tooltip, "Remaining", BreakUpLargeNumbers(total - earned))
    if GameTooltip_ShowStatusBar then
        GameTooltip_ShowStatusBar(tooltip, 0, total, earned, FormatPercent(earned, total))
    else
        AddRow(tooltip, "Completed", FormatPercent(earned, total))
    end

    tooltip:AddLine(" ")
    for _, bracket in ipairs(BRACKETS) do
        local fromLevel, toLevel = bracket[1], bracket[2]
        local size = XpBetween(fromLevel, toLevel)
        local earnedInBracket = math.max(0, math.min(earned - XpBetween(1, fromLevel), size))
        local label = ("Levels %d-%d"):format(fromLevel, toLevel)
        if earnedInBracket >= size then
            AddRow(tooltip, label, "Done", DONE_COLOR)
        elseif earnedInBracket <= 0 then
            AddRow(tooltip, label, "0%", PENDING_COLOR)
        else
            AddRow(tooltip, label, FormatPercent(earnedInBracket, size))
        end
    end

    local rested = GetXPExhaustion and GetXPExhaustion()
    if rested and rested > 0 and level < MAX_LEVEL then
        tooltip:AddLine(" ")
        AddRow(tooltip, "Rested", BreakUpLargeNumbers(rested))
    end

    tooltip:Show()
end

-- 1-60 bar ------------------------------------------------------------------

-- While Shift is held, a copy of the XP bar filled to the 1-60 progress is
-- drawn over Blizzard's bar. Blizzard's own fill and text are never changed,
-- so their animations and updates carry on underneath, and hiding the copy
-- is all it takes to go back.
local overlays = {} -- XP bar -> its 1-60 copy

local function HighestFrameLevel(frame)
    local highest = frame:GetFrameLevel()
    for _, child in ipairs({ frame:GetChildren() }) do
        highest = math.max(highest, HighestFrameLevel(child))
    end
    return highest
end

local function CreateOverlay(bar)
    local frameLevel = HighestFrameLevel(bar) + 1

    local overlay = CreateFrame("Frame", nil, bar)
    -- Blizzard draws the XP text at MEDIUM strata, above the rest of the bar.
    -- Drawing the copy at MEDIUM and above every part of the bar covers the
    -- fill, the rested-XP marker and the text.
    overlay:SetFrameStrata("MEDIUM")
    overlay:SetFrameLevel(frameLevel)
    overlay:SetAllPoints(bar.StatusBar or bar)
    overlay:Hide()
    -- If the bar is hidden while the copy is up, keep the copy hidden when
    -- the bar comes back.
    overlay:SetScript("OnHide", overlay.Hide)

    -- Opaque base so Blizzard's fill never shows through the background art.
    local base = overlay:CreateTexture(nil, "BACKGROUND", nil, -8)
    base:SetAllPoints()
    base:SetColorTexture(0, 0, 0, 1)

    local background = overlay:CreateTexture(nil, "BACKGROUND", nil, -7)
    background:SetAllPoints()
    background:SetAtlas(BAR_BACKGROUND_ATLAS)

    local fill = overlay:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetAtlas(BAR_FILL_ATLAS)

    local text = overlay:CreateFontString(nil, "OVERLAY")
    local blizzardText = bar.OverlayFrame and bar.OverlayFrame.Text
    text:SetFontObject(blizzardText and blizzardText:GetFontObject() or "GameFontHighlightSmall")
    text:SetPoint("CENTER", bar, "CENTER", 0, 1)

    overlay.fill = fill
    overlay.text = text
    return overlay
end

local function ShowOverlay(bar)
    local overlay = overlays[bar]
    if not overlay then
        overlay = CreateOverlay(bar)
        overlays[bar] = overlay
    end

    local _, earned, total = GetProgress()
    overlay:Show()
    local fillWidth = total > 0 and overlay:GetWidth() * earned / total or 0
    if fillWidth >= 1 then
        overlay.fill:SetWidth(fillWidth)
        overlay.fill:Show()
    else
        overlay.fill:Hide()
    end
    overlay.text:SetText(("Levels 1-%d: %s / %s (%s)"):format(
        MAX_LEVEL, BreakUpLargeNumbers(earned), BreakUpLargeNumbers(total), FormatPercent(earned, total)))
end

local function HideOverlays()
    for _, overlay in pairs(overlays) do
        overlay:Hide()
    end
end

-- Hooking -------------------------------------------------------------------

-- Hooked frame -> the XP bar it belongs to. Kept here rather than flagged on
-- Blizzard's own frames, so the addon never writes into Blizzard tables
-- (which would taint them).
local hookedFrames = {}
local hoveredFrame

local function ShowHorizon(frame)
    ShowOverlay(hookedFrames[frame])
    ShowHorizonTooltip()
end

local function OnEnterHook(frame)
    hoveredFrame = frame
    if IsShiftKeyDown() then
        LearnCurrentLevel()
        ShowHorizon(frame)
    end
end

local function OnLeaveHook(frame)
    -- Moving between the bar and its rested-XP marker can fire the new
    -- frame's OnEnter before the old frame's OnLeave; only the frame still
    -- under the mouse decides what is shown.
    if hoveredFrame == frame then
        hoveredFrame = nil
        HideOverlays()
    end
end

local function HookFrame(frame, bar)
    if not frame or hookedFrames[frame] then
        return
    end
    hookedFrames[frame] = bar
    frame:HookScript("OnEnter", OnEnterHook)
    frame:HookScript("OnLeave", OnLeaveHook)
end

-- Forever uses the modern status bar system: the XP bar is an unnamed frame
-- in the bars table of each status bar container.
local function FindXpBars()
    local found = {}
    local barsEnum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    local experienceIndex = barsEnum and barsEnum.Experience
    for _, containerName in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
        local container = _G[containerName]
        if container and type(container.bars) == "table" then
            local bar = experienceIndex and container.bars[experienceIndex]
            if not bar then
                -- Only the XP bar has a rested-XP marker.
                for _, candidate in pairs(container.bars) do
                    if candidate.ExhaustionTick then
                        bar = candidate
                        break
                    end
                end
            end
            if bar then
                table.insert(found, bar)
            end
        end
    end
    -- Older Classic-style XP bar, in case a UI addon brings it back.
    if MainMenuExpBar then
        table.insert(found, MainMenuExpBar)
    end
    return found
end

local function HookXpBars()
    for _, bar in ipairs(FindXpBars()) do
        HookFrame(bar, bar)
        -- The rested-XP marker is a child button with its own tooltip.
        HookFrame(bar.ExhaustionTick, bar)
    end
end

local function RestoreDefaultTooltip(frame)
    GameTooltip:Hide()
    -- On the modern XP bar, the bar and its rested-XP marker both show the
    -- rested-XP tooltip. Calling only that keeps the addon away from the rest
    -- of the bar's Blizzard code.
    local tick = frame.ExhaustionToolTipText and frame or frame.ExhaustionTick
    if tick and tick.ExhaustionToolTipText then
        tick:ExhaustionToolTipText()
        return
    end
    local onEnter = frame:GetScript("OnEnter")
    if onEnter then
        onEnter(frame, false)
    end
end

local function IsHovering(frame)
    return frame and frame:IsVisible() and frame:IsMouseOver()
end

local function OnShiftChanged()
    local frame = hoveredFrame
    if not IsHovering(frame) then
        return
    end
    if IsShiftKeyDown() then
        LearnCurrentLevel()
        ShowHorizon(frame)
    else
        HideOverlays()
        RestoreDefaultTooltip(frame)
    end
end

-- Events --------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("UPDATE_EXHAUSTION")

events:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON_NAME then
            InitDb()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        LearnCurrentLevel()
        HookXpBars() -- Runs after every loading screen; already-hooked bars are skipped.
    elseif event == "MODIFIER_STATE_CHANGED" then
        local key = ...
        if key == "LSHIFT" or key == "RSHIFT" then
            OnShiftChanged()
        end
    else
        -- XP or rested XP changed: refresh the 1-60 view if it is showing.
        if IsShiftKeyDown() and IsHovering(hoveredFrame) then
            ShowHorizon(hoveredFrame)
        end
    end
end)
