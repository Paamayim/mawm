awful = require("awful")
awful.rules = require("awful.rules")
require "awful.autofocus"
naughty = require "naughty"
wibox = require "wibox"
beautiful = require "beautiful"
gears = require "gears"
lfs = require "lfs"

html = require "markup"

mawm = { }


-- Setup env

local function get_tag(tagid)
    return tagid and (tags[tagid] or tags[tagid .. ":1"])
end

system = awful.util.spawn_with_shell

function launch(program, tagid)
    mawm.nextTag = get_tag(tagid)
    awful.util.spawn(program)
end

function launch1(cmd)
    findme = cmd
    firstspace = cmd:find(" ")
    if firstspace then
        findme = cmd:sub(0, firstspace-1)
    end
    awful.util.spawn_with_shell("pgrep -u $USER -x " .. findme .. " > /dev/null || (" .. cmd .. ")")
end


function theme(theme)
    local path = string.format("%s/themes/%s/theme.lua", awful.util.getdir("config"), theme)
    beautiful.init(path)

    if beautiful.wallpaper then
        for s = 1, screen.count() do
            gears.wallpaper.maximized(beautiful.wallpaper, s, true)
        end
    end
end


function first_line(f)
    local fp = io.open(f)
    if not fp
    then
        return nil
    end

    local content = fp:read("*l")
    fp:close()
    return content
end


modkey = "Mod4"
local function parse_shortcut(method, short, cmd)
    local mods = { }
    local key = nil

    for token in tostring(short).gmatch(short, "[^ +]+") do
        if key ~= nil then
            table.insert(mods, key)
        end

        if token == "mod" then
            key = modkey
        elseif token == "alt" then
            key = "Mod1"
        elseif token == "ctrl" then
            key = "Control"
        elseif token == "shift" then
            key = "Shift"
        else
            key = token
        end
    end

    -- Buid a canonical nae to allow for remapping defaults
    table.sort(mods)
    local canonicalName = string.lower(table.concat(mods, "+") .. "+" .. key)

    -- Cast the key to a number if possible
    key = tonumber(key) or key

    return canonicalName, method(mods, key, cmd)
end

local function join(t)
    local result = { }
    for k, v in pairs(t) do
        result = awful.util.table.join(result, v)
    end

    return result
end

widgets = { }
-- Plugins
function plugin(repo)
    local name = string.gsub(repo, "/", "-")
    local root = string.format("%s/installed-plugins", awful.util.getdir("config"), name)
    local path = string.format("%s/%s", root, name)
    if not lfs.attributes(path) then
        -- TODO: Show naughty messages
        os.execute("mkdir -p " .. root)
        os.execute(string.format("git clone https://github.com/%s.git %s", repo, path))
    end

    require(string.format("installed-plugins/%s/init", name))
end


local function gen_glob_client_raw(which)
    -- Generate which(), cwhich() and rawwhich() functions
    local function gen_one(kind)
        local tprefix, fprefix
        if kind == "root" then
            tprefix = "g"
            fprefix = ""
        elseif kind == "client" then
            tprefix = "c"
            fprefix = "c"
        elseif kind == "raw" then
            fprefix = "raw"
        end

        local tab
        if tprefix then
            local name = string.format("%s%ss", tprefix, which)
            mawm[name] = { }
            tab = mawm[name]
        end

        _G[fprefix .. which] = function(short, cmd)
            local name, result = parse_shortcut(awful[which], short, cmd)
            if tab then
                tab[name] = result
            end
            return result
        end

        if tab then
            _G["u" .. fprefix .. which] = function(short)
                -- kinda gross but let's repurpose parsing to find our name
                local name = parse_shortcut(function() end, short)
                tab[name] = nil
            end
        end
    end

    gen_one("root")
    gen_one("client")
    gen_one("raw")
end

gen_glob_client_raw("key")
gen_glob_client_raw("button")


awful.rules.rules = -- Default rule
    {   rule = { },
        properties = {  keys = join(mawm.ckeys),
                        buttons = join(mawm.cbuttons),
                        focus = awful.client.focus.filter,
                        raise = true,
        }
    }
function rule()
end

mawm.nextTag = nil
function raise(cmd, val, tagid, prop)
    prop = prop or "class"

    return function()
        local clients = client.get()
        local focused = awful.client.next(0)
        local findex = 0
        local matched_clients = {}
        local n = 0

        --make an array of matched clients
        for i, c in pairs(clients) do
            print "trying"
            if c[prop] ~= val and (c[prop] == val or c[prop]:find(val)) then
                print "got a match!"
                n = n + 1
                matched_clients[n] = c
                if c == focused then
                    findex = n
                end
            end
        end

        if n > 0 then
            local c = matched_clients[1]
            if 0 < findex and findex < n then
                -- if the focused window matched switch focus to next in list
                c = matched_clients[findex+1]
            end

            local ctags = c:tags()
            if table.getn(ctags) == 0 then
                -- ctags is empty, show client on current tag
                local curtag = awful.tag.selected()
                awful.client.movetotag(curtag, c)
            else
                -- Otherwise, pop to first tag client is visible on
                awful.tag.viewonly(ctags[1])
            end

            -- And then focus the client
            client.focus = c
            c:raise()
        else
            launch(cmd, tagid)
        end
    end
end



mawm.tags = { }
mawm.taglayouts = { }
for s = 1, screen.count() do
    table.insert(mawm.tags, { })
    table.insert(mawm.taglayouts, { })
end

function tag(name, default)
    for s = 1, screen.count() do
        stag(s, name, default)
    end
end

function stag(s, tags, default)
    default = default or awful.layout.layouts[1] or awful.layout.suit.tile

    if type(tags) ~= "table" then
        tags = { tags }
    end

    for _, name in ipairs(tags) do
        table.insert(mawm.tags[s], name)
        table.insert(mawm.taglayouts[s], default)
    end
end

awful.layout.layouts = { }
function layout(which)
    table.insert(awful.layout.layouts, which)
end


mawm.start = { }
function start(program, tagid)
    table.insert(mawm.start, { program, tagid })
end

signal = awesome.connect_signal
csignal = client.connect_signal

-- Install tag spawning support
mawm.clientsToSpawn = 0
csignal("manage", function(c)
        local tag = mawm.nextTag
        if tag then
            awful.client.movetotag(tag, c)

            if mawm.clientsToSpawn == 0 then
                -- suppress changing tags if we are starting up
                awful.tag.viewonly(tag)
            else
                mawm.clientsToSpawn = mawm.clientsToSpawn - 1
            end
            mawm.nextTag = nil
        end
end)



-- Wiboxing
function bar(position, s, left, middle, right, width)
    local left_method = "set_left"
    local right_method = "set_right"
    local layout_type = "horizontal"
    local width_type = "height"

    if position == "left" or position == "right" then
        left_method = "set_top"
        right_method = "set_bottom"
        layout_type = "vertical"
        width_type = "width"
    end

    local context = {
        screen = s,
        orientation = layout_type,
        oriented_container = wibox.layout.fixed[layout_type]
    }

    local properties = { position = position, screen = s }
    properties[width_type] = width or 20

    local wi = awful.wibox(properties)
    local layout = wibox.layout.align[layout_type]()

    local data = {}
    data[left_method] = left
    data["set_middle"] = middle
    data[right_method] = right

    for method, contents in pairs(data) do
        if contents then
            local builder = context.oriented_container()
            for _, widget in ipairs(contents) do
                local result = widget(context)
                if result then
                    builder:add(result)
                end
            end

            layout[method](layout, builder)
        end
    end

    wi:set_widget(layout)
end




-- Finish setting up environment
layouts = awful.layout.suit



-- Include user rc
-- require "default"
require "config"

tags = { }
for s = 1, screen.count() do
    local gentags = awful.tag(mawm.tags[s], s, mawm.taglayouts[s])
    for i, name in ipairs(mawm.tags[s]) do
        local id = string.format("%s:%d", name, s)
        tags[id] = gentags[i]
    end
end

-- Mapping installers
root.buttons(join(mawm.gbuttons))
root.keys(join(mawm.gkeys))

mawm.clientsToSpawn = #mawm.start
for i, tup in ipairs(mawm.start) do
    local program = tup[1]
    local tagid = tup[2]

    if tag then
        launch(program, tagid)
    else
        launch1(program)
    end
end

