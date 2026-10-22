import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const paystackSecret = Deno.env.get("PAYSTACK_SECRET_KEY");

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return json({ ok: false, error: "Supabase Edge Function environment is incomplete." }, 500);
    }
    if (!paystackSecret) {
      return json({ ok: false, error: "PAYSTACK_SECRET_KEY is not configured." }, 500);
    }

    const authHeader = req.headers.get("Authorization") ?? "";

    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: { user }, error: userError } = await authClient.auth.getUser();
    if (userError || !user) return json({ ok: false, error: "Unauthorized applicant." }, 401);

    const body = await req.json().catch(() => ({}));
    const applicationId = body?.application_id;
    if (!applicationId) return json({ ok: false, error: "application_id is required." }, 400);

    const { data: applicant, error: applicantError } = await adminClient
      .from("applicants")
      .select("id,institution_id,user_id,email,first_name,last_name,applicant_category")
      .eq("user_id", user.id)
      .maybeSingle();

    if (applicantError) return json({ ok: false, error: applicantError.message }, 500);
    if (!applicant) return json({ ok: false, error: "Applicant profile not found." }, 403);

    const { data: application, error: applicationError } = await adminClient
      .from("applications")
      .select("id,institution_id,applicant_id,admission_cycle_id,status,payment_status,application_number")
      .eq("id", applicationId)
      .maybeSingle();

    if (applicationError) return json({ ok: false, error: applicationError.message }, 500);
    if (!application) return json({ ok: false, error: "Application not found." }, 404);

    if (application.applicant_id !== applicant.id || application.institution_id !== applicant.institution_id) {
      return json({ ok: false, error: "You do not own this application." }, 403);
    }

    if (!["draft","incomplete","returned"].includes((application.status ?? "").toLowerCase())) {
      return json({ ok: false, error: "Only draft applications can be paid for." }, 400);
    }

    const { data: feeResult, error: feeError } = await adminClient.rpc(
      "unimis_get_application_fee",
      { p_application_id: application.id }
    );

    if (feeError) return json({ ok: false, error: feeError.message }, 500);

    let amount: number | null = null;
    let currency = "GHS";

    if (Array.isArray(feeResult)) {
      const row = feeResult[0];
      amount = row?.amount != null ? Number(row.amount) : null;
      currency = row?.currency_code ?? row?.currency ?? "GHS";
    } else if (feeResult && typeof feeResult === "object") {
      amount = (feeResult as any)?.amount != null ? Number((feeResult as any).amount) : null;
      currency = (feeResult as any)?.currency_code ?? (feeResult as any)?.currency ?? "GHS";
    } else if (typeof feeResult === "number") {
      amount = feeResult;
    }

    if (!amount || amount <= 0) {
      return json({ ok: false, error: "No valid application fee is configured for this application." }, 400);
    }

    const email = applicant.email || user.email;
    if (!email) return json({ ok: false, error: "Applicant email is required for Paystack." }, 400);

    const callbackUrl =
      body?.callback_url ||
      `${req.headers.get("origin") || "http://localhost:5173"}/apply?payment=callback`;

    const reference = `UNIMIS-${application.application_number || application.id.slice(0,8)}-${Date.now()}`;

    const paystackResponse = await fetch("https://api.paystack.co/transaction/initialize", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${paystackSecret}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email,
        amount: Math.round(amount * 100),
        currency,
        reference,
        callback_url: callbackUrl,
        metadata: {
          application_id: application.id,
          applicant_id: applicant.id,
          institution_id: applicant.institution_id,
          application_number: application.application_number,
          user_id: user.id,
        },
      }),
    });

    const paystackJson = await paystackResponse.json();

    if (!paystackResponse.ok || !paystackJson?.status) {
      return json({
        ok: false,
        error: paystackJson?.message || "Paystack initialization failed.",
        paystack: paystackJson,
      }, 400);
    }

    const { error: paymentError } = await adminClient
      .from("admission_application_payments")
      .insert({
        institution_id: applicant.institution_id,
        application_id: application.id,
        amount,
        currency,
        channel: "online",
        payment_method: "online",
        provider: "paystack",
        provider_reference: reference,
        status: "pending",
        metadata: {
          authorization_url: paystackJson.data.authorization_url,
          access_code: paystackJson.data.access_code,
          initialized_at: new Date().toISOString(),
        },
      });

    if (paymentError) return json({ ok: false, error: paymentError.message }, 500);

    return json({
      ok: true,
      reference,
      authorization_url: paystackJson.data.authorization_url,
      access_code: paystackJson.data.access_code,
      amount,
      currency,
    });
  } catch (error) {
    return json({ ok: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
