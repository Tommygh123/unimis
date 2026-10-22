import {useEffect} from "react";
import {useNavigate,useSearchParams} from "react-router-dom";
import {supabase} from "../../lib/supabase";

export default function AuthCallback(){
 const nav=useNavigate();
 const [params]=useSearchParams();

 useEffect(()=>{
  let cancelled=false;

  async function routeUser(){
   // Give Supabase a brief moment to finish exchanging/reading the auth session.
   await new Promise(resolve=>setTimeout(resolve,500));

   const requested=params.get("next");
   if(requested&&requested.startsWith("/")){
    if(!cancelled)nav(requested,{replace:true});
    return;
   }

   const {data}=await supabase.auth.getSession();
   const user=data?.session?.user;
   const accountType=user?.user_metadata?.account_type;

   if(!cancelled){
    nav(accountType==="applicant"?"/apply":"/dashboard",{replace:true});
   }
  }

  routeUser();
  return()=>{cancelled=true;};
 },[nav,params]);

 return <div className="card"><h2>Confirming account...</h2></div>;
}
