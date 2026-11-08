-- XP Horizon
-- Hold Shift while hovering the XP bar to see how much of the total XP from
-- level 1 to the level cap you have already earned: the bar itself fills to
-- show it, and the tooltip adds the numbers and an estimate of the /played
-- time at which you will reach the cap.

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

-- Art from Forever's status bars, so the 1-60 bar looks like the normal XP
-- bar. The fill is the green one the reputation bar uses from Friendly up,
-- from the same set as the purple XP fill.
local BAR_BACKGROUND_ATLAS = "UI-HUD-ExperienceBar-Background"
local BAR_FILL_ATLAS = "UI-HUD-ExperienceBar-Fill-Reputation-Faction-Green"

local LABEL_COLOR = { 1, 0.82, 0 }      -- gold
local VALUE_COLOR = { 1, 1, 1 }         -- white
local MUTED_COLOR = { 0.5, 0.5, 0.5 }   -- grey

-- XP data --------------------------------------------------------------------

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

-- Played time ----------------------------------------------------------------

-- The client only learns the character's /played by asking the server
-- (RequestTimePlayed), and the server's answer is also printed in chat. It is
-- asked for once per session, the first time the 1-60 view opens, and counted
-- forward locally from then on. Typing /played yourself updates it as well.
local playedSeconds     -- /played total in the server's last answer
local playedAnsweredAt  -- GetTime() when that answer arrived
local playedRequested = false

local function RequestPlayedOnce()
    if not playedSeconds and not playedRequested then
        playedRequested = true
        RequestTimePlayed()
    end
end

local function GetPlayedSeconds()
    if not playedSeconds then
        return nil
    end
    return playedSeconds + (GetTime() - playedAnsweredAt)
end

-- Formatting -----------------------------------------------------------------

local function FormatPercent(part, whole)
    if whole <= 0 then
        return "0%"
    end
    -- Round down so 99.96% shows as 99.9% rather than 100.0%.
    return ("%.1f%%"):format(math.floor(part / whole * 1000) / 10)
end

local function FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds % 86400 / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    if days > 0 then
        return ("%dd %dh %dm"):format(days, hours, minutes)
    elseif hours > 0 then
        return ("%dh %dm"):format(hours, minutes)
    end
    return ("%dm"):format(minutes)
end

-- Tooltip --------------------------------------------------------------------

local function AddRow(tooltip, label, value, valueColor)
    local l, v = LABEL_COLOR, valueColor or VALUE_COLOR
    tooltip:AddDoubleLine(label, value, l[1], l[2], l[3], v[1], v[2], v[3])
end

local function ShowHorizonTooltip()
    local level, earned, total = GetProgress()
    local remaining = total - earned
    local tooltip = GameTooltip

    tooltip:Hide()
    GameTooltip_SetDefaultAnchor(tooltip, UIParent)

    -- The percentage sits on the title line, next to the addon name.
    tooltip:AddDoubleLine("XP Horizon",
        ("|cffffffff%s|r to level %d"):format(FormatPercent(earned, total), MAX_LEVEL),
        1, 1, 1, LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3])
    AddRow(tooltip, "Level", ("%d / %d"):format(level, MAX_LEVEL))
    AddRow(tooltip, "XP earned", BreakUpLargeNumbers(earned) .. " / " .. BreakUpLargeNumbers(total))
    AddRow(tooltip, "XP remaining", BreakUpLargeNumbers(remaining))

    -- Estimate: the character's average XP per second of /played so far,
    -- applied to the XP still needed.
    tooltip:AddLine(" ")
    local played = GetPlayedSeconds()
    if not played then
        AddRow(tooltip, "Time played", "Asking the server...", MUTED_COLOR)
    else
        AddRow(tooltip, "Time played", FormatDuration(played))
        if remaining > 0 then
            if earned > 0 and played > 0 then
                local xpPerSecond = earned / played
                local timeLeft = remaining / xpPerSecond
                AddRow(tooltip, "XP per hour played", BreakUpLargeNumbers(math.floor(xpPerSecond * 3600)))
                AddRow(tooltip, ("Est. time to %d"):format(MAX_LEVEL), FormatDuration(timeLeft))
                AddRow(tooltip, ("Est. time at %d"):format(MAX_LEVEL), FormatDuration(played + timeLeft))
            else
                AddRow(tooltip, ("Est. time at %d"):format(MAX_LEVEL), "Not enough data yet", MUTED_COLOR)
            end
        end
    end

    local rested = GetXPExhaustion and GetXPExhaustion()
    if rested and rested > 0 and level < MAX_LEVEL then
        AddRow(tooltip, "Rested XP", BreakUpLargeNumbers(rested))
    end

    tooltip:Show()
end

-- 1-60 bar -------------------------------------------------------------------

-- While Shift is held, Blizzard's fill, rested-XP marks and text are faded
-- out, and a status bar with the same background art and a green fill from
-- the same set is drawn in their place, filled to the 1-60 progress. The
-- copy sits on the same frame layers as the parts it replaces, so the bar
-- keeps Blizzard's look, transparency included.
-- Blizzard's parts are only faded (alpha), nothing else about them changes,
-- so their own updates carry on underneath and they come back as they were.
local overlays = {}    -- XP bar -> its 1-60 copy
local fadedParts = {}  -- XP bar -> { [Blizzard region] = its alpha before fading }

-- The parts of Blizzard's XP bar that the 1-60 copy replaces.
local function GetBlizzardParts(bar)
    return {
        bar.StatusBar,              -- background, fill and XP-gain animations
        bar.ExhaustionLevelFillBar, -- rested-XP shading ahead of the fill
        bar.ExhaustionTick,         -- rested-XP marker; still takes the mouse while faded
        bar.OverlayFrame and bar.OverlayFrame.Text or nil,
    }
end

local function FadeBlizzardParts(bar)
    if fadedParts[bar] then
        return
    end
    local saved = {}
    for _, region in pairs(GetBlizzardParts(bar)) do
        saved[region] = region:GetAlpha()
        region:SetAlpha(0)
    end
    fadedParts[bar] = saved
end

local function RestoreBlizzardParts(bar)
    local saved = fadedParts[bar]
    if not saved then
        return
    end
    for region, alpha in pairs(saved) do
        region:SetAlpha(alpha)
    end
    fadedParts[bar] = nil
end

local function CreateOverlay(bar)
    local statusBar = bar.StatusBar

    -- Background and fill, on the frame layer of Blizzard's status bar.
    local overlay = CreateFrame("StatusBar", nil, bar)
    overlay:SetFrameStrata(statusBar:GetFrameStrata())
    overlay:SetFrameLevel(statusBar:GetFrameLevel())
    overlay:SetAllPoints(statusBar)
    overlay:Hide()
    -- Bring Blizzard's parts back whenever the copy goes away, including when
    -- the whole bar is hidden while the copy is up. Hiding the copy itself
    -- there also keeps it hidden when the bar comes back.
    overlay:SetScript("OnHide", function(self)
        self:Hide()
        RestoreBlizzardParts(bar)
    end)

    local background = overlay:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetAtlas(BAR_BACKGROUND_ATLAS)

    -- Set up the way Blizzard's XP bar sets its fill, so it renders the same.
    overlay:SetStatusBarTexture(BAR_FILL_ATLAS)
    overlay:GetStatusBarTexture():SetDrawLayer("BORDER")

    -- Text, on the frame layer of Blizzard's XP text (MEDIUM strata).
    local textFrame = CreateFrame("Frame", nil, overlay)
    textFrame:SetFrameStrata("MEDIUM")
    textFrame:SetFrameLevel((bar.OverlayFrame or bar):GetFrameLevel() + 1)
    textFrame:SetAllPoints(bar)

    local text = textFrame:CreateFontString(nil, "OVERLAY")
    local blizzardText = bar.OverlayFrame and bar.OverlayFrame.Text
    text:SetFontObject(blizzardText and blizzardText:GetFontObject() or "GameFontHighlightSmall")
    text:SetPoint("CENTER", bar, "CENTER", 0, 1)

    overlay.text = text
    return overlay
end

local function ShowOverlay(bar)
    if not bar or not bar.StatusBar then
        return
    end
    local overlay = overlays[bar]
    if not overlay then
        overlay = CreateOverlay(bar)
        overlays[bar] = overlay
    end

    local _, earned, total = GetProgress()
    FadeBlizzardParts(bar)
    overlay:SetMinMaxValues(0, math.max(total, 1))
    overlay:SetValue(earned)
    overlay:Show()
    overlay.text:SetText(("%s to level %d (%s / %s)"):format(
        FormatPercent(earned, total), MAX_LEVEL, BreakUpLargeNumbers(earned), BreakUpLargeNumbers(total)))
end

local function HideOverlays()
    for bar, overlay in pairs(overlays) do
        overlay:Hide()
        RestoreBlizzardParts(bar) -- In case the copy was never visible, so OnHide did not run.
    end
end

-- Hooking --------------------------------------------------------------------

-- Hooked frame -> the XP bar it belongs to. Kept here rather than flagged on
-- Blizzard's own frames, so the addon never writes into Blizzard tables
-- (which would taint them).
local hookedFrames = {}
local hoveredFrame

local function ShowHorizon(frame)
    RequestPlayedOnce()
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

-- Redraws the 1-60 view after XP, rested XP or /played changed, if it is up.
local function RefreshIfShowing()
    if IsShiftKeyDown() and IsHovering(hoveredFrame) then
        ShowHorizon(hoveredFrame)
    end
end

-- Events ---------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("UPDATE_EXHAUSTION")
events:RegisterEvent("TIME_PLAYED_MSG")

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
    elseif event == "TIME_PLAYED_MSG" then
        playedSeconds, playedAnsweredAt = ..., GetTime()
        RefreshIfShowing()
    else -- PLAYER_XP_UPDATE, UPDATE_EXHAUSTION
        RefreshIfShowing()
    end
end)
