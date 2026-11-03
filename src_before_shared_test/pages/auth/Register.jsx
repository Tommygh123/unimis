import {useState} from "react";
import {Link} from "react-router-dom";
import {useAuth} from "../../contexts/AuthContext";
export default function Register(){
 const {signUp}=useAuth(); const [f,setF]=useState({name:"",email:"",password:""}),[msg,setMsg]=useState("");
 async function submit(e){e.preventDefault();const {error}=await signUp(f.email,f.password,f.name);setMsg(error?error.message:"Account created. Confirm the email if confirmation is enabled, then sign in.");}
 return <div className="card"><h1>Create UniMIS account</h1>{msg&&<p>{msg}</p>}<form onSubmit={submit}><label>Full name<input value={f.name} onChange={e=>setF({...f,name:e.target.value})} required/></label><label>Email<input type="email" value={f.email} onChange={e=>setF({...f,email:e.target.value})} required/></label><label>Password<input type="password" minLength="8" value={f.password} onChange={e=>setF({...f,password:e.target.value})} required/></label><button>Create account</button></form><p><Link to="/login">Back to sign in</Link></p></div>;
}
