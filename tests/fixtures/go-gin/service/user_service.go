// service/user_service.go - User business logic

package service

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"myapp/models"
	"myapp/repository"
)

var (
	ErrUserNotFound      = errors.New("user not found")
	ErrEmailExists       = errors.New("email already registered")
	ErrUsernameExists    = errors.New("username already taken")
	ErrInvalidPassword   = errors.New("invalid password")
	ErrUserSuspended     = errors.New("user account is suspended")
	ErrUserNotVerified   = errors.New("email not verified")
)

type UserService struct {
	userRepo     *repository.UserRepository
	emailService *EmailService
}

func NewUserService(userRepo *repository.UserRepository, emailService *EmailService) *UserService {
	return &UserService{
		userRepo:     userRepo,
		emailService: emailService,
	}
}

type CreateUserInput struct {
	Email           string
	Username        string
	Password        string
	FirstName       string
	LastName        string
	SendVerification bool
}

func (s *UserService) CreateUser(ctx context.Context, input CreateUserInput) (*models.User, error) {
	// Check email uniqueness
	existing, _ := s.userRepo.GetByEmail(ctx, input.Email)
	if existing != nil {
		return nil, ErrEmailExists
	}

	// Check username uniqueness
	existing, _ = s.userRepo.GetByUsername(ctx, input.Username)
	if existing != nil {
		return nil, ErrUsernameExists
	}

	// Hash password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(input.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}

	user := &models.User{
		Email:        input.Email,
		Username:     input.Username,
		PasswordHash: string(hashedPassword),
		Role:         models.RoleUser,
		Status:       models.StatusPending,
	}

	if err := s.userRepo.Create(ctx, user); err != nil {
		return nil, err
	}

	// Create profile
	profile := &models.UserProfile{
		UserID:    user.ID,
		FirstName: input.FirstName,
		LastName:  input.LastName,
	}
	user.Profile = profile

	// Create preferences
	preferences := &models.UserPreferences{
		UserID: user.ID,
	}
	user.Preferences = preferences

	// Send verification email
	if input.SendVerification {
		s.emailService.SendVerificationEmail(user)
	}

	return user, nil
}

func (s *UserService) GetUser(ctx context.Context, id uuid.UUID) (*models.User, error) {
	user, err := s.userRepo.GetByID(ctx, id)
	if err != nil {
		return nil, ErrUserNotFound
	}
	return user, nil
}

func (s *UserService) GetUserByEmail(ctx context.Context, email string) (*models.User, error) {
	return s.userRepo.GetByEmail(ctx, email)
}

// Q: What's the best strategy for handling partial updates with validation?
func (s *UserService) UpdateUser(ctx context.Context, id uuid.UUID, updates map[string]interface{}) (*models.User, error) {
	user, err := s.userRepo.GetByID(ctx, id)
	if err != nil {
		return nil, ErrUserNotFound
	}

	// Handle username change
	if newUsername, ok := updates["username"].(string); ok && newUsername != user.Username {
		existing, _ := s.userRepo.GetByUsername(ctx, newUsername)
		if existing != nil {
			return nil, ErrUsernameExists
		}
		user.Username = newUsername
	}

	// Handle role change
	if newRole, ok := updates["role"].(string); ok {
		user.Role = models.UserRole(newRole)
	}

	// Handle status change
	if newStatus, ok := updates["status"].(string); ok {
		user.Status = models.UserStatus(newStatus)
	}

	if err := s.userRepo.Update(ctx, user); err != nil {
		return nil, err
	}

	return user, nil
}

func (s *UserService) UpdateProfile(ctx context.Context, userID uuid.UUID, input UpdateProfileInput) (*models.UserProfile, error) {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return nil, ErrUserNotFound
	}

	profile := user.Profile
	if profile == nil {
		profile = &models.UserProfile{UserID: userID}
	}

	if input.FirstName != nil {
		profile.FirstName = *input.FirstName
	}
	if input.LastName != nil {
		profile.LastName = *input.LastName
	}
	if input.Bio != nil {
		profile.Bio = *input.Bio
	}
	if input.Phone != nil {
		profile.Phone = *input.Phone
	}

	return profile, nil
}

type UpdateProfileInput struct {
	FirstName *string
	LastName  *string
	Bio       *string
	Phone     *string
}

func (s *UserService) ActivateUser(ctx context.Context, id uuid.UUID) (*models.User, error) {
	user, err := s.userRepo.GetByID(ctx, id)
	if err != nil {
		return nil, ErrUserNotFound
	}

	user.Status = models.StatusActive
	user.EmailVerified = true

	if err := s.userRepo.Update(ctx, user); err != nil {
		return nil, err
	}

	return user, nil
}

func (s *UserService) SuspendUser(ctx context.Context, id uuid.UUID, reason string, durationDays int) (*models.User, error) {
	user, err := s.userRepo.GetByID(ctx, id)
	if err != nil {
		return nil, ErrUserNotFound
	}

	user.Status = models.StatusSuspended

	if err := s.userRepo.Update(ctx, user); err != nil {
		return nil, err
	}

	// Send notification
	s.emailService.SendSuspensionNotice(user, reason, durationDays)

	return user, nil
}

func (s *UserService) DeleteUser(ctx context.Context, id uuid.UUID) error {
	return s.userRepo.Delete(ctx, id)
}

func (s *UserService) ListUsers(ctx context.Context, opts repository.ListOptions) ([]models.User, int64, error) {
	return s.userRepo.List(ctx, opts)
}

func (s *UserService) SearchUsers(ctx context.Context, query string, limit int) ([]models.User, error) {
	return s.userRepo.Search(ctx, query, limit)
}

func (s *UserService) ChangePassword(ctx context.Context, userID uuid.UUID, currentPassword, newPassword string) error {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return ErrUserNotFound
	}

	// Verify current password
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(currentPassword)); err != nil {
		return ErrInvalidPassword
	}

	// Hash new password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	user.PasswordHash = string(hashedPassword)
	return s.userRepo.Update(ctx, user)
}

func (s *UserService) Authenticate(ctx context.Context, email, password string) (*models.User, error) {
	user, err := s.userRepo.GetByEmail(ctx, email)
	if err != nil {
		return nil, ErrInvalidPassword
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		return nil, ErrInvalidPassword
	}

	if user.Status == models.StatusSuspended {
		return nil, ErrUserSuspended
	}

	return user, nil
}

func (s *UserService) UpdateLastLogin(ctx context.Context, userID uuid.UUID, ip string) error {
	return s.userRepo.UpdateLastLogin(ctx, userID, ip)
}

func (s *UserService) GetStats(ctx context.Context) (*repository.UserStats, error) {
	return s.userRepo.GetStats(ctx)
}

func (s *UserService) CleanupUnverifiedUsers(ctx context.Context, days int) (int64, error) {
	cutoff := time.Now().AddDate(0, 0, -days)
	// Would implement cleanup logic
	_ = cutoff
	return 0, nil
}
