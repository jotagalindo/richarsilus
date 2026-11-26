-- luacheck: Lua 5.1 (la versión del cliente de WoW) más las globales de WoW que usa el addon.
std = "lua51"
max_line_length = 140
exclude_files = { ".luarocks", "lua_modules" }

-- Globales que el addon define.
globals = {
  "RicharsilusDB",
  "SLASH_RICHARSILUS1",
  "SLASH_RICHARSILUS2",
  "SlashCmdList",
  "UISpecialFrames",
}

-- API y constantes de WoW: Forever 1.60.1 (verificadas en Blizzard_APIDocumentationGenerated).
read_globals = {
  "AuctionHouseFrame",
  "BACKDROP_DIALOG_32_32",
  "C_AuctionHouse",
  "C_Container",
  "C_Item",
  "C_Map",
  "C_MerchantFrame",
  "C_TradeSkillUI",
  "CreateFrame",
  "DEFAULT_CHAT_FRAME",
  "Enum",
  "GetLocale",
  "GetMerchantItemID",
  "GetMerchantNumItems",
  "GetRealmName",
  "GetTime",
  "IsShiftKeyDown",
  "ItemLocation",
  "NUM_BAG_SLOTS",
  "time",
  "UIParent",
  "UnitName",
}

files["spec/**/*.lua"] = {
  std = "+busted",
}
