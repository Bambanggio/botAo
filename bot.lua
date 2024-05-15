
-- Initializing global variables to store the latest game state and game host process.
MyGameState = MyGameState or nil
ActionInProgress = ActionInProgress or false -- Prevents the agent from taking multiple actions at once.
EnemyLogs = EnemyLogs or {}
LastPosition = LastPosition or nil
HealthPotions = HealthPotions or 3 -- Assume we start with 3 health potions

-- Define colors for console output
colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

-- Function to add logs
function addLog(msg, text)
    EnemyLogs[msg] = EnemyLogs[msg] or {}
    table.insert(EnemyLogs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function isWithinRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Function to avoid direct confrontation
function avoidEnemy()
    local me = MyGameState.Players[ao.id]
    local safePosition = findSafePosition(me)
    if safePosition then
        print(colors.blue .. "Moving to safe position." .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Position = safePosition })
        ActionInProgress = false
    end
end

-- Function to find a safe position away from enemies
function findSafePosition(me)
    for x = 1, GameMap.width do
        for y = 1, GameMap.height do
            local isSafe = true
            for _, player in pairs(MyGameState.Players) do
                if player.id ~= ao.id and isWithinRange(x, y, player.x, player.y, 2) then
                    isSafe = false
                    break
                end
            end
            if isSafe then
                return { x = x, y = y }
            end
        end
    end
    return nil
end

-- Function to maintain high health
function maintainHealth()
    local me = MyGameState.Players[ao.id]
    if me.health < 0.7 and HealthPotions > 0 then
        print(colors.green .. "Using health potion." .. colors.reset)
        ao.send({ Target = Game, Action = "UseItem", Player = ao.id, Item = "HealthPotion" })
        HealthPotions = HealthPotions - 1
        ActionInProgress = false
    end
end

-- Function to gather intelligence
function gatherIntel()
    print(colors.gray .. "Gathering game state information..." .. colors.reset)
    ao.send({ Target = Game, Action = "GetGameState" })
    ActionInProgress = false
end

-- Function to decide attack or avoid
function decideAttackOrAvoid()
    local me = MyGameState.Players[ao.id]
    local closestEnemy = findClosestEnemy(me)
    if closestEnemy then
        if me.energy > 0.5 and isWithinRange(me.x, me.y, closestEnemy.x, closestEnemy.y, 1) and closestEnemy.health < me.health then
            attackEnemy(closestEnemy)
        else
            avoidEnemy()
        end
    else
        avoidEnemy()
    end
end

-- Function to find the closest enemy
function findClosestEnemy(me)
    local closestEnemy = nil
    local minDistance = math.huge
    for _, player in pairs(MyGameState.Players) do
        if player.id ~= ao.id then
            local distance = math.sqrt((me.x - player.x)^2 + (me.y - player.y)^2)
            if distance < minDistance then
                minDistance = distance
                closestEnemy = player
            end
        end
    end
    return closestEnemy
end

-- Function to attack enemy
function attackEnemy(enemy)
    print(colors.red .. "Attacking enemy." .. colors.reset)
    ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(MyGameState.Players[ao.id].energy * 0.5) })
    ActionInProgress = false
end

-- Handler to decide the next action
Handlers.add(
    "DecideNextAction",
    Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
    function()
        if MyGameState.GameMode ~= "Playing" then
            print("Game not started yet.")
            ActionInProgress = false
            return
        end

        print("Deciding next action.")
        maintainHealth()
        decideAttackOrAvoid()
        gatherIntel()
        ActionInProgress = false
    end
)

-- Handler to update the game state
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        MyGameState = json.decode(msg.Data)
        ao.send({ Target = ao.id, Action = "UpdatedGameState" })
        print("Game state updated. Print 'MyGameState' for detailed view.")
        ActionInProgress = false
    end
)

-- Handler to trigger game state updates
Handlers.add(
    "GetGameStateOnTick",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function()
        if not ActionInProgress then
            ActionInProgress = true
            print("Getting game state...")
            ao.send({ Target = Game, Action = "GetGameState" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)

-- Handler to automatically confirm payment when waiting period starts
Handlers.add(
    "AutoPay",
    Handlers.utils.hasMatchingTag("Action", "AutoPay"),
    function(msg)
        print("Auto-paying confirmation fees.")
        ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
    end
)

-- Handler to automate actions based on game announcements
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        if msg.Event == "Started-Waiting-Period" then
            ao.send({ Target = ao.id, Action = "AutoPay" })
        elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not ActionInProgress then
            ActionInProgress = true
            ao.send({ Target = Game, Action = "GetGameState" })
        elseif ActionInProgress then
            print("Previous action still in progress. Skipping.")
        end

        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    end
)

-- Handler to automatically counter-attack when hit by another player
Handlers.add(
    "ReturnAttack",
    Handlers.utils.hasMatchingTag("Action", "Hit"),
    function(msg)
        if not ActionInProgress then
            ActionInProgress = true
            local me = MyGameState.Players[ao.id]
            local attacker = msg.Attacker

            if me.energy > 0 and isWithinRange(me.x, me.y, attacker.x, attacker.y, 1) and attacker.health < me.health then
                print(colors.red .. "Returning attack on attacker." .. colors.reset)
                ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(me.energy * 0.5) })
            else
                avoidEnemy()
            end
            ActionInProgress = false
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)

