// include/repository/user_repository.hpp - User repository interface

#ifndef REPOSITORY_USER_REPOSITORY_HPP
#define REPOSITORY_USER_REPOSITORY_HPP

#include <memory>
#include <optional>
#include <vector>
#include <string>
#include "models/user.hpp"

namespace myapp {
namespace repository {

struct ListOptions {
    int page = 1;
    int page_size = 20;
    std::optional<std::string> role_filter;
    std::optional<std::string> status_filter;
    std::optional<std::string> search_query;
};

struct PaginatedResult {
    std::vector<models::User> users;
    int64_t total;
    int page;
    int page_size;
    int total_pages;
};

struct UserStats {
    int64_t total;
    int64_t active;
    int64_t verified;
    int64_t new_this_month;
};

class IUserRepository {
public:
    virtual ~IUserRepository() = default;

    virtual std::optional<models::User> find_by_id(int64_t id) = 0;
    virtual std::optional<models::User> find_by_email(const std::string& email) = 0;
    virtual std::optional<models::User> find_by_username(const std::string& username) = 0;

    virtual models::User create(const models::User& user) = 0;
    virtual models::User update(const models::User& user) = 0;
    virtual void remove(int64_t id) = 0;

    virtual PaginatedResult list(const ListOptions& options) = 0;
    virtual std::vector<models::User> search(const std::string& query, int limit) = 0;

    virtual UserStats get_stats() = 0;
    virtual void update_last_login(int64_t user_id, const std::string& ip) = 0;
};

// Q: What's the best strategy for implementing connection pooling in C++?
class UserRepository : public IUserRepository {
public:
    explicit UserRepository(/* db connection */);
    ~UserRepository() override;

    std::optional<models::User> find_by_id(int64_t id) override;
    std::optional<models::User> find_by_email(const std::string& email) override;
    std::optional<models::User> find_by_username(const std::string& username) override;

    models::User create(const models::User& user) override;
    models::User update(const models::User& user) override;
    void remove(int64_t id) override;

    PaginatedResult list(const ListOptions& options) override;
    std::vector<models::User> search(const std::string& query, int limit) override;

    UserStats get_stats() override;
    void update_last_login(int64_t user_id, const std::string& ip) override;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace repository
} // namespace myapp

#endif // REPOSITORY_USER_REPOSITORY_HPP
