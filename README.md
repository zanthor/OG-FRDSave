# OG-FRDSave

**Automatic Force Reactive Disk Durability Management for Turtle WoW**

## Overview

OG-FRDSave automatically monitors your equipped Force Reactive Disk (Item ID: 18168) and swaps it out when durability gets low. Perfect for tanks who want to maximize the use of their FRD without letting it break.

## Features

- **Automatic Monitoring**: Checks equipped shield durability every 2 seconds
- **Smart Swapping**: When Force Reactive Disk durability drops below threshold:
  1. First, tries to find another Force Reactive Disk in bags with >100 durability
  2. If none found, equips your configured backup shield (no durability check)
- **Customizable Threshold**: Set when to trigger the swap (default: 20 durability)
- **Multiple Backup Options**: Configure any shield as your backup

## Commands

### Basic Commands

- **`/frd`** - Toggle addon on/off
- **`/frd status`** - Show current status including:
  - Enabled/disabled state
  - Current swap threshold
  - Configured backup shield
  - Currently equipped shield and its durability

### Configuration

- **`/frd swap <number>`** - Set durability threshold for swapping
  - Example: `/frd swap 20` (swap when durability reaches 20)
  - The value is in raw durability points (e.g., 20/120)

- **`/frd <itemID>`** - Set backup shield by item ID
  - Example: `/frd 1168` (sets Skullflame Shield as backup)
  - Default backup: 1168

- **`/frd [ItemLink]`** - Set backup shield using item link
  - Shift-click an item in your bags or inventory
  - Type `/frd ` and paste the item link

## How It Works

1. Addon continuously monitors your equipped off-hand slot (slot 17)
2. If equipped item is Force Reactive Disk (18168), checks its durability
3. When durability drops below your threshold:
   - Searches bags for another FRD with high durability
   - If found, swaps to it
   - If not found, equips your backup shield
4. Shows status messages for all swaps and errors

## Default Settings

- **Enabled**: Yes
- **Backup Shield**: 1168 (Skullflame Shield)
- **Swap Threshold**: 20 durability points

## Examples

```
/frd status
/frd swap 15
/frd 2946
/frd [Aegis of the Scarlet Commander]
```

## Notes

- The addon only activates when Force Reactive Disk is equipped
- Durability is displayed as current/maximum (e.g., 95/120)
- Works with any shield as a backup, not just Skullflame
- Settings are saved per character
