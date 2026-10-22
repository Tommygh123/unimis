import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function toHex(buffer: ArrayBuffer) {
  return Array.from(new Uint8Array(buffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  try {
    const secret = Deno.env.get("PAYSTACK_SECRET_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    if (!secret) return new Response("Missing secret", { status: 500 });

    const rawBody = await req.text();
    const signature = req.headers.get("x-paystack-signature") || "";

    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(secret),
      { name: "HMAC", hash: "SHA-512" },
      false,
      ["sign"]
    );

    const signed = await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(rawBody)
    );

    if (toHex(signed) !== signature) {
      return new Response("Invalid signature", { status: 401 });
    }

    const event = JSON.parse(rawBody);

    if (event?.event !== "charge.success") {
      return new Response("ok", { status: 200 });
    }

    const reference = event?.data?.reference;
    if (!reference) return new Response("ok", { status: 200 });

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: payment } = await admin
      .from("admission_application_payments")
      .select("*")
      .eq("provider", "paystack")
      .eq("provider_reference", reference)
      .maybeSingle();

    if (!payment) return new Response("ok", { status: 200 });

    const expected = Math.round(Number(payment.amount) * 100);
    const actual = Number(event.data?.amount || 0);
    const currency = String(event.data?.currency || "").toUpperCase();

    if (
      actual === expected &&
      currency === String(payment.currency).toUpperCase()
    ) {
      await admin
        .from("admission_application_payments")
        .update({
          status: "verified",
          payment_method: event.data?.channel || "paystack",
          paid_at: event.data?.paid_at || new Date().toISOString(),
          verified_at: new Date().toISOString(),
          metadata: { paystack_webhook: event.data },
          updated_at: new Date().toISOString(),
        })
        .eq("id", payment.id);
    }

    return new Response("ok", { status: 200 });
  } catch {
    return new Response("ok", { status: 200 });
  }
});
