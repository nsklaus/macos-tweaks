--[[

HAMMERSPOON init.lua for docklower

this creates a real "lower window" for macos, like on linux.
MMB click on a window titlebar sends the window to the back of the stack.
there's a special case for brave browser tabs, MMB click closes tab,
and MMB clicking elsewhere on the window titlebar but,
not on a tab does lower the window as for the other windows.

]] 


local defaultHeight = 28
-- title bar zone height per app (bundle ID)
local appHeight = {
  ["com.brave.Browser"] = 40,
}
-- apps where we check what is under the cursor (tabs, buttons)
local axCheck = {
  ["com.brave.Browser"] = true,
}

-- Chromium only builds its accessibility tree on request
local function enableAX(app)
  if app and axCheck[app:bundleID()] then
    hs.axuielement.applicationElement(app):setAttributeValue("AXManualAccessibility", true)
  end
end

for bid in pairs(axCheck) do
  for _, app in ipairs(hs.application.applicationsForBundleID(bid)) do
    enableAX(app)
  end
end

axWatcher = hs.application.watcher.new(function(_, event, app)
  if event == hs.application.watcher.launched then enableAX(app) end
end)
axWatcher:start()

local function contains(f, pos)
  return f and pos.x >= f.x and pos.x <= f.x + f.w and pos.y >= f.y and pos.y <= f.y + f.h
end

local function sameFrame(a, b)
  return a and b and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- true if the cursor is on one of Brave's tabs or buttons.
-- Brave's tab strip only exposes anonymous AXGroups: the tabs sit in a group wrapped by
-- another group with the same frame, the empty strip after them does not.
-- Only AXRole, AXFrame and AXParent are read: AXChildren on the tab strip can block for seconds.
local function onControl(pos, winFrame)
  local el = hs.axuielement.systemElementAtPosition(pos.x, pos.y)
  if not el then return false end
  local role = el:attributeValue("AXRole")
  if role == "AXRadioButton" or role == "AXButton" then return true end
  local ef = el:attributeValue("AXFrame")
  -- the groups spanning the whole window are wrapped the same way: not a tab
  if not ef or ef.w >= winFrame.w then return false end
  local parent = el:attributeValue("AXParent")
  return sameFrame(ef, parent and parent:attributeValue("AXFrame")) or false
end

local function titlebarWindow(pos)
  for _, win in ipairs(hs.window.orderedWindows()) do
    local f = win:frame()
    if contains(f, pos) then
      local app = win:application()
      local bid = app and app:bundleID()
      local h = appHeight[bid] or defaultHeight
      if pos.y > f.y + h then return nil end
      if axCheck[bid] and onControl(pos, f) then return nil end
      return win
    end
  end
end

-- true lower, done by the docklower tweak inside the Dock
local function lower(win)
  hs.distributednotifications.post("org.nsklaus.docklower", tostring(win:id()))
end

local types = hs.eventtap.event.types
-- window picked on press, lowered on release (nil = click passed to the app)
local pending = nil

middleClick = hs.eventtap.new({types.otherMouseDown, types.otherMouseUp}, function(event)
  if event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) ~= 2 then
    return false
  end

  if event:getType() == types.otherMouseDown then
    pending = titlebarWindow(event:location())
    return pending ~= nil
  end

  -- release
  local top = pending
  pending = nil
  if not top then return false end
  lower(top)
  return true
end)
middleClick:start()