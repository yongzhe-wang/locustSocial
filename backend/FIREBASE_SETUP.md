# Firebase Admin SDK Credentials Setup

## ⚠️ Security Notice

The Firebase Admin SDK credentials file (`*-firebase-adminsdk-*.json`) contains sensitive information and should **NEVER** be committed to version control.

## How to Get Your Credentials

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Click the gear icon → Project Settings
4. Go to "Service Accounts" tab
5. Click "Generate new private key"
6. Save the downloaded JSON file to this directory as:
   ```
   firebase-credentials.json
   ```

## Configuration

After downloading your credentials file:

1. **Rename it** to `firebase-credentials.json` (or update the path in your code)
2. **Verify .gitignore** includes this pattern:
   ```
   *firebase-adminsdk*.json
   firebase-credentials.json
   ```
3. **Never share** this file or commit it to git

## Environment Variable Alternative (Recommended for Production)

Instead of using a file, you can set the credentials as an environment variable:

```bash
# Set the entire JSON as an environment variable
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/firebase-credentials.json"

# Or use the JSON content directly
export FIREBASE_CREDENTIALS='{"type":"service_account",...}'
```

## Docker Setup

For Docker deployments, mount the credentials as a secret or use environment variables:

```yaml
# docker-compose.yml
services:
  api:
    environment:
      - GOOGLE_APPLICATION_CREDENTIALS=/app/secrets/firebase-credentials.json
    volumes:
      - ./secrets/firebase-credentials.json:/app/secrets/firebase-credentials.json:ro
```

## Security Best Practices

✅ **DO:**
- Use environment variables in production
- Rotate credentials regularly
- Use different credentials for dev/staging/production
- Store in secure secret management systems (AWS Secrets Manager, etc.)

❌ **DON'T:**
- Commit credentials to git
- Share credentials via email/chat
- Use production credentials in development
- Hardcode credentials in your code

## Troubleshooting

If you see authentication errors:
1. Verify the credentials file exists and is valid JSON
2. Check file permissions (should be readable by your app)
3. Ensure the service account has necessary IAM permissions
4. Verify you're using the correct Firebase project

## Questions?

See the [Firebase Admin SDK documentation](https://firebase.google.com/docs/admin/setup) for more information.
