// src/handlers/user_handler.rs - User HTTP handlers

use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::AppError;
use crate::models::user::{UserResponse, UserRole, UserStatus};
use crate::repository::user_repository::ListOptions;
use crate::services::user_service::{CreateUserInput, UpdateUserInput, UserService};
use crate::AppState;

pub async fn list_users(
    State(state): State<Arc<AppState>>,
    Query(params): Query<ListUsersParams>,
) -> Result<impl IntoResponse, AppError> {
    let opts = ListOptions {
        page: params.page.unwrap_or(1),
        page_size: params.page_size.unwrap_or(20),
        role: params.role,
        status: params.status,
        search: params.search,
    };

    let (users, total) = state.user_service.list_users(opts).await?;
    let page = params.page.unwrap_or(1);
    let page_size = params.page_size.unwrap_or(20);

    Ok(Json(ListUsersResponse {
        users: users.into_iter().map(|u| UserResponse::from((u, None))).collect(),
        total,
        page,
        page_size,
        total_pages: (total as f64 / page_size as f64).ceil() as i64,
    }))
}

pub async fn get_user(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let user = state.user_service.get_user(id).await?;
    Ok(Json(UserResponse::from((user, None))))
}

// Q: How should we structure error responses for better client-side handling?
pub async fn create_user(
    State(state): State<Arc<AppState>>,
    Json(input): Json<CreateUserRequest>,
) -> Result<impl IntoResponse, AppError> {
    let user = state
        .user_service
        .create_user(CreateUserInput {
            email: input.email,
            username: input.username,
            password: input.password,
            first_name: input.first_name,
            last_name: input.last_name,
            send_verification: true,
        })
        .await?;

    Ok((StatusCode::CREATED, Json(UserResponse::from((user, None)))))
}

pub async fn update_user(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
    Json(input): Json<UpdateUserRequest>,
) -> Result<impl IntoResponse, AppError> {
    let user = state
        .user_service
        .update_user(
            id,
            UpdateUserInput {
                username: input.username,
                role: input.role,
                status: input.status,
            },
        )
        .await?;

    Ok(Json(UserResponse::from((user, None))))
}

pub async fn delete_user(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    state.user_service.delete_user(id).await?;
    Ok(StatusCode::NO_CONTENT)
}

pub async fn get_current_user(
    State(state): State<Arc<AppState>>,
    // Would extract user_id from auth middleware
) -> Result<impl IntoResponse, AppError> {
    // Placeholder - would get user_id from auth context
    let user_id = Uuid::nil();
    let user = state.user_service.get_user(user_id).await?;
    Ok(Json(UserResponse::from((user, None))))
}

pub async fn change_password(
    State(state): State<Arc<AppState>>,
    Json(input): Json<ChangePasswordRequest>,
) -> Result<impl IntoResponse, AppError> {
    // Would get user_id from auth context
    let user_id = Uuid::nil();
    state
        .user_service
        .change_password(user_id, &input.current_password, &input.new_password)
        .await?;

    Ok(Json(MessageResponse {
        message: "Password changed successfully".to_string(),
    }))
}

pub async fn activate_user(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let user = state.user_service.activate_user(id).await?;
    Ok(Json(UserResponse::from((user, None))))
}

pub async fn suspend_user(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
    Json(input): Json<SuspendUserRequest>,
) -> Result<impl IntoResponse, AppError> {
    let user = state
        .user_service
        .suspend_user(id, &input.reason, input.duration_days)
        .await?;

    Ok(Json(UserResponse::from((user, None))))
}

pub async fn get_stats(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, AppError> {
    let stats = state.user_service.get_stats().await?;
    Ok(Json(stats))
}

pub async fn search_users(
    State(state): State<Arc<AppState>>,
    Query(params): Query<SearchUsersParams>,
) -> Result<impl IntoResponse, AppError> {
    let users = state
        .user_service
        .search_users(&params.q, params.limit.unwrap_or(20))
        .await?;

    Ok(Json(users.into_iter().map(|u| UserResponse::from((u, None))).collect::<Vec<_>>()))
}

// Request/Response types
#[derive(Debug, Deserialize)]
pub struct ListUsersParams {
    pub page: Option<i32>,
    pub page_size: Option<i32>,
    pub role: Option<String>,
    pub status: Option<String>,
    pub search: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ListUsersResponse {
    pub users: Vec<UserResponse>,
    pub total: i64,
    pub page: i32,
    pub page_size: i32,
    pub total_pages: i64,
}

#[derive(Debug, Deserialize)]
pub struct CreateUserRequest {
    pub email: String,
    pub username: String,
    pub password: String,
    pub first_name: Option<String>,
    pub last_name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateUserRequest {
    pub username: Option<String>,
    pub role: Option<UserRole>,
    pub status: Option<UserStatus>,
}

#[derive(Debug, Deserialize)]
pub struct ChangePasswordRequest {
    pub current_password: String,
    pub new_password: String,
}

#[derive(Debug, Deserialize)]
pub struct SuspendUserRequest {
    pub reason: String,
    pub duration_days: Option<i32>,
}

#[derive(Debug, Deserialize)]
pub struct SearchUsersParams {
    pub q: String,
    pub limit: Option<i32>,
}

#[derive(Debug, Serialize)]
pub struct MessageResponse {
    pub message: String,
}
