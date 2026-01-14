// Package models contains database models
package models

import (
	"time"

	"gorm.io/gorm"
)

// UserRole represents the role of a user
type UserRole string

const (
	RoleAdmin UserRole = "admin"
	RoleUser  UserRole = "user"
	RoleGuest UserRole = "guest"
)

// User represents a user in the system
type User struct {
	ID             string         `json:"id" gorm:"primaryKey"`
	Email          string         `json:"email" gorm:"uniqueIndex;not null"`
	Name           string         `json:"name" gorm:"not null"`
	HashedPassword string         `json:"-" gorm:"not null"`
	Role           UserRole       `json:"role" gorm:"default:user"`
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      gorm.DeletedAt `json:"-" gorm:"index"`
}

// CreateUserInput represents input for creating a user
type CreateUserInput struct {
	Email    string   `json:"email" binding:"required,email"`
	Name     string   `json:"name" binding:"required,min=2,max=100"`
	Password string   `json:"password" binding:"required,min=8"`
	Role     UserRole `json:"role"`
}

// UpdateUserInput represents input for updating a user
type UpdateUserInput struct {
	Email *string   `json:"email" binding:"omitempty,email"`
	Name  *string   `json:"name" binding:"omitempty,min=2,max=100"`
	Role  *UserRole `json:"role"`
}

// UserResponse represents the user data returned to clients
type UserResponse struct {
	ID        string    `json:"id"`
	Email     string    `json:"email"`
	Name      string    `json:"name"`
	Role      UserRole  `json:"role"`
	CreatedAt time.Time `json:"created_at"`
}

// UserFilters represents filters for listing users
type UserFilters struct {
	Role   *UserRole `form:"role"`
	Search *string   `form:"search"`
	Page   int       `form:"page,default=1"`
	Limit  int       `form:"limit,default=20"`
}
