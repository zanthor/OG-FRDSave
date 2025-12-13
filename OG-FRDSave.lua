-- OG-FRDSave: Force Reactive Disk Durability Management
-- Automatically swaps Force Reactive Disk (18168) when durability gets low

local FORCE_REACTIVE_DISK = 18168
local SHIELD_SLOT = 17  -- Off-hand/shield slot

-- Saved variables
OGFRD_SV = OGFRD_SV or {
  enabled = true,
  backupShield = 1168,  -- Default backup shield
  swapThreshold = 20  -- Durability threshold to trigger swap
}

-- Hidden tooltip for scanning
local scanTooltip = CreateFrame("GameTooltip", "OGFRDSaveTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- Event frame
local frame = CreateFrame("Frame")
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Entering combat
frame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Leaving combat

-- Periodic check timer
local timeSinceLastCheck = 0
local CHECK_INTERVAL = 2  -- Check every 2 seconds

-- Warning message tracking
local timeSinceLastWarning = 0
local WARNING_INTERVAL = 30  -- Warn every 30 seconds

-- Parse durability from tooltip text (e.g., "Durability 95 / 120")
local function ParseDurability(tooltipText)
  if not tooltipText then return nil, nil end
  local current, maximum = string.match(tooltipText, "Durability (%d+) / (%d+)")
  if current and maximum then
    return tonumber(current), tonumber(maximum)
  end
  return nil, nil
end

-- Get durability from bag item
local function GetBagItemDurability(bag, slot)
  scanTooltip:ClearLines()
  scanTooltip:SetBagItem(bag, slot)
  
  for i = 1, scanTooltip:NumLines() do
    local line = getglobal("OGFRDSaveTooltipTextLeft" .. i)
    if line then
      local text = line:GetText()
      local current, maximum = ParseDurability(text)
      if current and maximum then
        return current, maximum
      end
    end
  end
  return nil, nil
end

-- Find an item in bags by itemID and return bag, slot, current, maximum
local function FindItemInBags(itemID)
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, slot)
      if link then
        local _, _, foundItemID = string.find(link, "item:(%d+)")
        foundItemID = tonumber(foundItemID)
        if foundItemID == itemID then
          local current, maximum = GetBagItemDurability(bag, slot)
          return bag, slot, current, maximum
        end
      end
    end
  end
  return nil, nil, nil, nil
end

-- Get equipped shield info
local function GetEquippedShieldInfo()
  local link = GetInventoryItemLink("player", SHIELD_SLOT)
  if not link then
    return nil, nil, nil
  end
  
  local _, _, itemID = string.find(link, "item:(%d+)")
  itemID = tonumber(itemID)
  
  -- Scan tooltip for durability
  scanTooltip:ClearLines()
  scanTooltip:SetInventoryItem("player", SHIELD_SLOT)
  
  local current, maximum
  for i = 1, scanTooltip:NumLines() do
    local line = getglobal("OGFRDSaveTooltipTextLeft" .. i)
    if line then
      local text = line:GetText()
      current, maximum = ParseDurability(text)
      if current and maximum then
        break
      end
    end
  end
  
  return itemID, current, maximum
end

-- Equip item from bags
local function EquipItemFromBags(bag, slot)
  PickupContainerItem(bag, slot)
  PickupInventoryItem(SHIELD_SLOT)
end

-- Main durability check logic
local function CheckAndSwapShield()
  if not OGFRD_SV.enabled then
    return
  end
  
  local equippedID, current, maximum = GetEquippedShieldInfo()
  
  -- Check if we have Force Reactive Disk equipped
  if equippedID ~= FORCE_REACTIVE_DISK then
    return
  end
  
  -- Check if we have durability info
  if not current or not maximum then
    -- Warn user that durability cannot be read
    timeSinceLastWarning = timeSinceLastWarning + timeSinceLastCheck
    if timeSinceLastWarning >= WARNING_INTERVAL then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r |cffff0000WARNING:|r Cannot read Force Reactive Disk durability. Type /reload to fix.")
      timeSinceLastWarning = 0
    end
    return
  end
  
  -- Reset warning timer when durability is readable
  timeSinceLastWarning = 0
  
  -- Check if durability is low
  if current >= OGFRD_SV.swapThreshold then
    return
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Force Reactive Disk durability low (" .. current .. "/" .. maximum .. "), searching for replacement...")
  
  -- Look for another Force Reactive Disk with > 100 durability
  local bag, slot, bagCurrent, bagMaximum = FindItemInBags(FORCE_REACTIVE_DISK)
  if bag and bagCurrent and bagCurrent > 100 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Found Force Reactive Disk with " .. bagCurrent .. "/" .. bagMaximum .. " durability, swapping...")
    EquipItemFromBags(bag, slot)
    return
  end
  
  -- No good FRD found, look for backup shield
  bag, slot, bagCurrent, bagMaximum = FindItemInBags(OGFRD_SV.backupShield)
  if bag then
    local backupLink = GetContainerItemLink(bag, slot)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r No replacement Force Reactive Disk found, equipping backup shield: " .. (backupLink or ("ItemID: " .. OGFRD_SV.backupShield)))
    EquipItemFromBags(bag, slot)
    return
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r |cffff0000ERROR:|r No replacement shield found!")
end

-- Event handler
frame:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    -- Initialize saved variables
    OGFRD_SV = OGFRD_SV or {}
    if OGFRD_SV.enabled == nil then
      OGFRD_SV.enabled = true
    end
    if not OGFRD_SV.backupShield then
      OGFRD_SV.backupShield = 1168
    end
    if not OGFRD_SV.swapThreshold then
      OGFRD_SV.swapThreshold = 20
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Loaded. Type /frd for help.")
    
  elseif event == "UPDATE_INVENTORY_DURABILITY" then
    CheckAndSwapShield()
  elseif event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then
    CheckAndSwapShield()
  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    CheckAndSwapShield()
  end
end)

-- OnUpdate handler for periodic checks
frame:SetScript("OnUpdate", function()
  timeSinceLastCheck = timeSinceLastCheck + arg1
  if timeSinceLastCheck >= CHECK_INTERVAL then
    timeSinceLastCheck = 0
    CheckAndSwapShield()
  end
end)

-- Slash command handler
local function SlashCommandHandler(msg)
  msg = string.lower(msg or "")
  msg = string.gsub(msg, "^%s+", "")  -- Trim leading spaces
  msg = string.gsub(msg, "%s+$", "")  -- Trim trailing spaces
  
  if msg == "" then
    -- Toggle on/off
    OGFRD_SV.enabled = not OGFRD_SV.enabled
    if OGFRD_SV.enabled then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r |cff00ff00Enabled|r")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r |cffff0000Disabled|r")
    end
    
  elseif msg == "status" then
    -- Show status
    local statusText = OGFRD_SV.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
    -- Try to find backup shield link in bags
    local backupBag, backupSlot = FindItemInBags(OGFRD_SV.backupShield)
    local backupLink = backupBag and GetContainerItemLink(backupBag, backupSlot)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Status: " .. statusText)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Swap Threshold: " .. OGFRD_SV.swapThreshold)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Backup Shield: " .. (backupLink or ("ItemID: " .. OGFRD_SV.backupShield)))
    
    -- Show equipped shield durability
    local equippedID, current, maximum = GetEquippedShieldInfo()
    if equippedID then
      local equippedLink = GetInventoryItemLink("player", SHIELD_SLOT)
      if current and maximum then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Equipped Shield: " .. (equippedLink or ("ItemID: " .. equippedID)) .. " (" .. current .. "/" .. maximum .. ")")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Equipped Shield: " .. (equippedLink or ("ItemID: " .. equippedID)) .. " (no durability)")
      end
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Equipped Shield: None")
    end
    
  elseif string.find(msg, "^swap%s+%d+$") then
    -- Set swap threshold
    local threshold = tonumber(string.match(msg, "swap%s+(%d+)"))
    if threshold > 99 then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r |cffff0000ERROR:|r Swap threshold cannot exceed 99 (prevents endless loop)")
      return
    end
    OGFRD_SV.swapThreshold = threshold
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Swap threshold set to: " .. threshold)
    
  elseif string.find(msg, "^%d+$") then
    -- Set backup shield by item ID
    local itemID = tonumber(msg)
    OGFRD_SV.backupShield = itemID
    -- Try to find the item in bags for the link
    local itemBag, itemSlot = FindItemInBags(itemID)
    local itemLink = itemBag and GetContainerItemLink(itemBag, itemSlot)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Backup shield set to: " .. (itemLink or ("ItemID: " .. itemID)))
    
  elseif string.find(msg, "|H") then
    -- Item link provided
    local _, _, itemID = string.find(msg, "item:(%d+)")
    if itemID then
      itemID = tonumber(itemID)
      OGFRD_SV.backupShield = itemID
      -- Extract the full link from the message
      local itemLink = string.match(msg, "(|c%x+|Hitem:.-|h.-|h|r)")
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Backup shield set to: " .. (itemLink or ("ItemID: " .. itemID)))
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r |cffff0000ERROR:|r Invalid item link")
    end
    
  else
    -- Help
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Commands:")
    DEFAULT_CHAT_FRAME:AddMessage("  /frd - Toggle on/off")
    DEFAULT_CHAT_FRAME:AddMessage("  /frd status - Show current status")
    DEFAULT_CHAT_FRAME:AddMessage("  /frd swap <number> - Set durability threshold (e.g., /frd swap 20)")
    DEFAULT_CHAT_FRAME:AddMessage("  /frd <itemID> - Set backup shield (e.g., /frd 1168)")
    DEFAULT_CHAT_FRAME:AddMessage("  /frd [ItemLink] - Set backup shield from item link")
  end
end

SLASH_OGFRDSAVE1 = "/frd"
SlashCmdList["OGFRDSAVE"] = SlashCommandHandler
