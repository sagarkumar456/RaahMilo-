# RaahMilo Backend API Server

Safe, secure, and private REST API backend for the **RaahMilo Vehicle Security & Anti-Theft System**.

---

## 🚀 Quick Start

1. Open your terminal in this `server` folder:
   ```bash
   cd server
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. (Optional) Configure SMTP in `.env`:
   ```bash
   cp .env.example .env
   ```
   Add your Gmail App Password to `.env` if you want emails sent directly via your own Gmail SMTP without any third-party services.

4. Start the server:
   ```bash
   npm start
   ```
   Server runs at: `http://localhost:3000/api`

---

## 🔒 Security Features
- **100% Private & Branded**: All emails sent with **"Team RaahMilo Security Desk"** header and footer.
- **No 3rd-Party Ads or Footers**: Completely free of third-party branding.
- **TLS/SSL Encryption**: Standard port 465 SSL transport.
- **CORS Protected**: Safe for both mobile app and web clients.
- **Auto Graceful Fallback**: If internet is down or SMTP is not set, the app continues smoothly with in-memory logging.

---

## 📡 API Endpoints
- `GET  /api/health` — Check system status
- `POST /api/vehicles/:id/arm` — Arm vehicle with motion anchor
- `POST /api/vehicles/:id/disarm` — Disarm vehicle
- `POST /api/alarm/trigger` — Trigger emergency siren alarm
- `POST /api/alarm/silence` — Silence active alarms
- `POST /api/support/ai-chat` — AI security chatbot
- `POST /api/support/alert-email` — Dispatch branded alert email to skdas1641999@gmail.com
- `GET  /api/user/settings` — Get security settings
- `POST /api/user/settings` — Save security settings
