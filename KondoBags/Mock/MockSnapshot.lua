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
}

-- Which physical slots hold something; everything else is empty.
local filled = {
  [0] = { [1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 5, [6] = 6, [11] = 7, [12] = 8, [13] = 9, [14] = 10, [15] = 11, [16] = 12 },
  [1] = { [2] = 13, [5] = 14, [6] = 15 },
}
local sizes = { [0] = 16, [1] = 6 }

function Mock.Slots()
  local slots = {}
  for bagID = 0, 1 do
    for slot = 1, sizes[bagID] do
      local idx = filled[bagID][slot]
      slots[#slots + 1] = { bagID = bagID, slot = slot, item = idx and items[idx] or nil }
    end
  end
  return slots
end

function Mock.Money()
  return 8 * 100 + 62   -- 8s 62c
end