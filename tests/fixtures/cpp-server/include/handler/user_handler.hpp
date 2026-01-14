// include/handler/user_handler.hpp - HTTP handlers for user endpoints

#ifndef HANDLER_USER_HANDLER_HPP
#define HANDLER_USER_HANDLER_HPP

#include <memory>
#include <string>
#include <functional>
#include "service/user_service.hpp"

namespace myapp {
namespace handler {

// Forward declarations for HTTP types (would be from actual HTTP library)
struct Request {
    std::string method;
    std::string path;
    std::map<std::string, std::string> params;
    std::map<std::string, std::string> query;
    std::map<std::string, std::string> headers;
    std::string body;

    // Auth context (set by middleware)
    std::optional<int64_t> user_id;
    std::optional<std::string> user_role;
};

struct Response {
    int status_code = 200;
    std::map<std::string, std::string> headers;
    std::string body;

    static Response ok(const std::string& body);
    static Response created(const std::string& body);
    static Response no_content();
    static Response bad_request(const std::string& message);
    static Response unauthorized(const std::string& message);
    static Response forbidden(const std::string& message);
    static Response not_found(const std::string& message);
    static Response conflict(const std::string& message);
    static Response internal_error(const std::string& message);
};

using HandlerFunc = std::function<Response(const Request&)>;

class UserHandler {
public:
    explicit UserHandler(std::shared_ptr<service::UserService> user_service);
    ~UserHandler();

    // CRUD endpoints
    Response list_users(const Request& req);
    Response get_user(const Request& req);
    Response create_user(const Request& req);
    Response update_user(const Request& req);
    Response delete_user(const Request& req);

    // Current user endpoints
    Response get_current_user(const Request& req);
    Response update_profile(const Request& req);
    Response update_preferences(const Request& req);
    Response change_password(const Request& req);

    // Admin endpoints
    Response activate_user(const Request& req);
    Response suspend_user(const Request& req);
    Response get_stats(const Request& req);

    // Search
    Response search_users(const Request& req);

    // Q: How should we implement request validation and return structured error responses?
    // Route registration helper
    void register_routes(
        std::function<void(const std::string& method, const std::string& path, HandlerFunc handler)> router
    );

private:
    // JSON serialization helpers
    std::string user_to_json(const models::User& user);
    std::string users_to_json(const std::vector<models::User>& users);
    std::string paginated_to_json(const repository::PaginatedResult& result);
    std::string stats_to_json(const repository::UserStats& stats);

    // Request parsing helpers
    models::CreateUserDTO parse_create_dto(const std::string& body);
    models::UpdateUserDTO parse_update_dto(const std::string& body);
    repository::ListOptions parse_list_options(const Request& req);

    // Validation
    std::vector<std::string> validate_create_dto(const models::CreateUserDTO& dto);
    std::vector<std::string> validate_update_dto(const models::UpdateUserDTO& dto);

    std::shared_ptr<service::UserService> user_service_;
};

} // namespace handler
} // namespace myapp

#endif // HANDLER_USER_HANDLER_HPP
