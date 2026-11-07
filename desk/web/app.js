'use strict';
const $ = id => document.getElementById(id);
let state = null, busy = false, tab = 'board', toastTimer;
const time = seconds => new Date(seconds * 1000).toLocaleString([], {month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'});
function el(tag, text, cls) { const n = document.createElement(tag); if (text !== undefined) n.textContent = text; if (cls) n.className = cls; return n; }
function message(text, error = false) { $('toast').textContent = text; $('toast').className = error ? 'error' : ''; $('toast').hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => $('toast').hidden = true, 6500); }
function showTab(next) { tab = next; for(const name of ['board','discovery','peers','settings']) { $(name).hidden = name !== next; $('tab-'+name).setAttribute('aria-selected', String(name === next)); } }
async function request(path, body) {
  const r = await fetch('/omachan/'+path, {credentials:'same-origin',cache:'no-store',headers:{'content-type':'application/json','x-omachan':'1'},...(body === undefined ? {} : {method:'POST',body:JSON.stringify(body)})});
  if (r.status === 401) { $('login').hidden=false; $('app').hidden=true; $('identity').textContent='Sign in to this ship'; throw new Error('Sign in to your ship'); }
  let data; try { data=await r.json(); } catch { throw new Error('The ship returned an unexpected response'); }
  if(!r.ok) throw new Error(data.error || 'Request failed');
  return data;
}
async function refresh() { if (busy) return false; try { state = await request('state.json'); render(); return true; } catch(e) { if($('login').hidden) message(e.message,true); return false; } }
async function action(name, fields={}) {
  if(busy) return false;
  busy=true;
  try { state=await request('action',{action:name,...fields}); render(); message(state.note || 'Done'); return true; }
  catch(e){message(e.message,true);return false;} finally{busy=false;}
}
function peerButton(label, name, ship, cls='') { const n=el('button',label,cls); n.type='button'; n.onclick=()=>action(name,{ship}); return n; }
function peerCard(p) {
  const card=el('article',undefined,'peer'); card.append(el('h3',p.ship));
  let label=p.connected ? 'CONNECTED · TAGGED MUTUAL' : p.tagged ? (p.mutual ? 'WAITING FOR PEER TAG / CONNECTION' : 'WAITING FOR ADD-BACK') : p.incoming ? 'WANTS TO BE PALS' : p.active ? 'SIGNED OMARCHY CLAIM' : 'NO CURRENT CLAIM';
  card.append(el('span',label,'badge'));
  card.append(el('p',p.active ? `Signature verified · heard via ${p.via || p.ship}${p.expires ? ' · expires '+time(p.expires) : ''}` : 'This ship has no current verified discovery announcement.'));
  const buttons=el('div',undefined,'peer-actions');
  if(p.ignored) buttons.append(peerButton('Restore suggestion','restore',p.ship));
  else if(p.tagged) buttons.append(peerButton('Disconnect my side','remove',p.ship,'danger'));
  else {
    const add=peerButton(p.target ? 'Add omarchy tag' : p.incoming ? 'Add back + tag' : 'Add pal + omarchy tag','add',p.ship,'primary');
    add.disabled=!state.joined || !state.palsRunning || !p.active;
    buttons.append(add,peerButton('Hide','dismiss',p.ship));
  }
  card.append(buttons); return card;
}
const renderedPeers=new Map();
function peerList(id, peers, title, detail) { const area=$(id); const key=JSON.stringify([peers,title,detail,state.joined,state.palsRunning]); if(renderedPeers.get(id)===key)return; renderedPeers.set(id,key); area.replaceChildren(...peers.map(peerCard)); if(!peers.length){const empty=el('div',undefined,'empty');empty.append(el('b',title),el('span',detail));area.append(empty);} }
let renderedPosts='';
function render() {
  document.title='Omachan · '+state.our;
  $('login').hidden=true; $('app').hidden=false; $('identity').textContent=state.our;
  $('connections').textContent=state.peers.filter(p=>p.connected && p.eligible).length;
  $('post-count').textContent=state.posts.length;
  const candidates=state.peers.filter(p=>p.active&&!p.tagged&&!p.ignored);
  $('candidate-count').textContent=candidates.length;
  $('dependency').hidden=state.palsRunning;
  $('join-panel').hidden=state.joined;
  $('discovery-status').textContent=state.joined ? (state.autoAccept ? 'Your signed claim is being shared. Auto-accept is on.' : 'Your signed claim is being shared. Accept peers below.') : 'Join discovery to share your claim and exchange peers.';
  $('auto-accept').checked=!!state.autoAccept;
  $('membership-label').textContent=state.joined?'Your claim is being shared':'Discovery is off'; $('leave').disabled=!state.joined;
  $('desk-distributor').textContent=state.distributor||'';
  $('desk-hub').textContent=state.hub||state.seed||'';
  const serialized=JSON.stringify(state.posts);
  if(serialized!==renderedPosts || !$('posts').children.length){
    renderedPosts=serialized;
    $('posts').replaceChildren(...state.posts.map(p=>{const node=el('article',undefined,'post');const meta=el('div',undefined,'post-meta');meta.append(el('span','ANONYMOUS'),el('time',time(p.when)));node.append(meta,el('p',p.text));return node;}));
    if(!state.posts.length){const n=el('div',undefined,'empty');n.append(el('b','The wind is quiet.'),el('span','Add a tagged mutual, or leave the first whisper.'));$('posts').append(n);}
  }
  peerList('candidates',candidates,'No new faces yet.',state.joined?'Wait for discovery gossip, or check your bootstrap connection.':'Join discovery to introduce yourself.');
  peerList('peer-list',state.peers.filter(p=>(p.target||p.incoming)&&!p.ignored),'Your neighborhood starts here.','Explore Heard about to choose a pal.');
  peerList('hidden-peers',state.peers.filter(p=>p.ignored),'Nothing hidden.','You control which suggestions you see.');
}
document.querySelectorAll('[data-tab]').forEach(n=>n.onclick=()=>showTab(n.dataset.tab));
$('login-form').onsubmit=async e=>{e.preventDefault();try{const r=await fetch('/~/login',{method:'POST',credentials:'same-origin',body:new URLSearchParams({password:$('code').value.trim().replace(/^~/,'')})});$('code').value='';if(!r.ok || !await refresh())throw new Error('Login failed. Check the code from this ship.');}catch(e){message(e.message,true);}};
$('compose').onsubmit=async e=>{e.preventDefault();const text=$('post-text').value.trim();if(!text)return;if(await action('post',{text})){$('post-text').value='';countBytes();}};
function countBytes(){const bytes=new TextEncoder().encode($('post-text').value.trim()).length;$('bytes').textContent=`${bytes} / 1024 bytes`;$('send-post').disabled=bytes===0||bytes>1024;}
$('post-text').oninput=countBytes;
$('auto-accept').onchange=async e=>{if(!await action('preferences',{autoAccept:e.target.checked}))render();};
$('join').onclick=()=>action('join'); $('leave').onclick=()=>action('leave'); $('refresh').onclick=()=>action('retry');
countBytes();refresh();setInterval(()=>{if(!document.hidden)refresh();},4000);document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh();});
