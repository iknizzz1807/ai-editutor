// service/email_service.go - Email service

package service

import (
	"fmt"
	"html/template"
	"strings"

	"myapp/config"
	"myapp/models"
)

type EmailService struct {
	config   *config.Config
	fromEmail string
	siteName  string
	baseURL   string
}

func NewEmailService(cfg *config.Config) *EmailService {
	return &EmailService{
		config:    cfg,
		fromEmail: cfg.Email.FromAddress,
		siteName:  cfg.App.Name,
		baseURL:   cfg.App.BaseURL,
	}
}

func (s *EmailService) SendVerificationEmail(user *models.User) error {
	token := s.generateVerificationToken(user)
	verificationURL := fmt.Sprintf("%s/verify-email?token=%s", s.baseURL, token)

	subject := fmt.Sprintf("Verify your email for %s", s.siteName)
	body := s.renderTemplate("verify_email", map[string]interface{}{
		"User":           user,
		"VerificationURL": verificationURL,
		"SiteName":       s.siteName,
	})

	return s.sendEmail(user.Email, subject, body)
}

func (s *EmailService) SendPasswordResetEmail(user *models.User, token string) error {
	resetURL := fmt.Sprintf("%s/reset-password?token=%s", s.baseURL, token)

	subject := fmt.Sprintf("Reset your password for %s", s.siteName)
	body := s.renderTemplate("password_reset", map[string]interface{}{
		"User":      user,
		"ResetURL":  resetURL,
		"SiteName":  s.siteName,
		"ExpiresIn": "24 hours",
	})

	return s.sendEmail(user.Email, subject, body)
}

func (s *EmailService) SendWelcomeEmail(user *models.User) error {
	subject := fmt.Sprintf("Welcome to %s!", s.siteName)
	body := s.renderTemplate("welcome", map[string]interface{}{
		"User":     user,
		"SiteName": s.siteName,
		"LoginURL": fmt.Sprintf("%s/login", s.baseURL),
	})

	return s.sendEmail(user.Email, subject, body)
}

func (s *EmailService) SendSuspensionNotice(user *models.User, reason string, durationDays int) error {
	subject := fmt.Sprintf("Your %s account has been suspended", s.siteName)
	body := s.renderTemplate("suspension_notice", map[string]interface{}{
		"User":         user,
		"Reason":       reason,
		"DurationDays": durationDays,
		"SiteName":     s.siteName,
		"SupportEmail": s.config.Email.SupportAddress,
	})

	return s.sendEmail(user.Email, subject, body)
}

// Q: What's the best approach for handling email delivery failures and retries in Go?
func (s *EmailService) SendBulkEmail(users []*models.User, subject string, templateName string, extraData map[string]interface{}) (*BulkEmailResult, error) {
	result := &BulkEmailResult{
		Sent:   0,
		Failed: 0,
		Errors: make([]BulkEmailError, 0),
	}

	for _, user := range users {
		data := map[string]interface{}{
			"User":     user,
			"SiteName": s.siteName,
		}
		for k, v := range extraData {
			data[k] = v
		}

		body := s.renderTemplate(templateName, data)
		err := s.sendEmail(user.Email, subject, body)

		if err != nil {
			result.Failed++
			result.Errors = append(result.Errors, BulkEmailError{
				Email: user.Email,
				Error: err.Error(),
			})
		} else {
			result.Sent++
		}
	}

	return result, nil
}

func (s *EmailService) SendNotificationEmail(user *models.User, notificationType string, data map[string]interface{}) error {
	templates := map[string]string{
		"new_login":        "new_login",
		"password_changed": "password_changed",
		"profile_updated":  "profile_updated",
		"security_alert":   "security_alert",
	}

	templateName, ok := templates[notificationType]
	if !ok {
		return fmt.Errorf("unknown notification type: %s", notificationType)
	}

	subjects := map[string]string{
		"new_login":        fmt.Sprintf("New login to your %s account", s.siteName),
		"password_changed": fmt.Sprintf("Your %s password was changed", s.siteName),
		"profile_updated":  fmt.Sprintf("Your %s profile was updated", s.siteName),
		"security_alert":   fmt.Sprintf("Security alert for your %s account", s.siteName),
	}

	templateData := map[string]interface{}{
		"User":     user,
		"SiteName": s.siteName,
	}
	for k, v := range data {
		templateData[k] = v
	}

	body := s.renderTemplate(templateName, templateData)
	return s.sendEmail(user.Email, subjects[notificationType], body)
}

func (s *EmailService) sendEmail(to, subject, body string) error {
	// Would implement actual email sending via SMTP or email service
	// For now, just log
	fmt.Printf("Sending email to %s: %s\n", to, subject)
	return nil
}

func (s *EmailService) renderTemplate(name string, data map[string]interface{}) string {
	// Would load and render actual templates
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Template: %s\n", name))
	for k, v := range data {
		sb.WriteString(fmt.Sprintf("%s: %v\n", k, v))
	}
	return sb.String()
}

func (s *EmailService) generateVerificationToken(user *models.User) string {
	// Would generate actual secure token
	return fmt.Sprintf("verify_%s", user.ID.String())
}

type BulkEmailResult struct {
	Sent   int
	Failed int
	Errors []BulkEmailError
}

type BulkEmailError struct {
	Email string
	Error string
}

// Template parsing helper
func parseTemplate(name, content string) (*template.Template, error) {
	return template.New(name).Parse(content)
}
