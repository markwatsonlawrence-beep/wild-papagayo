let state=null,media=[],currentArticle=null,pickTarget=null,analytics={};const $=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];
async function api(path,opt={}){const r=await fetch(path,{headers:{'Content-Type':'application/json',...(opt.headers||{})},...opt});const d=await r.json();if(!r.ok)throw new Error(d.error||'La solicitud falló');return d}function esc(v=''){return String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}function toast(m){const t=$('#toast');t.textContent=m;t.classList.add('show');setTimeout(()=>t.classList.remove('show'),2200)}
const VIEW_TITLES={dashboard:'Panel',hotels:'Hoteles',tours:'Tours',destinations:'Destinos',questions:'Preguntas',content:'Contenido',categories:'Categorías',media:'Galería de Medios',intelligence:'Inteligencia',reports:'Reportes',settings:'Ajustes'};
function setView(n){$$('.view').forEach(v=>v.classList.remove('active'));$(`#view-${n}`).classList.add('active');$$('#nav button').forEach(b=>b.classList.toggle('active',b.dataset.view===n));$('#page-title').textContent=VIEW_TITLES[n]||n;const m={dashboard:'Administra toda la plataforma Wild Papagayo.',hotels:'Guías de Hoteles y su información.',tours:'Inteligencia de tours y perfiles de recomendación.',destinations:'Conocimiento de destinos y páginas generadas.',questions:'Preguntas reales de viajeros, etiquetadas y puntuadas por Wild Intelligence.',content:'Crea, edita y publica artículos.',categories:'Gestiona las categorías del blog.',media:'Sube y reutiliza recursos visuales.',intelligence:'Ejecuta herramientas de inteligencia de la plataforma.',reports:'Revisa los reportes del sistema.',settings:'Ajustes locales del CMS.'};$('#page-subtitle').textContent=m[n]||'';if(n==='media')loadMedia();if(n==='questions')loadQuestions();if(n==='reports')renderReports();if(n==='categories')loadCategories()}
async function loadCategories(){
  const r=await api('/api/categories/list');
  const cats=r.categories||[];
  $('#category-list').innerHTML=cats.length?table(['Nombre','Slug','Descripción',''],cats.map(c=>`<tr><td><strong>${esc(c.name)}</strong></td><td><code>${esc(c.slug)}</code></td><td>${esc(c.description||'')}</td><td><button data-cat-delete="${esc(c.slug)}" class="btn alt">Eliminar</button></td></tr>`)):'<p>Todavía no hay categorías.</p>';
  $$('[data-cat-delete]').forEach(b=>b.onclick=async()=>{
    if(!confirm(`¿Eliminar la categoría "${b.dataset.catDelete}"? Solo funciona si ningún artículo la usa.`))return;
    try{
      const res=await api('/api/categories/delete',{method:'POST',body:JSON.stringify({slug:b.dataset.catDelete})});
      if(!res.success)throw new Error(res.error||'No se pudo eliminar');
      toast('Categoría eliminada');await loadCategories();
    }catch(e){alert('Error: '+e.message)}
  });
}
$('#cat-new-save').onclick=async()=>{
  const status=$('#cat-status');
  const name=$('#cat-new-name').value.trim();
  const description=$('#cat-new-description').value.trim();
  if(!name){status.textContent='Escribe un nombre primero.';return}
  status.textContent='Guardando...';
  try{
    const r=await api('/api/categories/save',{method:'POST',body:JSON.stringify({name,description})});
    if(!r.success)throw new Error(r.error||'No se pudo guardar');
    status.textContent=`Creada. Ejecuta "Motor de Categorías" o "Construir Sitio" para publicarla.`;
    $('#cat-new-name').value='';$('#cat-new-description').value='';
    toast('Categoría creada');await loadCategories();
  }catch(e){status.textContent='Error: '+e.message}
};
async function renderReports(){
  if(!state)return;
  const p=state.platform;
  $('#reports-growth').innerHTML=[['Hoteles',p.hotels],['Tours',p.tours],['Destinos',p.destinations],['Artículos',p.articles]].map(x=>`<div class="summary-row"><span>${x[0]}</span><strong>${x[1]}</strong></div>`).join('');
  let questions=[];try{const r=await api('/api/question/list');questions=r.questions||[]}catch(e){}
  const pending=questions.filter(q=>q.status!=='published').length;
  const published=questions.filter(q=>q.status==='published').length;
  const avgPriority=questions.length?Math.round(questions.reduce((a,q)=>a+(q.priority||0),0)/questions.length):0;
  $('#reports-questions').innerHTML=[['Total de Preguntas',questions.length],['Pendientes',pending],['Publicadas como Artículo',published],['Puntaje Promedio de Prioridad',avgPriority]].map(x=>`<div class="summary-row"><span>${x[0]}</span><strong>${x[1]}</strong></div>`).join('');
  const catCounts={};(state.articles||[]).forEach(a=>{const c=a.category||'Sin categoría';catCounts[c]=(catCounts[c]||0)+1});
  const catRows=Object.entries(catCounts).sort((a,b)=>b[1]-a[1]);
  $('#reports-categories').innerHTML=catRows.length?catRows.map(([c,n])=>`<div class="summary-row"><span>${esc(c)}</span><strong>${n}</strong></div>`).join(''):'<p>Todavía no hay artículos.</p>';
  $('#reports-status').innerHTML=[['Estado de Construcción',p.build_status],['Errores',p.build_errors],['Advertencias',p.build_warnings],['Listo para Producción',p.production_ready?'Sí':'No']].map(x=>`<div class="summary-row"><span>${x[0]}</span><strong>${esc(x[1])}</strong></div>`).join('');
  let destHealth=[];try{const r=await api('/api/reports/destination-health');destHealth=r.destinations||[]}catch(e){}
  $('#reports-destination-health').innerHTML=destHealth.length?destHealth.map(d=>{
    const stars='&#9733;'.repeat(Math.round(d.score/20))+'&#9734;'.repeat(5-Math.round(d.score/20));
    const missing=(d.missing||[]).length?`<br><small style="color:#b8860b">Falta: ${esc(d.missing.join(', '))}</small>`:'';
    return `<div class="summary-row"><span>${esc(d.name)} <span style="color:#C9A24B">${stars}</span>${missing}</span><strong>${d.score}%</strong></div>`;
  }).join(''):'<p>Ejecuta el Reporte de Salud de Destinos desde Inteligencia para ver esto.</p>';
}
function table(h,r){return r.length?`<table class="data-table"><thead><tr>${h.map(x=>`<th>${x}</th>`).join('')}</tr></thead><tbody>${r.join('')}</tbody></table>`:'<p>No se encontraron registros.</p>'}
function render(){const p=state.platform;$('#api-status').textContent='Conectado';$('#api-status').classList.add('ok');$('#health-title').textContent=p.production_ready?'Listo para Producción':'Requiere Revisión';$('#health-orb').textContent=p.production_ready?'LISTO':'REVISAR';$('#kpis').innerHTML=[['Hoteles',p.hotels],['Tours',p.tours],['Destinos',p.destinations],['Artículos',p.articles],['Preguntas Pendientes',p.questions_pending],['Preguntas Publicadas',p.questions_published],['Borradores',p.drafts],['Oportunidades',p.opportunities]].map(x=>`<div class="kpi"><small>${x[0]}</small><strong>${x[1]}</strong></div>`).join('');$('#build-summary').innerHTML=[['Estado',p.build_status],['Última construcción',p.build_date||'—'],['Errores',p.build_errors],['Advertencias',p.build_warnings]].map(x=>`<div class="summary-row"><span>${x[0]}</span><strong>${esc(x[1])}</strong></div>`).join('');$('#hotel-table').innerHTML=table(['Hotel','Categoría','Ubicación','Flujo','Calidad','Página'],state.hotels.map(h=>`<tr class="hotel-row" data-hotel="${esc(h.id)}"><td><strong>${esc(h.name)}</strong></td><td>${esc(h.category)}</td><td>${esc(h.location)}</td><td><span class="badge">${esc(h.workflow)}</span></td><td>${h.quality==null?'—':h.quality+'%'}</td><td><a href="${esc(h.page)}" target="_blank" onclick="event.stopPropagation()">Abrir</a></td></tr>`));renderTours();$('#destination-table').innerHTML=table(['Destino','Provincia','Página',''],state.destinations.map(d=>`<tr class="destination-row" data-destination="${esc(d.id)}"><td><strong>${esc(d.name)}</strong></td><td>${esc(d.province)}</td><td><a href="${esc(d.page)}" target="_blank" onclick="event.stopPropagation()">Abrir</a></td><td><button onclick="event.stopPropagation();showDestinationDetail('${esc(d.id)}')">Editar</button></td></tr>`));$$('.destination-row').forEach(r=>r.onclick=()=>showDestinationDetail(r.dataset.destination));$('#opportunity-list').innerHTML=state.opportunities.map(o=>`<div class="summary-row"><div><strong>${esc(o.title)}</strong><br><small>${esc(o.reason||'')}</small></div><button data-op='${esc(JSON.stringify(o))}'>Usar</button></div>`).join('')||'<p>Todavía no hay oportunidades.</p>';$('#draft-list').innerHTML=table(['Título','Slug','Estado','Modificado','Acción'],state.drafts.map(d=>`<tr><td>${esc(d.title)}</td><td><code>${esc(d.slug)}</code></td><td>${esc(d.status)}</td><td>${esc(d.modified)}</td><td><button data-draft="${esc(d.slug)}">Editar</button></td></tr>`));renderPublished();bindDynamic()}
function setTab(n){$$('.tab').forEach(x=>x.classList.remove('active'));$(`#tab-${n}`).classList.add('active');$$('[data-tab]').forEach(b=>b.classList.toggle('active',b.dataset.tab===n))}
function bindDynamic(){$$('.hotel-row').forEach(r=>r.onclick=()=>showHotelDetail(r.dataset.hotel));$$('[data-draft]').forEach(b=>b.onclick=safeAction(async()=>{loadArticle(await api(`/api/content/draft?slug=${encodeURIComponent(b.dataset.draft)}`));setView('content');setTab('editor');toast('Artículo cargado')}));$$('[data-op]').forEach(b=>b.onclick=()=>{const o=JSON.parse(b.dataset.op);loadArticle({id:Date.now(),slug:o.slug,status:'draft',opportunity_id:o.id,content_type:o.type,category:'Tours & Experiences',date:new Date().toLocaleDateString('en-US',{month:'long',day:'numeric',year:'numeric'}),readTime:'7',iso_date:new Date().toISOString(),title:o.title,excerpt:`Una guía práctica de Wild Papagayo sobre ${o.title}.`,seo_title_pro:`${o.title} | Wild Papagayo`,seo_description:`Planifica ${o.title} con información local de Guanacaste.`,image_top:'',image_top_alt:o.title,image_middle:'',image_bottom:'',content_block_1:'<h2>Start With the Traveler\'s Main Question</h2>',content_block_2:'<h2>How to Plan It Well</h2>',content_block_faq:'<h2>Frequently Asked Questions</h2>',content_block_3:'<h2>Our Bottom Line</h2>',cta_url:'https://wa.me/50688566325',cta_text:'Plan This Experience With a Local Expert'});setTab('editor');toast('Borrador iniciado -- usa "Escribir Primer Borrador con Claude" para completarlo')})}
function imageUrl(p){if(!p)return'';return p.startsWith('images/')?'/project-media/'+p.substring(7):p}function syncPreview(){[['top','image_top'],['middle','image_middle'],['bottom','image_bottom']].forEach(([id,f])=>{$(`#preview-${id}`).src=imageUrl($(`#field-image-${id}`).value)})}
function calculateQuality(a){
  if(!a)return{score:0,improvements:[]};
  const imp=[];
  let s=0;
  let maxPts=0;
  const chk=(label,passed,pts,msg)=>{maxPts+=pts;if(passed){s+=pts;}else if(msg){imp.push(msg);}};
  const v=k=>String(a[k]||'');
  const title=v('title'),slug=v('slug'),excerpt=v('excerpt');
  const b1=v('content_block_1'),b2=v('content_block_2'),b3=v('content_block_3'),faq=v('content_block_faq');
  const st=v('seo_title_pro'),sd=v('seo_description'),kw=v('seo_keywords');
  const img=v('image_top'),imgAlt=v('image_top_alt');
  const imgM=v('image_middle'),imgMAlt=v('image_middle_alt');
  const imgB=v('image_bottom'),imgBAlt=v('image_bottom_alt');
  const cta=v('cta_text'),ctaUrl=v('cta_url'),tip=v('travel_tip');
  const links=Array.isArray(a.internal_links)?a.internal_links:[];
  const rels=(Array.isArray(a.tour_ids)?a.tour_ids.length:0)+(Array.isArray(a.hotel_ids)?a.hotel_ids.length:0)+(Array.isArray(a.destination_ids)?a.destination_ids.length:0);
  const kwCount=kw.split(',').filter(x=>x.trim()).length;
  const placeholders=['Editorial draft:','Replace this placeholder','Requires editorial','Summarize who should choose','Explain why this topic matters'];
  const raw=JSON.stringify(a);
  const hasPlaceholders=placeholders.some(p=>raw.includes(p));
  const usedImages=[img,imgM,imgB].filter(Boolean).length;
  chk('title',!!title.trim(),5,'Agrega un título claro al artículo.');
  chk('slug',!!slug.trim(),5,'Agrega un slug corto y descriptivo.');
  chk('excerpt',excerpt.length>=80,5,'Amplía el extracto a al menos 80 caracteres.');
  chk('blocks',!!(b1.trim()&&b2.trim()&&b3.trim()),10,'Completa los tres bloques principales de contenido.');
  chk('faq',faq.includes('<h3')&&faq.length>=180,5,'Agrega preguntas frecuentes útiles (con encabezados <h3>, mínimo 180 caracteres).');
  chk('seo_title_present',!!st.trim(),5,'Agrega un título SEO.');
  chk('seo_title_len',st.length>=40&&st.length<=60&&!st.endsWith('...'),5,'Mantén el título SEO entre 40 y 60 caracteres, sin puntos suspensivos de truncado.');
  chk('seo_desc_present',!!sd.trim(),5,'Agrega una descripción SEO.');
  chk('seo_desc_len',sd.length>=120&&sd.length<=155&&!sd.endsWith('...'),5,'Mantén la descripción SEO entre 120 y 155 caracteres, sin puntos suspensivos de truncado.');
  chk('keywords',kwCount>=3,5,'Agrega al menos tres palabras clave SEO relevantes.');
  chk('hero',!!img.trim(),5,'Selecciona una foto principal.');
  chk('hero_alt',!img.trim()||!!imgAlt.trim(),3,'Agrega texto alternativo a la foto principal.');
  chk('mid_alt',!imgM.trim()||!!imgMAlt.trim(),3,'Agrega texto alternativo a la foto de en medio.');
  chk('bot_alt',!imgB.trim()||!!imgBAlt.trim(),3,'Agrega texto alternativo a la foto final.');
  chk('visuals',usedImages>=1,6,'Agrega al menos una foto relevante.');
  chk('links',links.length>=3,5,'Agrega al menos tres enlaces internos.');
  chk('rels',rels>=1,5,'Relaciona el artículo con al menos un hotel, tour o destino.');
  chk('cta',!!(cta.trim()&&ctaUrl.trim()),5,'Agrega texto y URL para el botón de acción (CTA).');
  chk('editorial',!hasPlaceholders,7,'Reemplaza todos los textos de relleno con contenido final.');
  chk('tip',!!tip.trim()&&!tip.includes('Replace this placeholder'),3,'Agrega un consejo local específico.');
  chk('quick_facts',Array.isArray(a.quick_facts)&&a.quick_facts.length>=3,4,'Agrega al menos 3 Quick Facts.');
  const pct=maxPts>0?Math.round((s/maxPts)*100):0;
  return{score:Math.min(100,Math.max(0,pct)),improvements:imp};
}
function evaluateArticle(a){
  if(!a)return;
  const r=calculateQuality(a);
  const score=r.score,ring=$('#article-quality-ring');
  $('#article-quality-score').textContent=score;
  ring.style.setProperty('--quality',`${score*3.6}deg`);
  ring.classList.toggle('is-good',score>=90);
  ring.classList.toggle('is-perfect',score===100);
  $('#article-quality-status').textContent=score===100?'Excelente -- listo al 100%':score>=90?'Casi listo':score>=75?'Buena base':'Necesita mejorar';
  const items=r.improvements.slice(0,8);
  $('#article-quality-improvements').innerHTML=items.length?items.map(x=>`<li>${esc(x)}</li>`).join(''):'<li>Se cumplieron todos los criterios de calidad.</li>';
}
function fmtNum(n){return n?Number(n).toLocaleString():'0'}
function fmtDate(s){if(!s)return'—';const d=new Date(s);return isNaN(d)?'—':d.toLocaleDateString('es-CR',{month:'short',day:'numeric',year:'numeric'})}
function renderPublished(){
  const articles=state.articles||[];
  const vals=Object.values(analytics);
  const totalReads=vals.reduce((a,v)=>a+(v.views||0),0);
  const readersMonth=vals.reduce((a,v)=>a+(v.views_30d||0),0);
  const countryMap={};
  vals.forEach(v=>{if(v.countries)Object.entries(v.countries).forEach(([c,n])=>countryMap[c]=(countryMap[c]||0)+n)});
  const topCountry=Object.entries(countryMap).sort((a,b)=>b[1]-a[1])[0]?.[0]||'—';
  const waClicks=vals.reduce((a,v)=>a+(v.sources?.whatsapp||0),0);
  $('#analytics-kpi').innerHTML=`<div class="a-kpi-bar"><div class="a-kpi"><small>Publicados</small><strong>${articles.length}</strong></div><div class="a-kpi"><small>Lecturas Totales</small><strong>${fmtNum(totalReads)}</strong></div><div class="a-kpi"><small>Lectores (30d)</small><strong>${fmtNum(readersMonth)}</strong></div><div class="a-kpi"><small>País Principal</small><strong>${esc(topCountry)}</strong></div><div class="a-kpi"><small>Clics a WhatsApp</small><strong>${fmtNum(waClicks)}</strong></div></div>`;
  const rows=articles.map(a=>{const s=analytics[a.slug]||{};const tc=s.countries?Object.entries(s.countries).sort((x,y)=>y[1]-x[1])[0]?.[0]||'—':'—';return`<tr><td class="article-row" data-slug="${esc(a.slug)}"><strong>${esc(a.title)}</strong></td><td><span class="badge">${esc(a.status||'published')}</span></td><td class="num">${fmtNum(s.views)}</td><td class="num">${fmtNum(s.unique_visitors)}</td><td>${esc(tc)}</td><td>${fmtDate(s.last_view)}</td><td><button data-published-edit="${esc(a.slug)}">Editar</button></td></tr>`;});
  $('#article-list').innerHTML=rows.length?`<table class="data-table"><thead><tr><th>Título</th><th>Estado</th><th>Lecturas</th><th>Visitantes</th><th>País Principal</th><th>Última Lectura</th><th>Acción</th></tr></thead><tbody>${rows.join('')}</tbody></table>`:'<p>Todavía no hay artículos publicados.</p>';
  $$('.article-row').forEach(r=>r.onclick=()=>showArticleDetail(r.dataset.slug));
  $$('[data-published-edit]').forEach(b=>b.onclick=safeAction(async(e)=>{e.stopPropagation();loadArticle(await api(`/api/content/published?slug=${encodeURIComponent(b.dataset.publishedEdit)}`));setView('content');setTab('editor');toast('Artículo cargado')}));
}
function showArticleDetail(slug){
  const s=analytics[slug]||{};
  const a=(state.articles||[]).find(x=>x.slug===slug)||{};
  const countries=Object.entries(s.countries||{}).sort((a,b)=>b[1]-a[1]).slice(0,5);
  const devices=Object.entries(s.devices||{}).sort((a,b)=>b[1]-a[1]);
  const sources=Object.entries(s.sources||{}).sort((a,b)=>b[1]-a[1]);
  const statRows=(arr)=>arr.length?arr.map(([k,n])=>`<div class="a-stat-row"><span>${esc(k)}</span><span>${n}</span></div>`).join(''):'<p class="a-empty">Todavía no hay datos</p>';
  $('#article-detail').innerHTML=`<div class="a-detail-panel"><div class="a-detail-header"><h4>${esc(a.title||slug)}</h4><button onclick="document.getElementById('article-detail').innerHTML=''">×</button></div><div class="a-detail-grid"><div class="a-detail-kpi"><small>Lecturas Totales</small><strong>${fmtNum(s.views)}</strong></div><div class="a-detail-kpi"><small>Visitantes Únicos</small><strong>${fmtNum(s.unique_visitors)}</strong></div><div class="a-detail-kpi"><small>Últimos 7 Días</small><strong>${fmtNum(s.views_7d)}</strong></div><div class="a-detail-kpi"><small>Últimos 30 Días</small><strong>${fmtNum(s.views_30d)}</strong></div></div><div class="a-detail-sections"><div class="a-detail-section"><h5>Países</h5>${statRows(countries)}</div><div class="a-detail-section"><h5>Dispositivos</h5>${statRows(devices)}</div><div class="a-detail-section"><h5>Fuentes de Tráfico</h5>${statRows(sources)}</div></div><p class="a-detail-date">Última lectura: ${fmtDate(s.last_view)}</p></div>`;
}
function scheduleQuality(){clearTimeout(scheduleQuality.timer);scheduleQuality.timer=setTimeout(()=>{try{const a=currentArticle||parse();evaluateArticle(a)}catch(e){}},250)}
function linksToText(links){return(Array.isArray(links)?links:[]).map(l=>`${l.text||''} | ${l.url||''}`).join('\n')}
function textToLinks(text){return String(text||'').split('\n').map(l=>l.trim()).filter(Boolean).map(l=>{const i=l.indexOf('|');return i===-1?{text:l.trim(),url:''}:{text:l.slice(0,i).trim(),url:l.slice(i+1).trim()}})}
function factsToText(facts){return(Array.isArray(facts)?facts:[]).join('\n')}
function textToFacts(text){return String(text||'').split('\n').map(l=>l.trim()).filter(Boolean)}
const ACCENT_MAP={'á':'a','é':'e','í':'i','ó':'o','ú':'u','ñ':'n','ü':'u'};
function slugify(text){
  let s=(text||'').toLowerCase();
  for(const k in ACCENT_MAP)s=s.split(k).join(ACCENT_MAP[k]);
  return s.replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'');
}
function loadArticle(a){
  if(a&&!a.slug&&a.title)a.slug=slugify(a.title);
  currentArticle=a;$('#json-input').value=JSON.stringify(a,null,2);for(const [id,key] of [['title','title'],['slug','slug'],['excerpt','excerpt'],['seo-title','seo_title_pro'],['seo-description','seo_description'],['image-top','image_top'],['image-top-alt','image_top_alt'],['image-middle','image_middle'],['image-middle-alt','image_middle_alt'],['image-bottom','image_bottom'],['image-bottom-alt','image_bottom_alt'],['block1','content_block_1'],['block2','content_block_2'],['travel-tip','travel_tip'],['faq','content_block_faq'],['block3','content_block_3'],['cta-text','cta_text'],['cta-url','cta_url']])$(`#field-${id}`).value=a[key]||'';$('#field-internal-links').value=linksToText(a.internal_links);$('#field-quick-facts').value=factsToText(a.quick_facts);$('#auto-draft-status').textContent='';syncPreview();$('#validation-result').textContent='Artículo cargado.';evaluateArticle(a);renderSimilarWarning('article-similar-warning',a.title||'',a.slug||'')}
function parse(){try{return JSON.parse($('#json-input').value)}catch(e){$('#validation-result').textContent='JSON inválido: '+e.message;throw e}}function apply(silent=false){const a=currentArticle||parse(),m={title:'title',slug:'slug',excerpt:'excerpt','seo-title':'seo_title_pro','seo-description':'seo_description','image-top':'image_top','image-top-alt':'image_top_alt','image-middle':'image_middle','image-middle-alt':'image_middle_alt','image-bottom':'image_bottom','image-bottom-alt':'image_bottom_alt',block1:'content_block_1',block2:'content_block_2','travel-tip':'travel_tip',faq:'content_block_faq',block3:'content_block_3','cta-text':'cta_text','cta-url':'cta_url'};for(const [id,k] of Object.entries(m))a[k]=$(`#field-${id}`).value;if(!a.slug&&a.title){a.slug=slugify(a.title);$('#field-slug').value=a.slug}a.internal_links=textToLinks($('#field-internal-links').value);a.quick_facts=textToFacts($('#field-quick-facts').value);currentArticle=a;$('#json-input').value=JSON.stringify(a,null,2);syncPreview();evaluateArticle(a);if(!silent)toast('Cambios aplicados')}
async function loadMedia(){const d=await api('/api/media');media=d.items||[];renderMedia()}function renderMedia(){const q=($('#media-search')?.value||'').toLowerCase(),f=$('#media-folder')?.value||'';const items=media.filter(x=>(!f||x.folder===f)&&(!q||(`${x.name} ${x.alt} ${x.caption}`).toLowerCase().includes(q)));const html=items.map(x=>`<div class="media-card" data-media="${esc(x.id)}"><img src="${imageUrl(x.file)}"><div><strong>${esc(x.name)}</strong><br><small>${esc(x.folder)} · ${Math.round((x.size_bytes||0)/1024)} KB</small><br><small>${esc(x.alt||'Falta texto alternativo')}</small></div></div>`).join('')||'<p>Todavía no se ha subido ninguna imagen.</p>';$('#media-grid').innerHTML=html;$('#modal-media-grid').innerHTML=html;$$('[data-media]').forEach(c=>c.onclick=()=>{const x=media.find(m=>m.id===c.dataset.media);if(!pickTarget||!x)return;if(pickTarget==='hotel_hero'){$('#edit-hero-image').value=x.file;$('#edit-hero-image-preview').src=imageUrl(x.file);if(x.alt)$('#edit-hero-image-alt').value=x.alt}else if(pickTarget==='tour_hero'){$('#tour-edit-hero-image').value=x.file;$('#tour-edit-hero-preview').src=imageUrl(x.file);if(x.alt)$('#tour-edit-hero-alt').value=x.alt}else{const map={image_top:'top',image_middle:'middle',image_bottom:'bottom'};$(`#field-image-${map[pickTarget]}`).value=x.file;const altField=$(`#field-image-${map[pickTarget]}-alt`);if(altField&&x.alt)altField.value=x.alt;syncPreview()}$('#media-modal').classList.remove('show');pickTarget=null})}
async function run(name){$('#command-output').textContent='Ejecutando '+name+'...';setView('intelligence');const r=await api('/api/run',{method:'POST',body:JSON.stringify({name})});$('#command-output').textContent=r.output||'Completado';await refresh()}
function renderTours(){
  const q=($('#tour-search')?.value||'').toLowerCase();
  const rows=[...(state.tours||[])]
    .filter(t=>!q||(`${t.name} ${t.category}`).toLowerCase().includes(q))
    .sort((a,b)=>(b.priority||0)-(a.priority||0));
  $('#tour-table').innerHTML=table(['Tour','Categoría','Energía','Prioridad','Estado','Página',''],rows.map(t=>`<tr class="tour-row" data-tour="${esc(t.id)}"><td><strong>${esc(t.name)}</strong></td><td>${esc(t.category)}</td><td>${esc(t.energy)}</td><td>${t.priority}</td><td><span class="badge">${esc(t.status)}</span></td><td>${t.page?`<a href="${esc(t.page)}" target="_blank" onclick="event.stopPropagation()">Abrir</a>`:'—'}</td><td><button onclick="event.stopPropagation();showTourDetail('${esc(t.id)}')">Editar</button></td></tr>`));
  $$('.tour-row').forEach(r=>r.onclick=()=>showTourDetail(r.dataset.tour));
}
async function showTourDetail(id){
  const t=(state.tours||[]).find(x=>x.id===id);if(!t)return;
  $('#tour-detail').innerHTML=`<div class="a-detail-panel"><div class="a-detail-header"><h4>${esc(t.name)}</h4><button onclick="document.getElementById('tour-detail').innerHTML=''">×</button></div><div id="tour-edit-form"><p>Cargando...</p></div></div>`;
  await openTourEditForm(id);
}
async function openTourEditForm(id){
  const box=$('#tour-edit-form');
  const detail=await api(`/api/tour/detail?id=${encodeURIComponent(id)}`);
  const includedText=(detail.included||[]).join('\n');
  const bringText=(detail.what_to_bring||[]).join('\n');
  box.innerHTML=`<div class="form">
    <label class="wide">Descripción Corta<textarea id="tour-edit-desc">${esc(detail.short_description)}</textarea></label>
    <label>Dificultad<input id="tour-edit-difficulty" value="${esc(detail.difficulty)}" placeholder="ej. Easy to Moderate"></label>
    <label>Duración<input id="tour-edit-duration" value="${esc(detail.duration_label)}" placeholder="ej. Full Day (approx. 9 hours)"></label>
    <label class="wide">Foto Principal<div class="media-field"><img id="tour-edit-hero-preview" src="${imageUrl(detail.hero_image)}"><input id="tour-edit-hero-image" value="${esc(detail.hero_image)}" placeholder="images/ejemplo.webp"><button type="button" id="tour-edit-hero-pick">Elegir Foto</button></div></label>
    <label class="wide">Texto Alternativo (foto)<input id="tour-edit-hero-alt" value="${esc(detail.hero_image_alt)}"></label>
    <label class="wide">Precio Público Canónico (solo lectura)<input value="${detail.canonical_from_price!=null?('$'+detail.canonical_from_price+' p.p. ('+esc(detail.canonical_status)+')'):esc(detail.canonical_status||'no disponible')}" disabled title="Gestionado en knowledge/pricing/Matriz_Cotizador_Wild_Papagayo_Catalogo_Completo.xlsx -- editar el Excel y ejecutar excel-to-pricing.js, no aquí."></label>
    <label>Precio Guía Únicamente (Self-Drive)<input id="tour-edit-price" value="${esc(detail.from_price)}" placeholder="ej. 100"></label>
    <label>Moneda (Guía Únicamente)<input id="tour-edit-currency" value="${esc(detail.currency||'USD')}"></label>
    <label class="wide">Nota de Precio (primera opción)<input id="tour-edit-price-note" value="${esc(detail.pricing_note)}" placeholder="ej. Verify current rate before publishing."></label>
  </div>
  <h4>Qué Incluye</h4>
  <label class="wide">Uno por línea<textarea id="tour-edit-included" class="code" rows="5">${esc(includedText)}</textarea></label>
  <h4>Qué Llevar</h4>
  <label class="wide">Uno por línea<textarea id="tour-edit-bring" class="code" rows="5">${esc(bringText)}</textarea></label>
  <div class="row" style="margin-top:14px"><button id="tour-edit-save-btn" class="btn">Guardar</button></div>
  <pre id="tour-edit-status"></pre>`;
  $('#tour-edit-hero-pick').onclick=async()=>{pickTarget='tour_hero';await loadMedia();$('#media-modal').classList.add('show')};
  $('#tour-edit-save-btn').onclick=()=>saveTourEdit(id);
}
async function saveTourEdit(id){
  const status=$('#tour-edit-status');status.textContent='Guardando...';
  const short_description=$('#tour-edit-desc').value.trim();
  const difficulty=$('#tour-edit-difficulty').value.trim();
  const duration_label=$('#tour-edit-duration').value.trim();
  const hero_image=$('#tour-edit-hero-image').value.trim();
  const hero_image_alt=$('#tour-edit-hero-alt').value.trim();
  const from_price=$('#tour-edit-price').value.trim();
  const currency=$('#tour-edit-currency').value.trim();
  const pricing_note=$('#tour-edit-price-note').value.trim();
  const included=$('#tour-edit-included').value.split('\n').map(x=>x.trim()).filter(Boolean);
  const what_to_bring=$('#tour-edit-bring').value.split('\n').map(x=>x.trim()).filter(Boolean);
  try{
    const r=await api('/api/tour/update',{method:'POST',body:JSON.stringify({id,short_description,difficulty,duration_label,hero_image,hero_image_alt,from_price,currency,pricing_note,included,what_to_bring})});
    if(!r.success)throw new Error(r.error||'Falló el guardado');
    status.textContent='Guardado.';
    toast('Tour actualizado');
  }catch(e){status.textContent='Error: '+e.message}
}
async function showDestinationDetail(id){
  const d=(state.destinations||[]).find(x=>x.id===id);if(!d)return;
  $('#destination-detail').innerHTML=`<div class="a-detail-panel"><div class="a-detail-header"><h4>${esc(d.name)}</h4><button onclick="document.getElementById('destination-detail').innerHTML=''">×</button></div><div id="destination-edit-form"><p>Cargando...</p></div></div>`;
  await openDestinationEditForm(id);
}
async function openDestinationEditForm(id){
  const box=$('#destination-edit-form');
  box.innerHTML='<p>Cargando...</p>';
  const detail=await api(`/api/destination/detail?id=${encodeURIComponent(id)}`);
  const faqRows=(detail.faq&&detail.faq.length?detail.faq:[{q:'',a:''}]);
  box.innerHTML=`<h4>Editar Destino</h4>
  <div class="form">
    <label class="wide">Descripción Corta (hero)<textarea id="dest-edit-hero-desc" rows="2">${esc(detail.hero_description)}</textarea></label>
    <label class="wide">Descripción Completa<textarea id="dest-edit-description" rows="5">${esc(detail.description)}</textarea></label>
    <label>Mejor Temporada<input id="dest-edit-season" value="${esc(detail.best_season)}" placeholder="ej. Diciembre-Abril"></label>
    <label class="wide">Ideal Para (una por línea)<textarea id="dest-edit-best-for" rows="3">${esc((detail.best_for||[]).join('\n'))}</textarea></label>
    <label class="wide">Lo que más gusta (una por línea)<textarea id="dest-edit-highlights" rows="5">${esc((detail.highlights||[]).join('\n'))}</textarea></label>
    <label class="wide">A Considerar (una por línea)<textarea id="dest-edit-considerations" rows="4">${esc((detail.considerations||[]).join('\n'))}</textarea></label>
  </div>
  <h4>Preguntas Frecuentes</h4>
  <div id="dest-edit-faq">${faqRows.map(r=>faqRowHtml(r.q,r.a)).join('')}</div>
  <button id="dest-edit-faq-add" class="btn alt" type="button">+ Agregar Pregunta</button>
  <div class="row" style="margin-top:14px"><button id="dest-edit-save-btn" class="btn">Guardar</button></div>
  <pre id="dest-edit-status"></pre>`;
  $('#dest-edit-faq-add').onclick=()=>{$('#dest-edit-faq').insertAdjacentHTML('beforeend',faqRowHtml('',''))};
  $('#dest-edit-save-btn').onclick=()=>saveDestinationEdit(id);
}
async function saveDestinationEdit(id){
  const status=$('#dest-edit-status');status.textContent='Guardando...';
  const hero_description=$('#dest-edit-hero-desc').value.trim();
  const description=$('#dest-edit-description').value.trim();
  const best_season=$('#dest-edit-season').value.trim();
  const best_for=$('#dest-edit-best-for').value.split('\n').map(x=>x.trim()).filter(Boolean);
  const highlights=$('#dest-edit-highlights').value.split('\n').map(x=>x.trim()).filter(Boolean);
  const considerations=$('#dest-edit-considerations').value.split('\n').map(x=>x.trim()).filter(Boolean);
  const faq=$$('#dest-edit-faq .faq-row').map(r=>({q:r.querySelector('.faq-q').value.trim(),a:r.querySelector('.faq-a').value.trim()})).filter(x=>x.q);
  try{
    const r=await api('/api/destination/update',{method:'POST',body:JSON.stringify({id,hero_description,description,best_season,best_for,highlights,considerations,faq})});
    if(!r.success)throw new Error(r.error||'Falló el guardado');
    status.textContent='Guardado. Ejecuta "Construir Sitio" para verlo en la página en vivo.';
    toast('Destino actualizado');
  }catch(e){status.textContent='Error: '+e.message}
}
async function showHotelDetail(id){
  const h=(state.hotels||[]).find(x=>x.id===id);if(!h)return;
  let quality=null;try{quality=await api(`/api/hotel/quality?id=${encodeURIComponent(id)}`)}catch(e){}
  const score=quality?quality.overall:(h.quality||0);
  const sections=quality&&quality.sections?Object.entries(quality.sections):[];
  const ready=quality&&quality.ready_to_publish;
  const workflowBadge=`<span class="badge">${esc(h.workflow||'draft')}</span>`;
  $('#hotel-detail').innerHTML=`<div class="a-detail-panel"><div class="a-detail-header"><h4>${esc(h.name)} ${workflowBadge}</h4><button onclick="document.getElementById('hotel-detail').innerHTML=''">×</button></div>
  <div class="quality-card"><div class="quality-ring${score>=90?' is-good':''}${score>=100?' is-perfect':''}" style="--quality:${score*3.6}deg"><strong>${score}</strong><span>/100</span></div><div class="quality-copy"><small>CALIDAD DEL HOTEL</small><h4>${ready?'Listo para publicar':'Requiere revisión'}</h4><ul>${sections.length?sections.map(([k,v])=>`<li>${esc(k)}: ${v}%</li>`).join(''):'<li>Ejecuta Wild Intelligence para calcular un puntaje de calidad.</li>'}</ul></div></div>
  <div class="row"><button id="hotel-complete-btn" class="btn">✨ Completar con Wild Intelligence</button><button id="hotel-edit-btn" class="btn alt">✎ Editar Detalles</button>${h.workflow!=='published'?`<button id="hotel-publish-btn" class="btn alt">🚀 Publicar Hotel</button>`:''}</div>
  <pre id="hotel-complete-output" class="console">${quality?'Última ejecución disponible. Vuelve a ejecutar para actualizar todas las secciones.':'Todavía no se ha ejecutado.'}</pre>
  <div id="hotel-edit-form"></div></div>`;
  $('#hotel-complete-btn').onclick=()=>completeHotel(id);
  $('#hotel-edit-btn').onclick=()=>openHotelEditForm(id);
  if($('#hotel-publish-btn'))$('#hotel-publish-btn').onclick=async()=>{
    const out=$('#hotel-complete-output');out.textContent='Publicando...';
    try{
      const r=await api('/api/hotel/publish',{method:'POST',body:JSON.stringify({id})});
      if(!r.success)throw new Error(r.error||'No se pudo publicar');
      out.textContent='Publicado. Ejecuta "Construir Sitio" para verlo en la página en vivo.';
      toast('Hotel publicado');
      await refresh();showHotelDetail(id);
    }catch(e){out.textContent='Error: '+e.message}
  };
}
async function openHotelEditForm(id){
  const box=$('#hotel-edit-form');
  box.innerHTML='<p>Cargando...</p>';
  const detail=await api(`/api/hotel/detail?id=${encodeURIComponent(id)}`);
  const tours=state.tours||[];
  const selectedTours=new Set(detail.featured_tours||[]);
  const faqRows=(detail.faq&&detail.faq.length?detail.faq:[{q:'',a:''}]);
  const roomRows=(detail.room_types&&detail.room_types.length?detail.room_types:[{name:'',description:''}]);
  const amenitiesText=(detail.amenities||[]).join('\n');
  box.innerHTML=`<h4>Editar Detalles del Hotel</h4>
  <div class="form">
    <label>Marca<input id="edit-brand" value="${esc(detail.brand)}"></label>
    <label>Categoría<input id="edit-category" value="${esc(detail.category)}" placeholder="ej. Resort de Lujo en la Playa"></label>
    <label class="wide">Nivel de Lujo<select id="edit-luxury-level"><option value="">Seleccionar...</option>${['Luxury','Upscale','Boutique','Standard'].map(o=>`<option value="${o}"${detail.luxury_level===o?' selected':''}>${o}</option>`).join('')}</select></label>
    <label class="wide">Foto Principal<div class="media-field"><img id="edit-hero-image-preview" src="${imageUrl(detail.hero_image)}"><input id="edit-hero-image" value="${esc(detail.hero_image)}" placeholder="images/hotels/ejemplo.jpg"><button type="button" id="edit-hero-pick">Elegir Foto</button></div></label>
    <label class="wide">Texto Alternativo (foto principal)<input id="edit-hero-image-alt" value="${esc(detail.hero_image_alt)}"></label>
  </div>
  <h4>Reserva</h4>
  <div class="form">
    <label class="wide">Link de Afiliado de Expedia (opcional)<input id="edit-expedia-link" value="${esc(detail.expedia_affiliate_link)}" placeholder="https://expedia.com/affiliates/..."><small>Si se deja vacío, no se muestra el botón "Reservar en Expedia" en la página del hotel.</small></label>
  </div>
  <h4>Amenidades</h4>
  <label class="wide">Una por línea<textarea id="edit-amenities" class="code" rows="8" placeholder="Restaurante frente al mar&#10;Spa de servicio completo&#10;Piscina infinita">${esc(amenitiesText)}</textarea></label>
  <h4>Tipos de Habitación</h4>
  <div id="edit-rooms">${roomRows.map(r=>roomRowHtml(r.name,r.description)).join('')}</div>
  <button id="edit-room-add" class="btn alt" type="button">+ Agregar Tipo de Habitación</button>
  <h4>Tours Destacados</h4>
  <div id="edit-tours" class="cards">${tours.map(t=>`<label style="font-weight:400"><input type="checkbox" value="${esc(t.id)}"${selectedTours.has(t.id)?' checked':''}> ${esc(t.name)}</label>`).join('')||'<p>No hay tours disponibles.</p>'}</div>
  <h4>Preguntas Frecuentes</h4>
  <div id="edit-faq">${faqRows.map(r=>faqRowHtml(r.q,r.a)).join('')}</div>
  <button id="edit-faq-add" class="btn alt" type="button">+ Agregar Pregunta</button>
  <div class="row" style="margin-top:14px"><button id="edit-save-btn" class="btn">Guardar y Re-ejecutar Wild Intelligence</button></div>
  <pre id="edit-status"></pre>`;
  $('#edit-faq-add').onclick=()=>{$('#edit-faq').insertAdjacentHTML('beforeend',faqRowHtml('',''))};
  $('#edit-room-add').onclick=()=>{$('#edit-rooms').insertAdjacentHTML('beforeend',roomRowHtml('',''))};
  $('#edit-hero-pick').onclick=async()=>{pickTarget='hotel_hero';await loadMedia();$('#media-modal').classList.add('show')};
  $('#edit-save-btn').onclick=()=>saveHotelEdit(id);
}
function faqRowHtml(q,a){return `<div class="row faq-row"><input class="faq-q" placeholder="Pregunta" value="${esc(q)}"><input class="faq-a" placeholder="Respuesta" value="${esc(a)}"><button type="button" class="btn alt" onclick="this.parentElement.remove()">×</button></div>`}
function roomRowHtml(name,description){return `<div class="row room-row"><input class="room-name" placeholder="Nombre (ej. Suite Junior)" value="${esc(name)}"><input class="room-desc" placeholder="Descripción" value="${esc(description)}"><button type="button" class="btn alt" onclick="this.parentElement.remove()">×</button></div>`}
async function saveHotelEdit(id){
  const status=$('#edit-status');status.textContent='Guardando...';
  const brand=$('#edit-brand').value.trim();
  const category=$('#edit-category').value.trim();
  const luxury_level=$('#edit-luxury-level').value;
  const hero_image=$('#edit-hero-image').value.trim();
  const hero_image_alt=$('#edit-hero-image-alt').value.trim();
  const expedia_affiliate_link=$('#edit-expedia-link').value.trim();
  const amenities=$('#edit-amenities').value.split('\n').map(x=>x.trim()).filter(Boolean);
  const room_types=$$('#edit-rooms .room-row').map(r=>({name:r.querySelector('.room-name').value.trim(),description:r.querySelector('.room-desc').value.trim()})).filter(x=>x.name);
  const featured_tours=$$('#edit-tours input:checked').map(c=>c.value);
  const faq=$$('#edit-faq .faq-row').map(r=>({q:r.querySelector('.faq-q').value.trim(),a:r.querySelector('.faq-a').value.trim()})).filter(x=>x.q);
  try{
    const r=await api('/api/hotel/update',{method:'POST',body:JSON.stringify({id,brand,category,luxury_level,hero_image,hero_image_alt,expedia_affiliate_link,amenities,room_types,featured_tours,faq})});
    if(!r.success)throw new Error(r.error||'Falló el guardado');
    status.textContent='Guardado. Re-ejecutando Wild Intelligence...';
    await completeHotel(id);
    status.textContent='Guardado y actualizado.';
  }catch(e){status.textContent='Error: '+e.message}
}
async function completeHotel(id){
  const out=$('#hotel-complete-output');out.textContent='Ejecutando el proceso de Wild Intelligence...';
  const btn=$('#hotel-complete-btn');if(btn)btn.disabled=true;
  try{
    const r=await api('/api/hotel/complete',{method:'POST',body:JSON.stringify({id})});
    const lines=(r.steps||[]).map(s=>`[${s.ok?'OK':'FALLÓ'}] ${s.label}\n${s.output}`);
    out.textContent=lines.join('\n---\n')||'Completado.';
    toast(r.success?'Hotel completado':'El proceso se detuvo por un error');
    await refresh();
    await showHotelDetail(id);
  }catch(e){out.textContent='Error: '+e.message}
  finally{if(btn)btn.disabled=false}
}
let allQuestions=[];
async function loadQuestions(){const r=await api('/api/question/list');allQuestions=r.questions||[];renderQuestions()}
function renderQuestions(){
  const q=($('#question-search')?.value||'').toLowerCase();
  const sourceLabels={facebook:'Facebook',reddit:'Reddit',tripadvisor:'TripAdvisor',whatsapp:'WhatsApp / Correo',google:'Google'};
  const list=[...allQuestions]
    .filter(x=>{
      const tags=[...(x.destination_ids||[]),...(x.hotel_ids||[])].join(' ');
      return !q||`${x.question} ${x.working_title||''} ${tags} ${x.source||''}`.toLowerCase().includes(q);
    })
    .sort((a,b)=>(b.priority||0)-(a.priority||0));
  const rows=list.map(x=>{
    const tags=[...(x.destination_ids||[]),...(x.hotel_ids||[])].slice(0,3).join(', ')||'—';
    const statusBadge=`<span class="badge">${esc(x.status||'pending')}</span>`;
    const sourceBadge=sourceLabels[x.source]||esc(x.source||'—');
    const action=x.status==='published'
      ? `<a href="../blog/${esc(x.article_slug)}.html" target="_blank" onclick="event.stopPropagation()">Ver Artículo</a>`
      : `<button data-publish="${esc(x.id)}" class="btn alt" onclick="event.stopPropagation()">Publicar como Artículo</button>`;
    return `<tr class="question-row" data-question="${esc(x.id)}"><td>${x.priority||0}</td><td><strong>${esc(x.working_title||x.question)}</strong><br><small>${esc(x.question)}</small></td><td>${sourceBadge}</td><td>${statusBadge}</td><td>${esc(tags)}</td><td>${action}</td></tr>`;
  });
  $('#question-table').innerHTML=table(['Prioridad','Pregunta','Fuente','Estado','Etiquetas','Acción'],rows);
  $$('[data-publish]').forEach(b=>b.onclick=()=>publishQuestion(b.dataset.publish,b));
  $$('.question-row').forEach(r=>r.onclick=()=>showQuestionDetail(r.dataset.question));
}
function showQuestionDetail(id){
  const x=allQuestions.find(q=>q.id===id);if(!x)return;
  $('#question-detail').innerHTML=`<div class="a-detail-panel"><div class="a-detail-header"><h4>${esc(x.working_title||x.question)}</h4><button onclick="document.getElementById('question-detail').innerHTML=''">×</button></div>
  <div class="form">
    <label class="wide">Texto de la Pregunta<textarea id="q-edit-question" rows="3">${esc(x.question)}</textarea></label>
    <label class="wide">Título de Trabajo<input id="q-edit-title" value="${esc(x.working_title)}"></label>
    <label>Fuente<select id="q-edit-source">${['facebook','reddit','tripadvisor','whatsapp','google'].map(s=>`<option value="${s}"${x.source===s?' selected':''}>${esc({facebook:'Facebook',reddit:'Reddit',tripadvisor:'TripAdvisor',whatsapp:'WhatsApp / Correo',google:'Google'}[s])}</option>`).join('')}</select></label>
    <label>Prioridad<input id="q-edit-priority" type="number" min="0" max="100" value="${x.priority||0}"></label>
    <label class="wide">Destinos etiquetados (separados por coma)<input id="q-edit-destinations" value="${esc((x.destination_ids||[]).join(', '))}"></label>
    <label class="wide">Hoteles etiquetados (separados por coma)<input id="q-edit-hotels" value="${esc((x.hotel_ids||[]).join(', '))}"></label>
  </div>
  <div class="row" style="margin-top:14px"><button id="q-edit-save-btn" class="btn">Guardar</button></div>
  <pre id="q-edit-status"></pre></div>`;
  $('#q-edit-save-btn').onclick=()=>saveQuestionEdit(id);
}
async function saveQuestionEdit(id){
  const status=$('#q-edit-status');status.textContent='Guardando...';
  const question=$('#q-edit-question').value.trim();
  const working_title=$('#q-edit-title').value.trim();
  const source=$('#q-edit-source').value;
  const priority=$('#q-edit-priority').value;
  const destination_ids=$('#q-edit-destinations').value.split(',').map(x=>x.trim()).filter(Boolean);
  const hotel_ids=$('#q-edit-hotels').value.split(',').map(x=>x.trim()).filter(Boolean);
  try{
    const r=await api('/api/question/update',{method:'POST',body:JSON.stringify({id,question,working_title,source,priority,destination_ids,hotel_ids})});
    if(!r.success)throw new Error(r.error||'Falló el guardado');
    status.textContent='Guardado.';
    toast('Pregunta actualizada');
    await loadQuestions();
  }catch(e){status.textContent='Error: '+e.message}
}
async function publishQuestion(id,btn){
  if(!confirm('¿Escribir y publicar este artículo ahora? Esto llama a Claude y reconstruye el sitio.'))return;
  btn.disabled=true;btn.textContent='Publicando...';
  try{
    const r=await api('/api/question/publish',{method:'POST',body:JSON.stringify({id})});
    if(!r.success)throw new Error(r.error||'Falló la publicación');
    toast('Artículo publicado');
    await loadQuestions();
  }catch(e){toast('Error: '+e.message);btn.disabled=false;btn.textContent='Publicar como Artículo'}
}
async function refresh(){state=await api('/api/state');try{analytics=await api('/api/analytics/summary')}catch(e){analytics={}}render()}
function safeAction(fn){return async(...args)=>{try{await fn(...args)}catch(e){toast('Error: '+e.message);$('#validation-result').textContent='Error: '+e.message}}}
function requireArticle(){if(!currentArticle)throw new Error('No hay ningún artículo cargado -- haz clic en Editar sobre un borrador o un artículo publicado primero.');return currentArticle}
$$('#nav button').forEach(b=>b.onclick=()=>setView(b.dataset.view));$$('[data-tab]').forEach(b=>b.onclick=()=>setTab(b.dataset.tab));$$('[data-run]').forEach(b=>b.onclick=safeAction(()=>run(b.dataset.run)));$$('[data-pick]').forEach(b=>b.onclick=async()=>{pickTarget=b.dataset.pick;await loadMedia();$('#media-modal').classList.add('show')});$('#close-media').onclick=()=>$('#media-modal').classList.remove('show');$('#open-upload').onclick=()=>$('#upload-modal').classList.add('show');$('#close-upload').onclick=()=>$('#upload-modal').classList.remove('show');$('#media-search').oninput=renderMedia;$('#media-folder').onchange=renderMedia;$('#tour-search').oninput=renderTours;$('#question-search').oninput=renderQuestions;
$('#upload-submit').onclick=()=>{const file=$('#upload-file').files[0];if(!file)return;const btn=$('#upload-submit');const label=btn.textContent;btn.disabled=true;btn.textContent='Subiendo...';const r=new FileReader();r.onload=async()=>{try{const x=await api('/api/media/upload',{method:'POST',body:JSON.stringify({name:file.name,folder:$('#upload-folder').value,alt:$('#upload-alt').value,caption:$('#upload-caption').value,data_url:r.result})});await loadMedia();toast('Imagen subida: '+x.file);$('#upload-modal').classList.remove('show');$('#upload-file').value='';$('#upload-alt').value='';$('#upload-caption').value='';$('#upload-status').textContent=''}catch(e){$('#upload-status').textContent=e.message}finally{btn.disabled=false;btn.textContent=label}};r.readAsDataURL(file)};
$('#validate-json').onclick=async()=>{const a=parse();if(!a.slug&&a.title){a.slug=slugify(a.title);$('#json-input').value=JSON.stringify(a,null,2)}const r=await api('/api/content/validate',{method:'POST',body:JSON.stringify(a)});$('#validation-result').textContent=[`Calidad: ${r.quality_score||0}%`,r.valid?'JSON válido':'Validación fallida',...(r.errors||[]),...(r.warnings||[]),...((r.improvements||[]).map(x=>'MEJORAR: '+x))].join('\n');evaluateArticle(a)};$('#load-editor').onclick=()=>loadArticle(parse());
$('#apply-editor').onclick=safeAction(async()=>{requireArticle();apply();toast('Cambios aplicados')});
$('#save-draft').onclick=safeAction(async()=>{requireArticle();apply();const btns=[$('#save-draft'),$('#save-draft-bottom')];const labels=btns.map(b=>b.textContent);btns.forEach(b=>{b.disabled=true;b.textContent='Guardando...'});try{const r=await api('/api/content/save',{method:'POST',body:JSON.stringify(currentArticle)});if(!r.success){$('#validation-result').textContent='Falló el guardado: '+(r.validation?.errors||[]).join(', ');toast('Falló el guardado -- ver detalles abajo');return}$('#validation-result').textContent='Borrador guardado';toast('Borrador guardado');await refresh()}finally{btns.forEach((b,i)=>{b.disabled=false;b.textContent=labels[i]})}});
$('#publish-article').onclick=safeAction(async()=>{requireArticle();if(!confirm('¿Publicar artículo?'))return;apply();const btns=[$('#publish-article'),$('#publish-article-bottom')];const labels=btns.map(b=>b.textContent);btns.forEach(b=>{b.disabled=true;b.textContent='Publicando... (puede tardar varios segundos)'});try{const r=await api('/api/content/publish',{method:'POST',body:JSON.stringify({article:currentArticle,run_generator:true})});if(!r.success){$('#validation-result').textContent='Falló la publicación: '+(r.validation?.errors||[]).join(', ');toast('Falló la publicación -- ver detalles abajo');return}$('#validation-result').textContent='Publicado';toast('Publicado con éxito');await refresh()}finally{btns.forEach((b,i)=>{b.disabled=false;b.textContent=labels[i]})}});
$('#save-draft-bottom').onclick=()=>$('#save-draft').click();
$('#publish-article-bottom').onclick=()=>$('#publish-article').click();
$('#suggest-links').onclick=safeAction(async()=>{requireArticle();apply(true);const r=await api('/api/content/suggest-links',{method:'POST',body:JSON.stringify(currentArticle)});const existing=textToLinks($('#field-internal-links').value);const existingUrls=new Set(existing.map(l=>l.url));const fresh=(r.suggestions||[]).filter(s=>!existingUrls.has(s.url));if(!fresh.length){$('#suggest-links-status').textContent='No se encontraron sugerencias nuevas.';return}const merged=existing.concat(fresh.map(s=>({text:s.text,url:s.url})));$('#field-internal-links').value=linksToText(merged);apply(true);$('#suggest-links-status').textContent=`Se agregaron ${fresh.length} sugerencia(s) -- revisa antes de publicar.`;toast(`Se agregaron ${fresh.length} enlace(s) sugerido(s)`)});
$('#auto-draft-btn').onclick=safeAction(async()=>{requireArticle();apply(true);const btn=$('#auto-draft-btn');btn.disabled=true;$('#auto-draft-status').textContent='Escribiendo con Claude... (puede tardar hasta un minuto)';try{const r=await api('/api/content/auto-draft',{method:'POST',body:JSON.stringify(currentArticle)});if(!r.success)throw new Error(r.error||'No se pudo generar el borrador');loadArticle(r.article);$('#auto-draft-status').textContent='Borrador generado -- revisa el contenido antes de publicar.';toast('Primer borrador escrito con Claude')}finally{btn.disabled=false}});
$$('#tab-editor input,#tab-editor textarea').forEach(el=>el.addEventListener('input',()=>{if(currentArticle){try{apply(true)}catch(e){} scheduleQuality()}}));
$('#open-hotel-wizard').onclick=()=>{$('#hotel-wizard-name').value='';$('#hotel-wizard-url').value='';$('#hotel-wizard-status').textContent='';$('#hotel-modal').classList.add('show')};
$('#close-hotel-wizard').onclick=()=>$('#hotel-modal').classList.remove('show');
$$('[data-wizard-mode]').forEach(b=>b.onclick=()=>{
  $$('[data-wizard-mode]').forEach(x=>x.classList.toggle('active',x===b));
  $('#wizard-mode-name').style.display=b.dataset.wizardMode==='name'?'':'none';
  $('#wizard-mode-url').style.display=b.dataset.wizardMode==='url'?'':'none';
});
async function afterHotelCreated(r){
  if(!r.success)throw new Error(r.error||'No se pudo crear el hotel');
  $('#hotel-wizard-status').textContent='Creado: '+r.id;
  $('#hotel-modal').classList.remove('show');
  toast('Hotel creado -- completando automáticamente...');
  await refresh();
  setView('hotels');
  await showHotelDetail(r.id);
  await completeHotel(r.id);
}
$('#hotel-wizard-create').onclick=async()=>{
  const name=$('#hotel-wizard-name').value.trim();
  if(!name){$('#hotel-wizard-status').textContent='Escribe primero un nombre de hotel.';return}
  $('#hotel-wizard-status').textContent='Creando registro del hotel...';
  try{
    await afterHotelCreated(await api('/api/hotel/create',{method:'POST',body:JSON.stringify({name})}));
  }catch(e){$('#hotel-wizard-status').textContent='Error: '+e.message}
};
$('#hotel-wizard-import').onclick=async()=>{
  const url=$('#hotel-wizard-url').value.trim();
  if(!url){$('#hotel-wizard-status').textContent='Pega primero una URL.';return}
  $('#hotel-wizard-status').textContent='Leyendo la página y pidiéndole a Claude que la analice... (puede tardar hasta un minuto)';
  try{
    await afterHotelCreated(await api('/api/hotel/import-url',{method:'POST',body:JSON.stringify({url})}));
  }catch(e){$('#hotel-wizard-status').textContent='Error: '+e.message}
};
const STOPWORDS=new Set(['the','a','an','is','are','was','were','be','to','of','in','on','at','for','and','or','with','from','my','i','you','your','it','this','that','do','does','did','can','could','should','would','will','how','what','when','where','why','which','de','la','el','los','las','un','una','y','o','en','con','para','que','es','son','del','al','se','su']);
function significantWords(text){return (text.toLowerCase().match(/[a-záéíóúñü0-9]+/g)||[]).filter(w=>w.length>2&&!STOPWORDS.has(w))}
function findSimilarContent(text,ownSlug){
  const words=new Set(significantWords(text));
  if(words.size<3)return[];
  const candidates=[];
  (allQuestions||[]).forEach(q=>{
    if(ownSlug&&q.article_slug===ownSlug)return;
    const cw=new Set(significantWords(`${q.working_title||''} ${q.question||''}`));
    const overlap=[...words].filter(w=>cw.has(w)).length;
    const score=overlap/Math.min(words.size,cw.size||1);
    if(score>=0.45)candidates.push({type:'Pregunta',title:q.working_title||q.question,status:q.status,score,link:q.status==='published'?`../blog/${q.article_slug}.html`:null});
  });
  (state.articles||[]).forEach(a=>{
    if(ownSlug&&a.slug===ownSlug)return;
    const cw=new Set(significantWords(a.title||''));
    const overlap=[...words].filter(w=>cw.has(w)).length;
    const score=overlap/Math.min(words.size,cw.size||1);
    if(score>=0.45)candidates.push({type:'Artículo publicado',title:a.title,status:'published',score,link:`../blog/${a.slug}.html`});
  });
  return candidates.sort((x,y)=>y.score-x.score).slice(0,4);
}
function renderSimilarWarning(targetId,text,ownSlug){
  const box=$(`#${targetId}`);if(!box)return;
  const matches=findSimilarContent(text,ownSlug);
  if(matches.length===0){box.innerHTML='';return}
  box.innerHTML=`<div class="similar-warning"><strong>⚠ Contenido similar ya existe:</strong><ul>${matches.map(m=>`<li>${Math.round(m.score*100)}% · ${esc(m.type)}: ${m.link?`<a href="${esc(m.link)}" target="_blank">${esc(m.title)}</a>`:esc(m.title)} ${m.status!=='published'?`<span class="badge">${esc(m.status)}</span>`:''}</li>`).join('')}</ul></div>`;
}
$('#open-question-wizard').onclick=()=>{$('#question-text').value='';$('#question-wizard-status').textContent='';$('#question-analysis-result').style.display='none';$('#question-similar-warning').innerHTML='';$('#question-modal').classList.add('show')};
$('#question-text').oninput=()=>renderSimilarWarning('question-similar-warning',$('#question-text').value);
$('#field-title').oninput=()=>renderSimilarWarning('article-similar-warning',$('#field-title').value,currentArticle?.slug||'');
$('#close-question-wizard').onclick=()=>$('#question-modal').classList.remove('show');
$('#question-analyze').onclick=async()=>{
  const text=$('#question-text').value.trim();
  if(!text){$('#question-wizard-status').textContent='Pega primero una pregunta.';return}
  const source=$('#question-source').value;
  $('#question-wizard-status').textContent='Analizando con Wild Intelligence... (puede tardar hasta un minuto)';
  $('#question-analysis-result').style.display='none';
  try{
    const r=await api('/api/question/analyze',{method:'POST',body:JSON.stringify({text,source})});
    if(!r.success)throw new Error(r.error||'Falló el análisis');
    const a=r.analysis;
    const record={question:text,source,working_title:a.working_title,intent:a.intent,content_type:a.content_type,priority:a.priority,seo_potential:a.seo_potential,competition:a.competition,commercial_intent:a.commercial_intent,suggested_slug:a.suggested_slug,destination_ids:a.destination_ids||[],hotel_ids:a.hotel_ids||[],tour_ids:a.tour_ids||[],activity_ids:a.activity_ids||[],season_ids:a.season_ids||[],traveler_profile_ids:a.traveler_profile_ids||[],transportation_ids:a.transportation_ids||[],business_goal:a.business_goal,notes:a.notes,source_note:`Preguntas frecuentes sugeridas: ${(a.suggested_faq||[]).join(' | ')}`};
    $('#question-analysis-summary').innerHTML=`<h4>${esc(a.working_title||'')}</h4><ul>
      <li>Intención: ${esc(a.intent||'—')} · Tipo: ${esc(a.content_type||'—')}</li>
      <li>Potencial SEO: ${esc(a.seo_potential)} · Competencia: ${esc(a.competition)} · Intención comercial: ${esc(a.commercial_intent)}</li>
      <li>Prioridad: <strong>${esc(a.priority)}</strong></li>
      <li>Destinos: ${esc((a.destination_ids||[]).join(', ')||'—')}</li>
      <li>Hoteles: ${esc((a.hotel_ids||[]).join(', ')||'—')}</li>
      <li>Tours: ${esc((a.tour_ids||[]).join(', ')||'—')}</li>
      <li>Temporada: ${esc((a.season_ids||[]).join(', ')||'—')} · Viajero: ${esc((a.traveler_profile_ids||[]).join(', ')||'—')}</li>
    </ul>`;
    $('#question-analysis-json').value=JSON.stringify(record,null,2);
    $('#question-analysis-result').style.display='';
    $('#question-wizard-status').textContent='Revisa las etiquetas de abajo, edítalas si hace falta, y luego guarda.';
  }catch(e){$('#question-wizard-status').textContent='Error: '+e.message}
};
$('#question-save').onclick=async()=>{
  let record;
  try{record=JSON.parse($('#question-analysis-json').value)}catch(e){$('#question-wizard-status').textContent='JSON inválido: '+e.message;return}
  $('#question-wizard-status').textContent='Guardando como pendiente...';
  try{
    const r=await api('/api/question/save',{method:'POST',body:JSON.stringify(record)});
    if(!r.success)throw new Error(r.error||'Falló el guardado');
    $('#question-wizard-status').textContent='Guardado: '+r.id;
    toast('Pregunta guardada como pendiente');
    $('#question-modal').classList.remove('show');
    await loadQuestions();
  }catch(e){$('#question-wizard-status').textContent='Error: '+e.message}
};
$('#open-destination-wizard').onclick=()=>{$('#destination-wizard-id').value='';$('#destination-wizard-url').value='';$('#destination-wizard-status').textContent='';$('#destination-modal').classList.add('show')};
$('#close-destination-wizard').onclick=()=>$('#destination-modal').classList.remove('show');
$('#destination-wizard-import').onclick=async()=>{
  const id=$('#destination-wizard-id').value.trim();
  const url=$('#destination-wizard-url').value.trim();
  if(!id||!url){$('#destination-wizard-status').textContent='Escribe el id del destino y una URL de fuente.';return}
  $('#destination-wizard-status').textContent='Leyendo la página y pidiéndole a Claude que extraiga los detalles... (puede tardar hasta un minuto)';
  try{
    const r=await api('/api/destination/import-url',{method:'POST',body:JSON.stringify({id,url})});
    if(!r.success)throw new Error(r.error||'Falló la importación');
    $('#destination-wizard-status').textContent='Importado. Ejecuta el Motor de Blog y Destinos (pestaña Inteligencia) para publicar la página, luego Puntuar Destino para Viajeros.';
    toast('Destino importado');
  }catch(e){$('#destination-wizard-status').textContent='Error: '+e.message}
};
refresh().catch(e=>{$('#api-status').textContent='Desconectado';console.error(e)});
