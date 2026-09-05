local T, QR, MockWoW = ...

local function withHelp(fn)
    local panel=QR.TeleportPanel
    local saved={att=_G.AllTheThings,attc=_G.ATTC,catalog=QR.Catalog,poi=QR.POIRouting,
        combat=MockWoW.config.inCombatLockdown,frame=panel.frame,help=panel.acquisitionFrame,
        show=panel.ShowAcquisitionHelp,open=panel.OpenInATT,db=QR.db,
        title=C_QuestLog.GetTitleForQuestID,currency=_G.C_CurrencyInfo,
        completed=C_QuestLog.IsQuestFlaggedCompleted,level=_G.UnitLevel,
        reputation=_G.C_Reputation,major=_G.C_MajorFactions,covenant=_G.C_Covenants,
        secret=_G.issecretvalue,build=_G.GetBuildInfo}
    _G.AllTheThings,_G.ATTC=nil,nil
    QR.db={}
    MockWoW.config.inCombatLockdown=false
    local missing
    for _,entry in ipairs(panel:CollectAllTeleports()) do
        if entry.status.key=="STATUS_MISSING" then missing=entry.status;break end
    end
    local entry={id=46874,isSpell=false,status=missing,data={name="Test Teleport",type=QR.TeleportTypes.ITEM,faction="both"}}
    local ok,err=pcall(fn,panel,entry)
    if panel.acquisitionFrame then panel.acquisitionFrame:Hide() end
    panel.frame,panel.acquisitionFrame=saved.frame,saved.help
    panel.ShowAcquisitionHelp,panel.OpenInATT=saved.show,saved.open
    _G.AllTheThings,_G.ATTC,QR.Catalog,QR.POIRouting=saved.att,saved.attc,saved.catalog,saved.poi
    MockWoW.config.inCombatLockdown=saved.combat
    C_QuestLog.GetTitleForQuestID,C_QuestLog.IsQuestFlaggedCompleted=saved.title,saved.completed
    _G.C_CurrencyInfo,QR.db=saved.currency,saved.db
    _G.UnitLevel,_G.C_Reputation,_G.C_MajorFactions=saved.level,saved.reputation,saved.major
    _G.C_Covenants,_G.issecretvalue=saved.covenant,saved.secret
    _G.GetBuildInfo=saved.build
    if not ok then error(err) end
end

T:run("Acquisition help: URLs distinguish items and spells and reject nonnumeric input",function(t)
    withHelp(function(panel,entry)
        t:assertEqual("https://www.wowhead.com/item=46874",panel:GetAcquisitionURL(entry),"Item URL uses numeric item identity")
        entry.isSpell=true
        t:assertEqual("https://www.wowhead.com/spell=46874",panel:GetAcquisitionURL(entry),"Spell URL uses spell identity")
        entry.id="46874/run exploit"
        t:assertNil(panel:GetAcquisitionURL(entry),"Text cannot become a command or injected URL")
        entry.id=0/0
        t:assertNil(panel:GetAcquisitionURL(entry),"NaN cannot become an external reference")
    end)
end)

local function withSourceGates(fn)
    withHelp(function(panel,entry)
        local checker=QR.Catalog.CheckRequirements
        local first={mapID=84,x=0.1,y=0.2,npcID=101}
        local second={mapID=84,x=0.3,y=0.4,npcID=102}
        local ancestor={}
        local source={npcID=101,description="First source",parent=ancestor}
        local alternate={npcID=102,description="Second source"}
        local matches={{itemID=entry.id,parent=source}}
        QR.Catalog={Initialize=function()end,byNPC={[101]={first},[102]={second}},
            CheckRequirements=checker,IsAvailable=function()return true end,GetQuestLocations=function()return {}end}
        _G.AllTheThings={SearchForField=function()return matches end,
            CurrentCharacterFilters=function()return true end,CreatePopoutForSearch=function()return true end}
        _G.UnitLevel=function()return 30 end
        _G.GetBuildInfo=function()return "12.1.0","", "",120100 end
        C_QuestLog.IsQuestFlaggedCompleted=function(id)return id==202 end
        _G.C_Reputation={GetFactionDataByID=function()return {currentStanding=9000}end}
        _G.C_MajorFactions={GetMajorFactionData=function(id)
            if id==2 then return {isUnlocked=true,renownLevel=8} end
        end}
        _G.C_Covenants={GetActiveCovenantID=function()return 1 end}
        fn(panel,entry,ancestor,source,alternate,matches,first,second)
    end)
end

T:run("Acquisition help: route source requires all ancestor unlocks and preserves any-of quests",function(t)
    withSourceGates(function(panel,entry,ancestor,source,alternate,matches,first,second)
        ancestor.sourceQuests={201,202}
        t:assertNil(panel:GetAcquisitionLocation(entry),"Incomplete all-of prerequisites above the NPC block its route")
        t:assertNotNil(panel:GetATTAcquisitionInfo(entry),"Locked-source preview still explains how to obtain the item")
        t:assertTrue(panel:OpenInATT(entry),"Locked sources retain the direct ATT popout")
        ancestor.sqreq=1
        t:assertEqual(first,panel:GetAcquisitionLocation(entry),"One completed alternative satisfies sqreq=1")
        ancestor.lvl=31
        t:assertNil(panel:GetAcquisitionLocation(entry),"A level gate above the NPC blocks a lower-level character")
        matches[2]={itemID=entry.id,parent=alternate}
        local point,path=panel:GetAcquisitionLocation(entry)
        t:assertEqual(second,point,"Routing selects another currently available source variant")
        local preview=panel:GetATTAcquisitionInfo(entry,path)
        t:assertTrue(preview and preview:find("Second source",1,true)~=nil,"The source preview matches the routable variant")
        t:assertFalse(preview and preview:find("First source",1,true)~=nil,"The route never borrows a different variant's description")
        t:assertEqual(ancestor,source.parent,"Checking access does not rewrite ATT ancestry")
    end)
end)

T:run("Acquisition help: exact source routing enforces catalog reputation renown and covenant gates",function(t)
    withSourceGates(function(panel,entry,ancestor,_,_,_,first)
        for _,case in ipairs({
            {"minReputation",{1,10000},{1,9000}},
            {"maxReputation",{1,9000},{1,10000}},
            {"minRenown",{2,9},{2,8}},
            {"covenantID",2,1},
            {"lvl",31,30},
            {"awp",130000,120000},
        }) do
            ancestor[case[1]]=case[2]
            t:assertNil(panel:GetAcquisitionLocation(entry),case[1].." rejects a currently locked source")
            ancestor[case[1]]=case[3]
            t:assertEqual(first,panel:GetAcquisitionLocation(entry),case[1].." accepts the actual satisfied condition")
            ancestor[case[1]]=nil
        end
    end)
end)

T:run("Acquisition help: uncertain temporal and malformed source gates keep help without routes",function(t)
    withSourceGates(function(panel,entry,ancestor)
        for _,key in ipairs({"e","eventID","u","unobtainable","isWorldQuest","isWeekly","isDaily","OnUpdate"}) do
            ancestor[key]=1
            t:assertNil(panel:GetAcquisitionLocation(entry),key.." cannot prove an exact source is available now")
            t:assertNotNil(panel:GetATTAcquisitionInfo(entry),key.." does not hide recorded source help")
            ancestor[key]=nil
        end
        local secret={}
        _G.issecretvalue=function(value)return value==secret end
        for _,case in ipairs({{"lvl",secret},{"lvl",0/0},{"lvl",{20,40}},
            {"sourceQuests",{202,"unknown"}},{"sourceQuests",{202,202}},
            {"minReputation",{1,math.huge}},{"covenantID","unknown"}}) do
            ancestor[case[1]]=case[2]
            t:assertNil(panel:GetAcquisitionLocation(entry),case[1].." with unknown data cannot grant a route")
            ancestor[case[1]]=nil
        end
        ancestor.sourceQuests={202}
        ancestor.sqreq=2
        t:assertNil(panel:GetAcquisitionLocation(entry),"Impossible prerequisite counts do not grant a route")
        ancestor.sqreq=nil
        QR.Catalog.CheckRequirements=function()error("character data unavailable")end
        t:assertNil(panel:GetAcquisitionLocation(entry),"A failed live requirement check remains unavailable")
        QR.Catalog.CheckRequirements=function()return secret end
        t:assertNil(panel:GetAcquisitionLocation(entry),"A secret requirement result never grants access")
    end)
end)

T:run("Acquisition help: direct missing-item click uses verified ATT API with fallback",function(t)
    withHelp(function(panel,entry)
        local query,shown
        _G.AllTheThings={CreatePopoutForSearch=function(search)query=search;return true end}
        panel.ShowAcquisitionHelp=function(_,value)shown=value;return true end
        t:assertTrue(panel:OpenAcquisitionDetails(entry),"Available ATT opens successfully")
        t:assertEqual("itemID:46874",query,"ATT receives its documented item search syntax")
        t:assertNil(shown,"Successful ATT lookup does not create a competing help window")
        entry.isSpell=true
        panel:OpenAcquisitionDetails(entry)
        t:assertEqual("spellID:46874",query,"Spell IDs remain distinct when opening ATT")
        _G.AllTheThings.CreatePopoutForSearch=function()error("ATT not ready")end
        panel:OpenAcquisitionDetails(entry)
        t:assertEqual(entry,shown,"Unavailable ATT safely falls back to QR acquisition help")
    end)
end)

T:run("Acquisition help: combat never invokes external ATT window code",function(t)
    withHelp(function(panel,entry)
        local calls=0
        _G.AllTheThings={CreatePopoutForSearch=function()calls=calls+1;return true end}
        MockWoW.config.inCombatLockdown=true
        t:assertFalse(panel:OpenInATT(entry),"ATT opening defers while combat is active")
        t:assertEqual(0,calls,"No third-party window code runs during combat")
    end)
end)

T:run("Acquisition help: vendor routing requires exact coordinates and an explicit click",function(t)
    withHelp(function(panel,entry)
        QR.Catalog=nil
        entry.data.vendor={mapID=118,name="Dame Evniki Kapsalis"}
        t:assertNil(panel:GetVendorLocation(entry),"Missing coordinates do not become a guessed map midpoint")
        local routed=0
        QR.POIRouting={RouteToMapPosition=function(_,mapID,x,y)
            routed=routed+1
            t:assertEqual(118,mapID,"Vendor route retains documented map")
            t:assertEqual(0.6938,x,"Vendor route retains documented x")
            t:assertEqual(0.231,y,"Vendor route retains documented y")
        end}
        t:assertTrue(panel:ShowAcquisitionHelp(entry),"Fallback help opens without a vendor position")
        local frame=panel.acquisitionFrame
        t:assertFalse(frame.routeButton:IsShown(),"No route action for unknown coordinates")
        t:assertEqual("https://www.wowhead.com/item=46874",frame.link:GetText(),"Details link remains available")
        entry.data.vendor.x,entry.data.vendor.y=0.6938,0.231
        panel:ShowAcquisitionHelp(entry)
        t:assertEqual(frame,panel.acquisitionFrame,"Repeated help reuses one window")
        t:assertTrue(frame.routeButton:IsShown(),"Known vendor enables explicit route action")
        t:assertEqual(0,routed,"Opening help alone does not start routing or cast anything")
        frame.routeButton:GetScript("OnClick")()
        t:assertEqual(1,routed,"Only the route button starts navigation")
    end)
end)

T:run("Acquisition help: ATT source links use independent coordinates and reject reference midpoints",function(t)
    withHelp(function(panel,entry)
        local npc={npcID=123,parent={}}
        local item={itemID=entry.id,parent=npc,coords={[84]={{50,50}}}}
        _G.AllTheThings={SearchForField=function()return {item}end,CurrentCharacterFilters=function()return true end}
        local point={npcID=123,mapID=118,x=0.69,y=0.23,name="Known Source"}
        QR.Catalog={Initialize=function()end,byNPC={[123]={point}},IsAvailable=function()return true end,
            GetQuestLocations=function()return {}end}
        local location=panel:GetAcquisitionLocation(entry)
        t:assertEqual(point,location,"NPC source is joined to its independently recorded coordinate")
        npc.parent=npc
        t:assertNil(panel:GetAcquisitionLocation(entry),"Cyclic ancestry cannot establish an eligible source")
        npc.parent=nil
        QR.Catalog.byNPC={}
        t:assertNil(panel:GetAcquisitionLocation(entry),"Generic ATT item coordinates never become an invented vendor position")
    end)
end)

T:run("Acquisition help: bounded ATT preview preserves prerequisite alternatives and costs",function(t)
    withHelp(function(panel,entry)
        local source={sourceQuests={101,102},sqreq=1,requireSkill=202,cost={{"c",2003,50}},description="Recorded source detail"}
        _G.AllTheThings={SearchForField=function()return {source}end,CurrentCharacterFilters=function()return true end}
        C_QuestLog.GetTitleForQuestID=function(id)return "Quest "..id end
        _G.C_CurrencyInfo={GetCurrencyInfo=function()return {name="Supplies"}end}
        local text=panel:GetATTAcquisitionInfo(entry)
        t:assertTrue(text and text:find("1 of 2",1,true)~=nil,"Any-of prerequisite count is preserved")
        t:assertTrue(text and text:find("50 Supplies",1,true)~=nil,"Known currency purchase cost is displayed")
        t:assertTrue(text and text:find(QR.L["HINT_REQUIRES_ENGINEERING"],1,true)~=nil,"Engineering source requirement is visible")
        t:assertTrue(#text<2000,"ATT preview remains bounded")
        source.parent=source
        t:assertNil(panel:GetATTAcquisitionInfo(entry),"Cyclic sources do not become a character-specific preview")
    end)
end)

T:run("Acquisition help: source ancestry filters character variants before source routing",function(t)
    withHelp(function(panel,entry)
        local wrong={npcID=100,description="Wrong source"}
        local right={npcID=200,description="Right source"}
        local locked={itemID=entry.id,parent=wrong,excluded=true}
        local available={itemID=entry.id,parent=wrong,sourceParent=right}
        local first={mapID=84,x=0.1,y=0.1,npcID=100}
        local second={mapID=85,x=0.9,y=0.9,npcID=200}
        QR.Catalog={Initialize=function()end,byNPC={[100]={first},[200]={second}},
            IsAvailable=function()return true end,GetQuestLocations=function()return {}end}
        _G.AllTheThings={SearchForField=function()return {locked,available}end,
            CurrentCharacterFilters=function(node)return not node.excluded end}
        t:assertEqual(second,panel:GetAcquisitionLocation(entry),"Eligible sourceParent wins over locked variant and UI category parent")
        local text=panel:GetATTAcquisitionInfo(entry)
        t:assertTrue(text and text:find("Right source",1,true)~=nil,"Preview describes the eligible variant")
        t:assertFalse(text and text:find("Wrong source",1,true)~=nil,"Preview excludes the ineligible alternative")
        right.excluded=true
        t:assertNil(panel:GetAcquisitionLocation(entry),"An ancestor restriction also excludes its child source")
        _G.AllTheThings.CurrentCharacterFilters=function()error("ATT loading")end
        t:assertNil(panel:GetAcquisitionLocation(entry),"Unavailable ATT filtering never grants a source route")
        _G.AllTheThings.CurrentCharacterFilters=nil
        t:assertNil(panel:GetAcquisitionLocation(entry),"An older ATT without character filtering retains only the direct ATT popout")
    end)
end)

T:run("Acquisition help: native atlas requirement markers replace unsupported glyphs",function(t)
    withHelp(function(panel,entry)
        entry.data.requiredQuest={id=101,name="Required Quest"}
        entry.data.profession="Engineering"
        C_QuestLog.IsQuestFlaggedCompleted=function()return true end
        local text=panel:GetAcquisitionInfo(entry.id,entry)
        t:assertTrue(text:find("|A:common-icon-checkmark:14:14|a",1,true)~=nil,"Completed quest uses native checkmark atlas")
        t:assertFalse(text:find("✓",1,true)~=nil,"No unsupported checkmark codepoint remains")
        t:assertFalse(text:find("✗",1,true)~=nil,"No unsupported cross codepoint remains")
    end)
end)

T:run("Acquisition help: missing rows and grid icons expose help without secure cast buttons",function(t)
    withHelp(function(panel,entry)
        panel.frame=CreateFrame("Frame")
        panel.frame:SetSize(560,450)
        panel.frame.scrollChild=CreateFrame("Frame",nil,panel.frame)
        local help,att=0,0
        panel.ShowAcquisitionHelp=function()help=help+1;return true end
        panel.OpenInATT=function()att=att+1;return true end
        local row=panel:CreateTeleportRow(entry,0)
        t:assertTrue(row.helpButton:IsShown(),"Missing item has a visible acquisition action")
        t:assertNil(row.useButton,"Unowned item never receives a secure casting overlay")
        row.helpButton:GetScript("OnClick")()
        t:assertEqual(1,help,"Visible help button opens QR acquisition details")
        row:GetScript("OnMouseUp")(row,"LeftButton")
        t:assertEqual(1,att,"Direct missing-item click opens its ATT source when available")
        local icon=panel:GetIconFrame()
        panel:ConfigureGridIcon(icon,entry)
        t:assertTrue(icon.helpBadge:IsShown(),"Missing grouped icon displays a help marker")
        icon:GetScript("OnMouseUp")(icon,"LeftButton")
        t:assertEqual(2,att,"Grouped missing-item click also opens source details")
        icon:GetScript("OnMouseUp")(icon,"RightButton")
        t:assertEqual(2,help,"Right-click on grouped missing item always opens QR source routing help")
        row:GetScript("OnMouseUp")(row,"RightButton")
        t:assertEqual(3,help,"Right-click on list item also opens QR help even with ATT available")
        t:assertEqual(2,att,"Right-click help does not invoke ATT or a secure item action")
        panel:ReleaseRowFrame(row)
        panel:ReleaseIconFrame(icon)
        t:assertNil(row:GetScript("OnMouseUp"),"Recycled rows cannot retain a previous acquisition click")
        t:assertNil(icon:GetScript("OnMouseUp"),"Recycled icons cannot retain a previous acquisition click")
    end)
end)
