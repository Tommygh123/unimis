import {useCallback,useEffect,useState} from "react";
import {Building2,RefreshCw,Send,UserPlus} from "lucide-react";
import {supabase} from "../../lib/supabase";
import Toast from "../../components/Toast";

const blank={name:"",short_name:"",code:"",institution_type:"university",email:"",phone:"",country:"Ghana",region:"",city:"",owner_email:"",owner_first_name:"",owner_last_name:""};

export default function PlatformInstitutions155(){
 const [rows,setRows]=useState([]),[form,setForm]=useState(blank),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[inviting,setInviting]=useState(""),[error,setError]=useState(""),[message,setMessage]=useState("");
 const load=useCallback(async()=>{setLoading(true);const r=await supabase.rpc("unimis_platform_institutions155");if(r.error)setError(r.error.message);else setRows(r.data||[]);setLoading(false)},[]);
 useEffect(()=>{load()},[load]);
 const patch=(k,v)=>setForm(x=>({...x,[k]:v}));
 async function create(e){
  e.preventDefault();setBusy(true);setError("");setMessage("");
  const r=await supabase.rpc("unimis_platform_create_institution155",{
   p_name:form.name.trim(),p_short_name:form.short_name.trim()||null,p_code:form.code.trim().toUpperCase(),
   p_type:form.institution_type,p_email:form.email.trim()||null,p_phone:form.phone.trim()||null,
   p_country:form.country.trim()||"Ghana",p_region:form.region.trim()||null,p_city:form.city.trim()||null,
   p_owner_email:form.owner_email.trim().toLowerCase()||null,p_owner_first_name:form.owner_first_name.trim()||null,p_owner_last_name:form.owner_last_name.trim()||null
  });
  if(r.error)setError(r.error.message);else{setMessage(r.data?.owner_status==="assigned"?"Institution created and existing account assigned as Owner.":"Institution created. Owner is awaiting account registration/activation.");setForm(blank);await load()}
  setBusy(false);
 }

 async function inviteOwner(x){
  setInviting(x.id);setError("");setMessage("");
  const {data,error:e}=await supabase.functions.invoke("invite-user",{body:{platform_owner:true,institution_id:x.id,redirect_to:`${window.location.origin}/reset-password`}});
  if(e||data?.ok===false)setError(data?.error||e?.message||"Owner invitation failed");else{setMessage(`Owner invitation sent to ${data.email}.`);await load()}
  setInviting("");
 }
 const ownerLabel=s=>({awaiting_registration:"Awaiting Registration",invitation_sent:"Invitation Sent",assigned:"Assigned",not_set:"Not Assigned"}[s]||s||"Pending");
 return <div>
  <div className="page-heading"><span className="eyebrow">Platform provisioning</span><h1>Institutions</h1><p>Create a clean institution tenant, prepare its Owner and track implementation readiness without demo seed data.</p></div>
  <Toast message={error||message} type={error?"error":"success"} onClose={()=>{setError("");setMessage("")}}/>
  <section className="card151"><div className="section-title"><div><h2>Add Institution</h2><p>This creates the tenant, institution roles, settings and onboarding record. It does not copy E2E117 students, results, invoices or other demo transactions.</p></div><Building2/></div>
   <form onSubmit={create}>
    <div className="grid151">
     <label>Institution name<input value={form.name} onChange={e=>patch("name",e.target.value)} placeholder="AGTU" required/></label>
     <label>Short name<input value={form.short_name} onChange={e=>patch("short_name",e.target.value)} placeholder="AGTU"/></label>
     <label>Institution code<input value={form.code} onChange={e=>patch("code",e.target.value)} placeholder="AGTU" required/></label>
     <label>Institution type<select value={form.institution_type} onChange={e=>patch("institution_type",e.target.value)}><option value="university">University</option><option value="college">College</option><option value="technical">Technical</option><option value="vocational">Vocational</option><option value="shs">SHS</option><option value="other">Other</option></select></label>
     <label>Official email<input type="email" value={form.email} onChange={e=>patch("email",e.target.value)}/></label>
     <label>Phone<input value={form.phone} onChange={e=>patch("phone",e.target.value)}/></label>
     <label>Country<input value={form.country} onChange={e=>patch("country",e.target.value)}/></label>
     <label>Region<input value={form.region} onChange={e=>patch("region",e.target.value)}/></label>
     <label>City<input value={form.city} onChange={e=>patch("city",e.target.value)}/></label>
    </div>
    <h3><UserPlus size={18}/> First Owner</h3>
    <div className="grid151">
     <label>Owner first name<input value={form.owner_first_name} onChange={e=>patch("owner_first_name",e.target.value)}/></label>
     <label>Owner last name<input value={form.owner_last_name} onChange={e=>patch("owner_last_name",e.target.value)}/></label>
     <label>Owner email<input type="email" value={form.owner_email} onChange={e=>patch("owner_email",e.target.value)} placeholder="owner@institution.edu"/></label>
    </div>
    <p className="notice151">If the email already has a UniMIS Auth account, it is assigned immediately as the institution Owner. Otherwise UniMIS records the Owner as awaiting account registration. Email invitation delivery will be connected in the next onboarding step.</p>
    <button disabled={busy||!form.name.trim()||!form.code.trim()}>{busy?"Creating…":"Create Institution"}</button>
   </form>
  </section>
  <section className="card151"><div className="section-title"><div><h2>Institution Onboarding</h2><p>Demo/training and production institutions remain separate tenants.</p></div><button className="secondary-button" disabled={loading} onClick={load}><RefreshCw size={16}/>Refresh</button></div>
   {loading?<p>Loading institutions…</p>:rows.length===0?<p>No institutions found.</p>:<div className="responsive-table"><table><thead><tr><th>Institution</th><th>Type</th><th>Owner</th><th>Setup</th><th>Go Live</th></tr></thead><tbody>{rows.map(x=><tr key={x.id}><td><strong>{x.name}</strong><small>{x.code} • {x.status}</small></td><td>{x.institution_type}</td><td>{x.owner_email||"Not assigned"}<small>{ownerLabel(x.owner_status)}</small>{x.owner_email&&["awaiting_registration","invitation_sent"].includes(x.owner_status)&&<button type="button" className="secondary-button" disabled={inviting===x.id} onClick={()=>inviteOwner(x)}><Send size={14}/>{inviting===x.id?"Sending…":x.owner_status==="invitation_sent"?"Resend Invitation":"Invite Owner"}</button>}</td><td><strong>{x.readiness_percent}%</strong><small>{x.completed_steps}/{x.total_steps} stages</small></td><td><span className={`status-pill ${x.go_live_status==="live"?"verified":""}`}>{x.go_live_status}</span></td></tr>)}</tbody></table></div>}
  </section>
 </div>
}
