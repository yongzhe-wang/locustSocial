# LocustSocial - Technical Overview 🦗

## Executive Summary

LocustSocial is a next-generation social networking platform that leverages AI and modern cloud architecture to deliver personalized, engaging user experiences. Built with SwiftUI for iOS and powered by a FastAPI backend with PostgreSQL vector database, the platform enables intelligent content discovery through multimodal search and machine learning-based recommendations.

## Technology Stack

### Frontend (iOS)
| Component | Technology | Version |
|-----------|-----------|---------|
| Language | Swift | 5.9+ |
| UI Framework | SwiftUI | iOS 17.0+ |
| Architecture | MVVM + DI | - |
| Auth | Firebase Auth | Latest |
| Database | Firestore | Latest |
| Storage | Firebase Storage | Latest |
| Concurrency | async/await | Native |

### Backend (Python)
| Component | Technology | Version |
|-----------|-----------|---------|
| Framework | FastAPI | 0.115+ |
| Language | Python | 3.11+ |
| Database | PostgreSQL | 15+ |
| Vector Search | pgvector | 0.5+ |
| ML Model | OpenAI CLIP | ViT-B/32 |
| Server | Uvicorn | Latest |
| Proxy | Caddy | 2.x |
| Container | Docker | Latest |

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                       iOS App                           │
│                     (SwiftUI)                           │
│  ┌─────────┬─────────┬─────────┬─────────┬──────────┐ │
│  │  Auth   │  Feed   │ Create  │ Profile │  Search  │ │
│  └─────────┴─────────┴─────────┴─────────┴──────────┘ │
└────────────┬──────────────────────────┬─────────────────┘
             │                          │
             │ Firebase SDK             │ HTTP/REST
             │                          │
    ┌────────▼────────┐        ┌───────▼────────┐
    │    Firebase     │        │  FastAPI       │
    │                 │        │  Backend       │
    │  ┌──────────┐  │        │                │
    │  │   Auth   │  │        │  ┌──────────┐ │
    │  ├──────────┤  │        │  │ Ranking  │ │
    │  │Firestore │  │        │  ├──────────┤ │
    │  ├──────────┤  │        │  │  CLIP    │ │
    │  │ Storage  │  │        │  ├──────────┤ │
    │  └──────────┘  │        │  │  Search  │ │
    └─────────────────┘        └───────┬──────┘
                                       │
                              ┌────────▼─────────┐
                              │   PostgreSQL     │
                              │   + pgvector     │
                              │                  │
                              │  ┌────────────┐ │
                              │  │   posts    │ │
                              │  │ embeddings │ │
                              │  └────────────┘ │
                              └──────────────────┘
```

## Data Models

### User (Firestore)
```swift
struct User {
    let id: String              // Firebase Auth UID
    var username: String
    var displayName: String
    var bio: String
    var profileImageUrl: String?
    var followerCount: Int
    var followingCount: Int
    var location: GeoPoint?
    let createdAt: Date
}
```

### Post (Firestore)
```swift
struct Post {
    let id: String
    let author: User
    var content: String
    var imageUrls: [String]
    var likeCount: Int
    var commentCount: Int
    var shareCount: Int
    let createdAt: Date
    var location: GeoPoint?
    var isLiked: Bool           // Current user state
}
```

### Post Embedding (PostgreSQL)
```sql
CREATE TABLE posts (
    id UUID PRIMARY KEY,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    image_url TEXT,
    embedding VECTOR(512),      -- CLIP embedding
    created_at TIMESTAMP DEFAULT NOW()
);
```

### Message (Firestore)
```swift
struct DMMessage {
    let id: String
    let threadId: String
    let senderId: String
    let receiverId: String
    let text: String
    let createdAt: Date
    var isRead: Bool
}
```

## Key Features Implementation

### 1. AI-Powered Feed Ranking

**Flow:**
1. User requests feed from Firebase
2. iOS app sends post IDs to FastAPI backend
3. Backend retrieves post embeddings from PostgreSQL
4. ML model ranks posts based on:
   - User interaction history
   - Content similarity to preferences
   - Engagement signals
   - Temporal relevance
5. Ranked post IDs returned to app
6. App displays posts in personalized order

**Code Location:**
- iOS: `PersonalizedFeedAPI.swift`, `BackendRankAPI.swift`
- Backend: `app/features/posts.py`, `app/embeddings.py`

### 2. Multimodal Search

**Text Search:**
```
User Query → CLIP Text Encoder → Query Embedding (512-dim) 
→ Cosine Similarity Search in pgvector → Ranked Results
```

**Image Search:**
```
User Image → CLIP Image Encoder → Query Embedding (512-dim)
→ Cosine Similarity Search in pgvector → Ranked Results
```

**Hybrid Search:**
```
Text + Image → Averaged Embeddings → Combined Query
→ Vector Search → Ranked Results
```

**Code Location:**
- Backend: `app/embeddings.py`, `app/main.py`
- Database: `migrations/001_init.sql`

### 3. Real-Time Messaging

**Architecture:**
- Firestore subcollections for message threads
- Real-time listeners for instant delivery
- Optimistic UI updates for sent messages
- Unread message counters with live sync

**Code Location:**
- iOS: `FirebaseMessageAPI.swift`, `ThreadsVM.swift`, `CommentsDetailView.swift`

### 4. Location-Based Discovery

**Implementation:**
- Geohash indexing for efficient proximity queries
- Firestore geo queries with radius filtering
- Privacy controls for location sharing
- Distance calculation for sorting

**Code Location:**
- iOS: `NearbyView.swift`, `FirebaseFeedAPI.swift`

## API Endpoints

### Backend (FastAPI)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/healthz` | GET | Health check |
| `/api/posts` | POST | Create post with embedding |
| `/api/search` | POST | Text search |
| `/api/search-multipart` | POST | Image/hybrid search |
| `/docs` | GET | Swagger UI |
| `/redoc` | GET | ReDoc documentation |

### Firebase (via SDK)

| Collection | Operations | Description |
|------------|-----------|-------------|
| `users` | CRUD | User profiles |
| `posts` | CRUD, Query | Post content |
| `followers` | CRUD | Follow relationships |
| `messages` | CRUD, Listen | Direct messages |
| `likes` | CRUD | Post likes |
| `comments` | CRUD | Post comments |

## Performance Optimizations

### iOS App
- **Lazy Loading**: Images loaded on-demand with caching
- **Pagination**: Infinite scroll with cursor-based fetching (20 posts/page)
- **Optimistic Updates**: Instant UI feedback before network confirmation
- **SwiftUI Efficiency**: ViewBuilders and @State for minimal re-renders
- **Background Tasks**: Image uploads and processing in background

### Backend
- **Vector Indexing**: IVFFlat index for O(log n) ANN search
- **Connection Pooling**: Reuse database connections
- **Model Caching**: CLIP model loaded once at startup
- **Async I/O**: All operations use async/await
- **Batch Processing**: Handle multiple queries efficiently

### Database
- **Firestore Indexes**: Compound indexes for common queries
- **Denormalization**: Reduce query complexity with redundant data
- **Pagination**: Cursor-based queries for large datasets
- **Vector Index**: Fast cosine similarity search in PostgreSQL

## Security Measures

### Authentication
- Firebase Auth with secure tokens
- JWT validation on API requests
- Refresh token rotation
- Password requirements enforcement

### Authorization
- Firestore security rules for data access
- User ownership validation
- Private message encryption
- API rate limiting

### Data Protection
- HTTPS-only communication
- Encrypted data at rest (Firebase/PostgreSQL)
- Input validation and sanitization
- SQL injection prevention (parameterized queries)

## Deployment Strategy

### Development
```
Local Machine → Xcode → iOS Simulator
Local Machine → Docker Compose → Backend Services
```

### Staging (Planned)
```
GitHub → CI/CD Pipeline → TestFlight (iOS)
GitHub → CI/CD Pipeline → Staging Server (Backend)
```

### Production (Planned)
```
GitHub → CI/CD Pipeline → App Store (iOS)
GitHub → CI/CD Pipeline → Kubernetes Cluster (Backend)
└─ Load Balancer → Multiple API Pods
   └─ PostgreSQL Cluster (Primary + Replicas)
```

## Monitoring & Analytics (Planned)

- **App Analytics**: Firebase Analytics for user behavior
- **Crash Reporting**: Firebase Crashlytics
- **Performance**: Firebase Performance Monitoring
- **Backend Metrics**: Prometheus + Grafana
- **Logs**: Centralized logging with ELK stack
- **Alerts**: PagerDuty for critical issues

## Testing Strategy

### iOS
- **Unit Tests**: Business logic and ViewModels
- **UI Tests**: Critical user flows (XCTest)
- **Manual Testing**: Device testing on multiple iOS versions
- **TestFlight**: Beta testing with real users

### Backend
- **Unit Tests**: Individual functions and modules
- **Integration Tests**: API endpoints with test database
- **Load Tests**: Concurrent request handling
- **CI/CD**: Automated testing on every commit

## Scalability Roadmap

### Phase 1: 0-10K Users (Current)
- Single Firebase project
- Single backend container
- PostgreSQL on single instance

### Phase 2: 10K-100K Users
- Firebase performance optimization
- Kubernetes deployment (3+ API pods)
- PostgreSQL read replicas
- CDN for images (Cloudflare)

### Phase 3: 100K-1M Users
- Multi-region Firebase
- Auto-scaling backend (10+ pods)
- Database sharding
- Redis caching layer
- Message queue (RabbitMQ)

### Phase 4: 1M+ Users
- Microservices architecture
- Service mesh (Istio)
- Global CDN
- Advanced caching strategies
- ML model serving infrastructure

## Development Workflow

1. **Feature Planning**: GitHub Issues & Project Boards
2. **Branch Creation**: `feature/*` or `fix/*`
3. **Development**: Local environment with hot reload
4. **Testing**: Unit tests + manual testing
5. **Code Review**: Pull request with peer review
6. **CI/CD**: Automated tests and linting
7. **Merge**: Squash and merge to main
8. **Deployment**: Automated to staging/production

## Cost Structure (Estimated)

### Current (Development)
- **Firebase**: Free tier (adequate for MVP)
- **Infrastructure**: Local development (no cost)
- **Total**: $0/month

### Phase 1 (0-10K users)
- **Firebase**: ~$200/month
- **Backend Server**: $50/month (DigitalOcean)
- **Database**: $25/month (managed PostgreSQL)
- **Domain/CDN**: $20/month
- **Total**: ~$300/month

### Phase 2 (10K-100K users)
- **Firebase**: ~$1,500/month
- **Kubernetes Cluster**: $500/month
- **Database**: $200/month (managed cluster)
- **CDN**: $300/month
- **Monitoring**: $100/month
- **Total**: ~$2,600/month

## Future Enhancements

### Short Term (Q1-Q2 2026)
- [ ] Push notifications
- [ ] Stories (24-hour ephemeral posts)
- [ ] Video posts
- [ ] Enhanced moderation tools
- [ ] Deep linking

### Medium Term (Q3-Q4 2026)
- [ ] Live streaming
- [ ] Group chats
- [ ] Creator monetization
- [ ] Advanced analytics dashboard
- [ ] Web application (PWA)

### Long Term (2027+)
- [ ] AR filters
- [ ] Blockchain integration
- [ ] Decentralized storage
- [ ] AI content moderation
- [ ] Voice/audio posts

## Repository Structure

```
LocustSocial/
├── README.md                    # Main investor-focused README
├── CONTRIBUTING.md              # Contribution guidelines
├── CODE_OF_CONDUCT.md          # Community standards
├── CHANGELOG.md                 # Version history
├── TECHNICAL_OVERVIEW.md        # This file
├── LICENSE                      # License information
├── .gitignore                   # Git ignore rules
│
├── LocustSocial/               # iOS Application
│   ├── LocustSocial.xcodeproj/ # Xcode project
│   ├── LocustSocial_App/       # App source code
│   ├── LocustSocialTests/      # Unit tests
│   └── LocustSocialUITests/    # UI tests
│
├── backend/                     # Python Backend
│   ├── app/                    # FastAPI application
│   ├── migrations/             # Database migrations
│   ├── tests/                  # Backend tests
│   ├── docker-compose.yml      # Local development
│   ├── Dockerfile              # Container image
│   └── README.md               # Backend documentation
│
└── firebase/                    # Firebase Configuration
    └── firebase/
        ├── firestore.rules     # Security rules
        ├── storage.rules       # Storage rules
        └── functions/          # Cloud Functions (optional)
```

## Contact & Resources

- **Repository**: https://github.com/LocustSocial/LocustSocial
- **Documentation**: See README.md files in each directory
- **Issues**: https://github.com/LocustSocial/LocustSocial/issues
- **Discussions**: https://github.com/LocustSocial/LocustSocial/discussions

---

**Last Updated**: February 7, 2026  
**Version**: 1.0.0  
**Authors**: LocustSocial Development Team
