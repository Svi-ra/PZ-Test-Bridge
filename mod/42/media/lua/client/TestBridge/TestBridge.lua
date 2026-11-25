-- Test Bridge: game control for automated tests (README.md). Development only: nothing here runs unless called,
-- through the command file (<Zomboid>/testbridge/command.txt: "lua return TB.pos()") or the game's debug console.
--
--   Player   TB.pos()  TB.tp(x, y [, z])  TB.walk(x, y [, z])  TB.stop()  TB.face(x, y)  TB.safe(on)  TB.speed(n)
--   Camera   TB.cam(dx, dy)  TB.zoom(z)  (also the "cam" / "zoom" commands); TB.screen(x, y [, z]) -> window pixel
--   UI       TB.ui([filter])  TB.click(target)  TB.text(target, s)  TB.close(target)  TB.shot(name)
--   Menus    TB.rmenu(x, y [, z]) opens a square's context menu; TB.option(text) picks an option
--   State    TB.state()  -> "mainmenu" | "ingame" | ...; TB.continue() loads the latest save from the main menu
--
-- UI targets are an id from the last TB.ui() listing ("4.2.1"), or text matched case-insensitively against an
-- element's title / name / text (first visible match, deepest first). All functions return a string for the log.

TB = TB or {}

local function player() return getSpecificPlayer(0) end

local function fmt(v) return string.format("%.2f", v) end

-- ---------------------------------------------------------------- player

function TB.pos()
    local p = player()
    if not p then return "no player" end
    return "x=" .. fmt(p:getX()) .. " y=" .. fmt(p:getY()) .. " z=" .. fmt(p:getZ()) .. " dir=" .. tostring(p:getDir())
            .. " moving=" .. tostring(p:isPlayerMoving())
end

function TB.tp(x, y, z)
    local p = player()
    if not p then return "no player" end
    p:teleportTo(x, y, z or math.floor(p:getZ()))
    return "teleported: " .. TB.pos()
end

function TB.walk(x, y, z)
    local p = player()
    if not p then return "no player" end
    local sq = getCell():getGridSquare(x, y, z or math.floor(p:getZ()))
    if not sq then return "square not loaded" end
    ISTimedActionQueue.clear(p)
    ISTimedActionQueue.add(ISWalkToTimedAction:new(p, sq))
    return "walking to " .. x .. "," .. y
end

function TB.stop()
    local p = player()
    if not p then return "no player" end
    ISTimedActionQueue.clear(p)
    p:getPathFindBehavior2():cancel()
    return "stopped"
end

function TB.face(x, y)
    local p = player()
    if not p then return "no player" end
    p:faceLocation(x, y)
    return "facing " .. x .. "," .. y
end

-- Test safety on the dev save: zombies ignore and cannot hurt the player.
function TB.safe(on)
    local p = player()
    if not p then return "no player" end
    on = on ~= false
    p:setGodMod(on)
    p:setInvisible(on)
    p:setGhostMode(on)
    return "safe=" .. tostring(on)
end

-- Game speed: 0 pause, 1 normal, 2-4 fast forward (as the speed buttons).
function TB.speed(n)
    setGameSpeed(n)
    return "speed=" .. tostring(n) .. " paused=" .. tostring(isGamePaused())
end

-- Screen pixel (window coordinates, UI scale) of a world point, for clicks through real input.
function TB.screen(x, y, z)
    local p = player()
    z = z or (p and math.floor(p:getZ())) or 0
    local sx = isoToScreenX(0, x, y, z)
    local sy = isoToScreenY(0, x, y, z)
    return "screen x=" .. math.floor(sx) .. " y=" .. math.floor(sy)
end

-- ---------------------------------------------------------------- camera (Java side: Bridge.cam / zoom / time)

-- the Java side answers "ok: ..." like every command; the lua command adds its own "ok:", so drop this one
local function bridge(line) return (string.gsub(TestBridge_command(line), "^ok: ", "")) end
function TB.cam(dx, dy) return bridge("cam " .. (dx or 0) .. " " .. (dy or 0)) end
function TB.zoom(z) return bridge(z and ("zoom " .. z) or "zoom") end
function TB.time(hour) return bridge(hour and ("time " .. hour) or "time") end

-- ---------------------------------------------------------------- UI

local last = {}   -- id -> element table, from the last TB.ui()

local function textOf(t)
    for _, k in ipairs({ "title", "name", "text", "label", "internal" }) do
        local v = t[k]
        if type(v) == "string" and v ~= "" then return v end
    end
    if t.javaObject and t.Type == "ISTextEntryBox" then return t:getText() end
    return ""
end

local function visible(t)
    return t.javaObject and t.javaObject:isReallyVisible()
end

local function childrenOf(t)
    local list = {}
    if t.children then
        for _, c in pairs(t.children) do table.insert(list, c) end
        table.sort(list, function(a, b) return (a.ID or 0) < (b.ID or 0) end)
    end
    return list
end

local function walk(t, id, depth, fn)
    fn(t, id, depth)
    for i, c in ipairs(childrenOf(t)) do walk(c, id .. "." .. i, depth + 1, fn) end
end

local function roots()
    local out = {}
    local ui = UIManager.getUI()
    for i = 0, ui:size() - 1 do
        local t = ui:get(i):getTable()
        if t then table.insert(out, t) end
    end
    return out
end

-- Lists visible UI elements: "id Type 'text' x,y wxh" (absolute window pixels), context menu options as "id/opt N".
-- filter: only lines containing it (case-insensitive). The listing also defines the ids TB.click() accepts.
function TB.ui(filter)
    last = {}
    local lines = {}
    filter = filter and string.lower(filter)
    for i, r in ipairs(roots()) do
        walk(r, tostring(i), 0, function(t, id, depth)
            if not visible(t) then return end
            last[id] = t
            local line = string.rep("  ", depth) .. id .. " " .. tostring(t.Type) .. " '" .. textOf(t) .. "' "
                    .. math.floor(t:getAbsoluteX()) .. "," .. math.floor(t:getAbsoluteY()) .. " "
                    .. math.floor(t:getWidth()) .. "x" .. math.floor(t:getHeight())
            if t.Type == "ISContextMenu" and t.options then
                for n = 1, t.numOptions - 1 do
                    local o = t.options[n]
                    if o then line = line .. "\n" .. string.rep("  ", depth + 1) .. id .. "/opt " .. n .. " '" .. tostring(o.name) .. "'"
                            .. ((o.notAvailable or o.isDisabled) and " (disabled)" or "") end
                end
            end
            if not filter or string.find(string.lower(line), filter, 1, true) then table.insert(lines, line) end
        end)
    end
    return "ui " .. #lines .. " elements\n" .. table.concat(lines, "\n")
end

local function find(target)
    if last[target] and visible(last[target]) then return last[target], target end
    local want = string.lower(tostring(target))
    local best, bestId, bestDepth = nil, nil, -1
    for i, r in ipairs(roots()) do
        walk(r, tostring(i), 0, function(t, id, depth)
            if visible(t) and depth > bestDepth and string.find(string.lower(textOf(t)), want, 1, true) then
                best, bestId, bestDepth = t, id, depth
            end
        end)
    end
    return best, bestId
end

-- Clicks a UI element the way its own handlers expect: ISButton:forceClick, else onMouseDown + onMouseUp at its
-- centre (main menu labels, list items, tick boxes). Returns its centre too, for a real click if this is not enough.
function TB.click(target)
    local t, id = find(target)
    if not t then return "no visible element matching '" .. tostring(target) .. "'" end
    local w, h = t:getWidth(), t:getHeight()
    local how
    if t.forceClick then
        t:forceClick()
        how = "forceClick"
    else
        if t.onMouseDown then t:onMouseDown(w / 2, h / 2) end
        if t.onMouseUp then t:onMouseUp(w / 2, h / 2) end
        how = "mouseDown/Up"
    end
    return "clicked " .. id .. " " .. tostring(t.Type) .. " '" .. textOf(t) .. "' (" .. how .. ") centre "
            .. math.floor(t:getAbsoluteX() + w / 2) .. "," .. math.floor(t:getAbsoluteY() + h / 2)
end

function TB.text(target, s)
    local t, id = find(target)
    if not t or not t.setText then return "no text box matching '" .. tostring(target) .. "'" end
    t:setText(s)
    if t.onTextChange then pcall(t.onTextChange, t.target or t, t) end
    return "text " .. id .. " = '" .. s .. "'"
end

-- Selects an option of the open context menu(s) by text, as its onMouseUp does.
function TB.option(text)
    local want = string.lower(text)
    for _, r in ipairs(roots()) do
        local found
        walk(r, "", 0, function(t)
            if not found and visible(t) and t.Type == "ISContextMenu" and t.options then
                for n = 1, t.numOptions - 1 do
                    local o = t.options[n]
                    if o and o.name and string.find(string.lower(o.name), want, 1, true) then found = { t, o } break end
                end
            end
        end)
        if found then
            local menu, o = found[1], found[2]
            if o.subOption then return "'" .. o.name .. "' opens a submenu: TB.ui('ISContextMenu') after hovering it" end
            if not o.onSelect or o.notAvailable or o.isDisabled then return "'" .. o.name .. "' is not available" end
            ISContextMenu.globalPlayerContext = menu.player
            menu:closeAll()
            o.onSelect(o.target, o.param1, o.param2, o.param3, o.param4, o.param5, o.param6, o.param7, o.param8, o.param9, o.param10)
            return "selected '" .. o.name .. "'"
        end
    end
    return "no context menu option matching '" .. text .. "'"
end

-- Opens the world context menu of a square, as a right-click there does (ISObjectClickHandler path). Real right-clicks
-- through SendInput are too short for the game to see; use this, then TB.ui('ISContextMenu') and TB.option(text).
function TB.rmenu(x, y, z)
    local p = player()
    if not p then return "no player" end
    z = z or math.floor(p:getZ())
    local sq = getCell():getGridSquare(x, y, z)
    if not sq then return "square not loaded" end
    local objects = {}
    local list = sq:getObjects()
    for i = 0, list:size() - 1 do table.insert(objects, list:get(i)) end
    if #objects == 0 then return "no objects on " .. x .. "," .. y end
    local sx = isoToScreenX(0, x + 0.5, y + 0.5, z)
    local sy = isoToScreenY(0, x + 0.5, y + 0.5, z)
    ISContextManager.getInstance().createWorldMenu(0, objects[#objects], objects, sx, sy)
    return "menu for " .. x .. "," .. y .. " (" .. #objects .. " objects) at " .. math.floor(sx) .. "," .. math.floor(sy)
end

function TB.close(target)
    local t, id = find(target)
    if not t then return "no visible element matching '" .. tostring(target) .. "'" end
    if t.close then t:close() else t:setVisible(false) end
    return "closed " .. id
end

-- Full frame with UI (front buffer, as vanilla's screenshot key) to <Zomboid>/Screenshots/<name>.png; written on the
-- render thread a frame later.
function TB.shot(name)
    name = (name or "pl") .. ".png"
    takeScreenshot(name)
    return "screenshot " .. name .. " " .. getCore():getScreenWidth() .. "x" .. getCore():getScreenHeight()
end

-- ---------------------------------------------------------------- state

function TB.state()
    local s = "unknown"
    if MainScreen and MainScreen.instance and MainScreen.instance:isReallyVisible() and not MainScreen.instance.inGame then
        s = "mainmenu"
    elseif player() then
        s = "ingame" .. (isGamePaused() and " paused" or "")
        if MainScreen and MainScreen.instance and MainScreen.instance:isReallyVisible() then s = s .. " escmenu" end
    end
    return s .. " screen=" .. getCore():getScreenWidth() .. "x" .. getCore():getScreenHeight()
            .. " mouse=" .. getMouseX() .. "," .. getMouseY()
end

function TB.continue()
    if not (MainScreen and MainScreen.latestSaveWorld) then return "no latest save" end
    MainScreen.continueLatestSave(MainScreen.latestSaveGameMode, MainScreen.latestSaveWorld)
    return "loading " .. tostring(MainScreen.latestSaveGameMode) .. "/" .. tostring(MainScreen.latestSaveWorld)
end

-- The command file is polled from here, every frame, in game and on the main menu. Remove first, so reloading this
-- file with "luafile" does not add a second handler.
if TB.onPostUIDraw then Events.OnPostUIDraw.Remove(TB.onPostUIDraw) end
function TB.onPostUIDraw()
    if TestBridge_tick then TestBridge_tick() end
end
Events.OnPostUIDraw.Add(TB.onPostUIDraw)

return TB
