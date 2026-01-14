// src/services/user_service.rs - User business logic

use std::sync::Arc;

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use chrono::Utc;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::user::{User, UserProfile, UserPreferences, UserRole, UserStatus};
use crate::repository::user_repository::{ListOptions, UserRepository, UserStats};
use crate::services::email_service::EmailService;

pub struct UserService {
    user_repo: Arc<UserRepository>,
    email_service: Arc<EmailService>,
}

impl UserService {
    pub fn new(user_repo: Arc<UserRepository>, email_service: Arc<EmailService>) -> Self {
        Self {
            user_repo,
            email_service,
        }
    }

    pub async fn create_user(&self, input: CreateUserInput) -> Result<User, AppError> {
        // Check email uniqueness
        if self.user_repo.find_by_email(&input.email).await?.is_some() {
            return Err(AppError::Conflict("Email already registered".to_string()));
        }

        // Check username uniqueness
        if self.user_repo.find_by_username(&input.username).await?.is_some() {
            return Err(AppError::Conflict("Username already taken".to_string()));
        }

        // Hash password
        let password_hash = self.hash_password(&input.password)?;

        let user = User::new(input.email, input.username, password_hash);
        let user = self.user_repo.create(&user).await?;

        // Send verification email
        if input.send_verification {
            self.email_service.send_verification_email(&user).await?;
        }

        Ok(user)
    }

    pub async fn get_user(&self, id: Uuid) -> Result<User, AppError> {
        self.user_repo
            .find_by_id(id)
            .await?
            .ok_or_else(|| AppError::NotFound("User not found".to_string()))
    }

    pub async fn get_user_by_email(&self, email: &str) -> Result<Option<User>, AppError> {
        self.user_repo.find_by_email(email).await
    }

    // Q: What's the best pattern for handling partial updates with optional fields in Rust?
    pub async fn update_user(&self, id: Uuid, input: UpdateUserInput) -> Result<User, AppError> {
        let mut user = self.get_user(id).await?;

        if let Some(username) = input.username {
            if username != user.username {
                if self.user_repo.find_by_username(&username).await?.is_some() {
                    return Err(AppError::Conflict("Username already taken".to_string()));
                }
                user.username = username;
            }
        }

        if let Some(role) = input.role {
            user.role = role;
        }

        if let Some(status) = input.status {
            user.status = status;
        }

        user.updated_at = Utc::now();
        self.user_repo.update(&user).await
    }

    pub async fn activate_user(&self, id: Uuid) -> Result<User, AppError> {
        let mut user = self.get_user(id).await?;
        user.status = UserStatus::Active;
        user.email_verified = true;
        self.user_repo.update(&user).await
    }

    pub async fn suspend_user(&self, id: Uuid, reason: &str, duration_days: Option<i32>) -> Result<User, AppError> {
        let mut user = self.get_user(id).await?;
        user.status = UserStatus::Suspended;
        let user = self.user_repo.update(&user).await?;

        self.email_service
            .send_suspension_notice(&user, reason, duration_days)
            .await?;

        Ok(user)
    }

    pub async fn delete_user(&self, id: Uuid) -> Result<(), AppError> {
        self.user_repo.delete(id).await
    }

    pub async fn list_users(&self, opts: ListOptions) -> Result<(Vec<User>, i64), AppError> {
        self.user_repo.list(opts).await
    }

    pub async fn search_users(&self, query: &str, limit: i32) -> Result<Vec<User>, AppError> {
        self.user_repo.search(query, limit).await
    }

    pub async fn change_password(
        &self,
        user_id: Uuid,
        current_password: &str,
        new_password: &str,
    ) -> Result<(), AppError> {
        let mut user = self.get_user(user_id).await?;

        // Verify current password
        if !self.verify_password(current_password, &user.password_hash)? {
            return Err(AppError::Unauthorized("Invalid password".to_string()));
        }

        // Hash new password
        user.password_hash = self.hash_password(new_password)?;
        self.user_repo.update(&user).await?;

        Ok(())
    }

    pub async fn authenticate(&self, email: &str, password: &str) -> Result<User, AppError> {
        let user = self
            .user_repo
            .find_by_email(email)
            .await?
            .ok_or_else(|| AppError::Unauthorized("Invalid credentials".to_string()))?;

        if !self.verify_password(password, &user.password_hash)? {
            return Err(AppError::Unauthorized("Invalid credentials".to_string()));
        }

        if user.status == UserStatus::Suspended {
            return Err(AppError::Forbidden("Account suspended".to_string()));
        }

        Ok(user)
    }

    pub async fn update_last_login(&self, user_id: Uuid, ip: Option<&str>) -> Result<(), AppError> {
        self.user_repo.update_last_login(user_id, ip).await
    }

    pub async fn get_stats(&self) -> Result<UserStats, AppError> {
        self.user_repo.get_stats().await
    }

    fn hash_password(&self, password: &str) -> Result<String, AppError> {
        let salt = SaltString::generate(&mut OsRng);
        let argon2 = Argon2::default();
        let hash = argon2
            .hash_password(password.as_bytes(), &salt)
            .map_err(|e| AppError::Internal(format!("Password hashing error: {}", e)))?;
        Ok(hash.to_string())
    }

    fn verify_password(&self, password: &str, hash: &str) -> Result<bool, AppError> {
        let parsed_hash = PasswordHash::new(hash)
            .map_err(|e| AppError::Internal(format!("Invalid password hash: {}", e)))?;
        Ok(Argon2::default()
            .verify_password(password.as_bytes(), &parsed_hash)
            .is_ok())
    }
}

#[derive(Debug)]
pub struct CreateUserInput {
    pub email: String,
    pub username: String,
    pub password: String,
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub send_verification: bool,
}

#[derive(Debug, Default)]
pub struct UpdateUserInput {
    pub username: Option<String>,
    pub role: Option<UserRole>,
    pub status: Option<UserStatus>,
}

#[derive(Debug)]
pub struct UpdateProfileInput {
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub bio: Option<String>,
    pub phone: Option<String>,
}
