-- KondoBags Mock/MockSnapshot.lua -- fake bag contents for the M0 UI mockup. No bag API.
--
-- Produces { KondoBags_SlotRef... } in bag order: { bagID, slot, item = KondoBags_ItemView | nil }.
-- KondoBags_ItemView = { itemID, name, icon, count, quality }  (icon = file path string).
-- Mirrors the owner's screenshot: a 16-slot backpack plus a 6-slot bag, mostly empty.

local _, ns = ...
local Mock = {}
ns.Mock = Mock

local I = "Interface\\Icons\\"

local items = {
  { itemID = 4536,  name = "Shiny Red Apple",        icon = I .. "INV_Misc_Food_19",       count = 1,  quality = 1 },
  { itemID = 2589,  name = "Linen Cloth",            icon = I .. "INV_Fabric_Linen_01",    count = 5,  quality = 1 },
  { itemID = 6529,  name = "Shiny Bauble",           icon = I .. "INV_Misc_Orb_03",        count = 1,  quality = 1 },
  { itemID = 6948,  name = "Hearthstone",            icon = I .. "INV_Misc_Rune_01",       count = 1,  quality = 1 },
  { itemID = 159,   name = "Refreshing Spring Water", icon = I .. "INV_Drink_07",           count = 5,  quality = 1 },
  { itemID = 117,   name = "Tough Jerky",            icon = I .. "INV_Misc_Food_14",       count = 7,  quality = 1 },
  { itemID = 6256,  name = "Fishing Pole",           icon = I .. "INV_Fishingpole_02",     count = 1,  quality = 1 },
  { itemID = 2070,  name = "Darnassian Bleu",        icon = I .. "INV_Misc_Food_15",       count = 1,  quality = 1 },
  { itemID = 6274,  name = "Blue Linen Vest",        icon = I .. "INV_Chest_Cloth_21",     count = 1,  quality = 1 },
  { itemID = 7005,  name = "Skinning Knife",         icon = I .. "INV_Weapon_ShortBlade_01", count = 1, quality = 1 },
  { itemID = 818,   name = "Tigerseye",              icon = I .. "INV_Misc_Gem_Variety_01", count = 15, quality = 1 },
  { itemID = 6265,  name = "Soul Shard",             icon = I .. "INV_Misc_Gem_Amethyst_02", count = 1, quality = 1 },
  { itemID = 4540,  name = "Tough Hunk of Bread",     icon = I .. "INV_Misc_Food_11",       count = 4,  quality = 1 },
  { itemID = 3300,  name = "Rabbit's Foot",          icon = I .. "INV_Misc_MonsterScales_05", count = 2, quality = 0 },
  { itemID = 3304,  name = "Broken Fang",            icon = I .. "INV_Misc_MonsterFang_01", count = 3, quality = 0 },
  { itemID = 2447,  name = "Peacebloom",             icon = I .. "INV_Misc_Flower_02",     count = 8,  quality = 1 },   -- 16
  { itemID = 765,   name = "Silverleaf",             icon = I .. "INV_Misc_Herb_10",       count = 3,  quality = 1 },   -- 17
  { itemID = 2512,  name = "Rough Arrow",            icon = I .. "INV_Ammo_Arrow_01",      count = 200, quality = 1 },  -- 18
  { itemID = 2512,  name = "Rough Arrow",            icon = I .. "INV_Ammo_Arrow_01",      count = 137, quality = 1 },  -- 19
}

-- Which physical slots hold something; everything else is empty.
-- Hearthstone (items[4]) sits in the LAST slot (bag 1 slot 6 = combined slot 21): under D11 the
-- Keep section owns the top of the combined bag, so a fresh store's Keep = { slot 21 }.
local filled = {
  [0] = { [1] = 1, [2] = 2, [3] = 3, [4] = 5, [5] = 6, [6] = 7, [11] = 8, [12] = 9, [13] = 10, [14] = 11, [15] = 12, [16] = 13 },
  [1] = { [2] = 14, [5] = 15, [6] = 4 },
  [2] = { [1] = 16, [3] = 17 },             -- herb bag
  [3] = { [1] = 18, [2] = 19 },             -- quiver
}
local sizes = { [0] = 16, [1] = 6, [2] = 6, [3] = 6 }
-- KondoBags_SlotKind per bag. General bags are the flat Keep/incoming index; typed bags are a
-- separate display-only run above incoming (SPECS/00 D13.3).
local kinds = { [0] = "general", [1] = "general", [2] = "herb", [3] = "quiver" }
Mock.HEARTHSTONE_SLOT = 21   -- 0-based combined index of the hearthstone above

-- Returns every slot in bag order; general slots first so the flat index is unchanged by typed bags.
function Mock.Slots()
  local slots = {}
  for bagID = 0, 3 do
    for slot = 1, sizes[bagID] do
      local idx = filled[bagID][slot]
      slots[#slots + 1] = { bagID = bagID, slot = slot, kind = kinds[bagID], item = idx and items[idx] or nil }
    end
  end
  return slots
end

function Mock.Money()
  return 8 * 100 + 62   -- 8s 62c
end