// src/middleware/auth.rs - Authentication middleware

use std::sync::Arc;

use axum::{
    body::Body,
    extract::State,
    http::{header, Request, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
    Json,
};
use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::config::Config;
use crate::error::AppError;
use crate::models::user::UserRole;

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: Uuid,      // user_id
    pub email: String,
    pub role: String,
    pub exp: i64,
    pub iat: i64,
}

pub struct AuthMiddleware {
    config: Arc<Config>,
}

impl AuthMiddleware {
    pub fn new(config: Arc<Config>) -> Self {
        Self { config }
    }

    pub fn generate_access_token(
        &self,
        user_id: Uuid,
        email: &str,
        role: &UserRole,
    ) -> Result<String, AppError> {
        let now = Utc::now();
        let expires_at = now + Duration::seconds(self.config.auth.access_token_expiry);

        let claims = Claims {
            sub: user_id,
            email: email.to_string(),
            role: format!("{:?}", role).to_lowercase(),
            exp: expires_at.timestamp(),
            iat: now.timestamp(),
        };

        encode(
            &Header::default(),
            &claims,
            &EncodingKey::from_secret(self.config.auth.jwt_secret.as_bytes()),
        )
        .map_err(|e| AppError::Internal(format!("Token generation error: {}", e)))
    }

    pub fn generate_refresh_token(
        &self,
        user_id: Uuid,
        email: &str,
        role: &UserRole,
    ) -> Result<String, AppError> {
        let now = Utc::now();
        let expires_at = now + Duration::seconds(self.config.auth.refresh_token_expiry);

        let claims = Claims {
            sub: user_id,
            email: email.to_string(),
            role: format!("{:?}", role).to_lowercase(),
            exp: expires_at.timestamp(),
            iat: now.timestamp(),
        };

        encode(
            &Header::default(),
            &claims,
            &EncodingKey::from_secret(self.config.auth.refresh_secret.as_bytes()),
        )
        .map_err(|e| AppError::Internal(format!("Token generation error: {}", e)))
    }

    pub fn verify_access_token(&self, token: &str) -> Result<Claims, AppError> {
        decode::<Claims>(
            token,
            &DecodingKey::from_secret(self.config.auth.jwt_secret.as_bytes()),
            &Validation::default(),
        )
        .map(|data| data.claims)
        .map_err(|e| AppError::Unauthorized(format!("Invalid token: {}", e)))
    }

    pub fn verify_refresh_token(&self, token: &str) -> Result<Claims, AppError> {
        decode::<Claims>(
            token,
            &DecodingKey::from_secret(self.config.auth.refresh_secret.as_bytes()),
            &Validation::default(),
        )
        .map(|data| data.claims)
        .map_err(|e| AppError::Unauthorized(format!("Invalid refresh token: {}", e)))
    }
}

// Q: How should we handle token expiration and automatic refresh in middleware?
pub async fn auth_middleware(
    State(config): State<Arc<Config>>,
    mut req: Request<Body>,
    next: Next,
) -> Result<Response, AppError> {
    let auth_header = req
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok());

    let token = match auth_header {
        Some(header) if header.starts_with("Bearer ") => &header[7..],
        _ => {
            return Err(AppError::Unauthorized("Missing authorization header".to_string()));
        }
    };

    let auth = AuthMiddleware::new(config);
    let claims = auth.verify_access_token(token)?;

    // Add claims to request extensions
    req.extensions_mut().insert(claims);

    Ok(next.run(req).await)
}

pub async fn require_role(
    required_roles: Vec<UserRole>,
    req: Request<Body>,
    next: Next,
) -> Result<Response, AppError> {
    let claims = req
        .extensions()
        .get::<Claims>()
        .ok_or_else(|| AppError::Unauthorized("Not authenticated".to_string()))?;

    let user_role: UserRole = match claims.role.as_str() {
        "admin" => UserRole::Admin,
        "moderator" => UserRole::Moderator,
        "user" => UserRole::User,
        _ => UserRole::Guest,
    };

    if !required_roles.contains(&user_role) {
        return Err(AppError::Forbidden("Insufficient permissions".to_string()));
    }

    Ok(next.run(req).await)
}

pub async fn require_admin(req: Request<Body>, next: Next) -> Result<Response, AppError> {
    require_role(vec![UserRole::Admin], req, next).await
}

#[derive(Debug, Serialize)]
pub struct TokenResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: i64,
}

impl TokenResponse {
    pub fn new(access_token: String, refresh_token: String, expires_in: i64) -> Self {
        Self {
            access_token,
            refresh_token,
            token_type: "Bearer".to_string(),
            expires_in,
        }
    }
}
