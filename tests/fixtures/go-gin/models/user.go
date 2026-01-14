// models/user.go - User models

package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type UserRole string

const (
	RoleAdmin     UserRole = "admin"
	RoleModerator UserRole = "moderator"
	RoleUser      UserRole = "user"
	RoleGuest     UserRole = "guest"
)

type UserStatus string

const (
	StatusActive    UserStatus = "active"
	StatusInactive  UserStatus = "inactive"
	StatusSuspended UserStatus = "suspended"
	StatusPending   UserStatus = "pending"
)

type User struct {
	ID            uuid.UUID  `gorm:"type:uuid;primary_key" json:"id"`
	Email         string     `gorm:"uniqueIndex;not null" json:"email"`
	Username      string     `gorm:"uniqueIndex;not null" json:"username"`
	PasswordHash  string     `gorm:"not null" json:"-"`
	Role          UserRole   `gorm:"default:user" json:"role"`
	Status        UserStatus `gorm:"default:pending" json:"status"`
	EmailVerified bool       `gorm:"default:false" json:"email_verified"`
	LastLoginAt   *time.Time `json:"last_login_at,omitempty"`
	LastLoginIP   string     `json:"last_login_ip,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Profile     *UserProfile     `gorm:"foreignKey:UserID" json:"profile,omitempty"`
	Preferences *UserPreferences `gorm:"foreignKey:UserID" json:"preferences,omitempty"`
	Addresses   []UserAddress    `gorm:"foreignKey:UserID" json:"addresses,omitempty"`
}

func (u *User) BeforeCreate(tx *gorm.DB) error {
	if u.ID == uuid.Nil {
		u.ID = uuid.New()
	}
	return nil
}

func (u *User) GetFullName() string {
	if u.Profile != nil {
		name := u.Profile.FirstName + " " + u.Profile.LastName
		if len(name) > 1 {
			return name
		}
	}
	return u.Username
}

type UserProfile struct {
	ID          uuid.UUID  `gorm:"type:uuid;primary_key" json:"id"`
	UserID      uuid.UUID  `gorm:"type:uuid;uniqueIndex" json:"user_id"`
	FirstName   string     `gorm:"size:50" json:"first_name"`
	LastName    string     `gorm:"size:50" json:"last_name"`
	Avatar      string     `json:"avatar,omitempty"`
	Bio         string     `gorm:"size:500" json:"bio,omitempty"`
	Phone       string     `gorm:"size:20" json:"phone,omitempty"`
	DateOfBirth *time.Time `json:"date_of_birth,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

func (p *UserProfile) BeforeCreate(tx *gorm.DB) error {
	if p.ID == uuid.Nil {
		p.ID = uuid.New()
	}
	return nil
}

type UserAddress struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key" json:"id"`
	UserID    uuid.UUID `gorm:"type:uuid;index" json:"user_id"`
	Label     string    `gorm:"size:50" json:"label"`
	Street    string    `gorm:"size:200" json:"street"`
	City      string    `gorm:"size:100" json:"city"`
	State     string    `gorm:"size:100" json:"state"`
	Country   string    `gorm:"size:100" json:"country"`
	ZipCode   string    `gorm:"size:20" json:"zip_code"`
	IsDefault bool      `gorm:"default:false" json:"is_default"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (a *UserAddress) BeforeCreate(tx *gorm.DB) error {
	if a.ID == uuid.Nil {
		a.ID = uuid.New()
	}
	return nil
}

type UserPreferences struct {
	ID                 uuid.UUID `gorm:"type:uuid;primary_key" json:"id"`
	UserID             uuid.UUID `gorm:"type:uuid;uniqueIndex" json:"user_id"`
	Theme              string    `gorm:"default:system" json:"theme"`
	Language           string    `gorm:"default:en" json:"language"`
	Timezone           string    `gorm:"default:UTC" json:"timezone"`
	EmailNotifications bool      `gorm:"default:true" json:"email_notifications"`
	PushNotifications  bool      `gorm:"default:true" json:"push_notifications"`
	SMSNotifications   bool      `gorm:"default:false" json:"sms_notifications"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

func (p *UserPreferences) BeforeCreate(tx *gorm.DB) error {
	if p.ID == uuid.Nil {
		p.ID = uuid.New()
	}
	return nil
}
