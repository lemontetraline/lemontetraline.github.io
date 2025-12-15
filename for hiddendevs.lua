-- dates back to 2023/2024, using legacy chat system
-- Services --
local ProximityPromptService = game:GetService("ProximityPromptService") -- For prompts
local ReplciatedStorage = game:GetService("ReplicatedStorage") -- Shared storage for modules/remotes (spelled here as Replciated 🔥🔥)
local UserInputService = game:GetService("UserInputService") -- Detects mouse/touch input
local ChatService = game:GetService("TextChatService") -- Manages chat
local TweenService = game:GetService("TweenService") -- for tweens
local RunService = game:GetService("RunService") -- Used for the game loop
local StarterGui = game:GetService("StarterGui") -- Used to manipulate core GUI elements (send chat messages, outdated rn)
local Players = game:GetService("Players") -- to get the player
---

--- Constants ---
local Camera = workspace.Camera -- Reference to the local player's camera

-- References to folders inside ReplicatedStorage
local Assets = ReplciatedStorage.Assets -- visual assets/particles
local Remotes = ReplciatedStorage.Remotes -- RemoteFunctions/Events for server communication

task.wait(0.25) -- Slight delay to ensure game has loaded enough before initializing UI

-- UI Variable References
local UI = script.Parent.UI -- The main ScreenGui
local UIScale = UI.UIScale -- The UIScale object used to resize the interface

local BoardUI = script.Parent:WaitForChild("BoardUI") -- The upgrade board surface GUI or UI
local PrestigeBoard = script.Parent:WaitForChild('PrestigeUI') -- The prestige menu
local CinematicUI = script.Parent:WaitForChild("CinematicUI") -- The UI overlay used during cutscenes

local UnderPrestige = PrestigeBoard.UnderPrestige -- Reference to the Underprestige frame

local Popups = UI.Popups -- Container for popup messages

-- Statistics labels
local ThingsAmount = UI.Things -- Label for "Things" currency
local FieldThings = UI.FieldThings -- UI for things on the field
local Information = UI.Info -- Info panel

-- Player References
local Player = Players.LocalPlayer -- The client playing the game
local Character = Player.Character or Player.CharacterAdded:Wait() -- The player's 3D character

-- Module Scripts (External logic)
local CameraShake = require(ReplciatedStorage.CameraShaker) -- Module for camera shake effects
local Upgrades  = require(ReplciatedStorage.Upgrades) -- Configuration data for upgrades
local Boosts = require(ReplciatedStorage.Boosts) -- Configuration data for boosts
local Utils = require(ReplciatedStorage.Utils) -- Helper functions

--- Variables ---
local Scale
-- Check if the device is mobile (Touch enabled but no Mouse)
if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
	Scale = 0.7 -- Make UI smaller for mobile
else
	Scale = 1 -- Standard size for PC
end

-- Request initial player data from the server immediately
local PlayerData = Remotes.RequestData:InvokeServer()

-- Apply the scale calculated above
UIScale.Scale = Scale

-- Map Initialization Logic
if workspace:FindFirstChild("TestMap") then -- Checks if the placeholder map exists
	local Map = tostring(PlayerData.Prestige) -- Gets current map name based on Prestige level

	ReplciatedStorage.Maps[Map]:Clone().Parent = workspace -- Clones the correct map from storage
	workspace[Map]:PivotTo(workspace.TestMap:GetPivot()) -- Moves new map to the TestMap's location
	workspace.TestMap:Destroy() -- Removes the placeholder

	-- Add a new music zone if you have reached prestige 2 to account for the shrine(see below in cutscene logic)
	if PlayerData.Prestige == 2 then
		local Spaghetti = Assets.Spaghetti:Clone()
		Spaghetti.Parent = workspace.MusicZones
	end
end

--- Functions ---
local UserInputService = game:GetService("UserInputService") -- (Redefined, though already defined at top)

-- Updates the "Friend Boost" UI label
function FriendBoostUpdate()
	-- Asks server for current friend count and multiplier
	local Players, Multiplier = Remotes.FriendBoost:InvokeServer()
	-- Updates text to show multiplier (e.g., "x1.2 for 2 friends")
	UI.FriendBoost.Text = ("Friend Boost: x%s for %s friends"):format(Multiplier, Players)
end

-- Plays visual and audio effects when leveling up
function LevelUpEffect()
	script.level_up:Play() -- Plays sound

	PlayerData = Remotes.RequestData:InvokeServer() -- Refreshes data

	-- Loops through particle effects in Assets and clones them to the player
	for _, Effect in pairs(Assets.LevelUp:GetChildren()) do
		local NewEffect = Effect:Clone()
		NewEffect.Parent = Character.PrimaryPart -- Attaches to HumanoidRootPart
		NewEffect.Enabled = true
	end

	-- Cleanup sequence after 1.5 seconds
	task.delay(1.5, function()
		for _, Effect in pairs(Character.PrimaryPart:GetChildren()) do
			if not Effect:IsA("ParticleEmitter") then continue end -- Only targets particles
			Effect.Enabled = false -- Stops emitting

			-- Fully destroy the object after another second (to let existing particles fade)
			task.delay(1, function()
				Effect:Destroy()
			end)
		end
	end)
end

-- Updates all main UI text/bars based on current PlayerData
function UpdateMenus()
	-- Updates the main currency text
	ThingsAmount.Label.Text = "things: " .. Utils:AbbreviateNumber(PlayerData.things)

	-- Logic for the main Prestige Button
	if PlayerData.things >= PlayerData.PrestigeCost then
		-- Player can afford prestige: Make button Green
		PrestigeBoard.MakePrestige.BackgroundColor3 = Color3.fromRGB(58, 156, 72)
		PrestigeBoard.MakePrestige.Text = "Upgrade"
	else
		-- Player cannot afford: Make button Grey and show cost
		PrestigeBoard.MakePrestige.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
		PrestigeBoard.MakePrestige.Text = ("You need %s more things to Prestige"):format(Utils:AbbreviateNumber(PlayerData.PrestigeCost - PlayerData.things))
	end

	-- Logic for UnderPrestige (a sub-tier of prestige)
	if PlayerData.Prestige >= 1 then
		if PlayerData.Level >= 10 + PlayerData.UnderPrestige then
			-- Available: Make Blue
			UnderPrestige.MakePrestige.BackgroundColor3 = Color3.fromRGB(27, 111, 236)
			UnderPrestige.MakePrestige.Text = "Upgrade"
		else 
			-- Locked by level: Make Grey
			UnderPrestige.MakePrestige.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
			UnderPrestige.MakePrestige.Text = ("Unlocks at level " .. 10 + PlayerData.UnderPrestige)
		end
	else
		-- Completely locked: Need Prestige 1 first
		UnderPrestige.MakePrestige.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
		UnderPrestige.MakePrestige.Text = "Prestige once to unlock"
	end 

	-- Update info labels
	UnderPrestige.PrestigeAmount.Text = "Underprestige "..PlayerData.UnderPrestige
	PrestigeBoard.PrestigeAmount.Text = "Prestige Milestone " .. PlayerData.Prestige 

	-- Update XP Text
	PrestigeBoard.Level.Text = "Level " .. PlayerData.Level
	PrestigeBoard.XPBar.XP.Text = ("%s / %s XP"):format(PlayerData.XP, PlayerData.LevelCost)

	-- Calculate XP Bar fill ratio (clamped between 0 and 1)
	local BarSize = UDim2.new(math.clamp(
		PlayerData.XP / PlayerData.LevelCost, 
		0, 
		1
		), 0, 1, 0)

	-- Smoothly tween the XP bar to the new size
	TweenService:Create(PrestigeBoard.XPBar.Bar, TweenInfo.new(0.15), {Size = BarSize}):Play()
end

-- Toggles visibility of "Things" in the workspace (a cutscene utility)
function ToggleCollection(Value)
	for _, Thing in pairs(workspace.Things:GetChildren()) do
		Thing.Transparency = Value and 0 or 1 -- Visible if true, invisible if false
		Thing.Decal.Transparency = Value and 0.25 or 1 -- Handle decal transparency
	end

	Character.CollectionZone.Transparency = Value and 0.5 or 1 -- Toggle player's collection radius visual
end

-- Updates the text and visual state of a specific Upgrade Button
function UpdateUpgrade(Name, Upgrade, UpgradeMenu)
	-- Asks server for the cost and stats of the next level
	local Cost, CurrentLevel, Percentage = Remotes.RequestNextUpgrade:InvokeServer(Name)

	local IncreaseLabel

	-- Formats the description text depending on if it's a Percentage or Multiplier upgrade
	if Upgrade.Percentage then
		if CurrentLevel%20 == 0 then -- Every 20 levels, logic is halved
			Percentage = Percentage/2
		end
		--Format the label with rich text
		IncreaseLabel = [[Increase Percentage:<br /><font color="rgb(13, 175, 1)">]] .. Percentage .. [[%</font> per upgrade]]
	else
		IncreaseLabel = [[Increase Mutliplier:<br /><font color="rgb(13, 175, 1)">]] .. Upgrade.Multiplier .. [[x</font> per upgrade]]
	end

	-- Sets the text labels
	UpgradeMenu.Value.Text = IncreaseLabel
	UpgradeMenu.Cost.Text = "Cost: " .. Utils:AbbreviateNumber(Cost)

	-- Sets text for upgrades that have this double bonus mechanic
	if Upgrade.Percentage then
		UpgradeMenu.Double.Text = [[Percentage is <font color="rgb(13, 175, 1)">doubled</font> every <font color="rgb(166, 175, 3)">20th</font> upgrade]]
	else
		UpgradeMenu.Double.Text = ""
	end

	-- Handling Max Level logic
	if Upgrade.MaxUpgrade then
		if PlayerData.Upgrades[Name][1] >= Upgrade.MaxUpgrade then
			-- Maxed out: Grey out button
			UpgradeMenu.BuyButton.BackgroundColor3 = Color3.fromRGB(140, 140, 140)
			UpgradeMenu.BuyButton.Text = "MAX"

			UpgradeMenu.BuyMaxButton.BackgroundColor3 = Color3.fromRGB(140, 140, 140)
			UpgradeMenu.BuyMaxButton.Text = "MAX"
		else
			-- Available: Green button
			UpgradeMenu.BuyButton.BackgroundColor3 = Color3.fromRGB(39, 190, 92)
			UpgradeMenu.BuyButton.Text = "Buy"

			UpgradeMenu.BuyMaxButton.BackgroundColor3 = Color3.fromRGB(39, 190, 92)
			UpgradeMenu.BuyMaxButton.Text = "Buy max"
		end

		UpgradeMenu.Level.Text = ("Level %s / %s"):format(CurrentLevel, Upgrade.MaxUpgrade)
	else
		-- Infinite upgrades
		UpgradeMenu.Level.Text = ("Level %s"):format(Utils:AbbreviateNumber(CurrentLevel))
	end
end

-- Toggles visibility of a specific character (helper for the function below)
function TogglePlayer(Character, Value)
	for _, Object in pairs(Character:GetDescendants()) do
		-- Hides/Shows parts and decals, excluding the RootPart (which is always invisible)
		if (Object:IsA("BasePart") or Object:IsA("Decal")) and Object.Name ~= "HumanoidRootPart" then
			Object.Transparency = Value and 0 or 1
		end
	end
end

-- Loops through all other players to hide/show them (I use it for cutscenes)
function TogglePlayers(Value)
	for _, OtherPlayer in pairs(Players:GetPlayers()) do
		if Player.UserId ~= OtherPlayer.UserId then
			local OtherCharacter = OtherPlayer.Character

			if OtherCharacter then
				TogglePlayer(OtherCharacter, Value)
			end
		end
	end
end

--- Updates (Initialization) ---
-- Tell server to start generating resources
Remotes.ToggleGeneration:FireServer(true)

-- Initial UI refresh
UpdateMenus()
FriendBoostUpdate()

-- Loop through the Upgrades module to generate the UI buttons dynamically
for Name, Upgrade in pairs(Upgrades) do
	local UpgradeMenu = script.Upgrade:Clone() -- Clone template button

	UpgradeMenu.Name = Name
	UpgradeMenu.Parent = BoardUI.Board -- Parent to the scrolling frame
	UpgradeMenu.UpgradeName.Text = Upgrade.Name
	UpgradeMenu.LayoutOrder = Upgrade.LayoutOrder -- Set sorting order

	UpdateUpgrade(Name, Upgrade, UpgradeMenu) -- Set initial text/cost

	-- Connect "Buy 1" button click
	UpgradeMenu.BuyButton.InputBegan:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			local Result = Remotes.MakeUpgrade:InvokeServer(Name) -- Attempt purchase on server
			UpdateUpgrade(Name, Upgrade, UpgradeMenu) -- Refresh visual

			if not Result then
				-- Purchase failed logic (Maxed or not enough money)
				if UpgradeMenu.BuyButton.Text == "MAX" then
					Utils:CreatePopup(Popups, "You've maxed out the upgrade")
				else
					Utils:CreatePopup(Popups, "You don't have enough things")
				end

				script.fail:Play() -- Error sound
			else
				script.click:Play() -- Success sound
			end
		end
	end)

	-- Connect "Buy Max" button click
	UpgradeMenu.BuyMaxButton.InputBegan:Connect(function(Input)
		-- More of this weird inputbegan code (i think i used have a bug on mobile)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			local Result = Remotes.MakeMaxUpgrade:InvokeServer(Name) -- Attempt max purchase from the server
			UpdateUpgrade(Name, Upgrade, UpgradeMenu)

			if not Result then
				-- Purchase failed logic
				-- SHow the popup of fail and also play the failed sound effect
				if UpgradeMenu.BuyButton.Text == "MAX" then
					Utils:CreatePopup(Popups, "You've maxed out the upgrade")
				else
					Utils:CreatePopup(Popups, "You don't have enough things")
				end

				script.fail:Play()
			else
				-- Else just play a regular click
				script.click:Play()
			end
		end
	end)
end

--- Events ---
local Debounce = false -- Used to prevent button spamming
local CurrentlyHovered -- Stores which boost icon is currently hovered

-- Listens for server announcements
Remotes.Send.OnClientEvent:Connect(function(Message, Show)
	if not Show then UI.Announcement.Visible = false return end -- Hide if 'Show' is false

	UI.Announcement.Visible = true
	UI.Announcement.Text = Message -- Set announcement text
end)

-- Update friend boost when people leave
Players.PlayerRemoving:Connect(FriendBoostUpdate)
-- Play level up effect when server fires it
Remotes.LevelUpEffect.OnClientEvent:Connect(LevelUpEffect)

-- Update friend boost when people join, also check if they are VIP
Players.PlayerAdded:Connect(function(NewPlayer)
	FriendBoostUpdate()

	-- If the new player is VIP, make a yellow system chat message
	-- Uses a legacy chat system because the script is old
	if Remotes.RequestData:InvokeServer(NewPlayer).VIP then
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = ("[System] A VIP-user %s has joined the server."):format(NewPlayer.DisplayName);
			Color = Color3.fromRGB(255, 201, 66);
			Font = Enum.Font.GothamBold;
			TextSize = 20
		})
	end
end)

-- Main data sync listener. Updates local data whenever server changes it.
Remotes.DataUpdated.OnClientEvent:Connect(function(NewData)
	PlayerData = NewData

	UpdateMenus() -- Refresh UI

	-- If player has a Robux boost, show it
	if PlayerData.RobuxBoostMultiplier then
		UI.RobuxBoost.Text = ("Robux Boost: x%s"):format(tostring(PlayerData.RobuxBoostMultiplier ))
	end

	-- Update statistics module (e.g., total playtime, etc.)
	require(Player.PlayerScripts:WaitForChild("Init").Statistics):Update(UI.Statistics)
end)

-- Handle Proximity Prompts (Interactive objects in world)
ProximityPromptService.PromptTriggered:Connect(function(Prompt, Player)
	if Prompt.Name == "PastaPrompt" then
		script.click:Play()

		-- Show the "Lore" UI
		Information.Visible = true
		Information.Position = UDim2.new(0.5, 0, 0.5, 50) -- Start lower for tween
		Information:TweenPosition(UDim2.new(0.5, 0, 0.5, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Sine, 0.15) -- Pop up

		Information.Content.Text = "'Thee may merge with the Holy Macaroni and posses an almighty power that may multiply thee's \"Thing Value\" statistic every solar day..."
		Information.Label.Text = "Ancient Scroll"
	elseif Prompt.Name == "SpaghettiPrompt" then
		-- Attempt to activate a bonus via server
		-- The results of the action are sent to creating a popur with either blue for success or default(red) for failure
		local Result, Message = Remotes.ActivateSpaghetti:InvokeServer()
		Utils:CreatePopup(Popups, Message, Result and Color3.fromRGB(62, 130, 255) or nil)
	end
end)

-- Close button for the Information UI
-- Im not sure about the purpose of Input Began here, some weird kind of legacy system
Information.Close.InputBegan:Connect(function(Input)
	if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
		Information.Visible = false
	end
end)

-- Handle incoming chat to add VIP tags
ChatService.OnIncomingMessage = function(Message)
	local Properties = Instance.new("TextChatMessageProperties")
	if not Message.TextSource then return Properties end

	local Speaker = Players:GetPlayerByUserId(Message.TextSource.UserId)

	-- If speaker has a "Crown" inside their character, prefix their chat with [VIP]
	-- Checking the model is the easiet way
	if Speaker.Character and Speaker.Character:FindFirstChild("Crown") then
		Properties.PrefixText = "<font color='#fcb103'>[VIP]</font> " .. Message.PrefixText
	end

	return Properties
end

-- Render Loop (Runs every frame)
RunService.Heartbeat:Connect(function()
	-- Get amount of things on field from server (Note: Invoking server every frame is usually bad practice for performance)
	-- ts is crazy although the game doesn't really lag
	-- Rather have the server fire it to me instead
	local FieldAmount = #Remotes.RequestThings:InvokeServer()

	-- Move the Tooltip UI to follow the mouse cursor
	-- also adjusting for ui scale
	local MouseLocation = UserInputService:GetMouseLocation()
	UI.Tooltip.Position = UDim2.new(0, MouseLocation.X / Scale, 0, MouseLocation.Y / Scale)

	-- Calculate field capacity bar size
	-- dividinng the cuurent amount by the total amoint
	local BarSize = UDim2.new(math.clamp(
		FieldAmount / PlayerData.Upgrades.ThingsCap[2], 
		0, 
		1
		), 0, 1, 0)

	-- Update Field UI text and tween bar
	-- [2] is the value, its done a way you shouldnt really do
	FieldThings.Label.Text = Utils:AbbreviateNumber(FieldAmount) .. " / " .. math.ceil(PlayerData.Upgrades.ThingsCap[2])
	TweenService:Create(FieldThings.Bar, TweenInfo.new(0.1), {Size = BarSize}):Play()

	-- Tooltip Logic: If hovering over a Boost icon
	-- Works this way for a smooth tooltip
	if CurrentlyHovered then
		UI.Tooltip.Visible = true

		-- Set Tooltip Title based on boost data in player save
		-- If theres no stack we show it bare, if there is we add it in parentheses
		if PlayerData.Boosts[CurrentlyHovered].Stack == 1 then
			UI.Tooltip.Label.Text = Boosts[CurrentlyHovered].Name
		else
			UI.Tooltip.Label.Text = Boosts[CurrentlyHovered].Name .. " (" .. PlayerData.Boosts[CurrentlyHovered].Stack .. "x)"
		end

		-- Set Tooltip Description (calculating total boost based on stacks)
		UI.Tooltip.Description.Text = ""
		-- Loop for each and every stat in boost
		for Name, Value in pairs(Boosts[CurrentlyHovered].Boosts) do
			-- If the stack is over or 5, we do one kind of formating (i dont remember exactly, but likely due to size limittations of a tooltip frame)
			if PlayerData.Boosts[CurrentlyHovered].Stack >= 5 then
				UI.Tooltip.Description.Text = UI.Tooltip.Description.Text .. ("%s x%s \n"):format(Name, tostring((math.floor(Value * PlayerData.Boosts[CurrentlyHovered].Stack * 10) / 10)+1):gsub("0", "1"))
			else
				-- And a different one if less
				UI.Tooltip.Description.Text = UI.Tooltip.Description.Text .. ("%s x%s \n"):format(Name, tostring(math.floor(Value * PlayerData.Boosts[CurrentlyHovered].Stack * 10) / 10):gsub("0", "1"))
			end
		end 

		-- Resize tooltip dynamically based on text length
		UI.Tooltip.Description.Size = UDim2.new(1, 0, 0, 
			50 + (#UI.Tooltip.Description.Text * 0.3)
		)

		UI.Tooltip.Size = UDim2.new(0, 250, 0, 
			90 + (#UI.Tooltip.Description.Text * 0.3)
		)

		-- Update countdown timer
		UI.Tooltip.Time.Text = Utils:ConvertSeconds(PlayerData.Boosts[CurrentlyHovered].End - os.time())
	else
		UI.Tooltip.Visible = false
	end

	-- Boost Icon Management
	for Name, Boost in PlayerData.Boosts do
		if not Boost.End then CurrentlyHovered = nil continue end -- Skip if invalid or expired boost

		-- If boost expired
		if Boost.End - os.time() <= 0 then
			if UI.Boosts:FindFirstChild(Name) then
				UI.Boosts:FindFirstChild(Name):Destroy() -- Remove icon
			end

			CurrentlyHovered = nil
			continue 
		end

		-- If boost is active but has no icon, create one
		if not UI.Boosts:FindFirstChild(Name) then
			local NewBoost = script.Boost:Clone()
			NewBoost.Name = Name
			NewBoost.Parent = UI.Boosts
			NewBoost.Image = Boosts[Name].Icon

			-- Handle Hover events for tooltip
			NewBoost.MouseEnter:Connect(function()
				CurrentlyHovered = Name
			end)
			
			-- and for mouse leave too
			NewBoost.MouseLeave:Connect(function()
				CurrentlyHovered = nil
			end)
		end
	end
end)

-- UnderPrestige Button Click Event
UnderPrestige.MakePrestige.InputBegan:Connect(function(Input)
	if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
		if Debounce then return end -- Prevent double clicks (global ui debonce)
		Debounce = true

		-- Attempt UnderPrestige on server
		-- Show error if not enouigh cash
		local Result = Remotes.MakeUnderPrestige:InvokeServer()
		if not Result then script.fail:Play() Utils:CreatePopup(Popups, "You are too weak to Underprestige") Debounce = false return end
	
		-- play click sound (bad way)
		script.click:Play()

		-- Play visual effects on character
		for _, Effect in pairs(Assets.Effects:GetChildren()) do
			local NewEffect = Effect:Clone()

			NewEffect.Parent = Character.PrimaryPart
			NewEffect.Enabled = true
		end

		-- Refresh Upgrade menus
		for Name, Upgrade in pairs(Upgrades) do
			local UpgradeMenu = BoardUI.Board[Name]

			UpdateUpgrade(Name, Upgrade, UpgradeMenu)
		end

		-- Play sound and cleanup effects
		script.Underprestige:Play()
		task.delay(1.5, function()
			for _, Effect in pairs(Character.PrimaryPart:GetChildren()) do
				if not Effect:IsA("ParticleEmitter") then continue end
				Effect.Enabled = false

				task.delay(1, function()
					Effect:Destroy()
					Debounce = false -- Reset debounce
				end)
			end
		end)
	end
end)

-- Main Prestige Button Click Event (This contains the Cutscene)
PrestigeBoard.MakePrestige.InputBegan:Connect(function(Input)
	if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
		if Debounce then return end --check for global ui debounce
		Debounce = true
	
		-- Refresh players save data for proper money check
		local PlayerData = Remotes.RequestData:InvokeServer()

		-- Check if max prestige is reached
		if PlayerData.Prestige >= 2 then
			Debounce = false 
			Utils:CreatePopup(Popups, "You have reached max Prestige Milestone")
			script.fail:Play()

			return 
		end

		-- Attempt Prestige on server
		-- Show an error popup if there's not enough money
		-- Use debounce to prevent spamming
		local Result, PlayerData = Remotes.MakePrestige:InvokeServer()
		if not Result then script.fail:Play() Utils:CreatePopup(Popups, "You don't have enough things") Debounce = false return end

		PlayerData = Remotes.RequestData:InvokeServer() -- Refresh data

		script.click:Play()

		-- Refresh upgrades using the function above
		for Name, Upgrade in pairs(Upgrades) do
			local UpgradeMenu = BoardUI.Board[Name]

			UpdateUpgrade(Name, Upgrade, UpgradeMenu)
		end

		local PreviousMap = tostring(PlayerData.Prestige - 1)
		local NewMap = tostring(PlayerData.Prestige)

		--- Cutscene Logic Starts Here ---
		-- Pause ambient music
		for _, Sound in pairs(workspace.Music:GetChildren()) do
			Sound:Pause()
		end

		-- Fade to black setup
		CinematicUI.Dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		CinematicUI.Dim.BackgroundTransparency = 0

		-- Disable Roblox default UI
		game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		Camera.CameraType = Enum.CameraType.Scriptable -- Take control of camera

		CinematicUI.Enabled = true
		BoardUI.Enabled = false -- Hide game UI

		-- Hide gameplay elements
		ToggleCollection(false)
		Utils:ToggleControls(false) -- Freeze player
		Remotes.ToggleGeneration:FireServer(false) -- Stop resource generation
		TogglePlayers(false) -- Hide other players

		-- Move camera to Cutscene start position
		Camera.CFrame = workspace.Cutscene.CameraPart.CFrame

		-- Load Animations
		local IdleMove = Character.Humanoid:LoadAnimation(script.Idle)
		local PrestigeAnimation = Character.Humanoid.Animator:LoadAnimation(script.Prestige)

		-- Animation settings
		IdleMove.Looped = false
		PrestigeAnimation.Looped = false
		PrestigeAnimation.Priority = Enum.AnimationPriority.Action
		IdleMove.Priority = Enum.AnimationPriority.Action

		-- Move player to cutscene start spot
		Character:PivotTo(workspace.Cutscene.Start.CFrame)

		task.wait(0.25)

		-- Fade in from black
		TweenService:Create(CinematicUI.Dim, TweenInfo.new(0.25), {Transparency = 1}):Play()

		task.wait(0.25)

		-- Play Idle animation and slight camera zoom
		IdleMove:Play()
		TweenService:Create(Camera, TweenInfo.new(IdleMove.Length), {CFrame = Camera.CFrame + Vector3.new(0, 0 ,-8)}):Play()

		IdleMove.Ended:Wait() -- Wait for idle to finish
		IdleMove:Stop()
		PrestigeAnimation:Play() -- Play the prestige animation

		script.Walk:Play() -- Footsteps sound

		-- Tween Character moving to the End position
		TweenService:Create(Character.PrimaryPart, TweenInfo.new(1.5, Enum.EasingStyle.Linear), {
			CFrame = CFrame.new(
				workspace.Cutscene.End.Position.X, 
				Character.PrimaryPart.Position.Y,
				workspace.Cutscene.End.Position.Z
			) * workspace.Cutscene.End.CFrame.Rotation
		}):Play()

		-- Update Camera Angle
		Camera.CFrame = CFrame.new(
			workspace.Cutscene.CameraPart.Position.X + 8, 
			Camera.CFrame.Y,
			workspace.Cutscene.CameraPart.Position.Z
		) * CFrame.Angles(0, math.rad(-90), 0)

		-- Move Camera alongside character
		TweenService:Create(Camera, TweenInfo.new(1.5, Enum.EasingStyle.Linear), {
			CFrame = CFrame.new(
				workspace.Cutscene.CameraPart.Position.X + 8, 
				Camera.CFrame.Y,
				workspace.Cutscene.End.Position.Z
			) * CFrame.Angles(0, math.rad(-90), 0)
		}):Play()

		task.wait(1.5)

		script.Walk:Stop()
		script.Jump:Play() -- Jump sound

		task.wait(0.2)

		-- Switch to second camera angle
		Camera.CFrame = workspace.Cutscene.CameraPart2.CFrame

		task.wait(0.3)


		--- Functional Part (Camera and transition to new world) ---
		CinematicUI.Dim.BackgroundColor3 = Color3.fromRGB(255, 255, 255) -- Set fade color to White

		-- Initialize Camera Shake
		local CameraShaker = CameraShake.new(Enum.RenderPriority.Camera.Value, function(ShakeCFrame)
			Camera.CFrame *= ShakeCFrame
		end)

		CameraShaker:Start()

		-- Intense lighting effects (Bloom and Light)
		TweenService:Create(game.Lighting.Bloom, TweenInfo.new(0.6), {Size = 59}):Play()
		TweenService:Create(workspace.Cutscene.BrightLight.PointLight, TweenInfo.new(0.6), {Range = 55}):Play()
		-- Fade to White
		TweenService:Create(CinematicUI.Dim, TweenInfo.new(2.5), {BackgroundTransparency = 0}):Play()

		script.stun3:Play() -- Sound effect

		task.wait(2)

		task.wait(0.8)
		-- Intense Earthquake shake
		CameraShaker:ShakeSustain(CameraShaker.Presets.Earthquake)
		script.arigato:Play() -- Voice line/Sound
		CinematicUI.Subtitle.Text = "It's truly, truly been a roundabout path..." -- Story text

		script.arigato.Ended:Wait()

		-- Cleanup subtitles and fade out white screen
		task.delay(0.8, function()
			CinematicUI.Subtitle.Text = "" 
			CinematicUI.BarTop.Visible = false
			CinematicUI.BarBottom.Visible = false

			TweenService:Create(CinematicUI.Dim, TweenInfo.new(3.25), {BackgroundTransparency = 1}):Play()
		end)

		Camera.CameraType = Enum.CameraType.Custom -- Reset camera control

		-- MAP SWAP LOGIC
		local Map2 = ReplciatedStorage.Maps[NewMap]:Clone() -- Clone new map
		Map2.Parent = workspace
		Map2:PivotTo(workspace[PreviousMap]:GetPivot()) -- Place it where old map was
		workspace[PreviousMap]:Destroy() -- Delete old map

		-- Spawn pasta shrine if you hit prestige 2
		if PlayerData.Prestige == 2 then
			local Spaghetti = Assets.Spaghetti:Clone()
			Spaghetti.Parent = workspace.MusicZones
		end

		task.wait(0.5)

		-- Reduce light intensity
		TweenService:Create(workspace.Cutscene.BrightLight.PointLight, TweenInfo.new(1), {Range = 0}):Play()

		-- Reset player state
		task.delay(1.5, function()
			PrestigeAnimation:Stop()
			CameraShaker:StopSustained(1)
			BoardUI.Enabled = true -- Show UI

			Utils:ToggleControls(true) -- Unfreeze
			ToggleCollection(true) -- Show items
			Remotes.ToggleGeneration:FireServer(true) -- Resume generation
			TogglePlayers(true) -- Show players
		end)

		-- Final Cleanup
		task.delay(3.5, function()
			CinematicUI.Enabled = false
			CinematicUI.BarTop.Visible = true
			CinematicUI.BarBottom.Visible = true

			-- Resume music if enabled in settings
			for _, Sound in pairs(workspace.Music:GetChildren()) do
				if PlayerData.Settings["Toggle Music"] then
					Sound:Play()
				end
			end

			-- Re-enable core UI
			game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
			Debounce = false

			PrestigeBoard.PrestigeAmount.Text = "Prestige Milestone " .. PlayerData.Prestige      
		end)

		-- Reset Bloom effect
		TweenService:Create(game.Lighting.Bloom, TweenInfo.new(2), {Size = 15}):Play()
	end
end)
