import { Router } from "express";
import twilio from "twilio";
import { asyncHandler } from "../lib/async-handler.js";
import { env } from "../lib/env.js";
import { fail, isUniqueViolation, notConfigured } from "../lib/errors.js";
import { rateLimit } from "../lib/rate-limit.js";
import { supabaseAdmin } from "../lib/supabase.js";
import { requireAuth } from "../middleware/require-auth.js";

// Twilio is an optional integration. The client is created per request, after
// the handler has confirmed the credentials exist, so a missing key can't crash
// startup (see `notConfigured`). The timeout cap stops a hung Twilio call from
// blocking the request until the SDK's much longer default.
function createTwilioClient(accountSid: string, authToken: string) {
  return twilio(accountSid, authToken, { timeout: 10_000 });
}

export const phoneRouter = Router();

phoneRouter.use(requireAuth);

// Sending a code costs money (Twilio SMS), so cap it hard per user...
const sendCodeLimit = rateLimit({
  name: "phone-send",
  windowMs: 60 * 60 * 1000,
  max: 5,
  message: "Too many verification codes requested — try again later.",
});
// ...and also per recipient number, so many accounts can't SMS-bomb one victim.
const sendCodePerNumberLimit = rateLimit({
  name: "phone-send-number",
  windowMs: 60 * 60 * 1000,
  max: 5,
  message: "Too many verification codes sent to that number — try again later.",
  key: (req) => String(req.body?.phoneNumber ?? "").trim() || undefined,
});
const checkCodeLimit = rateLimit({
  name: "phone-check",
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: "Too many verification attempts — try again later.",
});
// Also cap attempts per target number, so one account (or several) can't
// brute-force a victim's code.
const checkCodePerNumberLimit = rateLimit({
  name: "phone-check-number",
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: "Too many verification attempts for that number — try again later.",
  key: (req) => String(req.body?.phoneNumber ?? "").trim() || undefined,
});

const E164_RE = /^\+[1-9]\d{6,14}$/;

// POST /phone/send-code  { phoneNumber: string (E.164, e.g. +15551234567) }
phoneRouter.post(
  "/send-code",
  sendCodeLimit,
  sendCodePerNumberLimit,
  asyncHandler(async (req, res) => {
    const { twilioAccountSid, twilioAuthToken, twilioVerifyServiceSid } = env;
    if (!twilioAccountSid || !twilioAuthToken || !twilioVerifyServiceSid) {
      notConfigured(res, "Phone verification");
      return;
    }

    const phoneNumber = String(req.body?.phoneNumber ?? "").trim();
    if (!/^\+[1-9]\d{6,14}$/.test(phoneNumber)) {
      res.status(400).json({ error: "phoneNumber must be in E.164 format, e.g. +15551234567" });
      return;
    }

    try {
      await createTwilioClient(twilioAccountSid, twilioAuthToken)
        .verify.v2.services(twilioVerifyServiceSid)
        .verifications.create({ to: phoneNumber, channel: "sms" });
      res.json({ ok: true });
    } catch (err) {
      fail(res, err, 502, "Could not send the verification code. Please try again.", "phone: send-code");
    }
  }),
);

// POST /phone/check-code  { phoneNumber: string, code: string }
// On success, writes phone_number + phone_verified=true to the caller's own
// profile (never trusting a user id from the request body).
phoneRouter.post(
  "/check-code",
  checkCodeLimit,
  checkCodePerNumberLimit,
  asyncHandler(async (req, res) => {
    const { twilioAccountSid, twilioAuthToken, twilioVerifyServiceSid } = env;
    if (!twilioAccountSid || !twilioAuthToken || !twilioVerifyServiceSid) {
      notConfigured(res, "Phone verification");
      return;
    }

    const userId = req.userId;
    const phoneNumber = String(req.body?.phoneNumber ?? "").trim();
    const code = String(req.body?.code ?? "").trim();
    if (!E164_RE.test(phoneNumber) || !code) {
      res.status(400).json({ error: "phoneNumber must be E.164 and code must be present" });
      return;
    }

    let approved = false;
    try {
      const check = await createTwilioClient(twilioAccountSid, twilioAuthToken)
        .verify.v2.services(twilioVerifyServiceSid)
        .verificationChecks.create({ to: phoneNumber, code });
      approved = check.status === "approved";
    } catch (err) {
      fail(res, err, 502, "Could not check the code. Please try again.", "phone: check-code twilio");
      return;
    }

    if (!approved) {
      res.status(400).json({ error: "Incorrect or expired code" });
      return;
    }

    // Give a clear 409 when the number is already linked to another account,
    // and fall back to catching the unique violation so the race can't leak a
    // raw 500.
    const { data: existing, error: lookupError } = await supabaseAdmin
      .from("profiles")
      .select("id")
      .eq("phone_number", phoneNumber)
      .neq("id", userId)
      .maybeSingle();
    if (lookupError) {
      fail(res, lookupError, 500, "Something went wrong.", "phone: lookup number");
      return;
    }
    if (existing) {
      res.status(409).json({ error: "That number is already linked to another account" });
      return;
    }

    const { error } = await supabaseAdmin
      .from("profiles")
      .update({ phone_number: phoneNumber, phone_verified: true })
      .eq("id", userId);

    if (error) {
      if (isUniqueViolation(error)) {
        res.status(409).json({ error: "That number is already linked to another account" });
        return;
      }
      fail(res, error, 500, "Could not save your number. Please try again.", "phone: save number");
      return;
    }

    res.json({ ok: true, phoneNumber });
  }),
);
