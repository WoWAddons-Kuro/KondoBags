-- KondoBags UI/StockBags.lua -- replaces the stock held-bag windows (SPECS/01_Stock_Bag_Replacement.md).
--
-- Installed = replaced. No setting. The pattern is Bagnon/BagBrother's and is taint-free:
--   R1  the stock functions are NEVER replaced, only hooksecurefunc'd; the bindings and the secure
--       ShowUIPanel -> OpenAllBags path run stock code untouched and we react afterwards;
--   R2  stock ContainerFrameN (and Forever's ContainerFrameCombinedBags) are re-parented into a hidden
--       sink whenever they are assigned a bag we draw, so they "open" invisibly and stock IsBagOpen()
--       stays truthful for merchant / mail / bank logic;
--   R3  a bag we do not draw (Era bank bags until M7) is left alone and opens as a stock frame;
--   R9  auto open/close at vendor, bank, mail, AH, trade comes from PLAYER_INTERACTION_MANAGER_FRAME_*.
-- Window actions live in KondoBags.lua: ns.ToggleBags() / ns.OpenBags() / ns.CloseBags().

local _, ns = ...
local StockBags = {}
ns.StockBags = StockBags

local sink                       -- KondoBagsStockBagSink: hidden frame that swallows stock held-bag frames

local function StockParent() return ContainerFrameContainer or UIParent end

-- KondoBags_HeldBagID: a bag the active provider draws (backpack, bags 1-4, reagent, Era keyring).
function StockBags.IsOurBag(bagID)
  if bagID == nil then return false end
  for _, id in ipairs(ns.Client.Active().BagIDs()) do if id == bagID then return true end end
  -- An empty bag slot has no BagIDs() entry but is still a held bag, never a bank bag.
  local maxHeld = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  if bagID >= 0 and bagID <= maxHeld then return true end
  if KEYRING_CONTAINER and bagID == KEYRING_CONTAINER then return true end
  return false
end

-- The gates stock applies before it opens anything; we refuse whenever stock would.
function StockBags.AllowedToOpen()
  if ContainerFrame_AllowedToOpenBags then return ContainerFrame_AllowedToOpenBags() end
  if IsOptionFrameOpen and IsOptionFrameOpen() then return false end
  if CanOpenPanels and not CanOpenPanels() then return false end
  return true
end

-- ---------------------------------------------------------------------------
-- R2 / R4 / R8: stock frames never render
-- ---------------------------------------------------------------------------
local function Swallow(frame, bagID)
  if StockBags.IsOurBag(bagID) then
    if frame:GetParent() ~= sink then frame:SetParent(sink) end
  elseif frame:GetParent() == sink then
    frame:SetParent(StockParent())
  end
end

local function HookStockFrames()
  sink = CreateFrame("Frame", "KondoBagsStockBagSink", StockParent())
  sink:Hide()
  for i = 1, (NUM_CONTAINER_FRAMES or 13) do
    local f = _G["ContainerFrame" .. i]
    if f then
      hooksecurefunc(f, "SetID", Swallow)
      f:HookScript("OnShow", function(frame)                       -- R4 belt and braces
        if StockBags.IsOurBag(frame:GetID()) then
          Swallow(frame, frame:GetID())
          if not InCombatLockdown() then frame:Hide() end
        end
      end)
      Swallow(f, f:GetID())
    end
  end
  if ContainerFrameCombinedBags then
    ContainerFrameCombinedBags:SetParent(sink)
    if ToggleBackpack_Combined then
      hooksecurefunc("ToggleBackpack_Combined", function() ContainerFrameCombinedBags:SetParent(sink) end)
    end
  end
end

-- R8: Forever's combined-bag mode is forced off so every stock path is the individual one.
local function ForceIndividualBags()
  if not (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("combinedBags") ~= nil) then return end
  if InCombatLockdown() then return end
  if C_CVar.GetCVarBool("combinedBags") then C_CVar.SetCVar("combinedBags", "0") end
end

-- ---------------------------------------------------------------------------
-- R1: toggle hooks, deduped by debugstack like BagBrother
-- ---------------------------------------------------------------------------
local function HookToggles()
  hooksecurefunc("ToggleAllBags", function()
    if not debugstack():find("Manager") then ns.ToggleBags() end
  end)
  hooksecurefunc("ToggleBackpack", function()
    local s = debugstack()
    if not s:find("ToggleAllBags") and not s:find("Manager") then ns.ToggleBags() end
  end)
  hooksecurefunc("ToggleBag", function(bagID)
    if not StockBags.IsOurBag(bagID) then return end
    local s = debugstack()
    if not s:find("OpenBackpack") and not s:find("ToggleBackpack") and not s:find("Manager") then ns.ToggleBags() end
  end)
  -- Escape: CloseAllWindows -> CloseAllBags() with no frame. Frame-scoped calls are panel bookkeeping
  -- (merchant/mail closing "their" bags) and are covered by the interaction events below. Stock's own
  -- toggles also call CloseAllBags internally (ToggleBackpack_Individual when the invisible stock
  -- backpack is "open"); those are already handled by the toggle hooks above, so skip them here or the
  -- window closes and is toggled straight back open (the "first B after /reload does nothing" bug).
  -- Positive match on the Escape path (UIParentPanelManager.lua: CloseAllWindows -> CloseAllBags) rather
  -- than a negative match on toggle names, which also swallowed Escape.
  hooksecurefunc("CloseAllBags", function(frame)
    if frame ~= nil then return end
    local s = debugstack()
    if s:find("CloseAllWindows") then ns.CloseBags() end
  end)
end

-- ---------------------------------------------------------------------------
-- R9: auto display from the interaction manager
-- ---------------------------------------------------------------------------
-- KondoBags_AutoDisplayInteraction: Enum.PlayerInteractionType names that open the window.
local AUTO_DISPLAY = {
  Merchant = true, Banker = true, MailInfo = true, Auctioneer = true, TradePartner = true,
  GuildBanker = true, VoidStorageBanker = true,
}
local interactionName = {}      -- id -> enum name
if Enum and Enum.PlayerInteractionType then
  for name, id in pairs(Enum.PlayerInteractionType) do interactionName[id] = name end
end

local function OnInteraction(event, id)
  local name = interactionName[id]
  if not (name and AUTO_DISPLAY[name]) then return end
  if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then ns.OpenBags() else ns.CloseBags() end
end

-- ---------------------------------------------------------------------------
-- R7: stock parity on our window's show / hide
-- ---------------------------------------------------------------------------
local BAR_BUTTONS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
  "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }

function StockBags.OnWindowShown(shown)
  for _, name in ipairs(BAR_BUTTONS) do
    local b = _G[name]
    if b then
      if b.SlotHighlightTexture then b.SlotHighlightTexture:SetShown(shown)      -- Forever BagsBar
      elseif b.SetChecked then b:SetChecked(shown) end                            -- Era CheckButtons
    end
  end
  if SOUNDKIT then PlaySound(shown and SOUNDKIT.IG_BACKPACK_OPEN or SOUNDKIT.IG_BACKPACK_CLOSE) end
end

-- ---------------------------------------------------------------------------
function StockBags.Setup()
  if sink then return end
  HookStockFrames()
  ForceIndividualBags()
  HookToggles()
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
  f:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
  f:RegisterEvent("CVAR_UPDATE")
  f:SetScript("OnEvent", function(_, event, arg1)
    if event == "CVAR_UPDATE" then
      if arg1 == "combinedBags" then ForceIndividualBags() end
    else
      OnInteraction(event, arg1)
    end
  end)
end