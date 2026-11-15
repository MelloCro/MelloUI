"""Regression tests for CooldownText: python Tools/test_cooldown_text.py.

Requires lupa. Loads the real module against mock cooldown widgets. The native
object setter does not dispatch SetCooldown, as confirmed by the in-game probe.
Readable duration objects retain MelloUI's styling. Restricted objects must not
have their timing read, and unavailable getters must never leave stale numbers.
"""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "Modules/CooldownText.lua").read_text(encoding="utf-8-sig")

PRELUDE = r'''
now=1000
SlashCmdList={}
local queue={}
local function noop() end
function GetTime() return now end
function GetServerTime() return 1000000+now end
function wipe(t) for k in pairs(t) do t[k]=nil end end
C_Timer={After=function(delay,fn) queue[#queue+1]={at=now+delay,fn=fn} end}
function advance(seconds)
 local target=now+seconds
 while true do
  local index
  for i,job in ipairs(queue) do
   if job.at<=target and (not index or job.at<queue[index].at) then index=i end
  end
  if not index then break end
  local job=table.remove(queue,index);now=job.at;job.fn()
 end
 now=target
end
function hooksecurefunc(owner,name,after)
 local original=assert(owner[name],name)
 owner[name]=function(...) original(...);after(...) end
end
GameFontHighlightOutline={GetFont=function() return 'mock.ttf',12,'' end}
local function font()
 local f={shown=false,text=''}
 f.SetFontObject=noop;f.SetPoint=noop;f.SetJustifyH=noop
 function f:SetFont(path,size,flags) self.path=path;self.size=size;self.flags=flags end
 function f:SetTextColor(r,g,b) self.r=r;self.g=g;self.b=b end
 function f:SetText(text) self.text=text end
 function f:Show() self.shown=true end
 function f:Hide() self.shown=false end
 function f:IsShown() return self.shown end
 function f:GetText() return self.text end
 return f
end
local methods={}
function methods:SetCooldown(start,duration,rate)
 self.nativeEnd=start+duration/(rate or 1)
end
function methods:SetCooldownDuration(duration,rate) self.nativeEnd=now+duration/(rate or 1) end
function methods:SetCooldownUNIX(start,duration,rate) self.nativeEnd=start-1000000+duration/(rate or 1) end
-- Deliberately does not dispatch the public Lua SetCooldown method; native engine semantics are not verified here.
function methods:SetCooldownFromDurationObject(duration) self.nativeEnd=duration.expires end
function durationObject(seconds, rate)
 local d={start=now,seconds=seconds,rate=rate or 1,expires=now+seconds/(rate or 1)}
 function d:HasSecretValues() return false end
 function d:GetClock() return nil end
 function d:GetStartTime() return self.start end
 function d:GetTotalDuration() return self.seconds/self.rate end
 return d
end
function methods:Clear() self.nativeEnd=now end
function methods:SetHideCountdownNumbers(hidden) self.nativeHidden=hidden end
function methods:GetParent() return self.parent end
function methods:GetWidth() return 40 end
function methods:IsForbidden() return false end
function methods:CreateFontString() self.custom=font();return self.custom end
function CreateFrame() return setmetatable({nativeEnd=now,nativeHidden=false},{__index=methods}) end
UIParent={}
local scope={hooksecurefunc=hooksecurefunc,C_Timer=C_Timer}
MelloUI={Area={On=function() return true end,Listen=noop},Perf={Scope=function() return scope end},
 Meaning=setmetatable({},{__index=function() return {1,1,1} end}),Profile=noop}
function MelloUI:RegisterModule(name,spec)
 module={isEnabled=true,db=spec.defaults}
 return module
end
function newButton()
 local b={action=1,icon={}}
 b.cooldown=CreateFrame(); b.cooldown.parent=b
 return b
end
function visibleText(cd)
 if cd.custom and cd.custom.shown then return cd.custom.text end
 return nil
end
'''


def run(code, setup="", source=SOURCE):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(setup)
    lua.execute(source, "MelloUI", lua.table(MelloUI=lua.globals().MelloUI))
    lua.execute("module:OnEnable(module.db)")
    lua.execute(code)


# The exact update sequence reproduced in the real client: old custom number
# must update immediately and retain the custom styling, without waiting for a Clear.
STALE_CASE = '''
local cd=newButton().cooldown
cd:SetCooldown(now,25)
assert(visibleText(cd)=='25' and cd.nativeHidden)
cd:SetCooldownFromDurationObject(durationObject(10))
assert(visibleText(cd)=='10' and cd.nativeHidden==true)
assert(cd.nativeEnd-now==10)
advance(10.2)
assert(visibleText(cd)==nil and cd.nativeEnd<now)
'''
run(STALE_CASE)

# Object and numeric setters must use exactly the same custom text, fonts, size
# changes and colours, including settings, thresholds and speed modifiers.
for seconds, rate, tenths in ((10, 1, False), (4.3, 1, True), (61, 1, False),
                              (3601, 1, False), (10, 2, False), (1, 1, False)):
    run(f'''
module.db.tenths={str(tenths).lower()}
local normal,object=newButton().cooldown,newButton().cooldown
normal:SetCooldown(now,{seconds},{rate})
object:SetCooldownFromDurationObject(durationObject({seconds},{rate}))
local function compare()
 assert(visibleText(normal)==visibleText(object))
 assert(normal.nativeHidden==object.nativeHidden)
 if normal.custom then
  assert(object.custom and normal.custom.path==object.custom.path)
  assert(normal.custom.size==object.custom.size and normal.custom.flags==object.custom.flags)
  assert(normal.custom.r==object.custom.r and normal.custom.g==object.custom.g and normal.custom.b==object.custom.b)
 end
end
compare();advance(2.1);compare()
''', setup='''
MelloUI.Meaning.cooldownSoon={1,0,0}
MelloUI.Meaning.cooldownSeconds={1,1,0}
MelloUI.Meaning.cooldownMinutes={0.8,0.8,0.8}
''')

# A readable object replaces the pending timing too, when parenting finishes later.
run('''
local cd=CreateFrame()
cd:SetCooldown(now,25)
cd:SetCooldownFromDurationObject(durationObject(10))
cd.parent={cooldown=cd,action=1}
advance(0.2)
assert(visibleText(cd)=='10')
''')

# Restricted objects must not call timing getters. A separate non-default clock
# is also deliberately kept native, since MelloUI's numeric tick uses GetTime.
for restricted in (True, False):
    run(f'''
local cd=newButton().cooldown
cd:SetCooldown(now,25)
local d=durationObject(10)
function d:HasSecretValues() return {str(restricted).lower()} end
function d:GetClock() return {{}} end
function d:GetStartTime() error('timing must not be read') end
function d:GetTotalDuration() error('timing must not be read') end
cd:SetCooldownFromDurationObject(d)
assert(visibleText(cd)==nil and cd.nativeHidden==false)
''')

# Validate returned values before arithmetic even when the object's metadata says
# unrestricted. The numeric sentinel stands in for a client-marked secret value.
run('''
local cd=newButton().cooldown
cd:SetCooldown(now,25)
local d=durationObject(10)
function d:GetStartTime() return 1234 end
cd:SetCooldownFromDurationObject(d)
assert(visibleText(cd)==nil and cd.nativeHidden==false)
''', setup="function issecretvalue(v) return v==1234 end")

# Returning to a plain numeric update can start MelloUI's text again. A prior
# pending Clear must not erase that new timer on the next tick.
run('''
local cd=newButton().cooldown
cd:SetCooldown(now,25)
cd:Clear()
cd:SetCooldownFromDurationObject({expires=now+10})
cd:SetCooldown(now,8)
advance(0.2)
assert(visibleText(cd)=='8' and cd.nativeHidden)
''')

# Respect the caller's preference to hide native numbers, and do not touch
# unrelated cooldowns or invent a custom timer for a fresh duration object.
run('''
local cd=newButton().cooldown
cd:SetHideCountdownNumbers(true)
cd:SetCooldown(now,25)
cd:SetCooldownFromDurationObject({expires=now+10})
assert(visibleText(cd)==nil and cd.nativeHidden==true)
local changed=newButton().cooldown
changed:SetCooldown(now,25)
changed:SetHideCountdownNumbers(true)
changed:SetCooldownFromDurationObject({expires=now+10})
assert(visibleText(changed)==nil and changed.nativeHidden==true)
changed:SetHideCountdownNumbers(false)
changed:SetCooldown(now,25)
changed:SetHideCountdownNumbers(false)
changed:SetCooldownFromDurationObject({expires=now+10})
assert(visibleText(changed)==nil and changed.nativeHidden==false)
local fresh=newButton().cooldown
fresh:SetCooldownFromDurationObject({expires=now+10})
assert(fresh.custom==nil and fresh.nativeHidden==false)
local unrelated=CreateFrame()
unrelated:SetHideCountdownNumbers(true)
unrelated:SetCooldownFromDurationObject({expires=now+10})
assert(unrelated.custom==nil and unrelated.nativeHidden==true)
''')

# Abandon a pending classification retry when the object is not yet parented.
run('''
local cd=CreateFrame()
cd:SetCooldown(now,25)
cd:SetCooldownFromDurationObject({expires=now+10})
cd.parent={cooldown=cd,action=1}
advance(0.2)
assert(visibleText(cd)==nil and cd.nativeHidden==false)
''')

# The callback must not inspect an opaque duration object. Only the simulated
# native setter knows its timing; any field read by the module raises.
run('''
local cd=newButton().cooldown
cd:SetCooldown(now,25)
local opaque=setmetatable({}, {__index=function() error('duration inspected') end})
cd:SetCooldownFromDurationObject(opaque)
assert(visibleText(cd)==nil and cd.nativeHidden==false)
''', setup='''
getmetatable(CreateFrame()).__index.SetCooldownFromDurationObject=function(self, duration)
 self.nativeEnd=now+10
end
''')

# Numeric setters and speed modifiers retain their previous behaviour.
run('''
local cd=newButton().cooldown
cd:SetCooldown(now,10)
assert(visibleText(cd)=='10')
cd:SetCooldown(now,10,2)
assert(visibleText(cd)=='5')
cd:SetCooldownDuration(10)
assert(visibleText(cd)=='10')
cd:SetCooldownUNIX(GetServerTime(),12)
assert(visibleText(cd)=='12')
cd:Clear();advance(0.2)
assert(visibleText(cd)==nil and cd.nativeHidden==false)
''')

# Older clients with no duration-object setter can still install all other hooks.
run("local cd=newButton().cooldown;cd:SetCooldown(now,10);assert(visibleText(cd)=='10')",
    setup="getmetatable(CreateFrame()).__index.SetCooldownFromDurationObject=nil")

if __name__ == "__main__":
    print("PASS: readable object updates retain custom styling; restricted/unsupported timing drops stale text; visibility, retries, rates and numeric setters remain correct")
