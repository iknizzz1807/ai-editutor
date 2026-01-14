// Package services contains business logic
package services

import (
	"errors"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"myapp/internal/models"
)

var (
	ErrEmailExists = errors.New("email already exists")
)

// UserService handles user operations
type UserService struct {
	db          *gorm.DB
	authService *AuthService
}

// NewUserService creates a new user service
func NewUserService(db *gorm.DB, authService *AuthService) *UserService {
	return &UserService{
		db:          db,
		authService: authService,
	}
}

// PaginatedResult represents a paginated list result
type PaginatedResult struct {
	Data  []models.User `json:"data"`
	Total int64         `json:"total"`
	Page  int           `json:"page"`
	Limit int           `json:"limit"`
}

// List returns a paginated list of users
func (s *UserService) List(filters models.UserFilters) (*PaginatedResult, error) {
	var users []models.User
	var total int64

	query := s.db.Model(&models.User{})

	// Apply filters
	if filters.Role != nil {
		query = query.Where("role = ?", *filters.Role)
	}

	if filters.Search != nil && *filters.Search != "" {
		searchTerm := "%" + *filters.Search + "%"
		query = query.Where("name ILIKE ? OR email ILIKE ?", searchTerm, searchTerm)
	}

	// Count total
	if err := query.Count(&total).Error; err != nil {
		return nil, err
	}

	// Apply pagination
	offset := (filters.Page - 1) * filters.Limit
	if err := query.Offset(offset).Limit(filters.Limit).Find(&users).Error; err != nil {
		return nil, err
	}

	return &PaginatedResult{
		Data:  users,
		Total: total,
		Page:  filters.Page,
		Limit: filters.Limit,
	}, nil
}

// GetByID retrieves a user by ID
func (s *UserService) GetByID(id string) (*models.User, error) {
	var user models.User
	if err := s.db.First(&user, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrUserNotFound
		}
		return nil, err
	}
	return &user, nil
}

// GetByEmail retrieves a user by email
func (s *UserService) GetByEmail(email string) (*models.User, error) {
	var user models.User
	if err := s.db.Where("email = ?", email).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &user, nil
}

// Create creates a new user
func (s *UserService) Create(input models.CreateUserInput) (*models.User, error) {
	// Check if email exists
	existing, err := s.GetByEmail(input.Email)
	if err != nil {
		return nil, err
	}
	if existing != nil {
		return nil, ErrEmailExists
	}

	// Hash password
	hashedPassword, err := s.authService.HashPassword(input.Password)
	if err != nil {
		return nil, err
	}

	// Set default role
	role := input.Role
	if role == "" {
		role = models.RoleUser
	}

	user := &models.User{
		ID:             uuid.New().String(),
		Email:          input.Email,
		Name:           input.Name,
		HashedPassword: hashedPassword,
		Role:           role,
	}

	if err := s.db.Create(user).Error; err != nil {
		return nil, err
	}

	return user, nil
}

// Update updates an existing user
func (s *UserService) Update(id string, input models.UpdateUserInput) (*models.User, error) {
	user, err := s.GetByID(id)
	if err != nil {
		return nil, err
	}

	// Check email uniqueness if changing
	if input.Email != nil && *input.Email != user.Email {
		existing, err := s.GetByEmail(*input.Email)
		if err != nil {
			return nil, err
		}
		if existing != nil {
			return nil, ErrEmailExists
		}
		user.Email = *input.Email
	}

	if input.Name != nil {
		user.Name = *input.Name
	}

	if input.Role != nil {
		user.Role = *input.Role
	}

	if err := s.db.Save(user).Error; err != nil {
		return nil, err
	}

	return user, nil
}

// Delete soft-deletes a user
func (s *UserService) Delete(id string) error {
	result := s.db.Delete(&models.User{}, "id = ?", id)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return ErrUserNotFound
	}
	return nil
}
