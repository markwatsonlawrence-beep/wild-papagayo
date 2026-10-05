(function(){
  var slug=document.documentElement.getAttribute('data-slug');
  if(!slug)return;
  var vid=sessionStorage.getItem('_wpvid');
  if(!vid){vid=Math.random().toString(36).slice(2)+Date.now().toString(36);sessionStorage.setItem('_wpvid',vid);}
  var ref=document.referrer||'';
  var src='direct';
  if(ref.includes('google')||ref.includes('bing')||ref.includes('yahoo'))src='search';
  else if(ref.includes('facebook')||ref.includes('instagram')||ref.includes('twitter')||ref.includes('tiktok'))src='social';
  else if(ref.includes('wa.me')||ref.includes('whatsapp'))src='whatsapp';
  else if(ref)src='referral';
  var ua=navigator.userAgent||'';
  var dev='desktop';
  if(/iPhone|iPad|iPod|Android/i.test(ua))dev=/iPad/i.test(ua)?'tablet':'mobile';
  var country=(navigator.language||'en').split('-')[1]||'unknown';
  var payload={slug:slug,type:'view',visitor_id:vid,country:country,device:dev,source:src};
  if(navigator.sendBeacon){
    var blob=new Blob([JSON.stringify(payload)],{type:'application/json'});
    navigator.sendBeacon('/api/analytics/event',blob);
  } else {
    fetch('/api/analytics/event',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload),keepalive:true}).catch(function(){});
  }
  document.querySelectorAll('a[href*="wa.me"]').forEach(function(el){
    el.addEventListener('click',function(){
      var p2=Object.assign({},payload,{type:'whatsapp_click'});
      if(navigator.sendBeacon){var b2=new Blob([JSON.stringify(p2)],{type:'application/json'});navigator.sendBeacon('/api/analytics/event',b2);}
      else fetch('/api/analytics/event',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(p2),keepalive:true}).catch(function(){});
    });
  });
  document.querySelectorAll('a[href*="/tours/"]').forEach(function(el){
    el.addEventListener('click',function(){
      var p3=Object.assign({},payload,{type:'tour_click'});
      if(navigator.sendBeacon){var b3=new Blob([JSON.stringify(p3)],{type:'application/json'});navigator.sendBeacon('/api/analytics/event',b3);}
      else fetch('/api/analytics/event',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(p3),keepalive:true}).catch(function(){});
    });
  });
})();
