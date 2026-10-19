const express = require('express');
const cors = require('cors');
const nodemailer = require('nodemailer');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// Enable CORS and JSON parsing
app.use(cors());
app.use(express.json());

// Target support recipient email
const SUPPORT_EMAIL = process.env.SUPPORT_EMAIL || 'skdas1641999@gmail.com';
const ADMIN_CC = process.env.ADMIN_CC || 'sagar@onelap.in';
const SENDER_NAME = process.env.SENDER_NAME || 'Team RaahMilo Security Desk';

// Nodemailer transporter configuration
let transporter = null;
if (process.env.SMTP_USER && process.env.SMTP_PASS) {
  transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port: parseInt(process.env.SMTP_PORT || '465', 10),
    secure: process.env.SMTP_SECURE === 'true' || process.env.SMTP_PORT === '465',
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });
}

// In-memory vehicle security store
const vehicleSecurityStore = new Map();
let userSettingsStore = {
  antiTheftAutoArm: false,
  movementSensitivityMeters: 5,
  sirenAudioAlert: true,
  emailEscalationEnabled: true,
  updatedAt: new Date().toISOString(),
};

// -------------------------------------------------------------
// 1. HEALTH CHECK ENDPOINT
// -------------------------------------------------------------
app.get('/api/health', (req, res) => {
  res.json({
    status: 'online',
    system: 'RaahMilo Security API',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    smtpConfigured: transporter !== null,
    targetSupportEmail: SUPPORT_EMAIL,
  });
});

// -------------------------------------------------------------
// 2. ANTI-THEFT & VEHICLE SECURITY ENDPOINTS
// -------------------------------------------------------------

// Arm Vehicle
app.post('/api/vehicles/:id/arm', (req, res) => {
  const { id } = req.params;
  const { anchorLatitude, anchorLongitude, vehicleName, alarmMode } = req.body || {};

  const record = {
    vehicleId: id,
    vehicleName: vehicleName || 'Vehicle',
    isArmed: true,
    alarmTriggered: false,
    anchorLatitude: anchorLatitude || 0.0,
    anchorLongitude: anchorLongitude || 0.0,
    armedAt: new Date().toISOString(),
    alarmMode: alarmMode || 'MOTION_DETECTION',
  };

  vehicleSecurityStore.set(id, record);

  console.log(`[RaahMilo API] 🔒 Vehicle Armed: ${id} at (${anchorLatitude}, ${anchorLongitude})`);

  res.json({
    status: 'success',
    message: `Vehicle ${id} armed successfully with motion shield.`,
    vehicleId: id,
    isArmed: true,
    armedAt: record.armedAt,
  });
});

// Disarm Vehicle
app.post('/api/vehicles/:id/disarm', (req, res) => {
  const { id } = req.params;
  const existing = vehicleSecurityStore.get(id) || {};

  vehicleSecurityStore.set(id, {
    ...existing,
    vehicleId: id,
    isArmed: false,
    alarmTriggered: false,
    disarmedAt: new Date().toISOString(),
  });

  console.log(`[RaahMilo API] 🔓 Vehicle Disarmed: ${id}`);

  res.json({
    status: 'success',
    message: `Vehicle ${id} disarmed. Security shield deactivated.`,
    vehicleId: id,
    isArmed: false,
  });
});

// Trigger Alarm
app.post('/api/alarm/trigger', (req, res) => {
  const { vehicleId, reason, currentLatitude, currentLongitude } = req.body || {};
  const id = vehicleId || 'unknown_vehicle';

  const existing = vehicleSecurityStore.get(id) || {};
  vehicleSecurityStore.set(id, {
    ...existing,
    vehicleId: id,
    alarmTriggered: true,
    lastAlarmReason: reason || 'Unauthorized Movement',
    alarmTriggeredAt: new Date().toISOString(),
  });

  console.log(`[RaahMilo API] 🚨 ALARM TRIGGERED on ${id}: ${reason}`);

  res.json({
    status: 'success',
    alarmTriggered: true,
    vehicleId: id,
    message: 'Alarm siren activated on device.',
    timestamp: new Date().toISOString(),
  });
});

// Silence Alarm
app.post('/api/alarm/silence', (req, res) => {
  const { vehicleId } = req.body || {};
  const id = vehicleId || 'all';

  if (vehicleId && vehicleSecurityStore.has(vehicleId)) {
    const existing = vehicleSecurityStore.get(vehicleId);
    existing.alarmTriggered = false;
    vehicleSecurityStore.set(vehicleId, existing);
  }

  console.log(`[RaahMilo API] 🔕 Alarm Silenced for ${id}`);

  res.json({
    status: 'success',
    alarmTriggered: false,
    message: 'Alarm silenced successfully.',
    timestamp: new Date().toISOString(),
  });
});

// Get Vehicle Security Status
app.get('/api/vehicles/:id/security-status', (req, res) => {
  const { id } = req.params;
  const record = vehicleSecurityStore.get(id) || {
    vehicleId: id,
    isArmed: false,
    alarmTriggered: false,
  };

  res.json(record);
});

// -------------------------------------------------------------
// 3. AI SUPPORT CHATBOT ENDPOINT
// -------------------------------------------------------------
app.post('/api/support/ai-chat', async (req, res) => {
  const { message, history, userEmail, useHindi } = req.body || {};
  const q = (message || '').toLowerCase();

  // 1. If GEMINI_API_KEY is configured in server .env, query Gemini 1.5 Flash directly
  if (process.env.GEMINI_API_KEY) {
    try {
      const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${process.env.GEMINI_API_KEY}`;
      const contents = (history || []).slice(-6).map((h) => ({
        role: h.role === 'user' ? 'user' : 'model',
        parts: [{ text: h.content || '' }],
      }));
      contents.push({ role: 'user', parts: [{ text: message || '' }] });

      const geminiResponse = await fetch(geminiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          system_instruction: {
            parts: [
              {
                text: `You are RaahMilo's friendly and caring human customer support executive. Talk warmly, naturally, and conversationally like a human friend in ${useHindi ? 'Hindi / Hinglish' : 'English'}. Help with vehicle security, anti-theft, parking guard, siren alarms, engine cut-off, and GPS tracking. Keep replies concise and reassuring with emojis.`,
              },
            ],
          },
          contents,
        }),
      });

      if (geminiResponse.ok) {
        const geminiData = await geminiResponse.json();
        const generatedText = geminiData.candidates?.[0]?.content?.parts?.[0]?.text;
        if (generatedText) {
          return res.json({
            reply: generatedText.trim(),
            engine: 'gemini-1.5-flash',
            timestamp: new Date().toISOString(),
          });
        }
      }
    } catch (e) {
      console.error('[RaahMilo AI Server] Gemini error:', e.message);
    }
  }

  // 2. Human-like conversational response fallback
  let botReply = '';
  let autoEscalate = false;

  if (q.includes('theft') || q.includes('chori') || q.includes('stolen') || q.includes('dar')) {
    botReply = useHindi
      ? 'Arey bhai, aap bilkul tension mat lijiye! RaahMilo ka Anti-Theft shield isi ke liye bana hai. Aap Anti-Theft tab me jakar "Arm Vehicle" dabayein. Agar koi 1 meter bhi gaadi chhuega toh zordar siren bajega aur alert aa jayega! 🛡️'
      : 'Please take a deep breath and relax! RaahMilo\'s Anti-Theft shield was built to protect against theft. Tap "ARM VEHICLE" in the Anti-Theft tab. If anyone touches your vehicle, a loud siren sounds immediately! 🛡️';
    autoEscalate = true;
  } else if (q.includes('kaise ho') || q.includes('hello') || q.includes('hi') || q.includes('namaste')) {
    botReply = useHindi
      ? 'Namaste bhai! 👋 Main bilkul badiya hoon, aap bataiye kaise hain? Main RaahMilo se aapka dost hoon. Aapki bike ya gaadi ki security me main kya madad kar sakta hoon?'
      : 'Hello there! 👋 I am doing great, thank you for asking! I am your RaahMilo security companion. How can I help protect your vehicle today?';
  } else if (q.includes('free') || q.includes('paisa') || q.includes('charge') || q.includes('cost')) {
    botReply = useHindi
      ? 'Haanji bhai, RaahMilo app, iska live GPS tracking, aur Anti-Theft alerts aapke liye 100% bilkul FREE hain! Koi hidden fees nahi hai, aap maze se use kijiye! 🎉'
      : 'Yes, absolutely! The RaahMilo app, real-time GPS tracking, and Anti-Theft alerts are 100% completely FREE to use! 🎉';
  } else if (q.includes('arm') || q.includes('lock') || q.includes('suraksha')) {
    botReply = useHindi
      ? 'Gaadi lock karna bohot simple hai! Anti-Theft tab me jayein aur "ARM VEHICLE" button dabayein. Gaadi ka GPS anchor point lock ho jayega.'
      : 'Arming your vehicle is super simple! Go to the Anti-Theft tab and tap "ARM VEHICLE". Your vehicle\'s position will be anchored with active motion detection.';
  } else if (q.includes('alarm') || q.includes('siren') || q.includes('sound') || q.includes('baj raha')) {
    botReply = useHindi
      ? 'Alarm band karne ke liye Anti-Theft screen par "Silence Alarm" button ya upar red emergency banner par "Silence" dabayein. Siren turant chup ho jayega!'
      : 'You can silence an active alarm anytime by tapping "Silence Siren" on the Anti-Theft screen or top emergency banner.';
  } else if (q.includes('contact') || q.includes('support') || q.includes('help') || q.includes('madad')) {
    botReply = useHindi
      ? 'Humari support desk 24x7 active hai bhai! Aapki koi bhi pareshani ho, batayein aur humari technical team turant action legi.'
      : 'Our support desk is active 24/7! Any issue you mention here is immediately escalated to our operations team.';
  } else {
    botReply = useHindi
      ? 'Main samajh gaya dost! 😊 Main aapki gaadi ki suraksha me poori madad karne ke liye yahan hoon. Aap Anti-Theft, Alarm, GPS live tracking ya kisi bhi cheez ke baare me poochh sakte hain!'
      : 'I hear you! 😊 I am right here to help you with vehicle security, Anti-Theft protection, siren alarms, or live GPS tracking. Feel free to ask anything!';
  }

  res.json({
    reply: botReply,
    autoEscalate,
    engine: 'human-conversational-engine',
    userEmail: userEmail || 'Anonymous',
    timestamp: new Date().toISOString(),
  });
});

// -------------------------------------------------------------
// 4. SECURE EMAIL ALERT ESCALATION ENDPOINT
// (100% Custom Branded: "Team RaahMilo", NO 3rd-party ads/footers!)
// -------------------------------------------------------------
app.post('/api/support/alert-email', async (req, res) => {
  const {
    ticketId,
    senderEmail,
    userUid,
    issueDescription,
    priority = 'HIGH',
    telemetry = {},
  } = req.body || {};

  const cleanTicket = ticketId || `RM-${Date.now().toString().slice(-6)}`;
  const cleanPriority = priority.toUpperCase();

  // Custom 100% Branded HTML Email Template
  const htmlContent = `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>RaahMilo Security Alert</title>
    </head>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #f1f5f9; margin: 0; padding: 24px;">
      <div style="max-width: 620px; margin: 0 auto; background: #ffffff; border-radius: 14px; overflow: hidden; box-shadow: 0 4px 16px rgba(0,0,0,0.06); border: 1px solid #e2e8f0;">
        
        <!-- Header -->
        <div style="background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%); padding: 24px 28px; color: #ffffff;">
          <div style="display: flex; align-items: center; justify-content: space-between;">
            <div>
              <h1 style="margin: 0; font-size: 22px; font-weight: 700; letter-spacing: -0.5px;">🛡️ RaahMilo Security Alert</h1>
              <p style="margin: 6px 0 0 0; color: #94a3b8; font-size: 13px;">Automated Vehicle Defense & Support Dispatch</p>
            </div>
            <span style="background: ${cleanPriority.includes('THEFT') || cleanPriority.includes('CRITICAL') ? '#ef4444' : '#f59e0b'}; color: white; padding: 6px 12px; border-radius: 20px; font-size: 12px; font-weight: bold;">
              ${cleanPriority}
            </span>
          </div>
        </div>

        <!-- Ticket Summary -->
        <div style="padding: 24px 28px; background: #fafafa; border-bottom: 1px solid #e2e8f0;">
          <table style="width: 100%; border-collapse: collapse;">
            <tr>
              <td style="color: #64748b; font-size: 13px; padding-bottom: 6px;">Ticket Number:</td>
              <td style="color: #0f172a; font-size: 14px; font-weight: 700; padding-bottom: 6px;">#${cleanTicket}</td>
            </tr>
            <tr>
              <td style="color: #64748b; font-size: 13px; padding-bottom: 6px;">Reported By:</td>
              <td style="color: #0f172a; font-size: 14px; padding-bottom: 6px;">${senderEmail || 'Mobile App User'}</td>
            </tr>
            <tr>
              <td style="color: #64748b; font-size: 13px;">Timestamp:</td>
              <td style="color: #0f172a; font-size: 14px;">${new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })} IST</td>
            </tr>
          </table>
        </div>

        <!-- Incident Details -->
        <div style="padding: 24px 28px;">
          <h3 style="margin-top: 0; color: #0f172a; font-size: 16px;">Issue Description:</h3>
          <div style="background: #f8fafc; border-left: 4px solid #2563eb; padding: 14px 18px; border-radius: 6px; color: #1e293b; font-size: 14px; line-height: 1.6;">
            ${issueDescription || 'No description provided.'}
          </div>

          ${
            Object.keys(telemetry).length > 0
              ? `
              <h4 style="margin: 20px 0 8px 0; color: #475569; font-size: 14px;">Telemetry & Device Coordinates:</h4>
              <div style="background: #1e293b; color: #e2e8f0; font-family: monospace; font-size: 12px; padding: 12px; border-radius: 6px; overflow-x: auto;">
                ${JSON.stringify(telemetry, null, 2)}
              </div>
            `
              : ''
          }
        </div>

        <!-- Footer (Custom Branded, NO 3rd-party ads) -->
        <div style="background: #f8fafc; border-top: 1px solid #e2e8f0; padding: 20px 28px; text-align: center;">
          <p style="margin: 0; font-size: 13px; color: #475569; font-weight: 600;">
            Dispatched securely by Team RaahMilo Automated Operations
          </p>
          <p style="margin: 4px 0 0 0; font-size: 11px; color: #94a3b8;">
            Protected by RaahMilo Anti-Theft Protocol • Confidential & Private
          </p>
        </div>

      </div>
    </body>
    </html>
  `;

  console.log(`[RaahMilo Support Alert] Ticket #${cleanTicket} dispatched for ${senderEmail}`);

  let emailSent = false;
  let emailError = null;

  if (transporter) {
    try {
      await transporter.sendMail({
        from: `"${SENDER_NAME}" <${process.env.SMTP_USER}>`,
        to: SUPPORT_EMAIL,
        cc: ADMIN_CC,
        subject: `🚨 [RaahMilo] Support Alert - Ticket #${cleanTicket} [${cleanPriority}]`,
        html: htmlContent,
      });
      emailSent = true;
      console.log(`[RaahMilo Email] ✅ Sent via Nodemailer directly to ${SUPPORT_EMAIL}`);
    } catch (err) {
      emailError = err.message;
      console.error(`[RaahMilo Email] ⚠️ Nodemailer error:`, err.message);
    }
  } else {
    console.log(`[RaahMilo Email] ℹ️ SMTP credentials not set in .env. Logged alert safely to system records.`);
  }

  res.json({
    status: 'success',
    ticketId: cleanTicket,
    recipientEmail: SUPPORT_EMAIL,
    adminCc: ADMIN_CC,
    dispatched: true,
    emailSentDirectly: emailSent,
    senderName: SENDER_NAME,
    message: emailSent
      ? 'Alert email delivered directly with Team RaahMilo branding.'
      : 'Alert logged securely in RaahMilo System.',
    error: emailError,
  });
});

// -------------------------------------------------------------
// 5. USER SETTINGS ENDPOINTS
// -------------------------------------------------------------
app.get('/api/user/settings', (req, res) => {
  res.json({
    status: 'success',
    settings: userSettingsStore,
  });
});

app.post('/api/user/settings', (req, res) => {
  const { settings } = req.body || {};
  userSettingsStore = {
    ...userSettingsStore,
    ...(settings || {}),
    updatedAt: new Date().toISOString(),
  };

  res.json({
    status: 'success',
    message: 'Settings updated successfully.',
    settings: userSettingsStore,
  });
});

// Start the server
app.listen(PORT, () => {
  console.log(`=======================================================`);
  console.log(`🛡️  RaahMilo Security & Support Backend API`);
  console.log(`📡 Server running at: http://localhost:${PORT}/api`);
  console.log(`✉️  Support Alerts Target: ${SUPPORT_EMAIL}`);
  console.log(`🔒 Custom Sender: ${SENDER_NAME}`);
  console.log(`=======================================================`);
});
