# Snapshot: Go Gin Repository

This document shows what gets sent to the LLM when a user asks a question in a Go repository file using GORM.

## Input

### Source File
- **Path:** `tests/fixtures/go-gin/repository/user_repository.go`
- **Filetype:** `go`
- **Total lines:** 223

### Question Location
- **Line number:** 70
- **Q: Comment:** `// Q: How can we implement efficient cursor-based pagination for large datasets?`

### Related Files (same project)
```
go-gin/
├── repository/
│   └── user_repository.go  <- THIS FILE
├── service/
│   └── user_service.go     <- uses this repository
├── handler/
│   └── user_handler.go     <- uses service
├── models/
│   └── user.go             <- imported
└── middleware/
    └── auth.go
```

## Context Extraction

### Imports Detected
```go
import (
    "context"
    "time"

    "github.com/google/uuid"
    "gorm.io/gorm"

    "myapp/models"
)
```

### Code Context (±50 lines around question)
The `>>>` marker shows where the question line is located:

```go
     15: type UserRepository struct {
     16:     db *gorm.DB
     17: }
     18:
     19: func NewUserRepository(db *gorm.DB) *UserRepository {
     20:     return &UserRepository{db: db}
     21: }
     22:
     23: func (r *UserRepository) Create(ctx context.Context, user *models.User) error {
     24:     return r.db.WithContext(ctx).Create(user).Error
     25: }
     26:
     27: func (r *UserRepository) GetByID(ctx context.Context, id uuid.UUID) (*models.User, error) {
     28:     var user models.User
     29:     err := r.db.WithContext(ctx).
     30:         Preload("Profile").
     31:         Preload("Preferences").
     32:         First(&user, "id = ?", id).Error
     33:     if err != nil {
     34:         return nil, err
     35:     }
     36:     return &user, nil
     37: }
     ...
     62: func (r *UserRepository) Update(ctx context.Context, user *models.User) error {
     63:     return r.db.WithContext(ctx).Save(user).Error
     64: }
     65:
     66: func (r *UserRepository) Delete(ctx context.Context, id uuid.UUID) error {
     67:     return r.db.WithContext(ctx).Delete(&models.User{}, "id = ?", id).Error
     68: }
     69:
>>>  70: // Q: How can we implement efficient cursor-based pagination for large datasets?
     71: func (r *UserRepository) List(ctx context.Context, opts ListOptions) ([]models.User, int64, error) {
     72:     var users []models.User
     73:     var total int64
     74:
     75:     query := r.db.WithContext(ctx).Model(&models.User{})
     76:
     77:     // Apply filters
     78:     if opts.Role != "" {
     79:         query = query.Where("role = ?", opts.Role)
     80:     }
     81:     if opts.Status != "" {
     82:         query = query.Where("status = ?", opts.Status)
     83:     }
     84:     if opts.Search != "" {
     85:         search := "%" + opts.Search + "%"
     86:         query = query.Where("email LIKE ? OR username LIKE ?", search, search)
     87:     }
     88:
     89:     // Get total count
     90:     if err := query.Count(&total).Error; err != nil {
     91:         return nil, 0, err
     92:     }
     93:
     94:     // Apply pagination
     95:     offset := (opts.Page - 1) * opts.PageSize
     96:     err := query.
     97:         Preload("Profile").
     98:         Offset(offset).
     99:         Limit(opts.PageSize).
    100:         Order("created_at DESC").
    101:         Find(&users).Error
    102:
    103:     return users, total, err
    104: }
```

## LLM Payload

### System Prompt

```
You are an expert coding mentor helping a developer learn and understand code.

Your role is to TEACH, not to do the work for them.

CRITICAL: Your response will be inserted as an INLINE COMMENT directly in the code file.
Keep responses CONCISE and well-structured. Avoid excessive length.

CORE PRINCIPLES:
1. EXPLAIN concepts clearly, don't just give solutions
2. Reference the actual code context provided
3. Always respond in English
4. Be concise - this will appear as code comments
5. Use plain text, avoid emoji headers

RESPONSE GUIDELINES:
- Keep explanations focused and to the point
- Include 1-2 short code examples when helpful
- Mention best practices briefly
- Warn about common mistakes in 1-2 sentences
- Suggest what to learn next in one line

DO NOT:
- Use emoji headers (no 📚, 💡, ✅, etc.)
- Write overly long responses
- Repeat information unnecessarily

QUESTION mode - Give direct, educational answer.

Structure:
1. Direct answer first (clear and concise)
2. Brief explanation of why/how
3. One code example if helpful
4. One common mistake to avoid
5. One thing to learn next
```

### User Prompt

```
Mode: Q

Context:
Language: go
File: user_repository.go

Code context (>>> marks the question line):
​```go
     15: type UserRepository struct {
     16:     db *gorm.DB
     17: }
     ...
     62: func (r *UserRepository) Update(ctx context.Context, user *models.User) error {
     63:     return r.db.WithContext(ctx).Save(user).Error
     64: }
     ...
>>>  70: // Q: How can we implement efficient cursor-based pagination for large datasets?
     71: func (r *UserRepository) List(ctx context.Context, opts ListOptions) ([]models.User, int64, error) {
     72:     var users []models.User
     ...
     94:     // Apply pagination
     95:     offset := (opts.Page - 1) * opts.PageSize
     96:     err := query.
     97:         Preload("Profile").
     98:         Offset(offset).
     99:         Limit(opts.PageSize).
    100:         Order("created_at DESC").
    101:         Find(&users).Error
​```

Question:
How can we implement efficient cursor-based pagination for large datasets?
```

## Expected Response Location

The AI response will be inserted as a block comment directly after line 70:

```go
// Q: How can we implement efficient cursor-based pagination for large datasets?

/*
A:
Current implementation uses OFFSET pagination which is inefficient for large datasets
because DB must scan and skip all previous rows.

Cursor-based pagination uses a WHERE clause with the last seen value:

type CursorOptions struct {
    Cursor    time.Time  // last created_at seen
    PageSize  int
}

func (r *UserRepository) ListCursor(ctx context.Context, opts CursorOptions) ([]models.User, error) {
    return r.db.WithContext(ctx).
        Where("created_at < ?", opts.Cursor).
        Order("created_at DESC").
        Limit(opts.PageSize).
        Find(&users).Error
}

Benefits: O(1) instead of O(n) for page access.

Common mistake: Using non-unique columns as cursor (use created_at + id for ties).

Learn next: Keyset pagination patterns and composite cursors.
*/
func (r *UserRepository) List(ctx context.Context, opts ListOptions) ([]models.User, int64, error) {
```
