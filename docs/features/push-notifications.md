# Push Notifications

Get alerts when backups finish or fail.

---

## Limitations

- Notifications are sent only to the endpoint you configure.
- If the endpoint is offline, messages may be lost.

---

## macOS Notifications

1. Enable in FilmCan **Settings**
2. Configure style in **System Settings** > **Notifications** > FilmCan

---

## ntfy (Phone/Remote)

1. Create a free account at https://ntfy.sh (or use a self‑hosted ntfy) and install the app on your phone.
2. Create a topic: e.g. `ntfy.sh/mymovie_backup`
3. Paste the topic URL in FilmCan **Settings**
4. (Optional) Paste a **Bearer token** if your topic requires auth

---

## Webhook

Send a JSON payload to your own endpoint (Discord, Slack, custom server, etc.).

1. Enable **Webhook** in FilmCan **Settings**
2. Paste your **Webhook URL**
3. (Optional) Add **Custom headers** (one per line, `Header: Value`)

Payload format:
```
{
  "title": "...",
  "message": "...",
  "fields": {
    "movie": "...",
    "source": "...",
    "destination": "...",
    "sources": "...",
    "destinations": "...",
    "backupAction": "...",
    "bytes": "...",
    "files": "...",
    "duration": "...",
    "backupStatus": "...",
    "backupDetails": "..."
  }
}
```

The **title** and **message** use the same templates as ntfy. Use custom headers to add auth tokens (e.g., `Authorization: Bearer <token>`).

---

## What You'll Get

- Backup complete / failed (per destination)

---

## Troubleshooting

**No macOS alerts**  
**System Settings** > **Notifications** > FilmCan

**ntfy not working**  
Check topic URL and internet connection

**Webhook not working**  
Check URL, SSL/TLS, and your endpoint logs

---

## Related

- [Transfer History](./transfer-history.md)
