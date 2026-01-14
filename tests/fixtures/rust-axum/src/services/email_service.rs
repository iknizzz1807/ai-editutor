// src/services/email_service.rs - Email service

use std::sync::Arc;

use crate::config::Config;
use crate::error::AppError;
use crate::models::user::User;

pub struct EmailService {
    config: Arc<Config>,
}

impl EmailService {
    pub fn new(config: Arc<Config>) -> Self {
        Self { config }
    }

    pub async fn send_verification_email(&self, user: &User) -> Result<(), AppError> {
        let token = self.generate_verification_token(user);
        let verification_url = format!("{}/verify-email?token={}", self.config.app.base_url, token);

        let subject = format!("Verify your email for {}", self.config.app.name);
        let body = format!(
            "Hello {},\n\nPlease verify your email by clicking: {}\n\nThanks,\n{}",
            user.username, verification_url, self.config.app.name
        );

        self.send_email(&user.email, &subject, &body).await
    }

    pub async fn send_password_reset_email(&self, user: &User, token: &str) -> Result<(), AppError> {
        let reset_url = format!("{}/reset-password?token={}", self.config.app.base_url, token);

        let subject = format!("Reset your password for {}", self.config.app.name);
        let body = format!(
            "Hello {},\n\nReset your password by clicking: {}\n\nThis link expires in 24 hours.\n\nThanks,\n{}",
            user.username, reset_url, self.config.app.name
        );

        self.send_email(&user.email, &subject, &body).await
    }

    pub async fn send_welcome_email(&self, user: &User) -> Result<(), AppError> {
        let login_url = format!("{}/login", self.config.app.base_url);

        let subject = format!("Welcome to {}!", self.config.app.name);
        let body = format!(
            "Hello {},\n\nWelcome to {}! Get started at: {}\n\nThanks,\n{}",
            user.username, self.config.app.name, login_url, self.config.app.name
        );

        self.send_email(&user.email, &subject, &body).await
    }

    pub async fn send_suspension_notice(
        &self,
        user: &User,
        reason: &str,
        duration_days: Option<i32>,
    ) -> Result<(), AppError> {
        let duration_text = match duration_days {
            Some(days) => format!("{} days", days),
            None => "indefinitely".to_string(),
        };

        let subject = format!("Your {} account has been suspended", self.config.app.name);
        let body = format!(
            "Hello {},\n\nYour account has been suspended for {}.\n\nReason: {}\n\nContact {} for support.\n\nThanks,\n{}",
            user.username, duration_text, reason, self.config.email.support_address, self.config.app.name
        );

        self.send_email(&user.email, &subject, &body).await
    }

    // Q: How should we implement retry logic for failed email deliveries?
    pub async fn send_bulk_email(
        &self,
        users: &[User],
        subject: &str,
        template: &str,
    ) -> Result<BulkEmailResult, AppError> {
        let mut result = BulkEmailResult::default();

        for user in users {
            let body = self.render_template(template, user);
            match self.send_email(&user.email, subject, &body).await {
                Ok(_) => result.sent += 1,
                Err(e) => {
                    result.failed += 1;
                    result.errors.push(BulkEmailError {
                        email: user.email.clone(),
                        error: e.to_string(),
                    });
                }
            }
        }

        Ok(result)
    }

    pub async fn send_notification_email(
        &self,
        user: &User,
        notification_type: NotificationType,
        data: &NotificationData,
    ) -> Result<(), AppError> {
        let (subject, body) = match notification_type {
            NotificationType::NewLogin => {
                let subject = format!("New login to your {} account", self.config.app.name);
                let body = format!(
                    "Hello {},\n\nA new login was detected from IP: {}\n\nIf this wasn't you, please secure your account.",
                    user.username,
                    data.ip_address.as_deref().unwrap_or("Unknown")
                );
                (subject, body)
            }
            NotificationType::PasswordChanged => {
                let subject = format!("Your {} password was changed", self.config.app.name);
                let body = format!(
                    "Hello {},\n\nYour password was recently changed.\n\nIf this wasn't you, please contact support.",
                    user.username
                );
                (subject, body)
            }
            NotificationType::SecurityAlert => {
                let subject = format!("Security alert for your {} account", self.config.app.name);
                let body = format!(
                    "Hello {},\n\nWe detected suspicious activity on your account.\n\n{}",
                    user.username,
                    data.message.as_deref().unwrap_or("")
                );
                (subject, body)
            }
        };

        self.send_email(&user.email, &subject, &body).await
    }

    async fn send_email(&self, to: &str, subject: &str, body: &str) -> Result<(), AppError> {
        // Would implement actual email sending via SMTP or email service
        tracing::info!("Sending email to {}: {}", to, subject);
        Ok(())
    }

    fn render_template(&self, template: &str, user: &User) -> String {
        // Simple template rendering - would use a proper template engine
        template
            .replace("{{username}}", &user.username)
            .replace("{{email}}", &user.email)
            .replace("{{site_name}}", &self.config.app.name)
    }

    fn generate_verification_token(&self, user: &User) -> String {
        // Would generate actual secure token
        format!("verify_{}", user.id)
    }
}

#[derive(Debug, Default)]
pub struct BulkEmailResult {
    pub sent: u32,
    pub failed: u32,
    pub errors: Vec<BulkEmailError>,
}

#[derive(Debug)]
pub struct BulkEmailError {
    pub email: String,
    pub error: String,
}

#[derive(Debug)]
pub enum NotificationType {
    NewLogin,
    PasswordChanged,
    SecurityAlert,
}

#[derive(Debug, Default)]
pub struct NotificationData {
    pub ip_address: Option<String>,
    pub message: Option<String>,
}
