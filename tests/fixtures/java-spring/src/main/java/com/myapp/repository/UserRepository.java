// src/main/java/com/myapp/repository/UserRepository.java - User repository

package com.myapp.repository;

import com.myapp.model.User;
import com.myapp.model.UserRole;
import com.myapp.model.UserStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface UserRepository extends JpaRepository<User, UUID>, JpaSpecificationExecutor<User> {

    Optional<User> findByEmailAndDeletedAtIsNull(String email);

    Optional<User> findByUsernameAndDeletedAtIsNull(String username);

    Optional<User> findByIdAndDeletedAtIsNull(UUID id);

    boolean existsByEmailAndDeletedAtIsNull(String email);

    boolean existsByUsernameAndDeletedAtIsNull(String username);

    Page<User> findAllByDeletedAtIsNull(Pageable pageable);

    Page<User> findByRoleAndDeletedAtIsNull(UserRole role, Pageable pageable);

    Page<User> findByStatusAndDeletedAtIsNull(UserStatus status, Pageable pageable);

    // Q: How can we optimize this search query for better performance with full-text search?
    @Query("""
        SELECT u FROM User u
        LEFT JOIN FETCH u.profile p
        WHERE u.deletedAt IS NULL
          AND (LOWER(u.email) LIKE LOWER(CONCAT('%', :query, '%'))
               OR LOWER(u.username) LIKE LOWER(CONCAT('%', :query, '%'))
               OR LOWER(p.firstName) LIKE LOWER(CONCAT('%', :query, '%'))
               OR LOWER(p.lastName) LIKE LOWER(CONCAT('%', :query, '%')))
        """)
    List<User> search(@Param("query") String query, Pageable pageable);

    @Query("SELECT u FROM User u WHERE u.role = :role AND u.deletedAt IS NULL")
    List<User> findByRole(@Param("role") UserRole role);

    @Query("SELECT u FROM User u WHERE u.status = 'ACTIVE' AND u.deletedAt IS NULL")
    List<User> findActiveUsers();

    @Query("SELECT u FROM User u WHERE u.lastLoginAt >= :cutoff AND u.deletedAt IS NULL")
    List<User> findRecentlyActive(@Param("cutoff") LocalDateTime cutoff);

    @Query("""
        SELECT u FROM User u
        WHERE (u.lastLoginAt < :cutoff OR u.lastLoginAt IS NULL)
          AND u.deletedAt IS NULL
        """)
    List<User> findInactiveUsers(@Param("cutoff") LocalDateTime cutoff);

    @Modifying
    @Query("UPDATE User u SET u.lastLoginAt = :loginAt, u.lastLoginIp = :ip WHERE u.id = :id")
    void updateLastLogin(@Param("id") UUID id, @Param("loginAt") LocalDateTime loginAt, @Param("ip") String ip);

    @Modifying
    @Query("UPDATE User u SET u.status = :status WHERE u.id IN :ids")
    int bulkUpdateStatus(@Param("ids") List<UUID> ids, @Param("status") UserStatus status);

    @Query("SELECT COUNT(u) FROM User u WHERE u.deletedAt IS NULL")
    long countActive();

    @Query("SELECT COUNT(u) FROM User u WHERE u.status = 'ACTIVE' AND u.deletedAt IS NULL")
    long countByStatusActive();

    @Query("SELECT COUNT(u) FROM User u WHERE u.emailVerified = true AND u.deletedAt IS NULL")
    long countVerified();

    @Query("SELECT COUNT(u) FROM User u WHERE u.createdAt >= :since AND u.deletedAt IS NULL")
    long countNewSince(@Param("since") LocalDateTime since);

    @Query("""
        SELECT u.role, COUNT(u) FROM User u
        WHERE u.deletedAt IS NULL
        GROUP BY u.role
        """)
    List<Object[]> countByRole();

    @Query("""
        SELECT u.status, COUNT(u) FROM User u
        WHERE u.deletedAt IS NULL
        GROUP BY u.status
        """)
    List<Object[]> countByStatus();
}
