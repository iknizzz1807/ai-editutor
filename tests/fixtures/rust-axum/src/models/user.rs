// src/models/user.rs - User models

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum UserRole {
    Admin,
    Moderator,
    User,
    Guest,
}

impl Default for UserRole {
    fn default() -> Self {
        UserRole::User
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum UserStatus {
    Active,
    Inactive,
    Suspended,
    Pending,
}

impl Default for UserStatus {
    fn default() -> Self {
        UserStatus::Pending
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct User {
    pub id: Uuid,
    pub email: String,
    pub username: String,
    #[serde(skip_serializing)]
    pub password_hash: String,
    pub role: UserRole,
    pub status: UserStatus,
    pub email_verified: bool,
    pub last_login_at: Option<DateTime<Utc>>,
    pub last_login_ip: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl User {
    pub fn new(email: String, username: String, password_hash: String) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            email,
            username,
            password_hash,
            role: UserRole::default(),
            status: UserStatus::default(),
            email_verified: false,
            last_login_at: None,
            last_login_ip: None,
            created_at: now,
            updated_at: now,
        }
    }

    pub fn get_full_name(&self, profile: Option<&UserProfile>) -> String {
        match profile {
            Some(p) if !p.first_name.is_empty() || !p.last_name.is_empty() => {
                format!("{} {}", p.first_name, p.last_name).trim().to_string()
            }
            _ => self.username.clone(),
        }
    }

    pub fn is_active(&self) -> bool {
        self.status == UserStatus::Active && self.email_verified
    }

    pub fn is_admin(&self) -> bool {
        self.role == UserRole::Admin
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct UserProfile {
    pub id: Uuid,
    pub user_id: Uuid,
    pub first_name: String,
    pub last_name: String,
    pub avatar: Option<String>,
    pub bio: Option<String>,
    pub phone: Option<String>,
    pub date_of_birth: Option<NaiveDate>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl UserProfile {
    pub fn new(user_id: Uuid) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            user_id,
            first_name: String::new(),
            last_name: String::new(),
            avatar: None,
            bio: None,
            phone: None,
            date_of_birth: None,
            created_at: now,
            updated_at: now,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct UserAddress {
    pub id: Uuid,
    pub user_id: Uuid,
    pub label: String,
    pub street: String,
    pub city: String,
    pub state: String,
    pub country: String,
    pub zip_code: String,
    pub is_default: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Theme {
    Light,
    Dark,
    System,
}

impl Default for Theme {
    fn default() -> Self {
        Theme::System
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct UserPreferences {
    pub id: Uuid,
    pub user_id: Uuid,
    pub theme: Theme,
    pub language: String,
    pub timezone: String,
    pub email_notifications: bool,
    pub push_notifications: bool,
    pub sms_notifications: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl UserPreferences {
    pub fn new(user_id: Uuid) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            user_id,
            theme: Theme::default(),
            language: "en".to_string(),
            timezone: "UTC".to_string(),
            email_notifications: true,
            push_notifications: true,
            sms_notifications: false,
            created_at: now,
            updated_at: now,
        }
    }
}

// Response types
#[derive(Debug, Serialize)]
pub struct UserResponse {
    pub id: Uuid,
    pub email: String,
    pub username: String,
    pub role: UserRole,
    pub status: UserStatus,
    pub email_verified: bool,
    pub full_name: String,
    pub created_at: DateTime<Utc>,
}

impl From<(User, Option<UserProfile>)> for UserResponse {
    fn from((user, profile): (User, Option<UserProfile>)) -> Self {
        let full_name = user.get_full_name(profile.as_ref());
        Self {
            id: user.id,
            email: user.email,
            username: user.username,
            role: user.role,
            status: user.status,
            email_verified: user.email_verified,
            full_name,
            created_at: user.created_at,
        }
    }
}

#[derive(Debug, Serialize)]
pub struct UserDetailResponse {
    pub id: Uuid,
    pub email: String,
    pub username: String,
    pub role: UserRole,
    pub status: UserStatus,
    pub email_verified: bool,
    pub full_name: String,
    pub last_login_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub profile: Option<UserProfile>,
    pub preferences: Option<UserPreferences>,
}
