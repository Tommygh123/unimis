import {createContext,useContext,useEffect,useState} from "react";
import {supabase} from "../lib/supabase";
const AuthContext=createContext(null);
export function AuthProvider({children}){
 const [session,setSession]=useState(null),[loading,setLoading]=useState(true);
 useEffect(()=>{
  supabase.auth.getSession().then(({data})=>{setSession(data.session);setLoading(false)});
  const {data:{subscription}}=supabase.auth.onAuthStateChange((_e,s)=>{setSession(s);setLoading(false)});
  return()=>subscription.unsubscribe();
 },[]);
 const signIn=(email,password)=>supabase.auth.signInWithPassword({email,password});
 const signUp=(email,password,full_name)=>supabase.auth.signUp({email,password,options:{data:{full_name,app_id:"unimis"},emailRedirectTo:`${window.location.origin}/auth/callback`}});
 const signOut=()=>supabase.auth.signOut();
 return <AuthContext.Provider value={{session,user:session?.user??null,loading,signIn,signUp,signOut}}>{children}</AuthContext.Provider>;
}
export const useAuth=()=>useContext(AuthContext);
