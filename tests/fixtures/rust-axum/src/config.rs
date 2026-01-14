// src/config.rs - Application configuration

use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    pub app: AppConfig,
    pub database: DatabaseConfig,
    pub auth: AuthConfig,
    pub email: EmailConfig,
}

#[derive(Debug, Clone)]
pub struct AppConfig {
    pub name: String,
    pub environment: String,
    pub port: u16,
    pub base_url: String,
    pub debug: bool,
}

#[derive(Debug, Clone)]
pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: u32,
    pub min_connections: u32,
}

#[derive(Debug, Clone)]
pub struct AuthConfig {
    pub jwt_secret: String,
    pub refresh_secret: String,
    pub access_token_expiry: i64,  // seconds
    pub refresh_token_expiry: i64, // seconds
}

#[derive(Debug, Clone)]
pub struct EmailConfig {
    pub smtp_host: String,
    pub smtp_port: u16,
    pub username: String,
    pub password: String,
    pub from_address: String,
    pub support_address: String,
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            app: AppConfig {
                name: env::var("APP_NAME").unwrap_or_else(|_| "MyApp".to_string()),
                environment: env::var("APP_ENV").unwrap_or_else(|_| "development".to_string()),
                port: env::var("APP_PORT")
                    .unwrap_or_else(|_| "8080".to_string())
                    .parse()
                    .unwrap_or(8080),
                base_url: env::var("APP_BASE_URL")
                    .unwrap_or_else(|_| "http://localhost:8080".to_string()),
                debug: env::var("APP_DEBUG")
                    .unwrap_or_else(|_| "true".to_string())
                    .parse()
                    .unwrap_or(true),
            },
            database: DatabaseConfig {
                url: env::var("DATABASE_URL")
                    .unwrap_or_else(|_| "postgres://localhost/myapp".to_string()),
                max_connections: env::var("DB_MAX_CONNECTIONS")
                    .unwrap_or_else(|_| "100".to_string())
                    .parse()
                    .unwrap_or(100),
                min_connections: env::var("DB_MIN_CONNECTIONS")
                    .unwrap_or_else(|_| "10".to_string())
                    .parse()
                    .unwrap_or(10),
            },
            auth: AuthConfig {
                jwt_secret: env::var("JWT_SECRET")
                    .unwrap_or_else(|_| "change-me-in-production".to_string()),
                refresh_secret: env::var("REFRESH_SECRET")
                    .unwrap_or_else(|_| "change-me-in-production".to_string()),
                access_token_expiry: env::var("ACCESS_TOKEN_EXPIRY")
                    .unwrap_or_else(|_| "900".to_string())
                    .parse()
                    .unwrap_or(900), // 15 minutes
                refresh_token_expiry: env::var("REFRESH_TOKEN_EXPIRY")
                    .unwrap_or_else(|_| "604800".to_string())
                    .parse()
                    .unwrap_or(604800), // 7 days
            },
            email: EmailConfig {
                smtp_host: env::var("SMTP_HOST").unwrap_or_else(|_| "localhost".to_string()),
                smtp_port: env::var("SMTP_PORT")
                    .unwrap_or_else(|_| "587".to_string())
                    .parse()
                    .unwrap_or(587),
                username: env::var("SMTP_USERNAME").unwrap_or_default(),
                password: env::var("SMTP_PASSWORD").unwrap_or_default(),
                from_address: env::var("EMAIL_FROM")
                    .unwrap_or_else(|_| "noreply@example.com".to_string()),
                support_address: env::var("EMAIL_SUPPORT")
                    .unwrap_or_else(|_| "support@example.com".to_string()),
            },
        }
    }

    pub fn is_production(&self) -> bool {
        self.app.environment == "production"
    }

    pub fn is_development(&self) -> bool {
        self.app.environment == "development"
    }
}
