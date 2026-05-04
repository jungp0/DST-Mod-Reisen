
local assets =
{

	Asset( "ANIM", "anim/reisen.zip" ),
	Asset( "ANIM", "anim/ghost_reisen_build.zip" ),
	
}

local skins =
{

	normal_skin = "reisen",
	ghost_skin = "ghost_reisen_build",
	
}

local base_prefab = "reisen"

local tags = {"REISEN", "CHARACTER"}

return CreatePrefabSkin("reisen_none",
{

	base_prefab = base_prefab, 
	skins = skins, 
	assets = assets,
	tags = tags,
	
	skip_item_gen = true,
	skip_giftable_gen = true,
	
})

--Current Mod Version: [1.3.8]
--DST Character Mod created by: Senshimi [https://steamcommunity.com/id/Senshimi/]
--Touhou Project Collection: [http://steamcommunity.com/sharedfiles/filedetails/?id=701414094]
