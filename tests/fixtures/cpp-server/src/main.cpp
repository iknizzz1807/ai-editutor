// src/main.cpp - Application entry point

#include <iostream>
#include <memory>
#include "config/config.hpp"
#include "repository/user_repository.hpp"
#include "service/user_service.hpp"
#include "service/email_service.hpp"
#include "handler/user_handler.hpp"
#include "middleware/auth_middleware.hpp"

using namespace myapp;

int main(int argc, char* argv[]) {
    try {
        // Load configuration
        auto& cfg = config::Config::instance();
        cfg.load_from_env();

        std::cout << "Starting " << cfg.app().name
                  << " on port " << cfg.app().port << std::endl;

        // Initialize database connection (would use actual DB library)
        // auto db = std::make_shared<Database>(cfg.database().connection_string());

        // Initialize repositories
        auto user_repo = std::make_shared<repository::UserRepository>(/* db */);

        // Initialize services
        auto email_service = std::make_shared<service::EmailService>(service::EmailConfig{
            .smtp_host = cfg.email().smtp_host,
            .smtp_port = cfg.email().smtp_port,
            .username = cfg.email().username,
            .password = cfg.email().password,
            .from_address = cfg.email().from_address,
            .support_address = cfg.email().support_address,
            .use_tls = cfg.email().use_tls
        });

        auto user_service = std::make_shared<service::UserService>(user_repo, email_service);

        // Initialize handlers
        auto user_handler = std::make_shared<handler::UserHandler>(user_service);

        // Initialize middleware
        auto auth_middleware = std::make_shared<middleware::AuthMiddleware>(cfg.auth());
        auto rate_limiter = std::make_shared<middleware::RateLimitMiddleware>(100, 10);

        // Setup routes (would use actual HTTP server library like crow, drogon, etc.)
        // server.route("/api/v1/users", user_handler->list_users);
        // ...

        std::cout << "Server started successfully" << std::endl;

        // Run server (would be actual server run loop)
        // server.run();

        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << std::endl;
        return 1;
    }
}
