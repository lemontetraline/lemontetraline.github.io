-- Incremental game part generator script
-- circa 2023 or 2024
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Imports the Data module script that handles saving/loading of player stats
local Data = require(ServerScriptService.Data)
-- Imports the BoostModule to handle the boosts
local BoostModule = require(ServerScriptService.BoostModule)
-- Imports the Utils function (I use it here to abbreviate numbers)
local Utils = require(ReplicatedStorage.Utils)

-- Waits for the Remotes folder
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
-- References the Field part in the Workspace, which determines where items spawn
local Field = workspace.Field
---

--- Variables ---
-- Creates a table for all spawned items for every player on the server
-- Id later find out all of this is a bad design decision but this game needs a full rework anyway
local GlobalThings = {}
-- Creates a table to store the active threads for each player's generation loop
local PlayerCoroutines = {}

--- Functions ---
-- Defines a function to spawn a new item for a specific player
function GenerateThing(Player)
	-- Checks if the player doesn't have a tracking table yet
	if not GlobalThings[Player.Name] then
		-- Creates a new empty table for the player if one didn't exist
		GlobalThings[Player.Name] = {}
	end

	-- Calculates a random Vector3 position relative to the Field's CFrame and Size
	local RandomPosition = (Field.CFrame * CFrame.new(
		-- Generates a random X offset between -0.5 and 0.5 of the Field size
		(math.random() - 0.5) * Field.Size.X,
		-- Generates a random Y offset, adding 0.25 studs so it sits slightly above the ground
		(math.random() - 0.5) * Field.Size.Y + 0.25,
		-- Generates a random Z offset between -0.5 and 0.5 of the Field size
		(math.random() - 0.5) * Field.Size.Z
		-- Gets the .Position property of the resulting CFrame
		)).Position

	-- Creates a data table describing this specific item
	local ThingData = {
		-- Sets the type of item to determine how much value they have later on
		Type = "regular",
		-- Sets the position
		Position = RandomPosition
	}

	-- Inserts this item data into the server's tracking table for this player
	table.insert(GlobalThings[Player.Name], ThingData)
	-- Fires a RemoteEvent to the specific client telling them to visually render the item
	-- Kinda is more optimised, it would've been so if this script was more optimised itself ngl
	Remotes.GenerateVisual:FireClient(Player, ThingData)
end

-- A function to find the thing in a list based on its position
function FindByPosition(Table, Position)
	-- Loops through every thing in the provided table
	for Index, Thing in pairs(Table) do
		-- Checks if the position of the current item matches the position we are looking for
		if Thing.Position == Position then
			-- If found, returns the item object and its index in the table
			return Thing, Index
		end
	end
end

-- Wrapper for the main loop that generates things for each player
function GenerationLoop(Player)
	-- Starts an infinite loop (here it runs until I close the coroutine for the player)
	while true do
		-- Retrieves the current saved data for the player
		local PlayerData = Data:Get(Player)

		-- Creates a new thread so the math doesn't block other code (??? Ion remember why is it here to be fair)
		task.spawn(function()
			-- Decides to try spawning between 1 and 3 items at once
			local GenerationAmount = math.random(1, 3)

			-- Checks if the player table exists, if they are under their max item cap, and if generation is enabled
			if (GlobalThings[Player.Name] and #GlobalThings[Player.Name] < PlayerData.Upgrades.ThingsCap[2]) and PlayerData.ShouldGenerate then
				-- If adding the random amount exceeds the cap, set amount to 1 to be safe
				if #GlobalThings[Player.Name] + GenerationAmount >= PlayerData.Upgrades.ThingsCap[2] then GenerationAmount = 1 end
				-- Loops from 1 to the decided generation amount
				for _ = 1, GenerationAmount do
					-- Calls the function above to create the item
					GenerateThing(Player)
				end
			end
		end)

		-- Checks if any temporary boosts (like x2 speed boost) have expired
		BoostModule:CheckBoosts(Player)
		-- Waits for a duration calculated by diving Base Respawn Delay by Respawn Speed Boost that we just cheked for
		task.wait(PlayerData.Upgrades.RespawnDelay[2] / PlayerData["RespawnDelayBoost"])
	end
end


--- Events ---
-- Connects a function to run when a player leaves the game
Players.PlayerRemoving:Connect(function(Player)
	-- Checks if the player has an entry in the item tracking table
	if GlobalThings[Player.Name] then
		-- Removes the player's item table to free up memory
		GlobalThings[Player.Name] = nil
	end

	-- Checks if the player has an active generation coroutine running
	if PlayerCoroutines[Player.Name] then
		-- Kills the coroutine immediately so the loop stops
		coroutine.close(PlayerCoroutines[Player.Name])
		-- Removes the reference to the coroutine
		PlayerCoroutines[Player.Name] = nil
	end
end)

-- Connects a function to run when a player joins the game
Players.PlayerAdded:Connect(function(Player)
	-- Checks if the player needs a new item tracking table (just in case)
	if not GlobalThings[Player.Name] then
		-- Creates the table
		GlobalThings[Player.Name] = {}
	end

	-- Creates a new coroutine for the thing generator loop function
	PlayerCoroutines[Player.Name] = coroutine.create(GenerationLoop)
	-- Waits 3 seconds after joining, then starts the coroutine passing the Player argument
	task.delay(3, coroutine.resume, PlayerCoroutines[Player.Name], Player)
end)


-- Listens for a Client event asking to remove an item (I dont remember the purpose of this)
Remotes.RemoveThing.OnServerEvent:Connect(function(Player, Position)
	-- Uses the function above to find the thing by i'ts position
	local Thing, Index = FindByPosition(GlobalThings[Player.Name], Position)
	-- If the item doesn't exist on the server, stop here
	if not Thing then return end

	-- Removes the item from the server table
	table.remove(GlobalThings[Player.Name], Index)
end)

-- Defines a function to show a UI pop-up when an item is collected
-- Was added later on (should happen on the client??)
function ShowCollectedTextLabel(Player, Value)
	-- Tries to find the PlayerGui folder inside the Player
	local PlayerGui = Player:FindFirstChildOfClass("PlayerGui")
	-- If PlayerGui doesn't exist (rare edge case), create it
	if not PlayerGui then
		-- Creates a new PlayerGui folder
		PlayerGui = Instance.new("PlayerGui")
		-- Names it
		PlayerGui.Name = "PlayerGui"
		-- Parents it to the Player
		PlayerGui.Parent = Player
	end

	-- Creates a new ScreenGui to hold the UI
	local ScreenGui = Instance.new("ScreenGui")
	-- Names the ScreenGui
	ScreenGui.Name = "CollectedGui"
	-- Parents it to the PlayerGui
	ScreenGui.Parent = PlayerGui

	-- Uses the Utils module to make the number look nice
	local roundedValue = Utils:AbbreviateNumber(Value)

	-- Creates a text label to display the number
	local TextLabel = Instance.new("TextLabel")
	-- Names the label
	TextLabel.Name = "CollectedLabel"
	-- Sets the size 
	TextLabel.Size = UDim2.new(0, 150, 0, 37)
	-- Sets the starting position (Center horizontal, Bottom vertical)
	TextLabel.Position = UDim2.new(0.5, 0, 1, -50)
	-- Sets the anchor point to the center of the label
	TextLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Makes the background invisible
	TextLabel.BackgroundTransparency = 1
	-- Sets the font
	TextLabel.Font = Enum.Font.FredokaOne
	-- Sets the text color to teal
	TextLabel.TextColor3 = Color3.new(0, 0.8, 0.8)
	-- Sets the text content to show the amount collected
	TextLabel.Text = `+{roundedValue} Things`
	-- Makes the text stroke visible
	TextLabel.TextStrokeTransparency = 0
	-- Sets the text stroke color to black
	TextLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	-- Enables RichText (allows markup tags)
	TextLabel.RichText = true
	-- Auto-scales the text to fit the box
	TextLabel.TextScaled = true
	-- Parents the label to the ScreenGui
	TextLabel.Parent = ScreenGui

	-- Initializes a variable for the previous animation goal
	local previousGoalPosition
	-- Initializes a table to store the tween target
	local goal = {}

	-- Starts a loop to find a random position that isn't the same as the last one
	repeat
		-- Generates a random horizontal position
		local horizontalPosition = math.random()
		-- Sets the goal position to that random horizontal spot, centered vertically
		goal.Position = UDim2.new(horizontalPosition, 0, 0.5, 0)
		-- Repeats until the new goal is different from the previous one
	until not previousGoalPosition or goal.Position ~= previousGoalPosition

	-- Updates the previous goal tracker
	previousGoalPosition = goal.Position

	-- Creates info for the animation: 0.8 seconds, Quad style, Out direction
	local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	-- Creates the tween using TweenService
	local tween = game:GetService("TweenService"):Create(TextLabel, tweenInfo, goal)
	-- Starts the movement animation
	tween:Play()
	-- Connects a function to run when the movement finishes
	tween.Completed:Connect(function()
		-- Creates a second tween for fading out
		game:GetService("TweenService"):Create(
			TextLabel, -- The label to animate
			TweenInfo.new(0.3), -- Duration of 0.3 seconds
			{TextStrokeTransparency = 1, TextTransparency = 1} -- Goals: Make text and stroke invisible
		):Play() -- Plays the fade out
		-- Waits 0.3 seconds for the fade to finish
		wait(0.3)
		-- Destroys the TextLabel
		TextLabel:Destroy()
		-- Destroys the ScreenGui
		ScreenGui:Destroy()
	end)
end


-- Sets up a RemoteFunction that the client calls when they hit (touch) an item
Remotes.CollectThing.OnServerInvoke = function(Player, HitPosition)
	-- Gets the list of items spawned for this specific player
	local PlayerThings = GlobalThings[Player.Name]
	-- Uses the function above to find the thing by i'ts position
	-- Although i should be checking it in a different way to further prevent exploiting
	-- I should just use the Player's position and try and find the closest one
	local Thing, Index = FindByPosition(PlayerThings, HitPosition)

	-- If no item matches the position (u can call it an 'anti cheat'), return false
	if not Thing then --warn("didn't manage to find thing")
		return false end
	-- Removes the verified item from the server's tracking table
	table.remove(GlobalThings[Player.Name], Index)

	-- Retrieves the player's save data
	local PlayerData = Data:Get(Player)

	-- Updates boosts in case they just expired
	BoostModule:CheckBoosts(Player)

	-- Calculates the value of the collected item based on upgrades and multipliers
	local Value = PlayerData.Upgrades.Value[2] * (
		PlayerData.UnderPrestigeMultiplier * PlayerData.PrestigeMultiplier * PlayerData.ThingValueBoost *
			PlayerData.FriendBoostMultiplier *
			PlayerData.RobuxBoostMultiplier
	)

	-- Checks if the DoubleThings gamepass is active
	if PlayerData.DoubleThings then
		-- If so then multiplies the value by 2
		Value *= 2
	end

	-- Adds the calculated value to the player's current currency
	PlayerData.things += Value
	-- Adds the value to their lifetime total
	PlayerData.TotalThings += Value
	-- Adds 1 point of XP
	PlayerData.XP += 1

	-- Checks if the player has the collection pop-up setting enabled
	if PlayerData.Settings["Toggle Collection Pop-ups"] then
		-- Calls the function to show the UI text
		ShowCollectedTextLabel(Player, Value)
	end
	-- Checks if the player has enough XP to level up
	-- Should've been on a separate function somewhere
	if PlayerData.XP >= PlayerData.LevelCost then
		-- Resets XP to 0
		PlayerData.XP = 0
		-- Increases the Level
		PlayerData.Level += 1
		-- Increases the cost for the next level by 50%
		PlayerData.LevelCost += (50 / 100) * PlayerData.LevelCost
		-- Rounds the new cost down to a whole number
		PlayerData.LevelCost = math.floor(PlayerData.LevelCost)

		-- Fires a remote to the client to play a Level Up effect
		Remotes.LevelUpEffect:FireClient(Player)
	end

	-- Saves the updated data back to the module
	Data:Set(Player, PlayerData)
	-- Returns true to the client to confirm collection was successful
	return true
end

-- Sets up a RemoteFunction for the client when they need to all your things spawned
Remotes.RequestThings.OnServerInvoke = function(Player)
	return GlobalThings[Player.Name]
end