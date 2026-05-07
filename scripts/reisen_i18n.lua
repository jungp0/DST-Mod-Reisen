-- Localization helpers for Reisen mod (Chinese UI when client language is set to Chinese).

local GLOBAL = _G

-- Returns true if the string contains at least one CJK character (UTF-8).
local function ContainsCJK(s)
	if type(s) ~= "string" then return false end
	for i = 1, #s do
		local b = s:byte(i)
		-- CJK Unified Ideographs first byte: E4-E9
		if b >= 0xE4 and b <= 0xE9 then return true end
	end
	return false
end

--- @return "s"|"t"|nil  simplified, traditional, or not Chinese
local function GetChineseVariant()
	local net = GLOBAL.TheNet

	-- Method 1: TheNet:GetLanguageCode() (Steam client language).
	-- Works when Steam client is set to Chinese.
	if net ~= nil and net.GetLanguageCode ~= nil then
		local ok, code = pcall(net.GetLanguageCode, net)
		if ok and type(code) == "string" then
			if code == "schinese" or code == "zhr" then return "s" end
			if code == "tchinese" or code == "zht" then return "t" end
		end
	end

	-- Method 2: locale global.
	-- rawget bypasses strict.lua's __index; locale may not exist.
	local loc = rawget(_G, "locale")
	if type(loc) == "string" then
		if loc == "zhr" then return "s" end
		if loc == "zht" then return "t" end
	end

	-- Method 3: TheNet:GetLanguageID() vs LANGUAGE constants.
	local LANG = GLOBAL.LANGUAGE
	if LANG ~= nil and net ~= nil and net.GetLanguageID ~= nil then
		local ok, id = pcall(net.GetLanguageID, net)
		if ok and id ~= nil then
			if id == LANG.CHINESE_S or id == LANG.CHINESE_S_RAIL then return "s" end
			if id == LANG.CHINESE_T then return "t" end
		end
	end

	-- Method 4: Inspect loaded STRINGS for CJK content.
	-- DST loads the .po language file before modmain.lua runs, so vanilla
	-- STRINGS already contain translated values. This catches the case where
	-- the in-game language is Chinese but the Steam client language is not
	-- (e.g. dedicated server where methods 1-3 are unavailable).
	local STRINGS = GLOBAL.STRINGS
	local sample = STRINGS and STRINGS.CHARACTER_NAMES and rawget(STRINGS.CHARACTER_NAMES, "wilson")
	if ContainsCJK(sample) then
		-- Distinguish simplified vs traditional using Wilson's localised name,
		-- which is already confirmed to contain CJK.
		-- Traditional: 威爾遜  (爾 U+723E → E7 88 BE)
		-- Simplified:  威尔逊  (爾 absent)
		for i = 1, #sample - 2 do
			if sample:byte(i) == 0xE7 and sample:byte(i+1) == 0x88 and sample:byte(i+2) == 0xBE then
				return "t"
			end
		end
		return "s"
	end

	return nil
end

local ZH = {
	s = {
		SCRAPBOOK_CASUAL = "回复理智有条件：仅在饥饿高于75%时生效。",
		SCRAPBOOK_UNIFORM = "移速小幅提升。穿戴时减少25%理智上限，随耐久下降加剧至50%。攻击命中扣除小额理智。理智为0时移速进一步提升并免疫击飞。与幻视丝带同时穿戴时夜晚触发负面事件。",
		SCRAPBOOK_CHARM = "噩梦燃料补充25%，恐怖燃料补充双倍。施加50%理智惩罚，但屏蔽一切其他负面理智效果。卸下时损失部分耐久。受击时有一定概率召唤恐怖尖喙并消耗燃料。被多个暗影生物包围或者饥饿耗尽时，屏蔽效果失效。内置3格储物，自动消耗补充耐久。可放置暗影心房或者附身暗影心房以消除不同程度的负面效果。",
		SCRAPBOOK_OINTMENT = "使用后治愈50点生命，降低25点理智。进入开悟状态，攻击命中后效果消失。",
		CASUAL_NAME = "居家服",
		CASUAL_RECIPE = "舒适的居家服，温暖柔软，能提供一定程度保护。",
		CASUAL_GENERIC = "吃饱了穿一定很舒服。",
		UNIFORM_NAME = "月夜制服",
		UNIFORM_RECIPE = "修身制服，提供专业保护和机动提升，但对精神和体力造成负担。",
		UNIFORM_GENERIC = "制服和我似乎是一体的，我能感觉它抗拒受伤。",
		CHARM_NAME = "幻视丝带",
		CHARM_RECIPE = "让人不安的丝带，散发对暗影的压制力，可由噩梦或恐怖燃料补充。",
		CHARM_GENERIC = "我好像看到一群暗影在黑夜中突破结界。",
		OINTMENT_NAME = "暗月药膏",
		OINTMENT_RECIPE = "与暗影同调的药膏，避免疯狂。",
		OINTMENT_GENERIC = "有股暗花和不安的气味。",
		CHAR_TITLE = "月兔",
		CHAR_NAME = "月兔",
		CHAR_DESC = "可爱或残酷，随理智而变\n *疯癫：力量随理智变化，理智低时牺牲生存强化战斗本能\n *幻梦：根据连击层数获得增益，强化后效果增强\n *强健体魄：抗寒、奔跑更快\n *胡萝卜成瘾：吃胡萝卜可以恢复理智；不能睡觉",
		CHAR_QUOTE = "「我不过是只小兔子，只有可爱这点可取。」",
		PREFAB_REISEN = "月兔",
		SPEECH_CASUAL = "休整模式，兔耳朵也要放个假。",
		SPEECH_UNIFORM = "月面制服就绪，别小看兔子。",
		SPEECH_CHARM = "你还保持理智吗？",
		SPEECH_DUALGEAR = "感觉晚上会有不好的事情发生",
		SPEECH_DUALGEAR_FULLMOON = "今晚月色真美...让我想起了...",
		SPEECH_VULNERABLE = "理智偏移了，受击会更痛。",
		SPEECH_HUNGER_MID_VULNERABLE = "有点饿了，破绽会被放大。",
		SPEECH_HUNGER_VULNERABLE = "肚子空了，被打到就完蛋了。",
		SPEECH_STARVING = "饿到极限了，意识开始沦入黑暗。",
		SPEECH_VULN_CHAIN = "好痛！想吃饭。",
		SPEECH_CHARM_SHADOW = "丝带又在呼唤影子了。",
		SPEECH_CHARM_INSANE = "他们要来了。",
		SPEECH_MOLT_PROGRESS = "身上痒痒的。",
		SPEECH_MOLT_READY = "新尾毛掉出来了。",
		SPEECH_MOLT_THERMO = "极端环境下，掉这点毛不算什么。",
		SPEECH_STAGE_1 = "别眨眼。",
		SPEECH_ZERO_SAN_WORK = "我现在不想工作！",
		SPEECH_MIND_BLOWING = "心灵风暴！",
		SPEECH_MIND_STOPPER = "心灵制止。",
		SPEECH_MOON_PORT = "月之相位！",
		SPEECH_SLOW_NEED_SOUL = "需要灵魂增强威力。",
		SPEECH_ACCUM_FULL = "心灵风暴已充能。",
		ACTION_RELEASE_HEAL = "释放心灵风暴",
		ACTION_MOON_PORT = "月之相位",
		ACTION_STATS = "状态",
		STATS_FMT = "攻击: x%.2f\n移速: x%.2f\n脆弱: %.2f\n蓄力: %d/%d",
		PETAL_ACCUM_FMT = "蓄力: %d/%d",
		SPEECH_CHARM_SHADOWHEART      = "卸下不再消耗耐久。",
		SPEECH_CHARM_SHADOWHEART_INF  = "被攻击和夜晚都不再召唤。",
		SPEECH_CHARM_FUEL_EMPTY       = "暗影燃料耗尽。",
		SPEECH_CRIT_MAX               = "剑刃出鞘！",
	},
	t = {
		SCRAPBOOK_CASUAL = "回復理智有條件：僅在飢餓高於75%時生效。",
		SCRAPBOOK_UNIFORM = "移速小幅提升。穿戴時減少25%理智上限，隨耐久下降加劇至50%。攻擊命中扣除小額理智。理智為0時移速進一步提升並免疫擊飛。與幻視絲帶同時穿戴時夜晚觸發負面事件。",
		SCRAPBOOK_CHARM = "噩夢燃料補充25%，恐怖燃料補充雙倍。施加50%理智懲罰，但屏蔽一切其他負面理智效果。卸下時損失部分耐久。受擊時有一定機率召喚恐怖尖喙並消耗燃料。被多個暗影生物包圍或者飢餓耗盡時，屏蔽效果失效。內建3格儲物，自動消耗補充耐久。可放置暗影心房或者附身暗影心房以消除不同程度的負面效果。",
		SCRAPBOOK_OINTMENT = "使用後治愈50點生命，降低25點理智。進入開悟狀態，攻擊命中後效果消失。",
		CASUAL_NAME = "居家服",
		CASUAL_RECIPE = "舒適的居家服，溫暖柔軟，能提供一定程度保護。",
		CASUAL_GENERIC = "吃飽了穿一定很舒服。",
		UNIFORM_NAME = "月夜制服",
		UNIFORM_RECIPE = "修身制服，提供專業保護和機動提升，但對精神和體力造成負擔。",
		UNIFORM_GENERIC = "制服和我似乎是一體的，我能感覺它抗拒受傷。",
		CHARM_NAME = "幻視絲帶",
		CHARM_RECIPE = "讓人不安的絲帶，散發對暗影的壓制力，可由噩夢或恐怖燃料補充。",
		CHARM_GENERIC = "我好像看到一群暗影在黑夜中突破結界。",
		OINTMENT_NAME = "暗月藥膏",
		OINTMENT_RECIPE = "與暗影同調的藥膏，避免瘋狂。",
		OINTMENT_GENERIC = "有股暗花和不安的氣味。",
		CHAR_TITLE = "月兔",
		CHAR_NAME = "月兔",
		CHAR_DESC = "可愛或殘酷，隨理智而變\n *瘋癲：力量隨理智變化，理智低時犧牲生存強化戰鬥本能\n *幻夢：根據連擊層數獲得增益，強化後效果增強\n *強健體魄：抗寒、奔跑更快\n *胡蘿蔔成癮：吃胡蘿蔔可以恢復理智；不能睡覺",
		CHAR_QUOTE = "「我不過是隻小兔子，只有可愛這點可取。」",
		PREFAB_REISEN = "月兔",
		SPEECH_CASUAL = "休整模式，兔耳朵也要放個假。",
		SPEECH_UNIFORM = "月面制服就緒，別小看兔子。",
		SPEECH_CHARM = "你還保持理智嗎？",
		SPEECH_DUALGEAR = "感覺晚上會有不好的事情發生",
		SPEECH_DUALGEAR_FULLMOON = "今晚月色真美...讓我想起了...",
		SPEECH_VULNERABLE = "理智偏移了，受擊會更痛。",
		SPEECH_HUNGER_MID_VULNERABLE = "有點餓了，破綻會被放大。",
		SPEECH_HUNGER_VULNERABLE = "肚子空了，被打到就完蛋了。",
		SPEECH_STARVING = "餓到極限了，意識開始淪入黑暗。",
		SPEECH_VULN_CHAIN = "好痛！想吃飯。",
		SPEECH_CHARM_SHADOW = "絲帶又在呼喚影子了。",
		SPEECH_CHARM_INSANE = "他們要來了。",
		SPEECH_MOLT_PROGRESS = "身上癢癢的。",
		SPEECH_MOLT_READY = "新尾毛掉出來了。",
		SPEECH_MOLT_THERMO = "極端環境下，掉這點毛不算什麼。",
		SPEECH_STAGE_1 = "別眨眼。",
		SPEECH_ZERO_SAN_WORK = "我現在不想工作！",
		SPEECH_MIND_BLOWING = "心靈風暴！",
		SPEECH_MIND_STOPPER = "心靈制止。",
		SPEECH_MOON_PORT = "月之相位！",
		SPEECH_SLOW_NEED_SOUL = "需要靈魂增強威力。",
		SPEECH_ACCUM_FULL = "心靈風暴已充能。",
		ACTION_RELEASE_HEAL = "釋放心靈風暴",
		ACTION_MOON_PORT = "月之相位",
		ACTION_STATS = "狀態",
		STATS_FMT = "攻擊: x%.2f\n移速: x%.2f\n脆弱: %.2f\n蓄力: %d/%d",
		PETAL_ACCUM_FMT = "蓄力: %d/%d",
		SPEECH_CHARM_SHADOWHEART      = "卸下不再消耗耐久。",
		SPEECH_CHARM_SHADOWHEART_INF  = "被攻擊和夜晚都不再召喚。",
		SPEECH_CHARM_FUEL_EMPTY       = "暗影燃料耗盡。",
		SPEECH_CRIT_MAX               = "劍刃出鞘！",
	},
}

local function ApplyToStrings(str, z)
	str.NAMES.REISEN_CASUAL = z.CASUAL_NAME
	str.RECIPE_DESC.REISEN_CASUAL = z.CASUAL_RECIPE
	str.CHARACTERS.GENERIC.DESCRIBE.REISEN_CASUAL = z.CASUAL_GENERIC

	str.NAMES.REISEN_UNIFORM = z.UNIFORM_NAME
	str.RECIPE_DESC.REISEN_UNIFORM = z.UNIFORM_RECIPE
	str.CHARACTERS.GENERIC.DESCRIBE.REISEN_UNIFORM = z.UNIFORM_GENERIC

	str.NAMES.REISEN_CHARM = z.CHARM_NAME
	str.RECIPE_DESC.REISEN_CHARM = z.CHARM_RECIPE
	str.CHARACTERS.GENERIC.DESCRIBE.REISEN_CHARM = z.CHARM_GENERIC

	str.NAMES.REISEN_OINTMENT = z.OINTMENT_NAME
	str.RECIPE_DESC.REISEN_OINTMENT = z.OINTMENT_RECIPE
	str.CHARACTERS.GENERIC.DESCRIBE.REISEN_OINTMENT = z.OINTMENT_GENERIC
	str.SCRAPBOOK.SPECIALINFO.REISEN_OINTMENT = z.SCRAPBOOK_OINTMENT

	str.CHARACTER_TITLES.reisen = z.CHAR_TITLE
	str.CHARACTER_NAMES.reisen = z.CHAR_NAME
	str.CHARACTER_DESCRIPTIONS.reisen = z.CHAR_DESC
	str.CHARACTER_QUOTES.reisen = z.CHAR_QUOTE
	str.NAMES.REISEN = z.PREFAB_REISEN

	str.SCRAPBOOK = str.SCRAPBOOK or {}
	str.SCRAPBOOK.SPECIALINFO = str.SCRAPBOOK.SPECIALINFO or {}
	str.SCRAPBOOK.SPECIALINFO.REISEN_CASUAL = z.SCRAPBOOK_CASUAL
	str.SCRAPBOOK.SPECIALINFO.REISEN_UNIFORM = z.SCRAPBOOK_UNIFORM
	str.SCRAPBOOK.SPECIALINFO.REISEN_CHARM = z.SCRAPBOOK_CHARM

	str.ACTIONS = str.ACTIONS or {}
	str.ACTIONS.REISEN_RELEASE_HEAL        = z.ACTION_RELEASE_HEAL
	str.ACTIONS.REISEN_MOON_PORT           = z.ACTION_MOON_PORT
	str.ACTIONS.REISEN_STATS               = z.ACTION_STATS
	str.REISEN_STATS_FMT            = z.STATS_FMT
	str.REISEN_ACCUM_FMT            = z.PETAL_ACCUM_FMT
end

local function ApplySpeechDescribe(reisen_speech, z)
	if reisen_speech == nil then
		return
	end
	if reisen_speech.DESCRIBE ~= nil then
		local d = reisen_speech.DESCRIBE
		d.REISEN_CASUAL = z.SPEECH_CASUAL
		d.REISEN_UNIFORM = z.SPEECH_UNIFORM
		d.REISEN_CHARM = z.SPEECH_CHARM
	end
	reisen_speech.ANNOUNCE_REISEN_DUALGEAR = z.SPEECH_DUALGEAR
	reisen_speech.ANNOUNCE_REISEN_DUALGEAR_FULLMOON = z.SPEECH_DUALGEAR_FULLMOON
	reisen_speech.ANNOUNCE_REISEN_VULNERABLE = z.SPEECH_VULNERABLE
	reisen_speech.ANNOUNCE_REISEN_HUNGER_MID_VULNERABLE = z.SPEECH_HUNGER_MID_VULNERABLE
	reisen_speech.ANNOUNCE_REISEN_HUNGER_VULNERABLE = z.SPEECH_HUNGER_VULNERABLE
	reisen_speech.ANNOUNCE_REISEN_STARVING = z.SPEECH_STARVING
	reisen_speech.ANNOUNCE_REISEN_VULN_CHAIN = z.SPEECH_VULN_CHAIN
	reisen_speech.ANNOUNCE_REISEN_CHARM_SHADOW = z.SPEECH_CHARM_SHADOW
	reisen_speech.ANNOUNCE_REISEN_CHARM_INSANE = z.SPEECH_CHARM_INSANE
	reisen_speech.ANNOUNCE_REISEN_MOLT_PROGRESS = z.SPEECH_MOLT_PROGRESS
	reisen_speech.ANNOUNCE_REISEN_MOLT_READY = z.SPEECH_MOLT_READY
	reisen_speech.ANNOUNCE_REISEN_MOLT_THERMO = z.SPEECH_MOLT_THERMO
	reisen_speech.ANNOUNCE_REISEN_STAGE_1 = z.SPEECH_STAGE_1
	reisen_speech.ANNOUNCE_REISEN_ZERO_SAN_WORK  = z.SPEECH_ZERO_SAN_WORK
	reisen_speech.ANNOUNCE_REISEN_MIND_BLOWING   = z.SPEECH_MIND_BLOWING
	reisen_speech.ANNOUNCE_REISEN_MIND_STOPPER   = z.SPEECH_MIND_STOPPER
	reisen_speech.ANNOUNCE_REISEN_MOON_PORT      = z.SPEECH_MOON_PORT
	reisen_speech.ANNOUNCE_REISEN_SLOW_NEED_SOUL = z.SPEECH_SLOW_NEED_SOUL
	reisen_speech.ANNOUNCE_REISEN_ACCUM_FULL          = z.SPEECH_ACCUM_FULL
	reisen_speech.ANNOUNCE_REISEN_CHARM_SHADOWHEART     = z.SPEECH_CHARM_SHADOWHEART
	reisen_speech.ANNOUNCE_REISEN_CHARM_SHADOWHEART_INF = z.SPEECH_CHARM_SHADOWHEART_INF
	reisen_speech.ANNOUNCE_REISEN_CHARM_FUEL_EMPTY      = z.SPEECH_CHARM_FUEL_EMPTY
	reisen_speech.ANNOUNCE_REISEN_CRIT_MAX              = z.SPEECH_CRIT_MAX
end

return {
	GetChineseVariant = GetChineseVariant,
	ApplyToStrings = ApplyToStrings,
	ApplySpeechDescribe = ApplySpeechDescribe,
	ZH = ZH,
}
