const baseCss=`*{box-sizing:border-box}body{font-family:Arial,sans-serif;color:#172b3f;margin:0;padding:24px;background:#fff}.doc{max-width:1100px;margin:auto}table{width:100%;border-collapse:collapse}th,td{padding:7px;border-bottom:1px solid #dce5ee;text-align:left}th{background:#e8eff8}td small{display:block}thead{display:table-header-group}tr{break-inside:avoid}button,nav,.no-print,.record-export121{display:none!important}.responsive-table{overflow:visible!important}@media print{body{padding:0}@page{size:A4;margin:14mm}}`;
const escape=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let closeActivePreview;
export function printHtmlInPlace(title,body,extraCss=''){
 if(typeof title!=="string")title="UniMIS Report";
 closeActivePreview?.();
 document.getElementById('unimis-print-preview122')?.remove();
 const modal=document.createElement('div');modal.id='unimis-print-preview122';modal.setAttribute('role','dialog');modal.setAttribute('aria-modal','true');modal.setAttribute('aria-label',`${title} print preview`);
 Object.assign(modal.style,{position:'fixed',inset:'0',zIndex:'2147483646',background:'#e2e8f0',display:'flex',flexDirection:'column'});
 const bar=document.createElement('div');Object.assign(bar.style,{display:'flex',gap:'12px',alignItems:'center',padding:'12px 20px',background:'#173f70',color:'white',flexWrap:'wrap'});
 const heading=document.createElement('strong');heading.textContent=title;bar.appendChild(heading);
 const print=document.createElement('button');print.className='export-pdf121';print.textContent='Print / Save PDF';print.disabled=true;const close=document.createElement('button');close.textContent='Close preview';
 for(const button of [print,close])Object.assign(button.style,{padding:'10px 16px',border:'0',borderRadius:'8px',background:'#6d28d9',color:'#fff',fontWeight:'700',cursor:'pointer'});
 const status=document.createElement('span');status.textContent='Loading document…';status.setAttribute('role','status');bar.append(print,close,status);
 const frame=document.createElement('iframe');frame.id='unimis-print-frame';frame.title=title;Object.assign(frame.style,{flex:'1',width:'100%',border:'0',background:'#fff',minHeight:'0'});
 const previousFocus=document.activeElement;const closePreview=()=>{closeActivePreview=null;modal.remove();document.removeEventListener('keydown',keydown);previousFocus?.focus?.()};const keydown=event=>{if(event.key==='Escape')closePreview()};closeActivePreview=closePreview;close.onclick=closePreview;document.addEventListener('keydown',keydown);
 print.onclick=()=>{const win=frame.contentWindow;if(!frame.isConnected||!win){status.textContent='Document unavailable. Close the preview and try again.';return}try{win.focus();win.print();status.textContent='Choose Save as PDF in the browser print destination.'}catch(error){status.textContent=`Printing could not start: ${error.message}. You can also focus the document and press Ctrl+P.`}};
 frame.onload=()=>{if(!frame.contentDocument?.getElementById('unimis-print-document'))return;print.disabled=false;status.textContent='Review the document, then choose Print / Save PDF.';print.focus()};
 // Remove executable markup from copied screens; retain safe report content.
 const template=document.createElement('template');template.innerHTML=body;template.content.querySelectorAll('script,iframe,object,embed').forEach(n=>n.remove());template.content.querySelectorAll('*').forEach(n=>{for(const a of [...n.attributes])if(a.name.toLowerCase().startsWith('on')||/^(href|src)$/i.test(a.name)&&/^javascript:/i.test(a.value))n.removeAttribute(a.name)});
 frame.srcdoc=`<!doctype html><html><head><meta charset="utf-8"><title>${escape(title)}</title><style>${baseCss}${extraCss}</style></head><body><div id="unimis-print-document" class="doc">${template.innerHTML}</div></body></html>`;
 modal.append(bar,frame);document.body.appendChild(modal);return frame;
}
export function printLegacyDocument122(title,html){const doc=new DOMParser().parseFromString(html,'text/html');return printHtmlInPlace(title,doc.body.innerHTML,[...doc.querySelectorAll('style')].map(s=>s.textContent).join('\n'))}
export function printCurrentView(title='UniMIS Report'){
 if(typeof title!=="string")title="UniMIS Report";
 const root=document.querySelector('main')||document.querySelector('.dashboard-content')||document.querySelector('#root');
 const clone=root?.cloneNode(true);if(clone){clone.querySelectorAll('.sidebar,.dashboard-sidebar,.no-print,button,nav,.record-export121').forEach(n=>n.remove());clone.querySelectorAll('input,select,textarea').forEach(n=>{const span=document.createElement('span');span.textContent=n.value||'';n.replaceWith(span)})}
 const css=[...document.querySelectorAll('style')].map(s=>s.textContent).join('\n');return printHtmlInPlace(title,clone?.innerHTML||'<p>No printable content available.</p>',css);
}
