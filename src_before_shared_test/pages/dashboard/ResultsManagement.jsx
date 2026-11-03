import {useCallback,useEffect,useState} from 'react';
import {Link} from 'react-router-dom';
import toast from 'react-hot-toast';
import {useUserContext} from '../../contexts/UserContext';
import {supabase} from '../../lib/supabase';
import IndependentProjectedReview133 from './IndependentProjectedReview133';
import '../../styles/academic-workspaces-115.css';
import '../../styles/committee-review-130.css';
export default function ResultsManagement(){
 const {institutionId,hasRole}=useUserContext();const manager=['owner','registrar','exam_officer'].some(hasRole);
 const [setup,setSetup]=useState(null),[batches,setBatches]=useState([]),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 const load=useCallback(async()=>{if(!institutionId||!manager)return;setBusy(true);setError('');try{const [s,b]=await Promise.all([supabase.rpc('unimis_review_setup130',{p_inst:institutionId}),supabase.rpc('unimis_review_batches130',{p_inst:institutionId})]);if(s.error)throw s.error;if(b.error)throw b.error;setSetup(s.data);setBatches(b.data||[])}catch(e){setError(e.message);toast.error(e.message,{id:'results-load135'})}finally{setBusy(false)}},[institutionId,manager]);
 useEffect(()=>{load()},[load]);
 return <section className="academic115 committee130"><div className="page-heading"><span className="eyebrow">Academic Operations</span><h1>Examinations & Results</h1><p>Projected review: select submitted results, discuss, approve or return, and publish approved results.</p><nav className="academic115-toolbar" aria-label="Results review workspaces"><button type="button" className="primary-action" disabled={busy} onClick={load}>Refresh Projected Review</button>{manager&&<Link className="primary-action" style={{backgroundColor:"#6750a4",color:"#fff",padding:"10px 16px",borderRadius:8,textDecoration:"none"}} to="/academic-review">Committee Results Approvals</Link>}</nav></div>{error&&<p className="form-error" role="alert">{error}</p>}{!manager?<p>Authorised academic coordinator access is required.</p>:setup?<IndependentProjectedReview133 institutionId={institutionId} setup={setup} batches={batches} reload={load}/>:<p>{busy?'Loading results workspace…':'Results workspace unavailable. Use Refresh to retry.'}</p>}</section>;
}
