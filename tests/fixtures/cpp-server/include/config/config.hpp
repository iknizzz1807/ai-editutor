// include/config/config.hpp - Application configuration

#ifndef CONFIG_CONFIG_HPP
#define CONFIG_CONFIG_HPP

#include <string>
#include <optional>
#include <chrono>

namespace myapp {
namespace config {

struct AppConfig {
    std::string name = "MyApp";
    std::string environment = "development";
    int port = 8080;
    std::string base_url = "http://localhost:8080";
    bool debug = true;
};

struct DatabaseConfig {
    std::string host = "localhost";
    int port = 5432;
    std::string name = "myapp";
    std::string user = "postgres";
    std::string password;
    std::string ssl_mode = "disable";
    int max_connections = 100;
    int min_connections = 10;
    std::chrono::seconds connection_timeout{30};

    std::string connection_string() const;
};

struct AuthConfig {
    std::string jwt_secret = "change-me-in-production";
    std::string refresh_secret = "change-me-in-production";
    std::chrono::seconds access_token_expiry{900};      // 15 minutes
    std::chrono::seconds refresh_token_expiry{604800};  // 7 days
    int bcrypt_cost = 10;
};

struct EmailConfig {
    std::string smtp_host = "localhost";
    int smtp_port = 587;
    std::string username;
    std::string password;
    std::string from_address = "noreply@example.com";
    std::string support_address = "support@example.com";
    bool use_tls = true;
};

struct CacheConfig {
    std::string redis_url = "redis://localhost:6379";
    std::chrono::seconds default_ttl{3600};
    int max_size = 10000;
};

class Config {
public:
    static Config& instance();

    // Load from environment variables
    void load_from_env();

    // Load from file
    void load_from_file(const std::string& path);

    // Accessors
    const AppConfig& app() const { return app_; }
    const DatabaseConfig& database() const { return database_; }
    const AuthConfig& auth() const { return auth_; }
    const EmailConfig& email() const { return email_; }
    const CacheConfig& cache() const { return cache_; }

    // Mutators (for testing)
    void set_app(const AppConfig& config) { app_ = config; }
    void set_database(const DatabaseConfig& config) { database_ = config; }
    void set_auth(const AuthConfig& config) { auth_ = config; }
    void set_email(const EmailConfig& config) { email_ = config; }
    void set_cache(const CacheConfig& config) { cache_ = config; }

    // Helpers
    bool is_production() const { return app_.environment == "production"; }
    bool is_development() const { return app_.environment == "development"; }

private:
    Config() = default;
    Config(const Config&) = delete;
    Config& operator=(const Config&) = delete;

    // Helper to get env with default
    static std::string get_env(const std::string& key, const std::string& default_value);
    static int get_env_int(const std::string& key, int default_value);
    static bool get_env_bool(const std::string& key, bool default_value);

    AppConfig app_;
    DatabaseConfig database_;
    AuthConfig auth_;
    EmailConfig email_;
    CacheConfig cache_;
};

} // namespace config
} // namespace myapp

#endif // CONFIG_CONFIG_HPP
