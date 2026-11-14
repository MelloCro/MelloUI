"""Exercise the MaxDPS bridge in Lua 5.1 without WoW: python Tools/test_maxdps.py.

Requires lupa. MaxDPS's spell-to-button registration and event-driven fetch are
stubbed; no rotation logic or protected action-button behaviour is simulated.
"""
from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
lua = LuaRuntime()
lua.execute('''
local listeners = {}
local scope = {}
hookCount = 0
function scope.hooksecurefunc(owner, key, after)
    hookCount = hookCount + 1
    local original = owner[key]
    owner[key] = function(...)
        original(...)
        after(...)
    end
end
function scope.SetScript(frame, key, callback) frame[key] = callback end
function CreateFrame()
    eventFrame = {RegisterEvent=function() end, UnregisterEvent=function() end}
    return eventFrame
end
function button(name, slot)
    return {action=slot, GetName=function() return name end}
end
barsOn, useIntegration = true, true
local own = {own={}, mine={}, Actions={shows={}}, Pad={on=false}}
function own.On() return barsOn end
MelloUI = {
    OwnBars=own,
    Integrations={Use=function() return useIntegration end},
    Safe={
        Finite=function(v) if type(v)=='number' and v==v and math.abs(v)<math.huge then return v end end,
        Text=function(v) if type(v)=='string' then return v end end,
    },
    Perf={Scope=function() return scope end},
}
function MelloUI:On(event, callback) listeners[event] = callback end
function MelloUI:Fire(event, ...) if listeners[event] then listeners[event](...) end end
function installMaxDps()
    MaxDps = {Spells={}, rotationEnabled=true, fetches=0, sources={}}
    function MaxDps:AddButton(spell, frame)
        self.Spells[spell] = self.Spells[spell] or {}
        table.insert(self.Spells[spell], frame)
    end
    function MaxDps:ButtonFetch()
        if not self.rotationEnabled then return end
        self.fetches = self.fetches + 1
        self.Spells = {}
        for _, source in ipairs(self.sources) do self:AddButton(source.spell, source.frame) end
    end
end
function count(spell, frame)
    local n=0
    for _, b in ipairs(MaxDps.Spells[spell] or {}) do if b==frame then n=n+1 end end
    return n
end
''')
lua.execute((ROOT / "Modules/MaxDps.lua").read_text(encoding="utf-8-sig"), "MelloUI", lua.table(MelloUI=lua.globals().MelloUI))
lua.execute('''
-- Optional addon absent, then loaded later; unrelated addons do not install hooks.
eventFrame.OnEvent(eventFrame, 'PLAYER_LOGIN')
eventFrame.OnEvent(eventFrame, 'ADDON_LOADED', 'OtherAddon')
assert(hookCount==0)
installMaxDps()
local original = button('ActionButton1', 1)
local replacement = button('MelloUIActionBar1Button1', 1)
local other = button('OtherAddonButton', 2)
local display = button('MelloUIPadDisplay', 1)
local own=MelloUI.OwnBars
own.own.ActionButton1=replacement
own.mine[replacement],own.mine[display]=true,true
own.Actions.shows={display}
MaxDps.sources={{spell=100,frame=original},{spell=200,frame=other}}
eventFrame.OnEvent(eventFrame, 'ADDON_LOADED', 'MaxDps')
assert(hookCount==1 and count(100,replacement)==1)
assert(count(200,other)==1 and count(200,replacement)==0)
assert(count(100,display)==0)
-- Repeated registration, another refresh and controller activation neither recurse nor duplicate ours.
MaxDps:AddButton(100,original)
assert(count(100,replacement)==1)
own.Pad.on=true
MelloUI:Fire('ownbars','actions',true)
assert(hookCount==1 and count(100,replacement)==1 and count(100,display)==1)
-- A form/page change supplies a new spell mapping, without keeping the old recommendation.
original.action,replacement.action,display.action=73,73,73
MaxDps.sources[1].spell=300
MaxDps:ButtonFetch()
assert(not MaxDps.Spells[100] and count(300,replacement)==1 and count(300,display)==1)
-- Controller-only slot changes refresh the mapping as well.
display.action=2
MelloUI:Fire('ownbars:padslots')
assert(count(300,display)==0 and count(200,display)==1)
-- Giving the bars back removes our mappings; returning them and the integration toggle work.
barsOn=false
MelloUI:Fire('ownbars','actions',false)
assert(count(300,replacement)==0 and count(300,original)==1)
barsOn=true; useIntegration=false
MaxDps:ButtonFetch()
assert(count(300,replacement)==0)
useIntegration=true
MaxDps:ButtonFetch()
assert(count(300,replacement)==1)
-- No rotation is started by a bars event while MaxDPS is disabled.
MaxDps.rotationEnabled=false
local fetches=MaxDps.fetches
MelloUI:Fire('ownbars','actions',true)
assert(MaxDps.fetches==fetches)
''')
print("PASS: MaxDPS late loading, spell mapping, duplicate prevention, page/form changes, controller slots, bar lifecycle and opt-out")
