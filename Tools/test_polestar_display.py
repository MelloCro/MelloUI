"""Simulate the guide display handover; this is not an in-game UI test.

Run with Python and lupa installed: python Tools/test_polestar_display.py
"""
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SETUP = r'''
combat = false
frames = {}
events = {}
waypoint = nil
clears = 0
function InCombatLockdown() return combat end
function hooksecurefunc(obj, key, hook)
    local old = obj[key]
    obj[key] = function(self, value) old(self, value); hook(self, value) end
end
function CreateFrame()
    local f = {alpha=0.8, scale=1.2, scripts={}, registered={}}
    function f:SetAlpha(v) self.alpha=v end
    function f:GetAlpha() return self.alpha end
    function f:SetScale(v) self.scale=v end
    function f:GetScale() return self.scale end
    function f:IsProtected() return true end
    function f:SetScript(k,v) self.scripts[k]=v end
    function f:RegisterEvent(k) self.registered[k]=true end
    function f:UnregisterEvent(k) self.registered[k]=nil end
    frames[#frames+1] = f
    return f
end
PolestarGuideFrame = CreateFrame()
PolestarNavArrow = CreateFrame()
PolestarQuestItemButton = CreateFrame()
PolestarHearthButton = CreateFrame()
nativeFrames = {PolestarGuideFrame, PolestarNavArrow, PolestarQuestItemButton, PolestarHearthButton}
local settings = {['nav.minimapPins']=true}
Polestar = {Get=function(k) return settings[k] end, Set=function(k,v) settings[k]=v end}
C_Map = {
    HasUserWaypoint=function() return waypoint ~= nil end,
    GetUserWaypoint=function() return waypoint end,
    ClearUserWaypoint=function() waypoint=nil; clears=clears+1 end,
    SetUserWaypoint=function(p) waypoint=p end,
}
UiMapPoint = {CreateFromCoordinates=function(m,x,y) return {uiMapID=m,position={x=x,y=y}} end}
M = {isEnabled=true, db={followGuide=true}, VectorXY=function(p) return p.x,p.y end}
timers={After=function(_,fn) fn() end}
MelloUI = {
    Safe={CreateFrame=CreateFrame, Value=function(v) return v end,
        Text=function(v) return type(v)=='string' and v or nil end,
        Finite=function(v) return type(v)=='number' and v or nil end},
    Perf={Scope=function() return {hooksecurefunc=hooksecurefunc, C_Timer=timers} end},
    GetModule=function() return M end,
    On=function() end,
    Fire=function(_,key,data) events[key]={data=data} end,
}
'''


def world(native=False, both=False):
    lua = LuaRuntime()
    lua.execute(SETUP)
    lua.globals().M.db.polestarNative = native
    lua.globals().M.db.polestarBoth = both
    lua.execute((ROOT / 'MelloUI_Route/Guides.lua').read_text(encoding='utf-8-sig'))
    lua.execute(r'''
        G = M.Guide
        for _,r in ipairs(G.readers) do if r.key=='polestar' then P=r end end
        P.hooked=true
        P.Point=function() return 1,0.25,0.5 end
        P.OriginalSteps=P.Steps
        P.Steps=function() return {title='Guide step',lines={{text='Goal'}}} end
        P.Items=function() return {{kind='item',id=123}} end
        P.Goals=function() return {{key='goal',text='Goal',cont=1,places={1,2}}} end
        GetItemCount=function() return 1 end
        G.Refresh()
    ''')
    return lua


lua = world()
lua.execute(r'''
    assert(G.active==P and events.guide.data and events.guideitem.data and events.guidegoals.data)
    assert(waypoint and not Polestar.Get('nav.minimapPins'))
    for _,f in ipairs(nativeFrames) do assert(f.alpha==0 and f.scale==0.001) end
    G.SetPolestarNative(true)
    assert(G.PolestarNative() and G.ArrowShown('polestar') and M.db.guideArrow_polestar==true)
    assert(not G.active and not events.guide.data and not events.guideitem.data and not events.guidegoals.data)
    assert(waypoint==nil and clears==1 and M.db.guidePin==nil)
    assert(Polestar.Get('nav.minimapPins'))
    for _,f in ipairs(nativeFrames) do assert(f.alpha==0.8 and f.scale==1.2) end
    G.Changed(P) -- native guide updates cannot take over MelloUI's tracker again
    assert(not G.active and not events.guide.data)
    G.SetArrowShown('polestar',false)
    assert(G.ArrowShown('polestar')) -- native presentation retains its arrow
    G.SetPolestarNative(false)
    assert(not G.PolestarNative() and not G.ArrowShown('polestar'))
    assert(G.active==P and waypoint and events.guide.data and events.guideitem.data and events.guidegoals.data)
    for _,f in ipairs(nativeFrames) do assert(f.alpha==0 and f.scale==0.001) end
    G.SetArrowShown('polestar',true) -- the existing optional arrow still works in MelloUI mode
    assert(PolestarNavArrow.alpha==0.8 and PolestarGuideFrame.alpha==0)
    waypoint={uiMapID=2,position={x=0.7,y=0.8}}
    G.SetPolestarNative(true)
    assert(waypoint.uiMapID==2 and clears==1) -- preserve a player's waypoint
''')

lua = world(native=True)
lua.execute(r'''
    assert(G.PolestarNative() and G.ArrowShown('polestar') and not G.active and waypoint==nil)
    for _,f in ipairs(nativeFrames) do assert(f.alpha==0.8 and f.scale==1.2) end
    G.SetPolestarNative(false)
    combat=true
    G.SetPolestarNative(true)
    for _,f in ipairs(nativeFrames) do assert(f.alpha==0) end -- secure changes wait
    combat=false
    for _,f in ipairs(frames) do
        if f.registered.PLAYER_REGEN_ENABLED then f.scripts.OnEvent(f) end
    end
    for _,f in ipairs(nativeFrames) do assert(f.alpha==0.8 and f.scale==1.2) end
    -- Other guide readers and their independent arrow settings keep working.
    other={key='rxp',hooked=true,Point=function() return 3,0.4,0.6 end,
        Steps=function() return {title='Other guide',lines={{text='Other goal'}}} end}
    G.readers[#G.readers+1]=other
    M.db.guideArrow_rxp=true
    G.Refresh()
    assert(G.active==other and events.guide.data.title=='Other guide' and G.ArrowShown('rxp'))
''')
# Profile refreshes and Polestar's optional TomTom arrow use the same handover path.
lua = world()
lua.execute(r'''
    M.db.polestarNative=true
    G.Refresh()
    assert(not G.active and waypoint==nil and clears==1)
    assert(M.db.guideArrow_polestar and not events.guide.data)
    TomTomCrazyArrow=CreateFrame()
    Polestar.Nav={UsingTomTomArrow=function() return true end}
    for _,r in ipairs(G.readers) do if r.key=='tomtom' then T=r end end
    T.hooked=true
    T.Point=function() return 1,0.25,0.5 end
    T.Steps=function() return {title='TomTom',lines={{text='Arrow target'}}} end
    G.Refresh()
    assert(not G.active and TomTomCrazyArrow.alpha==0.8)
    G.SetPolestarNative(false)
    assert(G.active==P and TomTomCrazyArrow.alpha==0)
    G.SetPolestarNative(true)
    assert(not G.active and TomTomCrazyArrow.alpha==0.8)
    -- An independent TomTom waypoint remains available when Polestar isn't using its arrow.
    Polestar.Nav.UsingTomTomArrow=function() return false end
    G.Refresh()
    assert(G.active==T)
''')
# Scale-dependent layout can run while MelloUI veils the window. Model Polestar's
# screen-height cap and retained frame height; the real game font/layout engine is not simulated.
for deferred in (False, True):
    lua = world()
    lua.execute(r'''
        layoutCalls=0
        local gf={frame=PolestarGuideFrame}
        function gf.Layout()
            if expectRestored then
                for _,f in ipairs(nativeFrames) do assert(f.scale==1.2, 'layout ran before restoration finished') end
            end
            layoutCalls=layoutCalls+1
            gf.height=math.min(1600,1080*0.5/math.max(0.01,gf.frame:GetScale()))
        end
        Polestar.UI={GuideFrame=gf}
        gf.Layout() -- a step refresh while veiled caches an oversized window
        assert(gf.height==1600)
        expectRestored=true
    ''')
    lua.globals().combat = deferred
    lua.execute('G.SetPolestarNative(true)')
    if deferred:
        lua.execute(r'''
            assert(layoutCalls==1, 'layout must wait for protected frame restoration')
            combat=false
            for _,f in ipairs(frames) do
                if f.registered.PLAYER_REGEN_ENABLED then f.scripts.OnEvent(f) end
            end
        ''')
    lua.execute(r'''
        assert(Polestar.UI.GuideFrame.height==450, 'native window kept its veiled layout')
        assert(layoutCalls==2, 'expected one layout refresh on window release')
        G.Refresh()
        G.Veil()
        assert(layoutCalls==2, 'ordinary guide updates must not repeatedly lay out a native window')
        G.SetPolestarNative(false)
        G.SetArrowShown('polestar',true)
        assert(layoutCalls==2, 'releasing just the arrow must not lay out the guide window')
        -- Optional or changed Polestar layout APIs must not break the handover.
        Polestar.UI.GuideFrame.Layout=nil
        G.SetPolestarNative(true)
        assert(not G.active and events.guide.data==nil)
    ''')
# Exercise the real Polestar reader (the earlier handover fixtures deliberately use synthetic steps).
lua = world()
lua.execute(r'''
    P.Steps=P.OriginalSteps
    local function node(text,top,parent,shown)
        local f={text=text,top=top or 0,left=0,parent=parent,shown=shown~=false,children={},regions={}}
        function f:IsShown() return self.shown end
        function f:GetText() return self.text end
        function f:GetObjectType() return self.text and "FontString" or "Frame" end
        function f:GetTop() return self.top end
        function f:GetLeft() return self.left end
        function f:GetEffectiveScale() return 0.001 end -- MelloUI's veil must not hide readable text
        function f:GetParent() return self.parent end
        function f:GetChildren() return table.unpack(self.children) end
        function f:GetRegions() return table.unpack(self.regions) end
        if parent then parent.children=parent.children or {}; parent.children[#parent.children+1]=f end
        return f
    end
    root=PolestarGuideFrame
    body=node(nil,900,root)
    card=node(nil,850,body)
    person=node(nil,840,card)
    person.Name=node('Speak to the innkeeper',840,person)
    person.Where=node('Riverglades',825,person)
    row=node(nil,800,card)
    goal={index=1,text='Hearthstone',status='active',tickable=true}
    row.psGoal=goal
    row.Icon={GetTexture=function() return 'QuestTurnIn' end}
    row.Text=node('|Hitem:6948|h[Hearthstone]|h  1/1',800,row)
    node('Use it to return home',780,row)
    tip=node(nil,760,card)
    node('Author instructions\nSecond paragraph',760,tip)
    hidden=node(nil,750,body,false)
    node('Hidden panel must stay hidden',745,hidden)
    travel=node('Travel: flight then walk',720,body)
    party=node('Party: waiting for a member',700,body)
    xp=node('XP: 42,000 to go',680,body)
    node('Up next: turn in the quest',660,body)
    foot=node('24%',640,root)
    foot.Pct=foot;foot.psDone=12;foot.psTotal=50
    node('Separate options window',950,nil) -- never part of the exposed guide
    local parts={window=root,body=body,card=card,person=person,tip=tip,rows={row},foot=foot,here=hidden}
    view={current=1,title='Return home',note='Author instructions',goals={goal},section={title='Chapter 1'},why='Training is due'}
    step=12
    toggles=0
    Polestar.Engine={GetStepIndex=function() return step end,GetStepView=function() return view end,
        GetGuide=function() return {title='Leveling'} end,GetStepCount=function() return 50 end,
        GetLiveStep=function() return step end,ToggleGoal=function(i,g) assert(i==12 and g==1); toggles=toggles+1 end}
    Polestar.UI={JourneyPanel={frame=travel},GuideFrame={party=party,xp=xp,SkinParts=function() return parts end,ShownStep=function() return step end,State=function() return 'steps' end}}
    hideCalls={}
    Polestar.Hidden=function() return polestarHidden==true end
    Polestar.SetHidden=function(on) hideCalls[#hideCalls+1]=on;polestarHidden=on end
    local function Find(result,text)
        for j,line in ipairs(result.lines) do if line.text==text then return line,j end end
        error('Missing content: '..text)
    end
    local result=P.Steps()
    assert(result.presentation=='polestar' and result.label=='Leveling' and result.counter=='12 / 50')
    assert(Find(result,'Speak to the innkeeper').role=='lead')
    for _,line in ipairs(result.lines) do assert(line.text~='Current step' and line.text~='Objectives' and line.text~='Notes') end
    local objective=Find(result,'|Hitem:6948|h[Hearthstone]|h  1/1')
    assert(objective.role=='objective' and objective.box and objective.current and objective.icon=='QuestTurnIn')
    objective.Toggle(true)
    assert(toggles==1)
    assert(Find(result,'Use it to return home').role=='detail')
    assert(objective.group==1 and Find(result,'Use it to return home').group==1)
    assert(Find(result,'Author instructions\nSecond paragraph').role=='note')
    assert(Find(result,'24%').progress==0.24)
    local _,goalAt=Find(result,objective.text)
    local _,noteAt=Find(result,'Author instructions\nSecond paragraph')
    local _,progressAt=Find(result,'24%')
    assert(goalAt<noteAt and noteAt<progressAt)
    -- Profession section headings precede the NPC, although they belong to the goal card.
    card.Section=node('Cooking 130-175',860,card)
    result=P.Steps()
    local heading=Find(result,'Cooking 130-175')
    assert(result.lines[1]==heading and heading.role=='lead' and not heading.ruleBefore,
        'profession section heading must precede the NPC header')
    G.SetPolestarBoth(true)
    assert(P.Steps().lines[1].text=='Cooking 130-175')
    G.SetPolestarBoth(false)
    person.shown=false
    result=P.Steps()
    assert(result.lines[1].text=='Cooking 130-175' and result.lines[2].text=='Return home')
    person.shown=true
    card.Section.shown=false
    assert(P.Steps().lines[1].text=='Speak to the innkeeper')
    -- No writes to native UI or guide settings while reading. Extra context cannot replace the current goal label.
    assert(root.alpha==0 and body.shown and card.shown and tip.shown)
    G.Refresh()
    assert(events.guide.data and G.stepText==objective.text)
    assert(type(events.guide.data.SetCollapsed)=='function')
    events.guide.data.SetCollapsed(true)
    assert(polestarHidden==true and hideCalls[1]==true)
    events.guide.data.SetCollapsed(false)
    assert(polestarHidden==false and hideCalls[2]==false)
    local hideAPI=Polestar.SetHidden
    Polestar.SetHidden=nil
    assert(not P.Steps().SetCollapsed, 'older versions keep tracker-only collapse')
    Polestar.SetHidden=hideAPI
    local old=events.guide.data
    foot.text='26%';foot.psDone=13
    G.Changed(P)
    assert(events.guide.data~=old and Find(events.guide.data,'26%'))
    -- A hidden ancestor still hides a separately exposed root.
    card.shown=false
    result=P.Steps()
    for _,line in ipairs(result.lines) do assert(line.text~='Speak to the innkeeper') end
    assert(Find(result,'Travel: flight then walk'))
    card.shown=true
    -- Inert action captions are excluded; inline native theme colours cannot destroy tracker contrast.
    local skip=node(nil,620,row)
    node('Skip this goal',620,skip)
    row.Skip=skip
    row.Text.text='|cff000000|Hitem:6948|h[Hearthstone]|h  1/1|r'
    result=P.Steps()
    assert(Find(result,objective.text))
    for _,line in ipairs(result.lines) do assert(line.text~='Skip this goal') end
    -- Only the authored guide picture is transferred; decorative icons are not.
    local image=node(nil,755,tip)
    function image:GetObjectType() return 'Texture' end
    function image:GetTexture() return 'Interface/Picture' end
    function image:GetWidth() return 360 end
    function image:GetHeight() return 200 end
    tip.Image=image
    result=P.Steps()
    assert(Find(result,'|TInterface/Picture:100:180|t').role=='note')
    image.shown=false
    -- Reproduce the screenshot's journey layout: header and row values occupy separate native font strings.
    local jp=Polestar.UI.JourneyPanel
    travel.text=nil
    jp.head=node(nil,100,travel)
    jp.head.Label=node('Journey',90,jp.head)
    jp.head.Time=node('5:39',110,jp.head)
    jp.head.Dot=node('.',105,jp.head)
    jp.head.Dist=node('6.0k yd',95,jp.head)
    local list=node(nil,80,travel)
    jp.dest=node('To Turn in "My Kingdom for a Horse"',75,list)
    jp.rows={}
    for k,caption in ipairs({'Walk to the flight master','Fly to Farholde Keep','Turn in "My Kingdom for a Horse"'}) do
        local leg=node(nil,70-k*10,list)
        leg.psCurrent=k==1
        leg.Num=node(tostring(k),68-k*10,leg)
        leg.Time=node(({'0:28','4:08','1:03'})[k],67-k*10,leg)
        leg.Text=node(caption,66-k*10,leg)
        leg.Sub=node('Hostile town: avoid the guards',65-k*10,leg,k==2)
        jp.rows[k]=leg
    end
    jp.more=node('1 more step',20,list,false)
    jp.Refresh=function() end
    result=P.Steps()
    assert(Find(result,'Journey').right=='5:39 \194\183 6.0k yd')
    local first,firstAt=Find(result,'Walk to the flight master')
    local second,secondAt=Find(result,'Fly to Farholde Keep')
    assert(first.number=='1' and first.right=='0:28' and second.number=='2' and second.right=='4:08' and firstAt<secondAt)
    assert(Find(result,'Hostile town: avoid the guards').role=='detail')
    for _,line in ipairs(result.lines) do
        assert(line.text~='.' and line.text~='5:39' and line.text~='1' and line.text~='0:28')
    end
    -- Preserve Polestar's number and expand/collapse settings, and never repeat stale pooled rows.
    jp.rows[1].Num.shown=false
    jp.rows[3].shown=false
    result=P.Steps()
    assert(Find(result,'Walk to the flight master').number==nil)
    for _,line in ipairs(result.lines) do assert(line.text~='Turn in "My Kingdom for a Horse"') end
    list.shown=false
    result=P.Steps()
    Find(result,'Journey')
    for _,line in ipairs(result.lines) do assert(line.role~='route') end
    list.shown=true
    -- Read-only foot/status updates are coalesced after Polestar renders, even without a step event.
    queue={}; callbacks=0
    timers.After=function(_,fn) queue[#queue+1]=fn end
    local listeners={}
    Polestar.On=function(key,fn) listeners[key]=fn end
    Polestar.UI.GuideFrame.Layout=function() end
    Polestar.UI.GuideFrame.UpdateXP=function() end
    assert(P.Hook(function() callbacks=callbacks+1 end))
    listeners.STEP_UPDATED()
    listeners.SETTING_CHANGED()
    assert(listeners.POLESTAR_HIDDEN)
    listeners.POLESTAR_HIDDEN(true)
    Polestar.UI.GuideFrame.Layout()
    Polestar.UI.GuideFrame.UpdateXP()
    jp.Refresh()
    assert(#queue==1 and callbacks==0)
    queue[1]()
    assert(callbacks==1)
    M.db.polestarNative=true
    Polestar.UI.GuideFrame.Layout()
    assert(#queue==1, 'native mode must not schedule tracker reads')
    M.db.polestarNative=false
    -- Section disclosures use the original Polestar settings and retain full text behind a closed note.
    result=P.Steps()
    local note=Find(result,'Author instructions\nSecond paragraph')
    assert(note.Collapse and note.singleLine and not note.expanded)
    note.Collapse()
    result=P.Steps()
    assert(Find(result,'Author instructions\nSecond paragraph').expanded)
    local journeyHead=Find(result,'Journey')
    journeyHead.Collapse()
    assert(Polestar.Get('nav.journeyOpen')==true)
    -- A skin can supply a different percentage region; cached native progress may also be pending.
    foot.psDone=nil;foot.psTotal=nil;foot.Pct=nil;foot.text='28%'
    result=P.Steps()
    assert(Find(result,'28%').progress==0.28)
    -- Native font faces, text colours and icon tint survive the content bridge.
    row.Text.text='|Hitem:6948|h[Hearthstone]|h  1/1'
    local nativeSize=14
    function row.Text:GetFont() return 'Fonts/FRIZQT__.TTF',nativeSize,'' end
    function row.Text:GetTextColor() return 1,0.84,0.45,1 end
    function row.Icon:GetVertexColor() return 1,0.8,0,1 end
    Polestar.Theme={SkinKey=function() return 'forever' end,Palette=function() return 'palette-a' end}
    local nativePad=18
    Polestar.Theme.Metric=function(key,fallback)
        if key=='guideLitInset' then return 10 end
        if key=='guideCheckMiddle' then return true end
        return fallback
    end
    function root:GetEffectiveScale() return self:GetScale()*0.8 end
    Polestar.UI.GuideFrame.Metrics=function()
        return {pad=nativePad,textX=nativePad+24,tabH=30,navH=32,progH=28,icon=15,
            rowMin=22,check=15,rowPad=4,checkIn=10,upRow=20,upToggle=26,glyphY=16}
    end
    Polestar.Guides={Get=function(id) return {id=id,minLevel=41,maxLevel=45} end}
    Polestar.UI.GuideLevels=function() return '41-45' end
    Polestar.Engine.GetTabs=function() return {{guideId='a',title='Riverglades'},{guideId='b',title='Second'}},1 end
    selected,closed=nil,nil
    Polestar.Engine.SelectTab=function(index) selected=index end
    Polestar.Engine.CloseTab=function(index) closed=index end
    local picker
    Polestar.UI.ShowPicker=function(options) picker=options end
    parts.nav={Steps={Count=row.Text},Skip={Label=row.Text}}
    Polestar.UI.GuideFrame.tabs={{Label=row.Text,Range=row.Text}}
    result=P.Steps()
    local styled=Find(result,row.Text.text)
    assert(styled.font=='Fonts/FRIZQT__.TTF' and styled.colour[2]==0.84 and styled.iconColour[2]==0.8)
    assert(styled.fontInfo.size==14 and styled.fontInfo.scale==1)
    -- The native window's real scale survives our veil and comparison-mode handover.
    Polestar.UI.GuideFrame.scale=1.2
    function row.Text:GetEffectiveScale() return root:GetScale()*0.8 end
    local veiled=Find(P.Steps(),row.Text.text).fontInfo
    assert(math.abs(veiled.scale-0.96)<0.00001)
    G.SetPolestarBoth(true)
    local visible=Find(P.Steps(),row.Text.text).fontInfo
    assert(visible.size==veiled.size and math.abs(visible.scale-veiled.scale)<0.00001)
    G.SetPolestarBoth(false)
    -- A size-only change publishes once; fresh font metadata tables do not cause repeated updates.
    G.Changed(P)
    local beforeSize=events.guide.data
    assert(beforeSize.fonts.counter.size==14 and beforeSize.tabs[1].fontInfo.size==14)
    assert(beforeSize.metrics.pad==18 and beforeSize.metrics.litInset==10 and beforeSize.metrics.checkMiddle)
    assert(math.abs(beforeSize.metrics.scale-0.96)<0.00001)
    nativeSize=16
    G.Changed(P)
    assert(events.guide.data~=beforeSize and Find(events.guide.data,row.Text.text).fontInfo.size==16)
    local afterSize=events.guide.data
    assert(afterSize.fonts.counter.size==16 and afterSize.fonts.control.size==16)
    G.Changed(P)
    assert(events.guide.data==afterSize)
    nativePad=20
    G.Changed(P)
    assert(events.guide.data~=afterSize and events.guide.data.metrics.pad==20)
    local afterPadding=events.guide.data
    G.Changed(P)
    assert(events.guide.data==afterPadding)
    nativePad=18
    assert(#result.tabs==2 and result.tabs[1].levels=='41-45' and result.tabs[1].active)
    result.tabs[2].Select();result.tabs[1].Close();result.AddTab()
    assert(selected==2 and closed==1 and picker.newTab)
    -- Both cache layers must react when only a tab's font face changes.
    local tabFace='Fonts/First.ttf'
    Polestar.UI.GuideFrame.tabs[1].Label={GetFont=function() return tabFace,14,'' end,GetEffectiveScale=function() return 1 end}
    G.Changed(P)
    local firstFont=events.guide.data
    tabFace='Fonts/Second.ttf'
    G.Changed(P)
    assert(events.guide.data~=firstFont and events.guide.data.tabs[1].fontInfo.face==tabFace)
    local sameFont=events.guide.data
    G.Changed(P)
    assert(events.guide.data==sameFont, 'fresh action closures must not invalidate an unchanged view')
    local fingerprint={lines={{text='Caption',ruleAfter=false,fontInfo={face='A',size=12,scale=1}}}}
    local first=G.SnapshotSignature(fingerprint)
    fingerprint.lines[1].ruleAfter=true
    assert(G.SnapshotSignature(fingerprint)~=first)
    first=G.SnapshotSignature(fingerprint)
    fingerprint.lines[1].fontInfo.face='B'
    assert(G.SnapshotSignature(fingerprint)~=first)
    first=G.SnapshotSignature(fingerprint)
    fingerprint.lines[1].Open=function() end
    assert(G.SnapshotSignature(fingerprint)~=first)
    first=G.SnapshotSignature(fingerprint)
    fingerprint.lines[1].Open=function() end
    assert(G.SnapshotSignature(fingerprint)==first)
    -- Native visibility changes must publish even when the guide content stays identical.
    polestarHidden=true
    G.Changed(P)
    assert(events.guide.data.collapsed==true and events.guide.data.GetCollapsed()==true)
    polestarHidden=false
    G.Changed(P)
    assert(events.guide.data.collapsed==false and events.guide.data.GetCollapsed()==false)
    Polestar.Theme=nil
    -- Stale rendered steps use the model until Polestar's next render.
    Polestar.UI.GuideFrame.ShownStep=function() return 11 end
    Polestar.UI.GoalLine=function(g) return 'Use '..g.text end
    Polestar.UI.GoalSubline=function() return 'Cooldown: ready' end
    result=P.Steps()
    assert(Find(result,'Chapter 1').role=='section' and Find(result,'Return home').role=='lead')
    assert(Find(result,'Training is due').role=='detail' and Find(result,'Use Hearthstone').role=='objective')
    assert(Find(result,'Cooldown: ready').role=='detail' and Find(result,'Author instructions').role=='note')
    -- A complete guide can still publish its native completion text with no current step view.
    Polestar.UI.GuideFrame.State=function() return 'complete' end
    Polestar.Engine.GetStepView=function() return nil end
    result=P.Steps()
    assert(Find(result,'Speak to the innkeeper')) -- fixture stands in for the completion card
    Polestar.Engine.GetStepView=function() return view end
    -- Future/changed window APIs keep the same fallback; notes-only steps remain readable.
    Polestar.UI.GuideFrame.SkinParts=function() error('changed API') end
    view={title='Read this',note='Only a note',goals={}}
    result=P.Steps()
    assert(Find(result,'Notes').role=='section' and Find(result,'Only a note').role=='note')
    -- Guide-completion and unavailable-guide messages are readable even without a step view.
    view=nil
    step=nil
    jp.frame.shown=false
    parts.body=node('Guide complete',500,root)
    parts.card=nil;parts.person=nil;parts.tip=nil;parts.rows={};parts.foot=nil;parts.here=nil
    Polestar.UI.GuideFrame.SkinParts=function() return parts end
    Polestar.UI.GuideFrame.State=function() return 'complete' end
    result=P.Steps()
    assert(result.title=='Leveling' and Find(result,'Guide complete') )
''')
# Use the real tracker formatter to verify that pictures fit a narrow tracker and ordinary guide text stays intact.
tracker = (ROOT / 'Modules/QuestTracker.lua').read_text(encoding='utf-8-sig')
start = tracker.index('\tfunction GuideText(block, line, width)')
end = tracker.index('\n\tend\n', start) + len('\n\tend')
formatter = LuaRuntime()
formatter.execute("TEXT_X=10; COLUMNS={text=10}; GUIDE_LINK='mellouiguide'")
formatter.execute(tracker[start:end])
formatter.execute(r'''
    assert(GuideText({}, {text='ordinary guide text'}, 110)=='ordinary guide text')
    assert(GuideText({}, {text='image',picture={texture='Image',width=180,height=100}}, 110)=='|TImage:50:90|t')
    assert(GuideText({}, {text='image',picture={texture='Image',width=180,height=100}}, 500)=='|TImage:100:180|t')
''')
# Run the real guide-row renderer with font/frame doubles. This tests layout intent, not WoW rendering.
start = tracker.index('\tlocal n, boxes, controls = 0, 0, 0', tracker.index('function GUIDE.PolestarLayout'))
end = tracker.index('\n\t-- (Guide: Next Steps)', start)
render = LuaRuntime()
render.execute(r'''
    function wipe(t) for k in pairs(t) do t[k]=nil end end
    TEXT_X=10; COLUMNS={text=12,bullet=0}; TITLE_GAP=4; LINE_GAP=3
    function TitleSize() return 14 end
    function GuideText(_,line) return line.text end
    function StyleText(fs,size) fs.size=size end
    function PutLine(block,n,text,y,width,dash,r,g,b)
        local fs={text=text,x=22,width=width-22,size=13,dash=dash,colour={r,g,b},y=y}
        function fs:ClearAllPoints() end
        function fs:SetPoint(_,_,_,x,top) self.x=x;self.y=-top end
        function fs:SetWidth(v) self.width=v end
        function fs:GetStringHeight()
            local lines=block.measureWrap and self.wrap~=false and math.max(1,math.ceil(#self.text*6/self.width)) or 1
            return self.size*lines
        end
        block.lines[n]=fs
        return y+13+LINE_GAP,fs
    end
''')
render.execute('function RenderRows(block,data,width) local y=0; local compact=data.presentation=="polestar"; block.guideData=data; block.guideMetrics=compact and GUIDE and GUIDE.Metrics and GUIDE.Metrics(block,data) or nil\n'+tracker[start:end]+'\nreturn y end')
render.execute(r'''
    local block={lines={}}
    local content={lines={{text='Current step',role='section'}, {text='Return home',role='lead'},
        {text='Objectives',role='section'}, {text='Use Hearthstone',role='objective'},
        {text='Cooldown: ready',role='detail'}, {text='Notes',role='section'},
        {text='Speak to the innkeeper afterward.',role='note'}}}
    RenderRows(block,content,240)
    local heading,objective,detail=block.lines[3],block.lines[4],block.lines[5]
    assert(heading.size>detail.size and heading.x<objective.x and objective.x<detail.x)
    assert(heading.colour[1]>heading.colour[3] and detail.colour[1]<objective.colour[1])
    assert(objective.dash and not detail.dash)
    assert(block.lines[6].y-detail.y-detail:GetStringHeight()>=TITLE_GAP*2)
    assert(detail.x+detail.width==240, 'details must wrap within the tracker')
    block={lines={}}
    RenderRows(block,{lines={{text='Other guide text'}}},240)
    assert(block.lines[1].x==22 and block.lines[1].size==13 and not block.lines[1].dash)
''')
# Exercise the native-style branch and its actual decorations, using simulated font/region objects.
render.execute(r'''
    MelloUI={Safe={Number=function(v) return type(v)=='number' and v or nil end},Meaning={questDone={0.4,0.8,0.3}}}
    W={Paint=function(region,key) region.paint=key end}
    MelloUI.Widgets=W
    function StoneColour(_,r,g,b) return r,g,b end
    local methods={}
    function methods:ClearAllPoints() end
    function methods:SetPoint(p,_,_,x,y) self.point=p;self.x=x;self.y=-(y or 0) end
    function methods:SetSize(w,h) self.width=w;self.height=h end
    function methods:SetColorTexture(...) self.colour={...} end
    function methods:SetTexture(v) self.texture=v end
    function methods:SetTexCoord(...) self.texCoord={...} end
    function methods:SetText(v) self.text=v end
    function methods:SetTextColor(...) self.colour={...} end
    function methods:SetJustifyH(v) self.justify=v end
    function methods:Show() self.shown=true end
    function methods:SetShown(v) self.shown=v end
    function methods:SetWordWrap(v) self.wrap=v end
    function methods:SetVertexColor(...) self.colour={...} end
    function methods:Hide() self.shown=false end
    function methods:IsShown() return self.shown end
    function methods:GetStringWidth() return #(self.text or '')*6 end
    function methods:GetStringHeight() return self.size or 13 end
    function methods:GetLineHeight() return self.size or 13 end
    function methods:SetFrameLevel(v) self.level=v end
    function methods:GetFrameLevel() return self.level or 1 end
    function methods:SetMaxLines(v) self.maxLines=v end
    function methods:SetFont(path,size,flags) self.font=path; self.face=path; self.size=size; self.flags=flags end
    function methods:GetParent() return self.parent end
    function methods:SetParent(v) self.parent=v end
    function methods:SetWidth(v) self.width=v end
    function MakeArt() return setmetatable({shown=true},{__index=methods}) end
    local old=PutLine
    function PutLine(...)
        local y,fs=old(...)
        setmetatable(fs,{__index=methods})
        fs.dashState=fs.dash
        fs.dash=MakeArt()
        fs.dash:SetShown(fs.dashState)
        return y,fs
    end
    layer={GetFrameLevel=function() return 10 end}
    function GuideBox(block,n)
        block.boxes=block.boxes or {}
        block.boxes[n]=block.boxes[n] or MakeArt()
        block.boxes[n].tick=MakeArt()
        return block.boxes[n]
    end
    GUIDE={}
''')
start = tracker.index('\tfunction GUIDE.ClearPresentation(')
end = tracker.index('\n\t-- a guide line as the tracker shows it:', start)
render.execute(tracker[start:end])
step_start = tracker.index('\tfunction GUIDE.StepLink(')
step_end = tracker.index('\nend\n', step_start)
render.execute('STEP_LINK="mellouistep"')
render.execute(tracker[step_start:step_end])
render.execute(r'''
    -- Native sizes override Mello offsets; compensate for the destination's effective scale.
    local fs=MakeArt()
    function fs:GetEffectiveScale() return 0.8 end
    for _,size in ipairs({11,12,14,15}) do
        GUIDE.NativeFont(fs,{}, {fontInfo={face='NativeFont',size=size,scale=0.96}},10)
        assert(fs.face=='NativeFont' and math.abs(fs.size-size*1.2)<0.00001)
    end
    GUIDE.NativeFont(fs,{font='FallbackFont'},nil,10)
    assert(fs.face=='FallbackFont' and fs.size==10)
''')
render.execute(r'''
    native={lines={}}
    function native:GetFrameLevel() return 1 end
    layer=MakeArt()
    native.linkLayer=layer
    function layer:CreateTexture() return MakeArt() end
    function layer:CreateFontString() return MakeArt() end
    function native:CreateTexture() return MakeArt() end
    function native:CreateFontString() return MakeArt() end
    RenderRows(native,{presentation='polestar',lines={
        {text='Benjy Wheeler',role='lead'},
        {text='Turn in My Kingdom for a Horse',role='objective',box=true,current=true,icon='quest'},
        {text='West of the farmhouse.',role='note'},
        {text='Journey',role='section',right='5:40 \194\183 6.0k yd',ruleBefore=true},
        {text='Walk to the flight master',role='routeCurrent',number='1',icon='walk',right='0:29'},
        {text='30%',role='progress',progress=0.3,ruleBefore=true},
    }},240)
    assert(native.boxes[1].point=='TOPRIGHT' and native.boxes[1].x==228)
    assert(native.lines[2].guideArt.focus.shown and native.lines[2].guideArt.focusEdgeTOPLEFT.shown)
    assert(native.lines[1].size>native.lines[4].size)
    local route=native.lines[5]
    assert(route.count.point=='TOPRIGHT' and route.count.x==228 and route.count.text=='0:29')
    assert(route.x+route.width<=route.count.x-route.count:GetStringWidth()-12)
    assert(route.guideArt.number.text=='1' and route.guideArt.icon.texture=='walk')
    assert(native.lines[4].guideArt.rule.shown)
    local progress=native.lines[6]
    assert(progress.justify=='CENTER' and progress.guideArt.progressFill.shown)
    assert(math.abs(progress.guideArt.progressFill.width-67.8)<0.01)
    -- Native padding stays symmetric, supporting lines share their main text column, and goals reflow.
    local metrics={pad=18,textX=42,tabH=30,navH=32,progH=28,icon=15,
        rowMin=22,check=15,rowPad=4,checkIn=10,upRow=20,upToggle=26,glyphY=16,litInset=10,checkMiddle=true}
    local content={presentation='polestar',metrics=metrics,lines={
        {text='Cooking 130-175',role='lead',section='heading'},
        {text='Shandrina',role='lead',section='current',icon='talk'},
        {text='Ashenvale',role='detail',section='current',ruleAfter=true},
        {text='Buy and read Expert Cookbook',role='objective',section='objectives',group=1,box=true,current=true,icon='book'},
        {text='Expert Cooking',role='detail',section='objectives',group=1},
        {text='Read the complete instructions.',role='note',section='notes'},
        {text='Journey',role='section',section='travel',right='5:25',ruleBefore=true},
        {text='To buy Expert Cookbook',role='destination',section='travel'},
        {text='Fly to Astranaar',role='route',section='travel',number='2',icon='flight',right='2:11'},
        {text='55%',role='progress',section='foot',progress=0.55,ruleBefore=true},
    }}
    native.measureWrap=true
    RenderRows(native,content,340)
    assert(native.lines[1].x==18 and native.lines[1].y==8)
    assert(native.lines[2].x==42 and native.lines[3].x==42)
    assert(native.lines[2].y-native.lines[1].y-native.lines[1]:GetStringHeight()==10)
    assert(native.lines[4].x==42 and native.lines[5].x==42)
    assert(native.lines[4].width==251 and native.lines[5].width==251 and native.boxes[1].width==15)
    assert(native.boxes[1].point=='RIGHT' and native.boxes[1].x==315)
    local focus=native.lines[4].guideArt.focus
    assert(focus.x==10 and focus.width==320 and focus.y==native.lines[4].y-8)
    assert(focus.y+focus.height==native.lines[5].y+native.lines[5]:GetStringHeight()+10)
    assert(native.boxes[1].y==focus.y+focus.height/2)
    local rule=native.lines[3].guideArt.rule
    assert(rule.x==18 and rule.width==304)
    assert(native.lines[6].x==36 and native.lines[6].width==286)
    assert(native.lines[7].x==14 and native.lines[8].x==39 and native.lines[9].x==61)
    assert(native.lines[9].guideArt.number.x==4 and native.lines[9].guideArt.icon.x==37)
    assert(native.lines[9].count.x==326)
    local bar=native.lines[10].guideArt.progressBase
    assert(bar.x==18 and bar.width==304 and bar.height==14)
    local previousHeight=native.lines[4]:GetStringHeight()
    RenderRows(native,content,180)
    assert(native.lines[4]:GetStringHeight()>previousHeight)
    assert(native.lines[4].x+native.lines[4].width<=native.boxes[1].x-native.boxes[1].width)
    assert(native.lines[5].y>=native.lines[4].y+native.lines[4]:GetStringHeight()+3)
    -- The Still to do glyph stays beside the first line as the same caption wraps.
    for _,section in ipairs({'along','upnext'}) do
        local summary={presentation='polestar',metrics=metrics,lines={
            {text='Still to do',role='detail',section=section,ruleBefore=true},
            {text='2 finished quests to hand in elsewhere (1,266 XP)',role='detail',section=section,icon='question'},
        }}
        local top=26
        local singleOffset
        for _,width in ipairs({500,260}) do
            RenderRows(native,summary,width)
            local caption=native.lines[2]
            local glyph=caption.guideArt.icon
            local firstCentre=caption.y+caption:GetLineHeight()/2
            assert(math.abs(glyph.y+glyph.height/2-firstCentre)<0.00001,
                'summary icon must align with the first text line, not the wrapped row')
            if width==500 then
                assert(caption:GetStringHeight()==caption:GetLineHeight())
                singleOffset=glyph.y-top
            else
                assert(caption:GetStringHeight()>caption:GetLineHeight())
                assert(glyph.y-top==singleOffset, 'wrapping must not move the icon down')
            end
        end
    end
    -- Scale padding and typography by the same factor, with no bleed into another guide provider.
    function native:GetEffectiveScale() return 0.8 end
    metrics.scale=0.96
    local scaled=GUIDE.Metrics(native,content)
    assert(math.abs(scaled.pad-21.6)<0.00001 and math.abs(scaled.textX-50.4)<0.00001)
    assert(not GUIDE.Metrics(native,{presentation='other',metrics=metrics}))
    native.GetEffectiveScale=nil
    native.measureWrap=nil
    native.guideMetrics=nil
''')
# The complete header and disclosure controls use real callbacks and tracker-owned frames.
render.execute(r'''
    unpack=table.unpack
    local methods=getmetatable(MakeArt()).__index
    function methods:SetAllPoints(parent) self.allPoints=parent end
    function methods:SetHeight(v) self.height=v end
    function methods:SetWidth(v) self.width=v end
    function methods:SetEnabled(v) self.enabled=v end
    function methods:EnableMouseWheel(v) self.wheel=v end
    function methods:CreateTexture() local r=MakeArt();r.parent=self;return r end
    function methods:CreateFontString() local r=MakeArt();r.parent=self;return r end
    function CreateFrame(kind,_,parent,template) local f=MakeArt();f.kind=kind;f.parent=parent;f.template=template;f.scripts={};return f end
    Perf={SetScript=function(frame,key,fn) frame.scripts[key]=fn end}
    function Scroll() end
    function Tr(text) return text end
    M={name='QuestTracker',db={},isEnabled=true}
    Art={Flat=function(button,glyph,lit) button.flatGlyph=glyph;button.flatLit=lit end}
    MelloUI.NotifySettingChanged=function() notified=true end
    native:GetFrameLevel() -- existing test block, not the Polestar guide window
    skin={Skin=function(frame,kind) frame.skinKind=kind end,Color=function() return 0.9,0.73,0.4,1 end,
        Media=function(key) return 'Polestar/'..key end}
    data={skin=skin,font='Fonts/FRIZQT__.TTF',counter='26 / 114',label='Riverglades',
        tabs={{title='Riverglades',levels='41-45',active=true,Select=function() selected='a' end,Close=function() closed='a' end},
            {title='Second',Select=function() selected='b' end}},
        AddTab=function() added=true end,
        nav={Back=function() backed=true end,Next=function() nexted=true end,Skip=function() skipped=true end},
        cog={Right=function() settings=true end}}
    assert(GUIDE.Surface(native,data,340,layer)==64)
    local f=native.polestarSurface
    assert(f.skinKind=='window' and f.psGuideWindow and f.psStrip==f.strip)
    assert(f.tabs[1].label.text=='Riverglades' and f.tabs[1].range.text=='(41-45)' and f.count.text=='26 / 114')
    assert(f.tabs[1].label.face=='Fonts/FRIZQT__.TTF')
    f.tabs[2].scripts.OnClick(f.tabs[2]);f.tabs[1].close.scripts.OnClick(f.tabs[1].close)
    f.add.scripts.OnClick(f.add);f.back.scripts.OnClick(f.back);f.next.scripts.OnClick(f.next)
    f.skip.scripts.OnClick(f.skip);f.menu.scripts.OnClick(f.menu)
    assert(selected=='b' and closed=='a' and added and backed and nexted and skipped and settings)
    assert(not f.fold, 'the standard section heading owns collapse; tabs do not duplicate it')
    for _,width in ipairs({340,260,180}) do
        GUIDE.Surface(native,data,width,layer)
        assert(f.add.shown and f.add.point=='TOPRIGHT')
    end
    GUIDE.Surface(native,data,340,layer)
    -- Collapsed note has a leading disclosure glyph, and expanded content can be read in full.
    native.guideData=data
    local fs=MakeArt()
    local disclosure={role='note',expanded=false,singleLine=true,Collapse=function() toggled=true end}
    assert(GUIDE.Control(native,layer,fs,disclosure,80,340,16,1)==18)
    local control=native.guideControls[1]
    assert(control.point=='TOPLEFT' and control.icon.texture=='Polestar/chevron-right' and fs.maxLines==1)
    control.scripts.OnClick(control)
    assert(toggled)
''')
# Render the complete guide block, including its native surface, header, controls, footer and pooled cleanup.
start = tracker.index('function GUIDE.BeginBlock(')
end = tracker.index('\n-- A section\'s header in the list', start)
render.execute(tracker[start:end].replace('local function FillGuideBlock(', 'function FillActualGuideBlock(', 1))
item_start = tracker.index('function GUIDE.Item(')
item_end = tracker.index('\nend', item_start) + len('\nend')
render.execute(tracker[item_start:item_end])
hide_start = tracker.index('local function HideLines(block, from)')
hide_end = tracker.index('\nend\n', hide_start) + len('\nend')
render.execute('Motion={Stop=function() end,Flash=function(block) block.flashes=(block.flashes or 0)+1 end}')
render.execute(tracker[hide_start:hide_end].replace('local function HideLines(', 'function RealHideLines(', 1))

render.execute(r'''
    function GuideLayer(block)
        block.linkLayer:SetFrameLevel(block:GetFrameLevel()+1)
        return block.linkLayer
    end
    function wipe(t) for k in pairs(t) do t[k]=nil end end
    function Inked() return false end
    function InkLine() end
    function HideBoxes(block,from) for k=from,#(block.boxes or {}) do block.boxes[k]:Hide() end end
    HideLines=RealHideLines
    -- Keep the same section-toggle painter when rendering the complete block.
    Act={Washed=function() end}
    Near={GUIDE='guide',Lay=function(block)
        if block.dist then block.dist:Hide() end
        return 0
    end}
    ITEM_SIZE=26
    M.db={}
    native.item=MakeArt()
    native.title=MakeArt()
    setmetatable(native,getmetatable(MakeArt()))
    data.presentation='polestar'
    data.lines={{text='Benjy Wheeler',role='lead',font='Fonts/FRIZQT__.TTF',colour={1,1,1}},
        {text='Turn in quest',role='objective',current=true,box=true,icon='quest',iconColour={1,0.8,0}},
        {text='Read the full instructions here.',role='note',singleLine=true,expanded=false,Collapse=function() collapsed=true end},
        {text='28%',role='progress',progress=0.28}}
    assert(FillActualGuideBlock(native,data,340)>64)
    assert(native.title.text=='' and native.polestarSurface.shown)
    assert(native.lines[1].face=='Fonts/FRIZQT__.TTF' and native.lines[2].y>=64)
    assert(native.lines[3].maxLines==1 and native.guideControls[1].shown)
    assert(native.lines[4].guideArt.progressFill.shown)
    data.metrics={pad=18,textX=42,tabH=30,navH=32,progH=28,icon=15,rowMin=22,
        check=15,rowPad=4,checkIn=10,upRow=20,upToggle=26,glyphY=16,litInset=10,checkMiddle=true}
    for i,section in ipairs({'current','objectives','notes','foot'}) do data.lines[i].section=section end
    FillActualGuideBlock(native,data,340)
    local header=native.polestarSurface
    assert(header.strip.height==25 and header.strip.y==4 and header.back.y==32 and header.back.x==12,
        'content-padding changes must not resize or inset the header')
    assert(header.tabs[1].height==23 and header.tabs[1].label.x==7 and header.tabs[1].close.width==16)
    assert(native.lines[1].x==42 and native.lines[2].x==42)
    assert(native.guideControls[1].x==18 and native.lines[3].x==36)
    assert(native.lines[4].guideArt.progressBase.width==304)
    -- Change only body padding, then only screen scale: the header retains its previous geometry.
    data.metrics.pad=30
    FillActualGuideBlock(native,data,340)
    assert(native.guideMetrics.pad==30 and native.lines[3].x==48)
    assert(header.back.x==12 and header.menu.x==-12 and header.tabs[1].label.x==7)
    function native:GetEffectiveScale() return 0.8 end
    data.metrics.scale=0.96
    FillActualGuideBlock(native,data,340)
    assert(math.abs(native.guideMetrics.pad-36)<0.00001)
    assert(header.strip.height==25 and header.tabs[1].height==23 and header.tabs[1].close.width==16)
    assert(header.add.width==22 and header.add.icon.width==12 and header.back.y==32)
    native.GetEffectiveScale=nil
    GUIDE.ClearPresentation(native)
    FillActualGuideBlock(native,{title='Another guide',lines={{text='Its usual step'}}},340)
    assert(not native.polestarSurface.shown and native.title.text=='Another guide' and not native.guideMetrics)
    for _,control in ipairs(native.guideHeader) do assert(not control.shown) end
    for _,control in ipairs(native.guideControls) do assert(not control.shown) end
''')
# The actual dispatcher uses the same items, distances, line state and completion effects for both layouts.
render.execute(r'''
    native.item.icon=MakeArt()
    Art.ItemTray=function() return nil end
    function ItemCooldown() end
    MelloUI.PaletteCode=function() return '|cff808080' end
    local oldNear=Near.Lay
    local measures=0
    Near.Lay=function(block,_,right)
        measures=measures+1
        block.dist=block.dist or MakeArt()
        block.dist:SetText('300 yd');block.dist:SetWidth(0);block.dist:Show()
        return 44
    end
    GUIDE.items={items={{kind='item',quest=true,id=6948,icon='hearth'}}}
    M.db.itemButtons=true
    for _,presentation in ipairs({'polestar','standard'}) do
        local content={presentation=presentation,section='Polestar',title='Guide - step 2/3',counter='2 / 3',
            away={count='2/3',Back=function() returnedToLive=true end},
            lines={{text='Use Hearthstone',quest=123,role='objective',section='objectives',done=false,box=true}}}
        local before=measures
        FillActualGuideBlock(native,content,340)
        assert(measures==before+1 and native.item.shown and native.item.itemLink=='item:6948')
        assert(native.item.itemID==6948 and native.dist.shown and native.guideQuest[1]==123)
        assert(native.item:GetFrameLevel()>native.linkLayer:GetFrameLevel(),
            'the item must receive mouse hover above the full-area hyperlink layer')
        assert(native.guideAway==content.away and native.boxes[1].n==1)
        if presentation=='polestar' then
            assert(native.polestarSurface.count.text:find('|Hmellouistep|h2 / 3|h',1,true))
            assert(native.item.y>=64 and native.lines[1].y>native.item.y)
            assert(native.dist.x==12 and native.dist.justify=='LEFT')
        else
            assert(native.title.text:find('|Hmellouistep|h2/3|h',1,true))
            assert(not native.polestarSurface.shown)
        end
        local flashes=native.flashes or 0
        content.lines[1].done=true
        FillActualGuideBlock(native,content,340)
        assert(native.flashes==flashes+1 and native.guideDone[1])
        FillActualGuideBlock(native,content,340)
        assert(native.flashes==flashes+1, 'completion flashes once')
        content.title='Next step'
        FillActualGuideBlock(native,content,340)
        assert(native.flashes==flashes+1, 'a new step must not inherit completion animation')
        native.guideHand[1]=true
        content.lines[1].done=false
        FillActualGuideBlock(native,content,340)
        content.lines[1].done=true
        FillActualGuideBlock(native,content,340)
        assert(native.flashes==flashes+1, 'manually ticked goals do not flash')
    end
    -- A missing item clears the same button after either presentation used it.
    GUIDE.items=nil
    FillActualGuideBlock(native,{presentation='polestar',lines={{text='Next',role='lead'}}},340)
    assert(not native.item.shown and not native.item.itemLink and not native.item.itemID)
    M.db.itemButtons=nil
    Near.Lay=oldNear
''')
# Exercise the production hover handler and secure-overlay setup, not just the displayed item.
overlay_start = tracker.index('local itemOverlay\n')
overlay_end = tracker.index('-- a fight is starting:', overlay_start)
hover_start = tracker.index('\tPerf.SetScript(item, "OnEnter", function(self)', tracker.index('local function NewBlock('))
hover_body = tracker.index('\n', hover_start) + 1
hover_end = tracker.index('\n\tend)', hover_body)
render.execute(r'''
    local methods=getmetatable(MakeArt()).__index
    function methods:GetFrameStrata() return self.strata or 'MEDIUM' end
    function methods:SetFrameStrata(value) self.strata=value end
    function methods:SetAttribute(key,value) self.attributes=self.attributes or {};self.attributes[key]=value end
    function methods:RegisterForClicks(...) self.clicks={...} end
    UIParent=MakeArt()
    function InCombatLockdown() return overlayCombat==true end
    Art.ItemLit=function() end
''')
render.execute('do\n'+tracker[overlay_start:overlay_end]
               +'\nfunction HoverActualGuideItem(self)\n'+tracker[hover_body:hover_end]+'\nend\n'
               +'function CurrentSecureOverlay() return itemOverlay end\n'
               +'function AttachActualGuideItem(button) AttachOverlay(button) end\nend')
render.execute(r'''
    local function itemContent(presentation)
        return {presentation=presentation,title='Item step',counter='1 / 2',lines={{text='Use item',role='objective'}}}
    end
    GUIDE.items={items={{kind='item',quest=true,id=6948,icon='hearth'}}}
    M.db.itemButtons=true
    for _,presentation in ipairs({'polestar','standard','polestar'}) do
        FillActualGuideBlock(native,itemContent(presentation),340)
        assert(native.item:GetFrameLevel()>native.linkLayer:GetFrameLevel())
        HoverActualGuideItem(native.item)
        local overlay=CurrentSecureOverlay()
        assert(overlay.shown and overlay.over==native.item and overlay.template=='SecureActionButtonTemplate')
        assert(overlay.attributes.type=='item' and overlay.attributes.item=='item:6948')
        assert(overlay.allPoints==native.item and overlay:GetFrameLevel()>native.item:GetFrameLevel())
        assert(overlay.clicks[1]=='AnyUp' and overlay.clicks[2]=='AnyDown')
    end
    -- Existing combat restriction: hovering may not rebind the protected overlay in combat.
    local overlay=CurrentSecureOverlay()
    overlayCombat=true
    AttachActualGuideItem({itemLink='item:999'})
    assert(overlay.attributes.item=='item:6948')
    overlayCombat=false
    GUIDE.items=nil
    M.db.itemButtons=nil
''')
# Visibility is reconciled through real guide/setting lifecycle entry points.
visibility_start = tracker.index('function GUIDE.SyncVisibility(')
visibility_end = tracker.index("-- the guide step's usable item", visibility_start)
render.execute(tracker[visibility_start:visibility_end])
receive_start = tracker.index('function GUIDE.OnData(')
receive_end = tracker.index('\nend', receive_start) + len('\nend')
render.execute(tracker[receive_start:receive_end])
setting_start = tracker.index('function M:OnSettingChanged(')
setting_end = tracker.index('\nend', setting_start) + len('\nend')
render.execute(tracker[setting_start:setting_end])
collapse_start = tracker.index('local function SectionCollapsed(key)')
collapse_end = tracker.index('\nend', collapse_start) + len('\nend')
render.execute(tracker[collapse_start:collapse_end].replace('local function SectionCollapsed', 'function SectionCollapsed', 1))
guide_start = tracker.index('\t-- a guide\'s steps on top (GUIDE, above)')
guide_end = tracker.index('\n\tif #quests > 0 then', guide_start)
render.execute('function GuidePlacement(guide) local y=0; local guideOpen=guide and not SectionCollapsed("guide"); local heading,block,options; '
               'local function Head(_,label,count,cog,nav) heading=label;options={count=count,cog=cog,nav=nav} end; local function Put(key) block=key end;\n'
               + tracker[guide_start:guide_end] + '\nreturn heading,block,options end')
expand_start = tracker.index('\t\t\tlocal c = ', tracker.index('row.toggle = MakeToggle('))
expand_end = tracker.index('\n\t\tend)', expand_start)
render.execute('function ToggleGuideSection(key) key=key or "guide"\n'+tracker[expand_start:expand_end]+'\nend')
render.execute(r'''
    frame=nil;header=nil;moverEntry=nil
    function ApplyLook() end
    function MarkDirty() dirtyNotifications=(dirtyNotifications or 0)+1 end
    MelloUI.NotifySettingChanged=function(_,_,key,value) M:OnSettingChanged(key,value,M.db) end
    local nativeHidden=false
    local calls=0
    data.GetCollapsed=function() return nativeHidden end
    data.SetCollapsed=function(on)
        calls=calls+1;nativeHidden=on
        GUIDE.OnData(data) -- synchronous notification must not produce recursive writes
    end
    M.db.collapsedSections={quests=true,professions=true}
    GUIDE.OnData(data)
    local heading,block=GuidePlacement(data)
    assert(heading=='Polestar' and block=='guide')
    ToggleGuideSection()
    assert(nativeHidden and calls==1 and SectionCollapsed('guide'))
    ToggleGuideSection()
    assert(not nativeHidden and calls==2 and not SectionCollapsed('guide'))
    ToggleGuideSection('quests')
    assert(calls==2 and M.db.collapsedSections.professions)
    nativeHidden=true
    GUIDE.OnData(data) -- provider's native hide event
    assert(SectionCollapsed('guide') and calls==2)
    nativeHidden=false
    GUIDE.OnData(data)
    assert(not SectionCollapsed('guide') and calls==2)
    ToggleGuideSection()
    assert(nativeHidden)
    M:OnSettingChanged('profile',nil,{collapsedSections={quests=true}})
    assert(not nativeHidden and not SectionCollapsed('guide') and M.db.collapsedSections.quests)
    -- A newly activated guide follows native visibility, including state saved over reload.
    nativeHidden=true
    GUIDE.OnData(nil)
    GUIDE.OnData(data)
    assert(SectionCollapsed('guide'))
    -- Re-enabling/profile activation reconciles the saved tracker choice, even if the provider arrives later.
    GUIDE.OnData(nil)
    M.db={collapsedSections={}}
    GUIDE.ActivateVisibility(true)
    assert(GUIDE.profileVisibility)
    GUIDE.OnData(data)
    assert(not nativeHidden and not GUIDE.profileVisibility)
    M.isEnabled=false
    nativeHidden=true
    GUIDE.OnData(data)
    assert(not SectionCollapsed('guide'))
    M.isEnabled=true
    GUIDE.ActivateVisibility(false)
    assert(SectionCollapsed('guide'))
    local other={section='Another guide',lines={{text='Step'}},cog={},nav={}}
    GUIDE.OnData(other)
    local before=calls
    ToggleGuideSection()
    assert(calls==before)
    heading,block=GuidePlacement(other)
    assert(heading=='Another guide' and block=='guide')
    -- Missing/throwing optional APIs leave the tracker usable.
    GUIDE.OnData({SetCollapsed=function() error('changed API') end})
    ToggleGuideSection()
    assert(SectionCollapsed('guide'))
    GUIDE.OnData(nil)
''')
# Pooled Polestar decorations must disappear when another guide or quest reuses that row.
start = tracker.index('local function Line(block, i)')
end = tracker.index('\n-- (0.24.0) an objective', start)
render.execute(tracker[start:end].replace('local function Line(block, i)', 'function ReuseLine(block, i)', 1))
render.execute(r'''
    native.lines[2].dash=MakeArt()
    ReuseLine(native,2)
    for _,art in pairs(native.lines[2].guideArt) do assert(not art.shown) end
    native.lines[6].dash=MakeArt()
    ReuseLine(native,6)
    assert(native.lines[6].justify=='LEFT')
    for _,art in pairs(native.lines[6].guideArt) do assert(not art.shown) end
''')
# The tracker section header must accept a step fraction, rather than treating it as a numeric quest count.
header_count = next(line.strip() for line in tracker.splitlines() if line.strip().startswith('local n = tonumber(count)'))
parse_count = formatter.eval('function(count) ' + header_count + ' return n end')
assert parse_count('26 / 114') == '26 / 114'
assert parse_count(4) == 4
assert not parse_count(None)
# Side-by-side comparison overrides either normal mode without changing its stored choice or arrow preference.
for native in (False, True):
    lua = world(native=native)
    lua.execute(r'''
        local mode=M.db.polestarNative
        local arrow=M.db.guideArrow_polestar
        local pin=waypoint
        G.SetPolestarBoth(true)
        assert(G.PolestarBoth() and G.active==P and events.guide.data and events.guideitem.data)
        assert(G.PolestarNative()==mode and M.db.guideArrow_polestar==arrow and G.ArrowShown('polestar'))
        assert(Polestar.Get('nav.minimapPins'))
        for _,f in ipairs(nativeFrames) do assert(f.alpha==0.8 and f.scale==1.2) end
        G.SetArrowShown('polestar',false)
        assert(M.db.guideArrow_polestar==arrow and G.ArrowShown('polestar'))
        G.Changed(P)
        assert(G.active==P and events.guide.data)
        G.SetPolestarBoth(false)
        assert(not G.PolestarBoth() and M.db.polestarNative==mode and M.db.guideArrow_polestar==arrow)
        if mode then
            assert(not G.active and not events.guide.data)
            for _,f in ipairs(nativeFrames) do assert(f.alpha==0.8 and f.scale==1.2) end
        else
            assert(G.active==P and events.guide.data and waypoint==pin)
            for _,f in ipairs(nativeFrames) do assert(f.alpha==0 and f.scale==0.001) end
        end
    ''')
lua = world(native=True, both=True)
lua.execute(r'''
    assert(G.PolestarNative() and G.PolestarBoth() and G.active==P and events.guide.data)
    for _,f in ipairs(nativeFrames) do assert(f.alpha==0.8 and f.scale==1.2) end
''')
lua = world()
lua.execute(r'''
    combat=true
    G.SetPolestarBoth(true)
    assert(G.active==P and events.guide.data)
    for _,f in ipairs(nativeFrames) do assert(f.alpha==0) end
    combat=false
    for _,f in ipairs(frames) do
        if f.registered.PLAYER_REGEN_ENABLED then f.scripts.OnEvent(f) end
    end
    for _,f in ipairs(nativeFrames) do assert(f.alpha==0.8 and f.scale==1.2) end
''')
print('PASS: guide content, shared renderer behavior, snapshot invalidation, visibility lifecycle, controls and combat-safe handover')
