import {useEffect,useState} from "react";
import {Link,useNavigate} from "react-router-dom";
import {BookOpenCheck,LockKeyhole,Mail,School,ShieldCheck,Eye,EyeOff} from "lucide-react";
import {useAuth} from "../../contexts/AuthContext";
import {supabase} from "../../lib/supabase";
import {loadPublicWebsite} from "../../services/publicWebsite";
import {classifyPortalAccount,portalMismatchMessage} from "../../lib/portalAccess";
import Toast from "../../components/Toast";
import "./Login.css";

const FALLBACK_PORTAL_IMAGE="https://images.unsplash.com/photo-1523050854058-8df90110c9f1?auto=format&fit=crop&w=1600&q=85";

export default function Login(){
 const {signIn}=useAuth();
 const nav=useNavigate();
 const [email,setEmail]=useState(()=>localStorage.getItem("unimis_staff_login_email")||""),[password,setPassword]=useState(""),[remember,setRemember]=useState(()=>Boolean(localStorage.getItem("unimis_staff_login_email"))),[error,setError]=useState(""),[busy,setBusy]=useState(false),[showPassword,setShowPassword]=useState(false);
 const [site,setSite]=useState(null);

 useEffect(()=>{loadPublicWebsite().then(r=>{if(!r.error)setSite(r.data||{});});},[]);

 async function submit(e){
  e.preventDefault();setError("");setBusy(true);
  if(remember)localStorage.setItem("unimis_staff_login_email",email.trim());else localStorage.removeItem("unimis_staff_login_email");
  const {data,error}=await signIn(email,password);
  if(error){setError(error.message);setBusy(false);return;}
  const signedInUser=data?.user||data?.session?.user;
  const access=await classifyPortalAccount(signedInUser);
  if(access.kind!=="staff"){await supabase.auth.signOut();setError(portalMismatchMessage(access.kind,"staff"));setBusy(false);return;}
  nav("/dashboard",{replace:true});setBusy(false);
 }

 const s=site?.settings||{},inst=site?.institution||{};
 const name=s.display_name||inst.name||"University";
 const short=s.short_name||inst.short_name||"UniMIS";
 const image=s.staff_portal_image_url||s.hero_image_url||FALLBACK_PORTAL_IMAGE;

 return <main className="university-login-shell">
   <Toast message={error} type="error" onClose={()=>setError("")}/>
   <section className="university-login-visual" style={{backgroundImage:`linear-gradient(180deg,rgba(5,29,56,.18),rgba(5,29,56,.91)),url(${image})`}}>
     <div className="university-login-brand"><span><School/></span><div><strong>{short}</strong><small>{name}</small></div></div>
     <div className="university-login-copy">
       <span className="university-login-kicker">University Portal</span>
       <h1>{s.staff_portal_title||"Secure access for staff and lecturers"}</h1>
       <p>{s.staff_portal_text||"Access teaching, academic administration and university services with your institution-issued account."}</p>
       <div className="university-login-points"><span><ShieldCheck size={17}/>Institution-managed accounts</span><span><BookOpenCheck size={17}/>Teaching & academic services</span></div>
     </div>
   </section>
   <section className="university-login-panel">
     <div className="university-login-form-wrap">
       <div className="university-login-mobile-brand"><School/><strong>{short}</strong></div>
       <span className="university-login-eyebrow">Staff & Lecturer Access</span>
       <h2>Sign in to University Portal</h2>
       <p className="university-login-intro">Use the account issued to you by an authorised university administrator.</p>
       <form onSubmit={submit} className="university-login-form">
         <label><span>Email address</span><div className="university-login-input"><Mail size={17}/><input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="name@university.edu" autoComplete="username" required/></div></label>
         <label><span>Password</span><div className="university-login-input"><LockKeyhole size={17}/><input type={showPassword?"text":"password"} value={password} onChange={e=>setPassword(e.target.value)} placeholder="Enter password" autoComplete="current-password" required/><button type="button" className="password-visibility-toggle" onClick={()=>setShowPassword(v=>!v)} aria-label={showPassword?"Hide password":"Show password"} title={showPassword?"Hide password":"Show password"}>{showPassword?<EyeOff size={18}/>:<Eye size={18}/>}</button></div></label>
         <div className="university-login-tools"><label className="university-remember"><input type="checkbox" checked={remember} onChange={e=>setRemember(e.target.checked)}/><span>Remember me</span></label><Link to="/forgot-password">Forgot password?</Link></div><small className="university-remember-note">For security, UniMIS never stores your password in the browser.</small>
         <button className="university-login-submit" disabled={busy}>{busy?"Signing in…":"Sign in securely"}</button>
       </form>
       <div className="university-login-help"><strong>Account access</strong><span>Staff and lecturer accounts are provisioned by the university. Contact your administrator if you do not yet have access.</span></div>
       <div className="university-login-route-links"><Link to="/student-login">Student Portal</Link><Link to="/apply">Applicant Portal</Link></div><Link className="university-login-home" to="/">← University website</Link>
     </div>
   </section>
 </main>;
}
