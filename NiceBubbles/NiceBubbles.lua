local ADDON = ...

-- Lua API
local abs, floor, min, max = math.abs, math.floor, math.min, math.max
local ipairs, pairs, select = ipairs, pairs, select
local tostring = tostring

-- WoW API
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local WorldFrame = WorldFrame

-- Bubble Data
local bubbles = {} -- local bubble registry
local numChildren, numBubbles = -1, 0 -- bubble counters
local minsize, maxsize, fontsize = 12, 16, 12 -- bubble font size
local offsetX, offsetY = 0, -100 -- bubble offset from its original position

-- Textures
local BLANK_TEXTURE = [[Interface\ChatFrame\ChatFrameBackground]]
local BUBBLE_TEXTURE = [[Interface\Tooltips\ChatBubble-Background]]
local TOOLTIP_BORDER = [[Interface\Tooltips\UI-Tooltip-Border]]


------------------------------------------------------------------------------
-- 	Utitlity Functions
------------------------------------------------------------------------------
local getPadding = function()
	return fontsize / 1.2
end

-- let the bubble size scale from 400 to 660ish (font size 22)
local getMaxWidth = function()
	return 400 + floor((fontsize - 12)/22 * 260)
end

-- Return a backdrop based on a given scale.
-- Doesn't do anything now, but might make it pixel perfect later. 
-- Not really needed though, since the border texture is made to be scaled.
local getBackdrop = function(scale) 
	return {
		bgFile = BLANK_TEXTURE,  
		edgeFile = TOOLTIP_BORDER, 
		edgeSize = 16 * scale,
		insets = {
			left = 2.5 * scale,
			right = 2.5 * scale,
			top = 2.5 * scale,
			bottom = 2.5 * scale
		}
	}
end


------------------------------------------------------------------------------
-- 	Namebubble Detection & Update Cycle
------------------------------------------------------------------------------
local Updater = CreateFrame("Frame", nil, WorldFrame) -- this needs to run even when the UI is hidden
Updater:SetFrameStrata("TOOLTIP") -- higher strata is called last

-- check whether the given frame is a bubble or not
Updater.IsBubble = function(self, bubble)
	local name = bubble.GetName and bubble:GetName()
	local region = bubble.GetRegions and bubble:GetRegions()
	if name or not region then 
		return 
	end
	local texture = region.GetTexture and region:GetTexture()
	return texture and texture == BUBBLE_TEXTURE
end

Updater.OnUpdate = function(self, elapsed)
	local children = select("#", WorldFrame:GetChildren())
	if numChildren ~= children then
		for i = 1, children do
			local frame = select(i, WorldFrame:GetChildren())
			if not(bubbles[frame]) and self:IsBubble(frame) then
				self:InitBubble(frame)
			end
		end
		numChildren = children
	end
	
	-- 	Reference:
	-- 		bubble, bubble.text = original bubble and message
	-- 		bubbles[bubble], bubbles[bubble].text = our custom bubble and message
	local scale = WorldFrame:GetHeight()/UIParent:GetHeight()
	for bubble in pairs(bubbles) do
		if bubble:IsShown() then
			-- continuing the fight against overlaps blending into each other! 
			bubbles[bubble]:SetFrameLevel(bubble:GetFrameLevel()) -- this works?
			
			local blizzTextWidth = floor(bubble.text:GetWidth())
			local blizzTextHeight = floor(bubble.text:GetHeight())
			local point, anchor, rpoint, blizzX, blizzY = bubble.text:GetPoint()
			local r, g, b = bubble.text:GetTextColor()
			bubbles[bubble].color[1] = r
			bubbles[bubble].color[2] = g
			bubbles[bubble].color[3] = b
			if blizzTextWidth and blizzTextHeight and point and rpoint and blizzX and blizzY then
				if not bubbles[bubble]:IsShown() then
					bubbles[bubble]:Show()
				end
				local msg = bubble.text:GetText()
				if msg and (bubbles[bubble].last ~= msg) then
					bubbles[bubble].text:SetText(msg or "")
					bubbles[bubble].text:SetTextColor(r, g, b)
					bubbles[bubble].last = msg
					local sWidth = bubbles[bubble].text:GetStringWidth()
					local maxWidth = getMaxWidth()
					if sWidth > maxWidth then
						bubbles[bubble].text:SetWidth(maxWidth)
					else
						bubbles[bubble].text:SetWidth(sWidth)
					end
				end
				local space = getPadding()
				local ourTextWidth = bubbles[bubble].text:GetWidth()
				local ourTextHeight = bubbles[bubble].text:GetHeight()
				local ourX = floor(offsetX + (blizzX - blizzTextWidth/2)/scale - (ourTextWidth-blizzTextWidth)/2) -- chatbubbles are rendered at BOTTOM, WorldFrame, BOTTOMLEFT, x, y
				local ourY = floor(offsetY + blizzY/scale - (ourTextHeight-blizzTextHeight)/2) -- get correct bottom coordinate
				local ourWidth = floor(ourTextWidth + space*2)
				local ourHeight = floor(ourTextHeight + space*2)
				bubbles[bubble]:Hide() -- hide while sizing and moving, to gain fps
				bubbles[bubble]:SetSize(ourWidth, ourHeight)
				local oldX, oldY = select(4, bubbles[bubble]:GetPoint())
				if not(oldX and oldY) or ((abs(oldX - ourX) > .5) or (abs(oldY - ourY) > .5)) then -- avoid updates if we can. performance. 
					bubbles[bubble]:ClearAllPoints()
					bubbles[bubble]:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", ourX, ourY)
				end
				bubbles[bubble]:SetBackdropColor(0, 0, 0, .5)
				bubbles[bubble]:SetBackdropBorderColor(0, 0, 0, .25)
				bubbles[bubble]:Show() -- show the bubble again
			end
			bubble.text:SetTextColor(r, g, b, 0)
		else
			if bubbles[bubble]:IsShown() then
				bubbles[bubble]:Hide()
			else
				bubbles[bubble].last = nil -- to avoid repeated messages not being shown
			end
		end
	end
end

Updater.HideBlizzard = function(self, bubble)
	local r, g, b = bubble.text:GetTextColor()
	bubbles[bubble].color[1] = r
	bubbles[bubble].color[2] = g
	bubbles[bubble].color[3] = b
	bubble.text:SetTextColor(r, g, b, 0)
	for region, texture in pairs(bubbles[bubble].regions) do
		region:SetTexture(nil)
	end
end

-- Not used here, leaving it for semantic reasons
Updater.ShowBlizzard = function(self, bubble)
	bubble.text:SetTextColor(bubbles[bubble].color[1], bubbles[bubble].color[2], bubbles[bubble].color[3], 1)
	for region, texture in pairs(bubbles[bubble].regions) do
		region:SetTexture(texture)
	end
end

Updater.InitBubble = function(self, bubble)
	numBubbles = numBubbles + 1

	local space = getPadding()
	bubbles[bubble] = CreateFrame("Frame", nil, self.BubbleBox)
	bubbles[bubble]:Hide()
	bubbles[bubble]:SetFrameStrata("BACKGROUND")
	bubbles[bubble]:SetFrameLevel(numBubbles%128 + 1) -- try to avoid overlapping bubbles blending into each other
	bubbles[bubble]:SetBackdrop(getBackdrop(1))
	
	bubbles[bubble].text = bubbles[bubble]:CreateFontString()
	bubbles[bubble].text:SetPoint("BOTTOMLEFT", space, space)
	bubbles[bubble].text:SetFontObject(ChatFontNormal)
	bubbles[bubble].text:SetFont(ChatFontNormal:GetFont(), fontsize, "")
	bubbles[bubble].text:SetShadowOffset(-.75, -.75)
	bubbles[bubble].text:SetShadowColor(0, 0, 0, 1)
	
	bubbles[bubble].regions = {}
	bubbles[bubble].color = { 1, 1, 1, 1 }
	
	-- gather up info about the existing blizzard bubble
	for i = 1, bubble:GetNumRegions() do
		local region = select(i, bubble:GetRegions())
		if region:GetObjectType() == "Texture" then
			bubbles[bubble].regions[region] = region:GetTexture()
		elseif region:GetObjectType() == "FontString" then
			bubble.text = region
		end
	end

	-- hide the blizzard bubble
	self:HideBlizzard(bubble)
end

Updater.UpdateBubbleSize = function(self, bubble)
	local space = getPadding()
	bubbles[bubble].text:SetFont(ChatFontNormal:GetFont(), fontsize, "")
	bubbles[bubble].text:ClearAllPoints()
	bubbles[bubble].text:SetPoint("BOTTOMLEFT", space, space)
end


local NiceBubbles = CreateFrame("Frame", nil, UIParent)
NiceBubbles:RegisterEvent("ADDON_LOADED")
NiceBubbles:RegisterEvent("PLAYER_LOGIN")
NiceBubbles:SetScript("OnEvent", function(self, event, ...) 
	local addon = ...
	if event == "ADDON_LOADED" and addon == ADDON then
		-- this will be our bubble parent
		self.BubbleBox = CreateFrame("Frame", nil, UIParent)
		self.BubbleBox:SetAllPoints()
		self.BubbleBox:Hide()
		
		-- give the updater a reference to the bubble parent
		self.Updater = Updater
		self.Updater.BubbleBox = self.BubbleBox
		
		hooksecurefunc(ChatFrame1, "SetFont", function() 
			local _, newsize = ChatFrame1:GetFont()
			newsize = min(max(newsize - 1, minsize), maxsize)
			if newsize ~= fontsize then
				fontsize = newsize
				for bubble in pairs(bubbles) do
					self.Updater:UpdateBubbleSize(bubble)
				end
			end
		end)

		self:UnregisterEvent("ADDON_LOADED")
		
	elseif event == "PLAYER_LOGIN" then

		self.Updater:SetScript("OnUpdate", self.Updater.OnUpdate)
		self.BubbleBox:Show()

		for bubble in pairs(bubbles) do
			self.Updater:HideBlizzard(bubble)
		end
		
		self:UnregisterEvent("PLAYER_LOGIN")
	end
end)
