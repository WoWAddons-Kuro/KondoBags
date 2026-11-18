std = "lua51"
max_line_length = 140
codes = true
exclude_files = {
    "KondoBags/Libs/",
}

ignore = {
    "212/self",
    "211/_.*",
    "213/_.*",
}

read_globals = {
    -- Lua / WoW Lua extensions
    "table", "string", "math", "pairs", "ipairs", "type", "tostring", "tonumber",
    "select", "unpack", "wipe", "strsplit", "strmatch", "strtrim", "format", "pcall",
    "ceil", "floor", "max", "min",

    -- WoW API
    "CreateFrame", "UIParent", "WorldFrame", "GameTooltip", "GameTooltip_Hide", "GetTime", "C_Timer",
    "InCombatLockdown", "hooksecurefunc", "IsShiftKeyDown", "IsAltKeyDown", "IsControlKeyDown",
    "GetCursorInfo", "CursorHasItem", "ClearCursor", "GetCursorPosition", "SetCursor", "ResetCursor",
    "PlaySound", "SOUNDKIT", "StaticPopupDialogs", "StaticPopup_Show", "ACCEPT", "CANCEL", "YES", "NO",
    "C_Container", "C_Item", "C_AddOns", "C_NewItems", "C_QuestLog", "GetQuestLogTitle", "GetMoney", "InterfaceOptionsFrame_OpenToCategory", "GetAddOnMetadata", "IsAddOnLoaded", "Enum",
    "SetItemButtonTexture", "SetItemButtonCount", "SetItemButtonQuality", "SetItemButtonDesaturated", "SetItemButtonNormalTextureVertexColor",
    "NineSliceUtil", "NineSliceLayouts",
    "BackdropTemplateMixin", "Settings", "InterfaceOptions_AddCategory", "MenuUtil",
    "WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CLASSIC", "WOW_PROJECT_CAMELOT",
    "WOW_PROJECT_CATACLYSM_CLASSIC", "WOW_PROJECT_MISTS_CLASSIC",
    "NUM_BAG_SLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "NUM_BAG_FRAMES", "KEYRING_CONTAINER",
    -- stock bag replacement (UI/StockBags.lua)
    "NUM_CONTAINER_FRAMES", "ContainerFrameContainer", "ContainerFrameCombinedBags", "ToggleBackpack_Combined",
    "ContainerFrame_AllowedToOpenBags", "IsOptionFrameOpen", "CanOpenPanels", "C_CVar", "debugstack",
    "TEXTURE_ITEM_QUEST_BANG", "TEXTURE_ITEM_QUEST_BORDER", "GetInventoryItemTexture", "GetItemFamily",
    "EditModeUtil", "CONTAINER_OFFSET_X", "CONTAINER_OFFSET_Y", "C_ActionBar", "GetKeyRingSize", "GetItemInfoInstant",
    "ITEM_QUALITY_COLORS", "GameFontHighlight", "GameFontNormal", "GameFontHighlightSmall",
    "NumberFontNormal", "ChatFontNormal", "STANDARD_TEXT_FONT",
    "LibStub",
}

files["KondoBags/"] = {
    globals = {
        "KondoBagsDB", "KondoBagsCharDB", "StaticPopupDialogs",
        "SLASH_KONDOBAGS1", "SLASH_KONDOBAGS2", "SlashCmdList",
    },
}

files["spec/**"] = {
    globals = { "CreateFrame", "UIParent", "LibStub", "wipe" },
}
