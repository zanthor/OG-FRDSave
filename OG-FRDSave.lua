-- OG-FRDSave: Force Reactive Disk Durability Management
-- Automatically swaps Force Reactive Disk (18168) when durability gets low

local FORCE_REACTIVE_DISK = 18168
local SHIELD_SLOT = 17  -- Off-hand/shield slot
local ARGENT_DEFENDER = 13243  -- Argent Defender

-- Saved variables
OGFRD_SV = OGFRD_SV or {
  enabled = true,
  backupShield = 1168,  -- Default backup shield
  swapThreshold = 20,  -- Durability threshold to trigger swap
  argentDefenderMode = false,  -- Argent Defender mode
  
  -- Trinket swapping
  trinketSwapEnabled = true,  -- Enable/disable trinket swapping
  lootTrinket = 19812,  -- Rune of the Guard Captain (looting trinket)
  combatTrinket = 55363,  -- Diamond Flask (combat trinket)
  trinketSlot = 13  -- Which trinket slot to swap (13 or 14)
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
frame:RegisterEvent("LOOT_OPENED")  -- Started looting
frame:RegisterEvent("LOOT_CLOSED")  -- Stopped looting

-- Periodic check timer
local timeSinceLastCheck = 0
local CHECK_INTERVAL = 2  -- Check every 2 seconds

-- Warning message tracking
local timeSinceLastWarning = 0
local WARNING_INTERVAL = 30  -- Warn every 30 seconds

-- Trinket swapping state
local isInLootMode = false
local lootTimer = nil
local LOOT_TIMEOUT = 5  -- Seconds after last loot to swap back to combat trinket
local combatEndTimer = nil
local COMBAT_END_DELAY = 1  -- 1 second delay after leaving combat before swapping trinket

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
local function EquipItemFromBags(bag, slot, inventorySlot)
  inventorySlot = inventorySlot or SHIELD_SLOT
  PickupContainerItem(bag, slot)
  PickupInventoryItem(inventorySlot)
end

-- Get player health percentage
local function GetHealthPercentage()
  local health = UnitHealth("player")
  local maxHealth = UnitHealthMax("player")
  if maxHealth == 0 then return 0 end
  return (health / maxHealth) * 100
end

-- Get player block skill value
local function GetBlockSkill()
  -- Block skill is index 15 in GetSkillLineInfo
  -- We need to scan through skills to find "Block"
  for i = 1, GetNumSkillLines() do
    local skillName, isHeader, _, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
    if not isHeader and skillName == "Block" then
      return skillRank or 0
    end
  end
  return 0
end

-- Argent Defender mode logic
local function CheckArgentDefender()
  if not OGFRD_SV.argentDefenderMode then
    return
  end
  
  local equippedID = GetEquippedShieldInfo()
  local healthPercent = GetHealthPercentage()
  local blockSkill = GetBlockSkill()
  
  -- Check if we should equip Argent Defender (13243)
  if equippedID ~= ARGENT_DEFENDER then
    -- If health > 80% and block < 50, equip Argent Defender
    if healthPercent > 80 and blockSkill < 50 then
      local bag, slot = FindItemInBags(ARGENT_DEFENDER)
      if bag then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Argent Defender Mode: Equipping Argent Defender (Block: " .. blockSkill .. ", Health: " .. string.format("%.1f", healthPercent) .. "%)")
        EquipItemFromBags(bag, slot)
        return
      end
    end
  else
    -- We have Argent Defender equipped, check if block > 50 OR health <= 80%
    if blockSkill > 50 or healthPercent <= 80 then
      -- Find highest durability Force Reactive Disk
      local bag, slot, bagCurrent, bagMaximum = FindItemInBags(FORCE_REACTIVE_DISK)
      if bag and bagCurrent then
        -- Look for additional FRDs and find the one with highest durability
        local bestBag, bestSlot, bestDurability = bag, slot, bagCurrent
        
        for checkBag = 0, 4 do
          for checkSlot = 1, GetContainerNumSlots(checkBag) do
            local link = GetContainerItemLink(checkBag, checkSlot)
            if link then
              local _, _, foundItemID = string.find(link, "item:(%d+)")
              foundItemID = tonumber(foundItemID)
              if foundItemID == FORCE_REACTIVE_DISK then
                local current, maximum = GetBagItemDurability(checkBag, checkSlot)
                if current and current > bestDurability then
                  bestBag, bestSlot, bestDurability = checkBag, checkSlot, current
                end
              end
            end
          end
        end
        
        local reason = blockSkill > 50 and "Block: " .. blockSkill or "Health: " .. string.format("%.1f", healthPercent) .. "%"
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Argent Defender Mode: Equipping Force Reactive Disk (" .. reason .. ", Durability: " .. bestDurability .. "/" .. bagMaximum .. ")")
        EquipItemFromBags(bestBag, bestSlot)
        return
      end
    end
  end
end

-- Main durability check logic
local function CheckAndSwapShield()
  if not OGFRD_SV.enabled then
    return
  end
  
  -- Check Argent Defender mode first
  CheckArgentDefender()
  
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

--[[ Trinket Swapping System ]]

-- Equip trinket by ID
local function EquipTrinketByID(itemID, trinketSlot)
  if not itemID or not trinketSlot then return false end
  
  local bag, slot = FindItemInBags(itemID)
  if bag and slot then
    local _, _, isLocked = GetContainerItemInfo(bag, slot)
    if not isLocked and not IsInventoryItemLocked(trinketSlot) then
      PickupContainerItem(bag, slot)
      PickupInventoryItem(trinketSlot)
      return true
    end
  end
  return false
end

-- Start loot mode - equip looting trinket
local function StartLootMode()
  if not OGFRD_SV.trinketSwapEnabled then return end
  
  -- Only swap trinkets in Stratholme
  local zone = GetRealZoneText()
  if zone ~= "Stratholme" then return end
  
  if not isInLootMode then
    isInLootMode = true
    lootTimer = GetTime() + LOOT_TIMEOUT
    
    -- Equip looting trinket
    if EquipTrinketByID(OGFRD_SV.lootTrinket, OGFRD_SV.trinketSlot) then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Looting mode: Equipped looting trinket")
    end
  else
    -- Already in loot mode, just reset timer
    lootTimer = GetTime() + LOOT_TIMEOUT
  end
end

-- Stop loot mode - equip combat trinket
local function StopLootMode()
  if not isInLootMode then return end
  
  isInLootMode = false
  lootTimer = nil
  
  -- Equip combat trinket
  if EquipTrinketByID(OGFRD_SV.combatTrinket, OGFRD_SV.trinketSlot) then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Looting timeout: Equipped combat trinket")
  end
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
    if OGFRD_SV.argentDefenderMode == nil then
      OGFRD_SV.argentDefenderMode = false
    end
    if OGFRD_SV.trinketSwapEnabled == nil then
      OGFRD_SV.trinketSwapEnabled = true
    end
    if not OGFRD_SV.lootTrinket then
      OGFRD_SV.lootTrinket = 19812
    end
    if not OGFRD_SV.combatTrinket then
      OGFRD_SV.combatTrinket = 55363
    end
    if not OGFRD_SV.trinketSlot then
      OGFRD_SV.trinketSlot = 13
    end
    
    if OGAALogger and OGAALogger.AddMessage then
      OGAALogger.AddMessage("FRD", "|cffff8800[FRD-Save]|r Loaded. Type /frd for help.")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Loaded. Type /frd for help.")
    end
    
  elseif event == "UPDATE_INVENTORY_DURABILITY" then
    CheckAndSwapShield()
  elseif event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then
    CheckAndSwapShield()
  elseif event == "PLAYER_REGEN_DISABLED" then
    CheckAndSwapShield()
  elseif event == "PLAYER_REGEN_ENABLED" then
    CheckAndSwapShield()
    -- Set timer to equip looting trinket 1 second after leaving combat
    combatEndTimer = GetTime() + COMBAT_END_DELAY
  elseif event == "LOOT_OPENED" then
    -- Started looting - equip loot trinket if not in combat
    if not UnitAffectingCombat("player") then
      combatEndTimer = nil  -- Cancel delayed swap
      StartLootMode()
    end
  elseif event == "LOOT_CLOSED" then
    -- Stopped looting - reset timer
    if lootTimer then
      lootTimer = GetTime() + LOOT_TIMEOUT
    end
  end
end)

-- OnUpdate handler for periodic checks
frame:SetScript("OnUpdate", function()
  timeSinceLastCheck = timeSinceLastCheck + arg1
  if timeSinceLastCheck >= CHECK_INTERVAL then
    timeSinceLastCheck = 0
    CheckAndSwapShield()
  end
  
  -- Check combat end timer
  if combatEndTimer and GetTime() >= combatEndTimer then
    combatEndTimer = nil
    StartLootMode()
  end
  
  -- Check loot timer
  if lootTimer and GetTime() >= lootTimer then
    StopLootMode()
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
    local argentText = OGFRD_SV.argentDefenderMode and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
    local trinketText = OGFRD_SV.trinketSwapEnabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
    
    -- Try to find backup shield link in bags
    local backupBag, backupSlot = FindItemInBags(OGFRD_SV.backupShield)
    local backupLink = backupBag and GetContainerItemLink(backupBag, backupSlot)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Status: " .. statusText)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Argent Defender Mode: " .. argentText)
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
    
    -- Show Argent Defender mode status
    if OGFRD_SV.argentDefenderMode then
      local healthPercent = GetHealthPercentage()
      local blockSkill = GetBlockSkill()
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Current Health: " .. string.format("%.1f", healthPercent) .. "%")
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Current Block Skill: " .. blockSkill)
    end
    
    -- Show trinket swapping status
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Trinket Swapping: " .. trinketText)
    if OGFRD_SV.trinketSwapEnabled then
      local lootBag, lootSlot = FindItemInBags(OGFRD_SV.lootTrinket)
      local lootLink = lootBag and GetContainerItemLink(lootBag, lootSlot)
      local combatBag, combatSlot = FindItemInBags(OGFRD_SV.combatTrinket)
      local combatLink = combatBag and GetContainerItemLink(combatBag, combatSlot)
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Trinket Slot: " .. OGFRD_SV.trinketSlot)
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Loot Trinket: " .. (lootLink or ("ItemID: " .. OGFRD_SV.lootTrinket)))
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Combat Trinket: " .. (combatLink or ("ItemID: " .. OGFRD_SV.combatTrinket)))
      if isInLootMode then
        local timeLeft = lootTimer and math.ceil(lootTimer - GetTime()) or 0
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Loot Mode: |cff00ff00Active|r (timeout in " .. timeLeft .. "s)")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Loot Mode: |cffccccccInactive|r")
      end
    end
    
  elseif msg == "argent" then
    -- Toggle Argent Defender mode
    OGFRD_SV.argentDefenderMode = not OGFRD_SV.argentDefenderMode
    if OGFRD_SV.argentDefenderMode then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Argent Defender Mode: |cff00ff00Enabled|r")
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Will swap to Argent Defender when Health > 80% and Block < 50")
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Will swap to Force Reactive Disk when Block > 50 or Health <= 80%")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Argent Defender Mode: |cffff0000Disabled|r")
    end
    
  elseif msg == "trinket" then
    -- Toggle trinket swapping
    OGFRD_SV.trinketSwapEnabled = not OGFRD_SV.trinketSwapEnabled
    if OGFRD_SV.trinketSwapEnabled then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Trinket Swapping: |cff00ff00Enabled|r")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Trinket Swapping: |cffff0000Disabled|r")
      -- Stop loot mode if active
      if isInLootMode then
        StopLootMode()
      end
    end
    
  elseif string.find(msg, "^trinket%s+slot%s+%d+$") then
    -- Set trinket slot (13 or 14)
    local slot = tonumber(string.match(msg, "slot%s+(%d+)"))
    if slot ~= 13 and slot ~= 14 then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r |cffff0000ERROR:|r Trinket slot must be 13 or 14")
      return
    end
    OGFRD_SV.trinketSlot = slot
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Trinket slot set to: " .. slot)
    
  elseif string.find(msg, "^trinket%s+loot%s+%d+$") then
    -- Set loot trinket by item ID
    local itemID = tonumber(string.match(msg, "loot%s+(%d+)"))
    OGFRD_SV.lootTrinket = itemID
    local itemBag, itemSlot = FindItemInBags(itemID)
    local itemLink = itemBag and GetContainerItemLink(itemBag, itemSlot)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Loot trinket set to: " .. (itemLink or ("ItemID: " .. itemID)))
    
  elseif string.find(msg, "^trinket%s+combat%s+%d+$") then
    -- Set combat trinket by item ID
    local itemID = tonumber(string.match(msg, "combat%s+(%d+)"))
    OGFRD_SV.combatTrinket = itemID
    local itemBag, itemSlot = FindItemInBags(itemID)
    local itemLink = itemBag and GetContainerItemLink(itemBag, itemSlot)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[FRD-Save]|r Combat trinket set to: " .. (itemLink or ("ItemID: " .. itemID)))
    
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
    DEFAULT_CHAT_FRAME:AddMessage("  /frd argent - Toggle Argent Defender mode")
    DEFAULT_CHAT_FRAME:AddMessage("  /frd swap <number> - Set durability threshold (e.g., /frd swap 20)")
    DEFAULT_CHAT_FRAME:AddMessage("  /frd <itemID> - Set backup shield (e.g., /frd 1168)")
    DEFAULT_CHAT_FRAME:AddMessage("  /frd [ItemLink] - Set backup shield from item link")
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800Trinket Swapping:|r")
    DEFAULT_CHAT_FRAME:AddMessage("  /frd trinket - Toggle trinket swapping")
    DEFAULT_CHAT_FRAME:AddMessage("  /frd trinket slot <13|14> - Set trinket slot to swap")
    DEFAULT_CHAT_FRAME:AddMessage("  /frd trinket loot <itemID> - Set looting trinket")
    DEFAULT_CHAT_FRAME:AddMessage("  /frd trinket combat <itemID> - Set combat trinket")
  end
end

SLASH_OGFRDSAVE1 = "/frd"
SlashCmdList["OGFRDSAVE"] = SlashCommandHandler
