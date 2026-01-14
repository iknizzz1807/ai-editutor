// repository/user_repository.go - User repository

package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"myapp/models"
)

type UserRepository struct {
	db *gorm.DB
}

func NewUserRepository(db *gorm.DB) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) Create(ctx context.Context, user *models.User) error {
	return r.db.WithContext(ctx).Create(user).Error
}

func (r *UserRepository) GetByID(ctx context.Context, id uuid.UUID) (*models.User, error) {
	var user models.User
	err := r.db.WithContext(ctx).
		Preload("Profile").
		Preload("Preferences").
		First(&user, "id = ?", id).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) GetByEmail(ctx context.Context, email string) (*models.User, error) {
	var user models.User
	err := r.db.WithContext(ctx).
		Preload("Profile").
		Where("email = ?", email).
		First(&user).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) GetByUsername(ctx context.Context, username string) (*models.User, error) {
	var user models.User
	err := r.db.WithContext(ctx).
		Where("username = ?", username).
		First(&user).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) Update(ctx context.Context, user *models.User) error {
	return r.db.WithContext(ctx).Save(user).Error
}

func (r *UserRepository) Delete(ctx context.Context, id uuid.UUID) error {
	return r.db.WithContext(ctx).Delete(&models.User{}, "id = ?", id).Error
}

// Q: How can we implement efficient cursor-based pagination for large datasets?
func (r *UserRepository) List(ctx context.Context, opts ListOptions) ([]models.User, int64, error) {
	var users []models.User
	var total int64

	query := r.db.WithContext(ctx).Model(&models.User{})

	// Apply filters
	if opts.Role != "" {
		query = query.Where("role = ?", opts.Role)
	}
	if opts.Status != "" {
		query = query.Where("status = ?", opts.Status)
	}
	if opts.Search != "" {
		search := "%" + opts.Search + "%"
		query = query.Where("email LIKE ? OR username LIKE ?", search, search)
	}

	// Get total count
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	// Apply pagination
	offset := (opts.Page - 1) * opts.PageSize
	err := query.
		Preload("Profile").
		Offset(offset).
		Limit(opts.PageSize).
		Order("created_at DESC").
		Find(&users).Error

	return users, total, err
}

func (r *UserRepository) Search(ctx context.Context, query string, limit int) ([]models.User, error) {
	var users []models.User
	search := "%" + query + "%"

	err := r.db.WithContext(ctx).
		Joins("LEFT JOIN user_profiles ON user_profiles.user_id = users.id").
		Where("users.email LIKE ? OR users.username LIKE ? OR user_profiles.first_name LIKE ? OR user_profiles.last_name LIKE ?",
			search, search, search, search).
		Limit(limit).
		Find(&users).Error

	return users, err
}

func (r *UserRepository) GetByRole(ctx context.Context, role models.UserRole) ([]models.User, error) {
	var users []models.User
	err := r.db.WithContext(ctx).
		Where("role = ?", role).
		Find(&users).Error
	return users, err
}

func (r *UserRepository) GetActiveUsers(ctx context.Context) ([]models.User, error) {
	var users []models.User
	err := r.db.WithContext(ctx).
		Where("status = ? AND deleted_at IS NULL", models.StatusActive).
		Find(&users).Error
	return users, err
}

func (r *UserRepository) GetRecentlyActive(ctx context.Context, days int) ([]models.User, error) {
	var users []models.User
	cutoff := time.Now().AddDate(0, 0, -days)

	err := r.db.WithContext(ctx).
		Where("last_login_at >= ?", cutoff).
		Find(&users).Error

	return users, err
}

func (r *UserRepository) GetInactiveUsers(ctx context.Context, days int) ([]models.User, error) {
	var users []models.User
	cutoff := time.Now().AddDate(0, 0, -days)

	err := r.db.WithContext(ctx).
		Where("last_login_at < ? OR last_login_at IS NULL", cutoff).
		Find(&users).Error

	return users, err
}

func (r *UserRepository) UpdateLastLogin(ctx context.Context, userID uuid.UUID, ip string) error {
	now := time.Now()
	return r.db.WithContext(ctx).
		Model(&models.User{}).
		Where("id = ?", userID).
		Updates(map[string]interface{}{
			"last_login_at": now,
			"last_login_ip": ip,
		}).Error
}

func (r *UserRepository) BulkUpdateStatus(ctx context.Context, userIDs []uuid.UUID, status models.UserStatus) (int64, error) {
	result := r.db.WithContext(ctx).
		Model(&models.User{}).
		Where("id IN ?", userIDs).
		Update("status", status)

	return result.RowsAffected, result.Error
}

func (r *UserRepository) GetStats(ctx context.Context) (*UserStats, error) {
	var stats UserStats

	// Total users
	r.db.WithContext(ctx).Model(&models.User{}).Count(&stats.Total)

	// Active users
	r.db.WithContext(ctx).Model(&models.User{}).Where("status = ?", models.StatusActive).Count(&stats.Active)

	// Verified users
	r.db.WithContext(ctx).Model(&models.User{}).Where("email_verified = ?", true).Count(&stats.Verified)

	// New this month
	monthAgo := time.Now().AddDate(0, -1, 0)
	r.db.WithContext(ctx).Model(&models.User{}).Where("created_at >= ?", monthAgo).Count(&stats.NewThisMonth)

	// By role
	stats.ByRole = make(map[string]int64)
	var roleStats []struct {
		Role  string
		Count int64
	}
	r.db.WithContext(ctx).Model(&models.User{}).Select("role, count(*) as count").Group("role").Scan(&roleStats)
	for _, rs := range roleStats {
		stats.ByRole[rs.Role] = rs.Count
	}

	return &stats, nil
}

type ListOptions struct {
	Page     int
	PageSize int
	Role     string
	Status   string
	Search   string
}

type UserStats struct {
	Total        int64
	Active       int64
	Verified     int64
	NewThisMonth int64
	ByRole       map[string]int64
}
