// src/repository/user_repository.rs - User repository

use async_trait::async_trait;
use chrono::{Duration, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::error::AppError;
use crate::models::user::{User, UserProfile, UserPreferences, UserRole, UserStatus};

pub struct UserRepository {
    pool: PgPool,
}

impl UserRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    pub async fn create(&self, user: &User) -> Result<User, AppError> {
        let row = sqlx::query_as::<_, User>(
            r#"
            INSERT INTO users (id, email, username, password_hash, role, status, email_verified, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            RETURNING *
            "#,
        )
        .bind(&user.id)
        .bind(&user.email)
        .bind(&user.username)
        .bind(&user.password_hash)
        .bind(&user.role)
        .bind(&user.status)
        .bind(user.email_verified)
        .bind(&user.created_at)
        .bind(&user.updated_at)
        .fetch_one(&self.pool)
        .await?;

        Ok(row)
    }

    pub async fn find_by_id(&self, id: Uuid) -> Result<Option<User>, AppError> {
        let row = sqlx::query_as::<_, User>(
            "SELECT * FROM users WHERE id = $1 AND deleted_at IS NULL",
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row)
    }

    pub async fn find_by_email(&self, email: &str) -> Result<Option<User>, AppError> {
        let row = sqlx::query_as::<_, User>(
            "SELECT * FROM users WHERE email = $1 AND deleted_at IS NULL",
        )
        .bind(email)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row)
    }

    pub async fn find_by_username(&self, username: &str) -> Result<Option<User>, AppError> {
        let row = sqlx::query_as::<_, User>(
            "SELECT * FROM users WHERE username = $1 AND deleted_at IS NULL",
        )
        .bind(username)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row)
    }

    pub async fn update(&self, user: &User) -> Result<User, AppError> {
        let row = sqlx::query_as::<_, User>(
            r#"
            UPDATE users
            SET username = $1, role = $2, status = $3, email_verified = $4,
                last_login_at = $5, last_login_ip = $6, updated_at = $7
            WHERE id = $8
            RETURNING *
            "#,
        )
        .bind(&user.username)
        .bind(&user.role)
        .bind(&user.status)
        .bind(user.email_verified)
        .bind(&user.last_login_at)
        .bind(&user.last_login_ip)
        .bind(Utc::now())
        .bind(&user.id)
        .fetch_one(&self.pool)
        .await?;

        Ok(row)
    }

    pub async fn delete(&self, id: Uuid) -> Result<(), AppError> {
        sqlx::query("UPDATE users SET deleted_at = $1 WHERE id = $2")
            .bind(Utc::now())
            .bind(id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    // Q: How can we optimize this query for better performance with large datasets?
    pub async fn list(&self, opts: ListOptions) -> Result<(Vec<User>, i64), AppError> {
        let mut count_query = String::from("SELECT COUNT(*) FROM users WHERE deleted_at IS NULL");
        let mut query = String::from("SELECT * FROM users WHERE deleted_at IS NULL");

        // Build WHERE clause
        let mut conditions = Vec::new();
        if let Some(role) = &opts.role {
            conditions.push(format!("role = '{}'", role));
        }
        if let Some(status) = &opts.status {
            conditions.push(format!("status = '{}'", status));
        }
        if let Some(search) = &opts.search {
            conditions.push(format!(
                "(email ILIKE '%{}%' OR username ILIKE '%{}%')",
                search, search
            ));
        }

        if !conditions.is_empty() {
            let where_clause = format!(" AND {}", conditions.join(" AND "));
            count_query.push_str(&where_clause);
            query.push_str(&where_clause);
        }

        // Get total count
        let total: i64 = sqlx::query_scalar(&count_query)
            .fetch_one(&self.pool)
            .await?;

        // Add pagination
        let offset = (opts.page - 1) * opts.page_size;
        query.push_str(&format!(
            " ORDER BY created_at DESC LIMIT {} OFFSET {}",
            opts.page_size, offset
        ));

        let users = sqlx::query_as::<_, User>(&query)
            .fetch_all(&self.pool)
            .await?;

        Ok((users, total))
    }

    pub async fn search(&self, query: &str, limit: i32) -> Result<Vec<User>, AppError> {
        let search = format!("%{}%", query);
        let users = sqlx::query_as::<_, User>(
            r#"
            SELECT u.* FROM users u
            LEFT JOIN user_profiles p ON p.user_id = u.id
            WHERE u.deleted_at IS NULL
              AND (u.email ILIKE $1 OR u.username ILIKE $1
                   OR p.first_name ILIKE $1 OR p.last_name ILIKE $1)
            LIMIT $2
            "#,
        )
        .bind(&search)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        Ok(users)
    }

    pub async fn find_by_role(&self, role: UserRole) -> Result<Vec<User>, AppError> {
        let users = sqlx::query_as::<_, User>(
            "SELECT * FROM users WHERE role = $1 AND deleted_at IS NULL",
        )
        .bind(role)
        .fetch_all(&self.pool)
        .await?;

        Ok(users)
    }

    pub async fn find_active(&self) -> Result<Vec<User>, AppError> {
        let users = sqlx::query_as::<_, User>(
            "SELECT * FROM users WHERE status = 'active' AND deleted_at IS NULL",
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(users)
    }

    pub async fn find_recently_active(&self, days: i64) -> Result<Vec<User>, AppError> {
        let cutoff = Utc::now() - Duration::days(days);
        let users = sqlx::query_as::<_, User>(
            "SELECT * FROM users WHERE last_login_at >= $1 AND deleted_at IS NULL",
        )
        .bind(cutoff)
        .fetch_all(&self.pool)
        .await?;

        Ok(users)
    }

    pub async fn find_inactive(&self, days: i64) -> Result<Vec<User>, AppError> {
        let cutoff = Utc::now() - Duration::days(days);
        let users = sqlx::query_as::<_, User>(
            r#"
            SELECT * FROM users
            WHERE (last_login_at < $1 OR last_login_at IS NULL)
              AND deleted_at IS NULL
            "#,
        )
        .bind(cutoff)
        .fetch_all(&self.pool)
        .await?;

        Ok(users)
    }

    pub async fn update_last_login(&self, user_id: Uuid, ip: Option<&str>) -> Result<(), AppError> {
        sqlx::query(
            "UPDATE users SET last_login_at = $1, last_login_ip = $2 WHERE id = $3",
        )
        .bind(Utc::now())
        .bind(ip)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_stats(&self) -> Result<UserStats, AppError> {
        let total: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE deleted_at IS NULL")
            .fetch_one(&self.pool)
            .await?;

        let active: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM users WHERE status = 'active' AND deleted_at IS NULL",
        )
        .fetch_one(&self.pool)
        .await?;

        let verified: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM users WHERE email_verified = true AND deleted_at IS NULL",
        )
        .fetch_one(&self.pool)
        .await?;

        let month_ago = Utc::now() - Duration::days(30);
        let new_this_month: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM users WHERE created_at >= $1 AND deleted_at IS NULL",
        )
        .bind(month_ago)
        .fetch_one(&self.pool)
        .await?;

        Ok(UserStats {
            total,
            active,
            verified,
            new_this_month,
        })
    }
}

#[derive(Debug, Default)]
pub struct ListOptions {
    pub page: i32,
    pub page_size: i32,
    pub role: Option<String>,
    pub status: Option<String>,
    pub search: Option<String>,
}

#[derive(Debug)]
pub struct UserStats {
    pub total: i64,
    pub active: i64,
    pub verified: i64,
    pub new_this_month: i64,
}
