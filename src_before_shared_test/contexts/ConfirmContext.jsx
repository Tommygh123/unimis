import {createContext,useCallback,useContext,useRef,useState} from "react";
const ConfirmContext=createContext(null);
export function ConfirmProvider({children}){
 const [dialog,setDialog]=useState(null);const resolver=useRef(null);
 const confirm=useCallback((o={})=>new Promise(resolve=>{resolver.current=resolve;setDialog({title:o.title||"Confirm action",message:o.message||"Are you sure?",confirmLabel:o.confirmLabel||"Confirm",cancelLabel:o.cancelLabel||"Cancel",tone:o.tone||"primary"});}),[]);
 function finish(v){resolver.current?.(v);resolver.current=null;setDialog(null);}
 return <ConfirmContext.Provider value={confirm}>{children}{dialog&&<div className="unimis-confirm-backdrop" onMouseDown={e=>{if(e.target===e.currentTarget)finish(false)}}><div className="unimis-confirm-dialog" role="dialog" aria-modal="true"><div className="unimis-confirm-icon">{dialog.tone==="danger"?"!":"✓"}</div><div className="unimis-confirm-copy"><h3>{dialog.title}</h3><p>{dialog.message}</p></div><div className="unimis-confirm-actions"><button className="unimis-confirm-cancel" onClick={()=>finish(false)}>{dialog.cancelLabel}</button><button className={`unimis-confirm-ok ${dialog.tone==="danger"?"danger":""}`} onClick={()=>finish(true)}>{dialog.confirmLabel}</button></div></div></div>}</ConfirmContext.Provider>;
}
export function useConfirm(){const v=useContext(ConfirmContext);if(!v)throw new Error("useConfirm must be used inside ConfirmProvider");return v;}
