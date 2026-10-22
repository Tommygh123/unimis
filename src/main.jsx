import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import { AuthProvider } from "./contexts/AuthContext";
import { UserProvider } from "./contexts/UserContext";
import { WorkflowProvider } from "./contexts/WorkflowContext";
import { ConfirmProvider } from "./contexts/ConfirmContext";
import App from "./App";
import toast, { Toaster, ToastBar } from "react-hot-toast";
import "./styles/global.css";
import "./styles/sidebar-100.css";

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <UserProvider>
          <WorkflowProvider>
            <ConfirmProvider>
              <App />
              <Toaster position="top-center" containerStyle={{top:16,left:12,right:12}} toastOptions={{duration:4500,className:'responsive-toast135',error:{duration:7500},style:{borderRadius:'12px',padding:'14px 16px',fontSize:'14px',width:'min(440px, calc(100vw - 24px))',maxWidth:'calc(100vw - 24px)',boxShadow:'0 12px 35px rgba(16,24,40,.16)'}}}>{t=><ToastBar toast={t}>{({icon,message})=><>{icon}<div className="toast-copy135">{message}</div>{t.type!=='loading'&&<button className="toast-dismiss135" aria-label="Dismiss notification" onClick={()=>toast.dismiss(t.id)}>×</button>}</>}</ToastBar>}</Toaster>
            </ConfirmProvider>
          </WorkflowProvider>
        </UserProvider>
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>
);
