// src/main.rs - Application entry point

mod config;
mod error;
mod handlers;
mod middleware;
mod models;
mod repository;
mod services;

use std::sync::Arc;

use axum::{
    routing::{delete, get, patch, post},
    Router,
};
use sqlx::postgres::PgPoolOptions;
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use config::Config;
use handlers::user_handler;
use middleware::auth::auth_middleware;
use repository::user_repository::UserRepository;
use services::{email_service::EmailService, user_service::UserService};

pub struct AppState {
    pub config: Arc<Config>,
    pub user_service: Arc<UserService>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Load configuration
    let config = Arc::new(Config::from_env());

    // Initialize database pool
    let pool = PgPoolOptions::new()
        .max_connections(config.database.max_connections)
        .min_connections(config.database.min_connections)
        .connect(&config.database.url)
        .await?;

    // Run migrations
    sqlx::migrate!("./migrations").run(&pool).await?;

    // Initialize services
    let user_repo = Arc::new(UserRepository::new(pool));
    let email_service = Arc::new(EmailService::new(config.clone()));
    let user_service = Arc::new(UserService::new(user_repo, email_service));

    // Build application state
    let state = Arc::new(AppState {
        config: config.clone(),
        user_service,
    });

    // Build router
    let app = Router::new()
        // Public routes
        .route("/api/v1/register", post(user_handler::create_user))
        .route("/api/v1/users/search", get(user_handler::search_users))
        // Protected routes
        .route("/api/v1/users", get(user_handler::list_users))
        .route("/api/v1/users/:id", get(user_handler::get_user))
        .route("/api/v1/users/:id", patch(user_handler::update_user))
        .route("/api/v1/users/:id", delete(user_handler::delete_user))
        .route("/api/v1/users/me", get(user_handler::get_current_user))
        .route("/api/v1/users/me/password", post(user_handler::change_password))
        .route("/api/v1/users/:id/activate", post(user_handler::activate_user))
        .route("/api/v1/users/:id/suspend", post(user_handler::suspend_user))
        // Admin routes
        .route("/api/v1/admin/users/stats", get(user_handler::get_stats))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    // Start server
    let addr = format!("0.0.0.0:{}", config.app.port);
    tracing::info!("Server starting on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
