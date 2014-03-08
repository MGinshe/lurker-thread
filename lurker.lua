--
-- lurker 
--
-- Copyright (c) 2014, rxi
--
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.
--

if tostring(...) == "Channel" then
  -- get the comms channel, path, and interval
  local channel   = ...
  local path      = channel:pop()
  local interval  = channel:pop()
  lurker_is_thread = true

  -- load lurker and dependencies
  require(path.."love.filesystem")
  require(path.."love.timer")
  local lurker  = require(path.."lurker")
  local lume    = require(path.."lume")
  local lastcheck = love.timer.getTime()

  -- enter check loop
  while true do
    if love.timer.getTime() >= lastcheck + interval  then
      lastcheck = love.timer.getTime()

      local changes = lurker.getchanged()

      if #changes > 0 then 
        for k,v in pairs(changes) do lurker.resetfile(v) end

        channel:supply(true)
      end
    end
  end
else
  local tpath = string.sub(..., 7, -1)

  local lume = lume or require "lume"

  local lurker = { _version = "1.0.0" }


  local dir = love.filesystem.enumerate or love.filesystem.getDirectoryItems
  local isdir = love.filesystem.isDirectory
  local time = love.timer.getTime or os.time
  local lastmodified = love.filesystem.getLastModified

  local lovecallbacknames = { "update", "load", "draw", "mousepressed",
                              "mousereleased", "keypressed", "keyreleased",
                              "focus", "quit" }


  function lurker.init()
    lurker.path = "."
    lurker.preswap = function() end
    lurker.postswap = function() end
    lurker.interval = .5
    lurker.protected = true
    lurker.last = 0
    lurker.files = {}
    lurker.funcwrappers = {}
    lurker.lovefuncs = {}
    lurker.state = "init"
    lurker._thread = lurker_is_thread
    lume.each(lurker.getchanged(), lurker.resetfile)

    if not lurker._thread then -- stops recursion
      lurker.print("Initing lurker")

      if lurker.thread then 
        -- kill the thread if it's already running
        lurker.thread:kill()
      end

      lurker.thread = love.thread.newThread(tpath.."lurker.lua")
      lurker.channel = love.thread.getChannel("__lurker__")
      lurker.thread:start(lurker.channel)
      lurker.channel:push(tpath or "")
      lurker.channel:push(lurker.interval)
    else
      lurker.print("Initing lurker thread")
    end

    return lurker
  end


  function lurker.print(...)
    print("[lurker] " .. lume.format(...))
  end


  function lurker.listdir(path, recursive, skipdotfiles)
    path = (path == ".") and "" or path
    local function fullpath(x) return path .. "/" .. x end
    local t = {}
    for _, f in pairs(lume.map(dir(path), fullpath)) do
      if not skipdotfiles or not f:match("/%.[^/]*$") then
        if recursive and isdir(f) then
          lume.merge(t, lurker.listdir(f, true, true))
        else
          table.insert(t, lume.trim(f, "/"))
        end
      end
    end
    return t
  end


  function lurker.initwrappers()
    for _, v in pairs(lovecallbacknames) do
      lurker.funcwrappers[v] = function(...)
        args = {...}
        xpcall(function()
          return lurker.lovefuncs[v] and lurker.lovefuncs[v](unpack(args))
        end, lurker.onerror)
      end
      lurker.lovefuncs[v] = love[v]
    end
    lurker.updatewrappers()
  end


  function lurker.updatewrappers()
    for _, v in pairs(lovecallbacknames) do
      if love[v] ~= lurker.funcwrappers[v] then
        lurker.lovefuncs[v] = love[v]
        love[v] = lurker.funcwrappers[v]
      end
    end
  end


  function lurker.onerror(e)
    lurker.print("An error occurred; switching to error state")
    lurker.state = "error"
    for _, v in pairs(lovecallbacknames) do
      love[v] = function() end
    end
    love.update = lurker.update

    local stacktrace = debug.traceback():gsub("\t", "")
    local msg = lume.format("{1}\n\n{2}", {e, stacktrace})
    local colors = { 0xFF1E1E2C, 0xFFF0A3A3, 0xFF92B5B0, 0xFF66666A, 0xFFCDCDCD }
    love.graphics.reset()
    love.graphics.setFont(love.graphics.newFont(12))

    love.draw = function()
      local pad = 25
      local width = love.graphics.getWidth()
      local function drawhr(pos, color1, color2)
        local animpos = lume.smooth(pad, width - pad - 8, lume.pingpong(time()))
        if color1 then love.graphics.setColor(lume.rgba(color1)) end
        love.graphics.rectangle("fill", pad, pos, width - pad*2, 1)
        if color2 then love.graphics.setColor(lume.rgba(color2)) end
        love.graphics.rectangle("fill", animpos, pos, 8, 1)
      end
      local function drawtext(str, x, y, color)
        love.graphics.setColor(lume.rgba(color))
        love.graphics.print(str, x, y)
      end
      love.graphics.setBackgroundColor(lume.rgba(colors[1]))
      love.graphics.clear()
      drawtext("An error has occurred", pad, pad, colors[2])
      drawtext("lurker", width - love.graphics.getFont():getWidth("lurker") - 
               pad, pad, colors[4])
      drawhr(pad + 32, colors[4], colors[5])
      drawtext("If you fix the problem and update the file the program will " ..
               "resume", pad, pad + 46, colors[3])
      drawhr(pad + 72, colors[4], colors[5])
      drawtext(msg, pad, pad + 90, colors[5])
      love.graphics.reset()
    end
  end


  function lurker.onfirstframe()
    if lurker.protected then
      lurker.initwrappers()
    end
  end


  function lurker.update() 
    if lurker.state == "init" then
      lurker.onfirstframe()
      lurker.state = "normal"
    end

    --[[local diff = time() - lurker.last 
    if diff > lurker.interval then
      lurker.last = lurker.last + diff
      lurker.scan()
    end]]

    -- if the thread found a change, force a scan
    if lurker.channel:peek() == true then
      lurker.scan()

      lurker.channel:pop()
    end
  end


  function lurker.getchanged()
    local function fn(f)
      return f:match("%.lua$") and lurker.files[f] ~= lastmodified(f)
    end
    return lume.filter(lurker.listdir(lurker.path, true, true), fn)
  end


  function lurker.modname(f)
    return (f:gsub("%.lua$", ""):gsub("[/\\]", "."))
  end


  function lurker.resetfile(f)
    lurker.files[f] = lastmodified(f)
  end


  function lurker.exiterrorstate()
    lurker.state = "normal"
    for _, v in pairs(lovecallbacknames) do
      love[v] = lurker.funcwrappers[v]
    end
  end


  function lurker.hotswapfile(f)
    lurker.print("Hotswapping '{1}'...", {f})
    if lurker.state == "error" then 
      lurker.exiterrorstate()
    end
    lurker.preswap(f)
    local modname = lurker.modname(f)
    local t, ok, err = lume.time(lume.hotswap, modname)
    if ok then
      lurker.print("Swapped '{1}' in {2} secs", {f, t})
    else 
      lurker.print("Failed to swap '{1}' : {2}", {f, err})
    end
    lurker.resetfile(f)
    lurker.postswap(f)
    if lurker.protected then
      lurker.updatewrappers()
    end
  end


  function lurker.scan()
    lume.each(lurker.getchanged(), lurker.hotswapfile)
  end

  return lurker.init()
end
