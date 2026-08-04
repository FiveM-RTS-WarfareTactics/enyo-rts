var P=GetParentResourceName();
var B={v:false,cat:'props',mdl:'',cnt:0};

var CATALOG={
props:[
{n:'prop_barrier_work01a',t:'Barr'},{n:'prop_barrier_work05',t:'Barr'},{n:'prop_roadcone01a',t:'Cone'},{n:'prop_roadcone02a',t:'Cone'},
{n:'prop_container_01a',t:'Cont'},{n:'prop_container_01c',t:'Cont'},{n:'prop_container_02a',t:'Cont'},{n:'prop_container_03a',t:'Cont'},{n:'prop_container_ld2',t:'Cont'},
{n:'prop_woodpile_01a',t:'Wood'},{n:'prop_woodpile_02a',t:'Wood'},{n:'prop_woodpile_03a',t:'Wood'},{n:'prop_woodpile_04a',t:'Wood'},
{n:'prop_sandbager_01',t:'Mili'},{n:'prop_sandbager_02',t:'Mili'},{n:'prop_mp_barrier_01',t:'Mili'},{n:'prop_mp_barrier_02',t:'Mili'},
{n:'prop_fncwood_01a',t:'Fnce'},{n:'prop_fnclink_01a',t:'Fnce'},{n:'prop_fnclink_02b',t:'Fnce'},{n:'prop_fnclink_03a',t:'Fnce'},{n:'prop_fnclink_05a',t:'Fnce'},
{n:'prop_tyre_01',t:'Tire'},{n:'prop_tyre_02',t:'Tire'},{n:'prop_cs_dumpster_01a',t:'Dump'},{n:'prop_dumpster_01a',t:'Dump'},
{n:'prop_pallet_01a',t:'Pall'},{n:'prop_pallet_02a',t:'Pall'},{n:'prop_beach_fire',t:'Fire'},{n:'prop_fire_hydrant',t:'Hydr'},
{n:'prop_bench_01a',t:'Benc'},{n:'prop_bench_05',t:'Benc'},{n:'prop_bin_01a',t:'Bin'},{n:'prop_bin_02a',t:'Bin'},
{n:'prop_sign_road_01a',t:'Sign'},{n:'prop_sign_road_03d',t:'Sign'},{n:'prop_sign_road_04a',t:'Sign'},{n:'prop_sign_road_05a',t:'Sign'},{n:'prop_sign_sec_01',t:'Sign'},
{n:'prop_lightpole_01a',t:'Lite'},{n:'prop_streetlight_01',t:'Lite'},
{n:'prop_gas_tank_01a',t:'Tank'},{n:'prop_gas_tank_02a',t:'Tank'},
{n:'prop_scaffold_01a',t:'Scaf'},{n:'prop_scaffold_02a',t:'Scaf'},
{n:'prop_traffic_01a',t:'Road'},{n:'prop_traffic_02a',t:'Road'},{n:'prop_traffic_02b',t:'Road'},{n:'prop_traffic_03a',t:'Road'},
{n:'prop_cons_cements01',t:'Cons'},{n:'prop_cons_cements02',t:'Cons'},{n:'prop_bricks_01a',t:'Cons'},{n:'prop_pipes_01a',t:'Cons'},
{n:'prop_toolchest_01',t:'Cons'},{n:'prop_toolchest_02',t:'Cons'},
{n:'prop_rock_1_a',t:'Rock'},{n:'prop_rock_1_b',t:'Rock'},{n:'prop_rock_2_a',t:'Rock'},{n:'prop_rock_4_a',t:'Rock'},
{n:'prop_tree_oak_01',t:'Tree'},{n:'prop_tree_cedar_02',t:'Tree'},{n:'prop_bush_med_01',t:'Bush'},{n:'prop_bush_lrg_01',t:'Bush'},
{n:'prop_crate_01a',t:'Crat'},{n:'prop_crate_02a',t:'Crat'},{n:'prop_barrel_01a',t:'Barl'},{n:'prop_barrel_02a',t:'Barl'},
{n:'v_ilev_fh_kitchenstool',t:'Furn'},{n:'v_ilev_fh_diningchair',t:'Furn'},{n:'v_ilev_fh_sofa01',t:'Furn'},
{n:'prop_off_chair_01',t:'Furn'},{n:'prop_off_chair_03',t:'Furn'},{n:'prop_off_desk_01',t:'Furn'},{n:'prop_off_desk_02',t:'Furn'},
{n:'v_corp_cd_chair',t:'Furn'},{n:'v_corp_cubrik',t:'Furn'},{n:'v_corp_officedesk001',t:'Furn'},
{n:'prop_atm_01',t:'Elec'},{n:'prop_atm_02',t:'Elec'},{n:'prop_atm_03',t:'Elec'},{n:'prop_vend_soda_01',t:'Elec'},
{n:'prop_weed_pallet',t:'Drug'},{n:'prop_coke_block_01',t:'Drug'},{n:'prop_meth_bag_01',t:'Drug'},
{n:'prop_money_bag_01',t:'Cash'},{n:'prop_ld_case_01',t:'Cash'},{n:'prop_gold_bar',t:'Cash'},
{n:'prop_tool_adjspanner',t:'Tool'},{n:'prop_tool_blowtorch',t:'Tool'},{n:'prop_tool_box_01',t:'Tool'},
{n:'prop_tool_consaw',t:'Tool'},{n:'prop_tool_crowbar',t:'Tool'},{n:'prop_tool_fireaxe',t:'Tool'},
{n:'prop_tool_hammer',t:'Tool'},{n:'prop_tool_pickaxe',t:'Tool'},{n:'prop_tool_shovel',t:'Tool'},{n:'prop_tool_wrench',t:'Tool'},
{n:'prop_bodyarmour_02',t:'Armr'},{n:'prop_bodyarmour_03',t:'Armr'},{n:'prop_armour_pickup',t:'Armr'},
{n:'prop_ld_ammo_pack_01',t:'Ammo'},{n:'prop_ld_ammo_pack_02',t:'Ammo'},
{n:'prop_cs_freightdoor_lft1',t:'Door'},{n:'prop_cs_freightdoor_rt1',t:'Door'},{n:'prop_fnclng_01a',t:'Gate'},
{n:'prop_fncsec_01a',t:'Gate'},{n:'prop_fncsec_02a',t:'Gate'},{n:'prop_fnclon_01a',t:'Gate'},{n:'prop_fnclon_02a',t:'Gate'},
{n:'prop_ramp_freew_01',t:'Ramp'},{n:'prop_ramp_01',t:'Ramp'},{n:'prop_ramp_02',t:'Ramp'},{n:'prop_jetski_ramp_01',t:'Ramp'},
],
vehicles:[
{n:'police',t:'Cop'},{n:'police2',t:'Cop'},{n:'police3',t:'Cop'},{n:'fbi',t:'FIB'},{n:'fbi2',t:'FIB'},
{n:'sheriff',t:'Shrf'},{n:'sheriff2',t:'Shrf'},{n:'riot',t:'Riot'},{n:'riot2',t:'Riot'},
{n:'insurgent',t:'Mili'},{n:'insurgent2',t:'Mili'},{n:'insurgent3',t:'Mili'},
{n:'barracks',t:'Mili'},{n:'barracks2',t:'Mili'},{n:'barracks3',t:'Mili'},
{n:'crusader',t:'Mili'},{n:'halftrack',t:'Mili'},
{n:'rhino',t:'Tank'},{n:'khanjali',t:'Tank'},{n:'apc',t:'APC'},
{n:'chernobog',t:'AA'},{n:'trailersmall2',t:'AA'},
{n:'buzzard',t:'Heli'},{n:'buzzard2',t:'Heli'},{n:'annihilator',t:'Heli'},
{n:'savage',t:'Heli'},{n:'valkyrie',t:'Heli'},{n:'hunter',t:'Heli'},{n:'akula',t:'Heli'},
{n:'lazer',t:'Jet'},{n:'hydra',t:'Jet'},{n:'bombushka',t:'Jet'},{n:'strikeforce',t:'Jet'},
{n:'technical',t:'Rebl'},{n:'technical2',t:'Rebl'},{n:'technical3',t:'Rebl'},
{n:'dune3',t:'Rebl'},{n:'dune4',t:'Rebl'},{n:'dune5',t:'Rebl'},
{n:'nightshark',t:'Armr'},{n:'menacer',t:'Armr'},
{n:'speedo4',t:'Van'},{n:'speedo5',t:'Van'},{n:'boxville4',t:'Van'},{n:'stockade',t:'Van'},
{n:'dinghy',t:'Boat'},{n:'dinghy2',t:'Boat'},{n:'seashark',t:'Boat'},{n:'seashark2',t:'Boat'},
{n:'tropic',t:'Boat'},{n:'tropic2',t:'Boat'},{n:'tug',t:'Boat'},{n:'marquis',t:'Boat'},
],
objectives:[
{n:'obj_victory',t:'Victory',d:'Main capture point'},
{n:'obj_resource',t:'Resource',d:'Resource capture point'},
]
};

var tabDefs=[
  {id:'props',icon:'\u25A0',label:'PROPS'},
  {id:'vehicles',icon:'\u25B6',label:'VEHICLES'},
  {id:'objectives',icon:'\u25C9',label:'OBJS'},
  {id:'spawns',icon:'\u2691',label:'SPAWNS'}
];

function bldFetch(a,d){fetch('https://'+P+'/'+a,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d||{})})}
function bldSend(a,d){bldFetch('editorAction',{action:a,data:d||{}})}

function renderCats(){
  var c=document.getElementById('bldrCats');if(!c)return;
  var h='';
  for(var i=0;i<tabDefs.length;i++){
    var t=tabDefs[i],act=B.cat===t.id?' active':'';
    h+='<div class="sidebar-cat'+act+'" onclick="switchCat(\''+t.id+'\')">'+t.icon+' '+t.label+'</div>';
  }
  c.innerHTML=h;
}

function switchCat(c){B.cat=c;document.getElementById('bldrSearch').value='';renderCats();renderCatalog();}

function renderCatalog(){
  var l=document.getElementById('bldrList');if(!l)return;
  if(B.cat==='spawns'){
    l.innerHTML='<div class="sidebar-item" onclick="bldSend(\'PLACE_SPAWN\',{side:\'team1\'})"><div class="item-tag" style="color:#32ff32">T1</div><div class="item-name">Team 1 Spawn</div></div><div class="sidebar-item" onclick="bldSend(\'PLACE_SPAWN\',{side:\'team2\'})"><div class="item-tag" style="color:#3278ff">T2</div><div class="item-name">Team 2 Spawn</div></div>';
    return;
  }
  var items=CATALOG[B.cat]||[],q=(document.getElementById('bldrSearch').value||'').toLowerCase();
  if(q)items=items.filter(function(i){return i.n.toLowerCase().indexOf(q)!==-1||i.t.toLowerCase().indexOf(q)!==-1});
  if(!items.length){l.innerHTML='<div style="color:#555;padding:20px;text-align:center;font-size:0.68rem">No matches</div>';return}
  l.innerHTML=items.map(function(i){return '<div class="sidebar-item" onclick="spawnModel(\''+i.n+'\')"><div class="item-tag">'+i.t+'</div><div class="item-name">'+i.n+'</div></div>';}).join('');
}

function spawnModel(n){bldSend('SPAWN_MODEL',{model:n});B.mdl=n;var e=document.getElementById('builderModelName');if(e)e.textContent=n.toUpperCase();var ib=document.getElementById('bldrInfoBody');if(ib)ib.innerHTML='<div style="color:#e8a838;font-size:0.72rem">Spawned:</div><div style="color:#5ba4f0;font-size:0.68rem;word-break:break-all;margin-top:3px">'+n+'</div>';}

function toggleSidebar(){
  var s=document.getElementById('bldrSidebar'),t=document.getElementById('bldrToggle');
  if(!s||!t)return;s.classList.toggle('collapsed');
  t.innerHTML=s.classList.contains('collapsed')?'&#x25B6;':'&#x25C0;';
}

function updateObj(idx){
  var n=document.getElementById('objName'),t=document.getElementById('objType'),r=document.getElementById('objRadius'),cr=document.getElementById('objRate'),b=document.getElementById('objBonus');
  console.log('UPDATE_OBJ idx='+idx+' name='+(n?n.value:'null')+' type='+(t?t.value:'null')+' radius='+(r?r.value:'null'));
  var bv=parseFloat(b?b.value:'');bldSend('UPDATE_OBJ',{idx:idx,name:n?n.value:'',type:t?t.value:'resource',radius:parseFloat(r?r.value:'20')||20,captureRate:parseFloat(cr?cr.value:'1.5')||1.5,bonus:isNaN(bv)?null:bv});
}

window.addEventListener('message',function(e){
  var d=e.data;if(!d||!d.action)return;
  if(d.action==='builderShow'){B.v=true;document.getElementById('builderShell').classList.add('active');renderCats();renderCatalog();}
  else if(d.action==='builderHide'){window.location.href='nui://enyo-rts/html/index.html';}
  else if(d.action==='builderInfo'){
    if(d.modelName!==undefined){B.mdl=d.modelName||'';var el=document.getElementById('builderModelName');if(el)el.textContent=B.mdl.toUpperCase();}
    if(d.count!==undefined){B.cnt=d.count;var e2=document.getElementById('builderObjCount');if(e2)e2.textContent=d.count+' objects';}
    if(d.toast){var t=document.createElement('div');t.textContent=d.toast;t.style.cssText='position:fixed;top:50px;left:50%;transform:translateX(-50%);padding:10px 24px;background:rgba(46,204,113,0.95);color:#fff;border-radius:6px;font-family:Share Tech Mono,monospace;font-size:0.75rem;z-index:99999;pointer-events:none';document.body.appendChild(t);setTimeout(function(){t.style.opacity='0';setTimeout(function(){t.remove()},300)},2000);}
    if(d.objData){
      var ib=document.getElementById('bldrInfoBody');if(!ib)return;
      ib.innerHTML='<div style="font-family:Share Tech Mono,monospace;font-size:0.85rem;color:#e8a838;margin-bottom:8px;text-transform:uppercase;letter-spacing:1px">OBJECTIVE #'+d.objIdx+'</div><input id="objName" value="'+d.objData.name+'" onchange="updateObj('+d.objIdx+')" style="width:100%;padding:7px 10px;background:rgba(0,0,0,0.5);border:1px solid rgba(255,255,255,0.12);border-radius:4px;color:#ccc;font-size:0.8rem;margin-bottom:7px;font-family:Share Tech Mono,monospace"><select id="objType" onchange="updateObj('+d.objIdx+')" style="width:100%;padding:7px 10px;background:rgba(0,0,0,0.5);border:1px solid rgba(255,255,255,0.12);border-radius:4px;color:#ccc;font-size:0.8rem;margin-bottom:7px;font-family:Share Tech Mono,monospace"><option value="victory"'+(d.objData.type==='victory'?' selected':'')+'>Victory</option><option value="resource"'+(d.objData.type==='resource'?' selected':'')+'>Resource</option></select><div style="display:flex;gap:6px;margin-bottom:5px;align-items:center"><span style="color:#888;font-size:0.72rem;min-width:32px">Rad:</span><input id="objRadius" value="'+d.objData.radius+'" onchange="updateObj('+d.objIdx+')" style="flex:1;padding:5px 7px;background:rgba(0,0,0,0.5);border:1px solid rgba(255,255,255,0.12);border-radius:3px;color:#ccc;font-size:0.75rem;font-family:Share Tech Mono,monospace"></div><div style="display:flex;gap:6px;margin-bottom:5px;align-items:center"><span style="color:#888;font-size:0.72rem;min-width:32px">Rate:</span><input id="objRate" value="'+d.objData.captureRate+'" onchange="updateObj('+d.objIdx+')" style="flex:1;padding:5px 7px;background:rgba(0,0,0,0.5);border:1px solid rgba(255,255,255,0.12);border-radius:3px;color:#ccc;font-size:0.75rem;font-family:Share Tech Mono,monospace"></div><div style="display:flex;gap:6px;margin-bottom:9px;align-items:center"><span style="color:#888;font-size:0.72rem;min-width:32px">Bon:</span><input id="objBonus" value="'+(d.objData.bonus||'')+'" onchange="updateObj('+d.objIdx+')" style="flex:1;padding:5px 7px;background:rgba(0,0,0,0.5);border:1px solid rgba(255,255,255,0.12);border-radius:3px;color:#ccc;font-size:0.75rem;font-family:Share Tech Mono,monospace"></div><button onclick="updateObj('+d.objIdx+')" style="width:100%;padding:7px;background:rgba(232,168,56,0.12);border:1px solid rgba(232,168,56,0.4);border-radius:4px;color:#e8a838;font-size:0.75rem;cursor:pointer;font-family:Share Tech Mono,monospace;text-transform:uppercase;letter-spacing:1px" onmouseover="this.style.background=\'rgba(232,168,56,0.22)\'" onmouseout="this.style.background=\'rgba(232,168,56,0.12)\'">Update</button>';
    }
  }
});

window.addEventListener('message',function(e){
  var d=e.data;if(!d||!d.type)return;
  if(d.type==='drawMarkers'){
    var c=document.getElementById('screenMarkers');if(!c)return;
    if(!d.markers||!d.markers.length){c.innerHTML='';return}
    var h='';
    for(var i=0;i<d.markers.length;i++){
      var m=d.markers[i],tc=m.color==='#ffffff'?'#000':'#fff';
      h+='<div class="screen-marker" style="left:'+(m.x*100)+'%;top:'+(m.y*100)+'%">'+m.icon+'<span style="background:'+m.color+';color:'+tc+'">'+m.label+'</span></div>';
    }
    c.innerHTML=h;
  }
});

window.addEventListener('keydown',function(e){
  if(e.key==='F10'){e.preventDefault();bldFetch('toggleAdmin');}
  if(!B.v)return;
  var tag=document.activeElement?document.activeElement.tagName:'';
  if(tag==='INPUT'||tag==='SELECT'||tag==='TEXTAREA'){
    if(e.key==='Backspace'||e.key==='Delete')return; // allow editing
  }
  var k={'e':'PICKUP','E':'PICKUP','c':'CLONE','C':'CLONE','r':'RESET_HEIGHT','R':'RESET_HEIGHT','Delete':'DELETE','Del':'DELETE','Backspace':'EXIT','ArrowLeft':'ROTATE_LEFT','ArrowRight':'ROTATE_RIGHT','Shift':'SHIFT_DOWN'};
  if(k[e.key]){if(e.key==='Backspace'&&!tag)return;bldSend(k[e.key]);}
});
window.addEventListener('keyup',function(e){if(!B.v)return;if(e.key==='Shift'&&(!document.activeElement||document.activeElement.tagName!=='INPUT'))bldSend('SHIFT_UP');});
window.addEventListener('mousedown',function(e){if(!B.v)return;var t=e.target;while(t){if(t.id==='bldrSidebar'||t.id==='bldrInfoPanel'||t.id==='bldrList'||t.classList.contains('sidebar-item'))return;t=t.parentElement;}var a=e.button===0?'CLICK_LEFT':e.button===2?'CLICK_RIGHT':null;if(a)bldSend(a);});
window.addEventListener('wheel',function(e){if(!B.v)return;var t=e.target;while(t){if(t.classList&&(t.classList.contains('sidebar-body')||t.classList.contains('panel-body')||t.classList.contains('builder-sidebar')||t.classList.contains('builder-panel')))return;t=t.parentElement;}bldSend(e.deltaY<0?'ZOOM_IN':'ZOOM_OUT');},{passive:true});

renderCats();
renderCatalog();