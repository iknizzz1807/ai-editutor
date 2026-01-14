// include/middleware/auth_middleware.hpp - Authentication middleware

#ifndef MIDDLEWARE_AUTH_MIDDLEWARE_HPP
#define MIDDLEWARE_AUTH_MIDDLEWARE_HPP

#include <string>
#include <optional>
#include <memory>
#include <chrono>
#include <functional>
#include "handler/user_handler.hpp"
#include "config/config.hpp"

namespace myapp {
namespace middleware {

struct TokenClaims {
    int64_t user_id;
    std::string email;
    std::string role;
    std::chrono::system_clock::time_point expires_at;
    std::chrono::system_clock::time_point issued_at;
};

class AuthMiddleware {
public:
    explicit AuthMiddleware(const config::AuthConfig& config);
    ~AuthMiddleware();

    // Token generation
    std::string generate_access_token(int64_t user_id, const std::string& email,
                                      const std::string& role);
    std::string generate_refresh_token(int64_t user_id, const std::string& email,
                                       const std::string& role);

    // Token verification
    std::optional<TokenClaims> verify_access_token(const std::string& token);
    std::optional<TokenClaims> verify_refresh_token(const std::string& token);

    // Q: How should we handle JWT token refresh without causing race conditions?
    // Middleware function
    handler::HandlerFunc authenticate(handler::HandlerFunc next);
    handler::HandlerFunc require_role(const std::vector<std::string>& roles,
                                      handler::HandlerFunc next);
    handler::HandlerFunc require_admin(handler::HandlerFunc next);

    // Token refresh endpoint handler
    handler::Response refresh_token(const handler::Request& req);

private:
    std::string sign_token(const TokenClaims& claims, const std::string& secret,
                          std::chrono::seconds expiry);
    std::optional<TokenClaims> parse_token(const std::string& token, const std::string& secret);
    std::string extract_bearer_token(const handler::Request& req);

    config::AuthConfig config_;
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

// Rate limiting middleware
class RateLimitMiddleware {
public:
    RateLimitMiddleware(int requests_per_minute, int burst_size = 10);
    ~RateLimitMiddleware();

    handler::HandlerFunc limit(handler::HandlerFunc next);
    handler::HandlerFunc limit_by_user(handler::HandlerFunc next);
    handler::HandlerFunc limit_by_ip(handler::HandlerFunc next);

    // Q: What are the tradeoffs between token bucket and sliding window rate limiting?
    void set_endpoint_limit(const std::string& path, int requests_per_minute);

private:
    bool check_limit(const std::string& identifier);
    void record_request(const std::string& identifier);
    std::string get_identifier(const handler::Request& req, bool by_user);

    int requests_per_minute_;
    int burst_size_;
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace middleware
} // namespace myapp

#endif // MIDDLEWARE_AUTH_MIDDLEWARE_HPP
