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
    const reference = body?.reference;
    if (!reference) return json({ ok: false, error: "reference is required." }, 400);

    const { data: payment, error: paymentLookupError } = await adminClient
      .from("admission_application_payments")
      .select("id,institution_id,application_id,amount,currency,status,provider_reference,metadata")
      .eq("provider_reference", reference)
      .maybeSingle();

    if (paymentLookupError) return json({ ok: false, error: paymentLookupError.message }, 500);
    if (!payment) return json({ ok: false, error: "Payment record not found." }, 404);

    const { data: applicant, error: applicantError } = await adminClient
      .from("applicants")
      .select("id,user_id")
      .eq("user_id", user.id)
      .maybeSingle();

    if (applicantError) return json({ ok: false, error: applicantError.message }, 500);
    if (!applicant) return json({ ok: false, error: "Applicant profile not found." }, 403);

    const { data: application, error: applicationError } = await adminClient
      .from("applications")
      .select("id,applicant_id")
      .eq("id", payment.application_id)
      .maybeSingle();

    if (applicationError) return json({ ok: false, error: applicationError.message }, 500);
    if (!application || application.applicant_id !== applicant.id) {
      return json({ ok: false, error: "You do not own this payment." }, 403);
    }

    const paystackResponse = await fetch(
      `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
      { headers: { Authorization: `Bearer ${paystackSecret}` } }
    );

    const paystackJson = await paystackResponse.json();

    if (!paystackResponse.ok || !paystackJson?.status) {
      return json({
        ok: false,
        error: paystackJson?.message || "Paystack verification failed.",
        paystack: paystackJson,
      }, 400);
    }

    const tx = paystackJson.data;
    const expectedAmount = Math.round(Number(payment.amount) * 100);
    const actualAmount = Number(tx?.amount ?? 0);
    const expectedCurrency = String(payment.currency || "GHS").toUpperCase();
    const actualCurrency = String(tx?.currency || "").toUpperCase();

    if (tx?.status !== "success") {
      return json({ ok: false, error: `Payment status is ${tx?.status || "unknown"}.` }, 400);
    }
    if (actualAmount !== expectedAmount) {
      return json({ ok: false, error: "Verified Paystack amount does not match UniMIS payment amount." }, 400);
    }
    if (actualCurrency !== expectedCurrency) {
      return json({ ok: false, error: "Verified Paystack currency does not match UniMIS payment currency." }, 400);
    }

    const now = new Date().toISOString();

    const { error: updateError } = await adminClient
      .from("admission_application_payments")
      .update({
        status: "verified",
        paid_at: now,
        verified_at: now,
        metadata: {
          ...(payment.metadata || {}),
          paystack_verification: tx,
        },
      })
      .eq("id", payment.id);

    if (updateError) return json({ ok: false, error: updateError.message }, 500);

    const { error: appUpdateError } = await adminClient
      .from("applications")
      .update({ payment_status: "paid" })
      .eq("id", payment.application_id);

    if (appUpdateError) return json({ ok: false, error: appUpdateError.message }, 500);

    return json({
      ok: true,
      reference,
      application_id: payment.application_id,
      payment_status: "verified",
      application_payment_status: "paid",
      amount: payment.amount,
      currency: payment.currency,
    });
  } catch (error) {
    return json({ ok: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
