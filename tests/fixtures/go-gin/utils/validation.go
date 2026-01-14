// utils/validation.go - Input validation utilities

package utils

import (
	"regexp"
	"strings"
	"unicode"
)

var (
	emailRegex    = regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)
	usernameRegex = regexp.MustCompile(`^[a-zA-Z][a-zA-Z0-9_-]*$`)
	phoneRegex    = regexp.MustCompile(`^\+?[0-9]{10,15}$`)
	slugRegex     = regexp.MustCompile(`^[a-z0-9]+(?:-[a-z0-9]+)*$`)
)

type ValidationErrors map[string][]string

func (v ValidationErrors) Add(field, message string) {
	v[field] = append(v[field], message)
}

func (v ValidationErrors) HasErrors() bool {
	return len(v) > 0
}

func ValidateEmail(email string) []string {
	var errors []string

	if email == "" {
		errors = append(errors, "email is required")
		return errors
	}

	if !emailRegex.MatchString(email) {
		errors = append(errors, "invalid email format")
	}

	return errors
}

func ValidateUsername(username string) []string {
	var errors []string

	if username == "" {
		errors = append(errors, "username is required")
		return errors
	}

	if len(username) < 3 {
		errors = append(errors, "username must be at least 3 characters")
	}

	if len(username) > 30 {
		errors = append(errors, "username must be at most 30 characters")
	}

	if !usernameRegex.MatchString(username) {
		errors = append(errors, "username must start with a letter and contain only letters, numbers, underscores, and hyphens")
	}

	reservedUsernames := []string{"admin", "root", "system", "api", "www", "mail", "support"}
	lowercaseUsername := strings.ToLower(username)
	for _, reserved := range reservedUsernames {
		if lowercaseUsername == reserved {
			errors = append(errors, "this username is reserved")
			break
		}
	}

	return errors
}

// Q: Should we implement password strength scoring for better user feedback?
func ValidatePassword(password string) []string {
	var errors []string

	if password == "" {
		errors = append(errors, "password is required")
		return errors
	}

	if len(password) < 8 {
		errors = append(errors, "password must be at least 8 characters")
	}

	hasUpper := false
	hasLower := false
	hasDigit := false
	hasSpecial := false

	for _, char := range password {
		switch {
		case unicode.IsUpper(char):
			hasUpper = true
		case unicode.IsLower(char):
			hasLower = true
		case unicode.IsDigit(char):
			hasDigit = true
		case unicode.IsPunct(char) || unicode.IsSymbol(char):
			hasSpecial = true
		}
	}

	if !hasUpper {
		errors = append(errors, "password must contain at least one uppercase letter")
	}

	if !hasLower {
		errors = append(errors, "password must contain at least one lowercase letter")
	}

	if !hasDigit {
		errors = append(errors, "password must contain at least one digit")
	}

	if !hasSpecial {
		errors = append(errors, "password must contain at least one special character")
	}

	// Check common passwords
	commonPasswords := []string{"password", "123456", "qwerty", "letmein", "welcome"}
	lowercasePassword := strings.ToLower(password)
	for _, common := range commonPasswords {
		if lowercasePassword == common {
			errors = append(errors, "this password is too common")
			break
		}
	}

	return errors
}

func ValidatePhone(phone string) []string {
	var errors []string

	if phone == "" {
		return errors // Phone is optional
	}

	// Remove common formatting characters
	cleaned := regexp.MustCompile(`[\s\-\(\)\.]`).ReplaceAllString(phone, "")

	if !phoneRegex.MatchString(cleaned) {
		errors = append(errors, "invalid phone number format")
	}

	return errors
}

func ValidateSlug(slug string) []string {
	var errors []string

	if slug == "" {
		errors = append(errors, "slug is required")
		return errors
	}

	if !slugRegex.MatchString(slug) {
		errors = append(errors, "slug must contain only lowercase letters, numbers, and hyphens")
	}

	return errors
}

type PasswordStrength int

const (
	PasswordWeak PasswordStrength = iota
	PasswordFair
	PasswordStrong
	PasswordVeryStrong
)

func GetPasswordStrength(password string) PasswordStrength {
	score := 0

	if len(password) >= 8 {
		score++
	}
	if len(password) >= 12 {
		score++
	}
	if len(password) >= 16 {
		score++
	}

	hasUpper := false
	hasLower := false
	hasDigit := false
	hasSpecial := false

	for _, char := range password {
		switch {
		case unicode.IsUpper(char):
			hasUpper = true
		case unicode.IsLower(char):
			hasLower = true
		case unicode.IsDigit(char):
			hasDigit = true
		case unicode.IsPunct(char) || unicode.IsSymbol(char):
			hasSpecial = true
		}
	}

	if hasUpper {
		score++
	}
	if hasLower {
		score++
	}
	if hasDigit {
		score++
	}
	if hasSpecial {
		score += 2
	}

	switch {
	case score >= 8:
		return PasswordVeryStrong
	case score >= 6:
		return PasswordStrong
	case score >= 4:
		return PasswordFair
	default:
		return PasswordWeak
	}
}

func (s PasswordStrength) String() string {
	switch s {
	case PasswordVeryStrong:
		return "very strong"
	case PasswordStrong:
		return "strong"
	case PasswordFair:
		return "fair"
	default:
		return "weak"
	}
}
