<!-- lang:en -->
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

<!-- lang:fr -->
# Notifications push

Recevez des alertes lorsque les backups se terminent ou échouent.

---

## Limitations

- Les notifications sont envoyées uniquement à l'endpoint que vous configurez.
- Si l'endpoint est hors ligne, les messages peuvent être perdus.

---

## Notifications macOS

1. Activez dans FilmCan **Settings**
2. Configurez le style dans **System Settings** > **Notifications** > FilmCan

---

## ntfy (Téléphone/Distant)

1. Créez un compte gratuit sur https://ntfy.sh (ou utilisez un ntfy auto-hébergé) et installez l'application sur votre téléphone.
2. Créez un sujet : par ex. `ntfy.sh/mymovie_backup`
3. Collez l'URL du sujet dans FilmCan **Settings**
4. (Optionnel) Collez un **Bearer token** si votre sujet nécessite une authentification

---

## Webhook

Envoyez une charge utile JSON à votre propre endpoint (Discord, Slack, serveur personnalisé, etc.).

1. Activez **Webhook** dans FilmCan **Settings**
2. Collez votre **Webhook URL**
3. (Optionnel) Ajoutez des **Custom headers** (un par ligne, `Header: Value`)

Format de charge utile :
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

Le **title** et le **message** utilisent les mêmes modèles que ntfy. Utilisez des en-têtes personnalisés pour ajouter des jetons d'authentification (par ex., `Authorization: Bearer <token>`).

---

## Ce que vous obtiendrez

- Backup terminé/échoué (par destination)

---

## Dépannage

**Pas d'alertes macOS**  
**System Settings** > **Notifications** > FilmCan

**ntfy ne fonctionne pas**  
Vérifiez l'URL du sujet et la connexion Internet

**Webhook ne fonctionne pas**  
Vérifiez l'URL, SSL/TLS et les journaux de votre endpoint

---

## Liens

- [Transfer History](./transfer-history.md)

<!-- lang:de -->
# Push-Benachrichtigungen

Erhalten Sie Benachrichtigungen, wenn Backups abgeschlossen sind oder fehlschlagen.

---

## Einschränkungen

- Benachrichtigungen werden nur an den Endpoint gesendet, den Sie konfigurieren.
- Wenn der Endpoint offline ist, können Nachrichten verloren gehen.

---

## macOS-Benachrichtigungen

1. Aktivieren Sie in FilmCan **Settings**
2. Konfigurieren Sie den Stil in **System Settings** > **Notifications** > FilmCan

---

## ntfy (Telefon/Fern)

1. Erstellen Sie ein kostenloses Konto unter https://ntfy.sh (oder verwenden Sie eine selbst gehostete ntfy) und installieren Sie die App auf Ihrem Telefon.
2. Erstellen Sie ein Thema: z. B. `ntfy.sh/mymovie_backup`
3. Fügen Sie die Thema-URL in FilmCan **Settings** ein
4. (Optional) Fügen Sie ein **Bearer token** ein, wenn Ihr Thema Authentifizierung erfordert

---

## Webhook

Senden Sie eine JSON-Nutzlast an Ihren eigenen Endpoint (Discord, Slack, benutzerdefinierter Server usw.).

1. Aktivieren Sie **Webhook** in FilmCan **Settings**
2. Fügen Sie Ihre **Webhook URL** ein
3. (Optional) Fügen Sie **Custom headers** hinzu (eine pro Zeile, `Header: Value`)

Nutzlastformat:
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

Der **title** und die **message** verwenden dieselben Vorlagen wie ntfy. Verwenden Sie benutzerdefinierte Header, um Authentifizierungstoken hinzuzufügen (z. B. `Authorization: Bearer <token>`).

---

## Was Sie erhalten

- Backup abgeschlossen/fehlgeschlagen (pro Ziel)

---

## Fehlerbehebung

**Keine macOS-Benachrichtigungen**  
**System Settings** > **Notifications** > FilmCan

**ntfy funktioniert nicht**  
Überprüfen Sie Thema-URL und Internetverbindung

**Webhook funktioniert nicht**  
Überprüfen Sie URL, SSL/TLS und Ihre Endpoint-Protokolle

---

## Links

- [Transfer History](./transfer-history.md)

<!-- lang:es -->
# Notificaciones push

Reciba alertas cuando los backups se completen o fallen.

---

## Limitaciones

- Las notificaciones se envían solo al endpoint que configura.
- Si el endpoint está desconectado, los mensajes pueden perderse.

---

## Notificaciones de macOS

1. Habilite en FilmCan **Settings**
2. Configure el estilo en **System Settings** > **Notifications** > FilmCan

---

## ntfy (Teléfono/Remoto)

1. Cree una cuenta gratuita en https://ntfy.sh (o use un ntfy autoalojado) e instale la aplicación en su teléfono.
2. Cree un tema: por ejemplo, `ntfy.sh/mymovie_backup`
3. Pegue la URL del tema en FilmCan **Settings**
4. (Opcional) Pegue un **Bearer token** si su tema requiere autenticación

---

## Webhook

Envíe una carga JSON a su propio endpoint (Discord, Slack, servidor personalizado, etc.).

1. Habilite **Webhook** en FilmCan **Settings**
2. Pegue su **Webhook URL**
3. (Opcional) Agregue **Custom headers** (una por línea, `Header: Value`)

Formato de carga:
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

El **title** y el **message** utilizan las mismas plantillas que ntfy. Utilice encabezados personalizados para agregar tokens de autenticación (por ejemplo, `Authorization: Bearer <token>`).

---

## Lo que obtendrá

- Backup completado/fallido (por destino)

---

## Resolución de problemas

¿No hay alertas de macOS?  
**System Settings** > **Notifications** > FilmCan

¿ntfy no funciona?  
Verifique la URL del tema y la conexión a Internet

¿Webhook no funciona?  
Verifique la URL, SSL/TLS y sus registros de endpoint

---

## Relacionado

- [Transfer History](./transfer-history.md)
