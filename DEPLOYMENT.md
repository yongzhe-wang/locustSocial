# LocustSocial Deployment Guide 🚀

Complete guide for deploying LocustSocial to production environments.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [iOS App Deployment](#ios-app-deployment)
3. [Backend Deployment](#backend-deployment)
4. [Firebase Configuration](#firebase-configuration)
5. [Database Setup](#database-setup)
6. [CI/CD Setup](#cicd-setup)
7. [Monitoring & Maintenance](#monitoring--maintenance)

## Prerequisites

### Required Accounts
- [ ] Apple Developer Account ($99/year)
- [ ] Google Cloud Platform / Firebase Account
- [ ] Cloud hosting provider (AWS, DigitalOcean, or similar)
- [ ] Domain name registrar
- [ ] GitHub account (for CI/CD)

### Required Tools
- macOS with Xcode 15.0+
- Docker and Docker Compose
- kubectl (for Kubernetes deployments)
- Firebase CLI: `npm install -g firebase-tools`
- Fastlane (optional, for iOS automation)

## iOS App Deployment

### Step 1: Prepare App for Release

1. **Update Version and Build Number**
   ```bash
   cd LocustSocial/LocustSocial
   # In Xcode: Select target → General → Version and Build
   ```

2. **Configure App Icons and Launch Screen**
   - Add app icons to Assets.xcassets
   - Verify launch screen appears correctly
   - Test on multiple device sizes

3. **Update Bundle Identifier**
   - Change from development to production bundle ID
   - Example: `com.locustsocial.app`

4. **Configure Firebase for Production**
   ```bash
   # Download production GoogleService-Info.plist from Firebase Console
   # Replace in Xcode project
   ```

5. **Code Signing**
   - Create Distribution Certificate in Apple Developer Portal
   - Create App Store Provisioning Profile
   - Configure in Xcode: Signing & Capabilities

### Step 2: Build and Archive

```bash
# Clean build folder
rm -rf ~/Library/Developer/Xcode/DerivedData

# In Xcode:
# 1. Select "Any iOS Device" as target
# 2. Product → Archive
# 3. Wait for archive to complete
```

### Step 3: App Store Connect

1. **Create App in App Store Connect**
   - Go to https://appstoreconnect.apple.com
   - Create new app with bundle identifier
   - Fill in app information

2. **Upload Build**
   - In Xcode Organizer, select archive
   - Click "Distribute App"
   - Choose "App Store Connect"
   - Upload build

3. **Configure App Listing**
   - Screenshots (required for all device sizes)
   - App description
   - Keywords
   - Privacy policy URL
   - Support URL
   - Age rating

4. **Submit for Review**
   - Add build to version
   - Fill in "What's New" section
   - Submit for review

### Step 4: TestFlight Beta Testing (Optional)

```bash
# Add beta testers in App Store Connect
# Send invite links
# Collect feedback before public release
```

## Backend Deployment

### Option 1: Docker Container (Simple)

**Using DigitalOcean App Platform:**

1. **Create App**
   ```bash
   # In DigitalOcean Console:
   # Apps → Create App → GitHub
   # Select repository and backend folder
   ```

2. **Configure Environment**
   ```
   DATABASE_URL=postgresql://user:pass@host:5432/locustsocial
   PORT=8000
   HOST=0.0.0.0
   ```

3. **Deploy**
   - App Platform automatically builds from Dockerfile
   - Sets up HTTPS with managed certificates
   - Provides domain: yourapp.ondigitalocean.app

### Option 2: Kubernetes (Scalable)

**Prerequisites:**
- Kubernetes cluster (GKE, EKS, or DigitalOcean Kubernetes)
- kubectl configured
- Docker registry (Docker Hub, GCR, etc.)

**Step 1: Build and Push Image**

```bash
cd backend

# Build image
docker build -t yourusername/locustsocial-api:1.0.0 .

# Push to registry
docker push yourusername/locustsocial-api:1.0.0
```

**Step 2: Create Kubernetes Manifests**

Create `k8s/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: locustsocial-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: locustsocial-api
  template:
    metadata:
      labels:
        app: locustsocial-api
    spec:
      containers:
      - name: api
        image: yourusername/locustsocial-api:1.0.0
        ports:
        - containerPort: 8000
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: url
---
apiVersion: v1
kind: Service
metadata:
  name: locustsocial-api
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8000
  selector:
    app: locustsocial-api
```

**Step 3: Deploy**

```bash
# Create secret for database
kubectl create secret generic db-credentials \
  --from-literal=url='postgresql://user:pass@host:5432/locustsocial'

# Apply manifests
kubectl apply -f k8s/deployment.yaml

# Check status
kubectl get pods
kubectl get services
```

### Option 3: Docker Compose (Development/Small Scale)

```bash
cd backend

# Update docker-compose.yml with production settings
# Set environment variables in .env file

docker-compose -f docker-compose.prod.yml up -d

# Check logs
docker-compose logs -f api
```

## Firebase Configuration

### Step 1: Create Production Project

1. **Firebase Console**
   - Go to https://console.firebase.google.com
   - Create new project: "LocustSocial Production"
   - Enable Google Analytics

2. **Enable Services**
   ```bash
   # Authentication
   Enable Email/Password provider
   
   # Firestore
   Create database in production mode
   Choose region close to users
   
   # Storage
   Enable Cloud Storage
   Configure security rules
   ```

### Step 2: Security Rules

**Firestore Rules** (`firestore.rules`):
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can read public profiles
    match /users/{userId} {
      allow read: if true;
      allow write: if request.auth.uid == userId;
    }
    
    // Posts: public read, owner write
    match /posts/{postId} {
      allow read: if true;
      allow create: if request.auth != null;
      allow update, delete: if request.auth.uid == resource.data.authorId;
    }
    
    // Messages: only participants
    match /messages/{messageId} {
      allow read, write: if request.auth.uid == resource.data.senderId 
                          || request.auth.uid == resource.data.receiverId;
    }
  }
}
```

**Storage Rules** (`storage.rules`):
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /users/{userId}/{allPaths=**} {
      allow read: if true;
      allow write: if request.auth.uid == userId;
    }
    
    match /posts/{allPaths=**} {
      allow read: if true;
      allow write: if request.auth != null;
    }
  }
}
```

**Deploy Rules:**
```bash
firebase login
firebase use production
firebase deploy --only firestore:rules
firebase deploy --only storage
```

### Step 3: Indexes

Create indexes for common queries in Firebase Console:
- `posts`: `authorId` ASC, `createdAt` DESC
- `posts`: `createdAt` DESC
- `followers`: `followerId` ASC, `createdAt` DESC
- `messages`: `threadId` ASC, `createdAt` DESC

## Database Setup

### PostgreSQL Production Setup

**Option 1: Managed Database (Recommended)**

Use managed PostgreSQL from:
- **DigitalOcean**: Managed Databases
- **AWS RDS**: PostgreSQL
- **Google Cloud SQL**: PostgreSQL
- **Heroku**: Postgres add-on

Benefits:
- Automated backups
- High availability
- Automatic updates
- Monitoring included

**Option 2: Self-Hosted**

```bash
# Install PostgreSQL 15+ on Ubuntu
sudo apt update
sudo apt install postgresql-15 postgresql-contrib-15

# Install pgvector
cd /tmp
git clone https://github.com/pgvector/pgvector.git
cd pgvector
make
sudo make install

# Create database
sudo -u postgres createuser locustsocial
sudo -u postgres createdb locustsocial -O locustsocial
sudo -u postgres psql -c "ALTER USER locustsocial WITH PASSWORD 'secure_password';"

# Enable pgvector
sudo -u postgres psql locustsocial -c "CREATE EXTENSION vector;"

# Run migrations
psql -U locustsocial -d locustsocial < migrations/001_init.sql
psql -U locustsocial -d locustsocial < migrations/002_users_and_events.sql
```

### Database Backups

**Automated Daily Backups:**
```bash
# Create backup script
cat > /usr/local/bin/backup-locustsocial.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/locustsocial"
mkdir -p $BACKUP_DIR

pg_dump -U locustsocial locustsocial | gzip > $BACKUP_DIR/backup_$DATE.sql.gz

# Keep only last 30 days
find $BACKUP_DIR -name "backup_*.sql.gz" -mtime +30 -delete
EOF

chmod +x /usr/local/bin/backup-locustsocial.sh

# Add to crontab (daily at 2 AM)
echo "0 2 * * * /usr/local/bin/backup-locustsocial.sh" | crontab -
```

## CI/CD Setup

### GitHub Actions

Create `.github/workflows/ios.yml`:
```yaml
name: iOS CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '15.0'
    
    - name: Build
      run: |
        cd LocustSocial/LocustSocial
        xcodebuild -scheme LocustSocial -destination 'platform=iOS Simulator,name=iPhone 15' build
    
    - name: Run Tests
      run: |
        cd LocustSocial/LocustSocial
        xcodebuild test -scheme LocustSocial -destination 'platform=iOS Simulator,name=iPhone 15'
```

Create `.github/workflows/backend.yml`:
```yaml
name: Backend CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.11'
    
    - name: Install dependencies
      run: |
        cd backend
        pip install -r requirements.txt
        pip install pytest
    
    - name: Run tests
      run: |
        cd backend
        pytest tests/
  
  build:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Build Docker image
      run: |
        cd backend
        docker build -t locustsocial/api:latest .
    
    - name: Push to registry
      run: |
        echo "${{ secrets.DOCKER_PASSWORD }}" | docker login -u "${{ secrets.DOCKER_USERNAME }}" --password-stdin
        docker push locustsocial/api:latest
```

## Monitoring & Maintenance

### Application Monitoring

**Firebase:**
- Enable Crashlytics in iOS app
- Enable Performance Monitoring
- Set up Analytics events

**Backend:**
- Set up health check monitoring (UptimeRobot, Pingdom)
- Configure logging (CloudWatch, Papertrail)
- Set up error tracking (Sentry)

### Performance Monitoring

```python
# Add to FastAPI app
from prometheus_client import Counter, Histogram, generate_latest

REQUEST_COUNT = Counter('requests_total', 'Total requests')
REQUEST_LATENCY = Histogram('request_latency_seconds', 'Request latency')

@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    REQUEST_COUNT.inc()
    with REQUEST_LATENCY.time():
        response = await call_next(request)
    return response

@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type="text/plain")
```

### Alerts

Set up alerts for:
- [ ] API response time > 1s
- [ ] Error rate > 1%
- [ ] Database CPU > 80%
- [ ] Storage > 80% full
- [ ] App crashes

### Maintenance Tasks

**Weekly:**
- [ ] Review error logs
- [ ] Check performance metrics
- [ ] Review user feedback

**Monthly:**
- [ ] Database backup verification
- [ ] Security audit
- [ ] Dependency updates
- [ ] Cost analysis

**Quarterly:**
- [ ] Performance optimization
- [ ] Scalability review
- [ ] Disaster recovery test

## Rollback Procedures

### iOS App

If critical bug found after release:
1. Reject current version in App Store Connect
2. Fix bug in code
3. Submit new version with expedited review request

### Backend

**Kubernetes:**
```bash
# Rollback to previous deployment
kubectl rollout undo deployment/locustsocial-api

# Check rollout status
kubectl rollout status deployment/locustsocial-api
```

**Docker Compose:**
```bash
# Pull previous image version
docker pull locustsocial/api:previous-version

# Update docker-compose.yml
# Restart services
docker-compose up -d
```

## Security Checklist

- [ ] HTTPS enabled on all endpoints
- [ ] Firebase security rules deployed
- [ ] Database credentials stored in secrets
- [ ] API rate limiting enabled
- [ ] Input validation on all endpoints
- [ ] CORS configured properly
- [ ] Sensitive data encrypted at rest
- [ ] Regular security updates applied
- [ ] DDoS protection enabled
- [ ] Backup encryption enabled

## Cost Optimization

### iOS
- Optimize image sizes before upload
- Implement aggressive caching
- Batch API requests when possible

### Backend
- Use auto-scaling to match demand
- Enable database query caching
- Implement CDN for static assets
- Use spot instances for non-critical workloads

### Firebase
- Implement offline persistence to reduce reads
- Use composite indexes efficiently
- Clean up old data regularly
- Monitor usage in Firebase Console

## Support & Troubleshooting

### Common Issues

**Issue**: App rejected for missing privacy policy
- **Solution**: Host privacy policy and add URL in App Store Connect

**Issue**: High Firebase costs
- **Solution**: Review security rules, implement caching, optimize queries

**Issue**: Slow API response times
- **Solution**: Add database indexes, enable caching, scale horizontally

### Getting Help

- Documentation: See README files
- Issues: GitHub Issues
- Community: GitHub Discussions
- Support: support@locustsocial.com

---

**Last Updated**: February 7, 2026  
**Version**: 1.0.0

Good luck with your deployment! 🚀
